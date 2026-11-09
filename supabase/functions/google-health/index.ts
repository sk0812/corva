// Corva ⇄ Google Health.
//
// Routes (under /functions/v1/google-health):
//   POST /connect     signed-in user → { url } of Google's consent screen
//   GET  /callback    Google redirects here; stores tokens, starts a first sync, sends the
//                     browser back to corva://google-health?status=…
//   POST /sync        signed-in user → sync their last `days` days (default 7)
//   POST /sync-all    hourly cron (x-corva-cron header) → sync everyone's last 3 days
//   POST /disconnect  signed-in user → revoke at Google, delete tokens and synced data
//
// Tokens never leave the server. Each sync normalises Google's data into one
// `daily_records` row per local day; the app turns those into recovery, strain and sleep.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";
const CRON_SECRET = Deno.env.get("CORVA_CRON_SECRET") ?? "";

const CALLBACK_URL = `${SUPABASE_URL}/functions/v1/google-health/callback`;
const APP_RETURN_URL = "corva://google-health";
const HEALTH_API = "https://health.googleapis.com/v4/users/me/dataTypes";
const SCOPES = [
  "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
  "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
  "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
];
const SCOPE_NAMES: Record<string, string> = {
  [SCOPES[0]]: "activity",
  [SCOPES[1]]: "heart and vitals",
  [SCOPES[2]]: "sleep",
};
const MISSING_ACCESS_MESSAGE =
  "Corva doesn't have access to your Google Health data. Connect again and tick every box on Google's screen.";

/** The Health permissions missing from a granted-scope string, by friendly name. */
function missingScopes(granted: string | null | undefined): string[] {
  const have = new Set((granted ?? "").split(/\s+/));
  return SCOPES.filter((scope) => !have.has(scope)).map((scope) => SCOPE_NAMES[scope]);
}

// ---------------------------------------------------------------------------------------
// HTTP entry point

Deno.serve(async (request) => {
  const route = new URL(request.url).pathname.split("/").filter(Boolean).pop();
  try {
    switch (route) {
      case "connect":
        return json(await connect(await requireUser(request)));
      case "callback":
        return await callback(new URL(request.url));
      case "sync": {
        const user = await requireUser(request);
        const body = await request.json().catch(() => ({}));
        const days = Math.min(Math.max(Number(body.days ?? 7), 1), 120);
        return json(await syncUser(user, days));
      }
      case "sync-all":
        if (!CRON_SECRET || request.headers.get("x-corva-cron") !== CRON_SECRET) {
          return json({ error: "Not allowed" }, 401);
        }
        return json(await syncAll());
      case "disconnect":
        return json(await disconnect(await requireUser(request)));
      default:
        return json({ error: "Not found" }, 404);
    }
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    console.error(route, error);
    return json({ error: error instanceof Error ? error.message : String(error) }, status);
  }
});

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------------------
// Supabase access (service role: bypasses row-level security, server only)

async function db(path: string, init: RequestInit = {}): Promise<any> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Database ${response.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

/** The signed-in user behind the request's access token. */
async function requireUser(request: Request): Promise<string> {
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) throw new HttpError(401, "Sign in first");
  const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new HttpError(401, "Your session has expired. Sign in again.");
  const user = await response.json();
  return user.id as string;
}

// ---------------------------------------------------------------------------------------
// Connecting

async function connect(userId: string) {
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
    throw new HttpError(503, "Google Health isn't configured on the server yet.");
  }
  const state = crypto.randomUUID();
  await db("oauth_states", { method: "POST", body: JSON.stringify({ state, user_id: userId }) });
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.search = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    redirect_uri: CALLBACK_URL,
    response_type: "code",
    access_type: "offline",
    prompt: "consent",
    include_granted_scopes: "true",
    scope: SCOPES.join(" "),
    state,
  }).toString();
  return { url: url.toString() };
}

async function callback(url: URL): Promise<Response> {
  const back = (status: string, message?: string) => {
    const target = new URL(APP_RETURN_URL);
    target.searchParams.set("status", status);
    if (message) target.searchParams.set("message", message);
    return new Response(null, { status: 302, headers: { Location: target.toString() } });
  };

  const error = url.searchParams.get("error");
  if (error) return back("error", error === "access_denied" ? "Access wasn't granted." : error);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state) return back("error", "Google didn't send a code.");

  const rows = await db(`oauth_states?state=eq.${encodeURIComponent(state)}&select=user_id,created_at`);
  await db(`oauth_states?state=eq.${encodeURIComponent(state)}`, { method: "DELETE" });
  const pending = rows?.[0];
  if (!pending || Date.now() - Date.parse(pending.created_at) > 15 * 60 * 1000) {
    return back("error", "That sign-in link expired. Try again.");
  }

  const tokens = await googleToken({
    grant_type: "authorization_code",
    code,
    redirect_uri: CALLBACK_URL,
  });
  if (!tokens.refresh_token) return back("error", "Google didn't grant ongoing access. Try again.");

  // Google's consent screen lists each permission with its own checkbox, and continuing
  // without ticking them still succeeds. Corva needs all three, so refuse anything less
  // instead of storing a connection that can't read anything.
  const missing = missingScopes(tokens.scope);
  if (missing.length > 0) {
    await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(tokens.refresh_token)}`, { method: "POST" })
      .catch(() => {});
    await db(`google_connections?user_id=eq.${pending.user_id}`, { method: "DELETE" });
    return back(
      "error",
      `Google didn't share your ${missing.join(", ")} data. Connect again and tick every box on Google's screen.`,
    );
  }

  await db("google_connections?on_conflict=user_id", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({
      user_id: pending.user_id,
      refresh_token: tokens.refresh_token,
      access_token: tokens.access_token,
      access_token_expires_at: new Date(Date.now() + (tokens.expires_in - 60) * 1000).toISOString(),
      refresh_token_expires_at: tokens.refresh_token_expires_in
        ? new Date(Date.now() + tokens.refresh_token_expires_in * 1000).toISOString()
        : null,
      scopes: tokens.scope ?? null,
      connected_at: new Date().toISOString(),
      last_error: null,
    }),
  });

  // Pull history in the background so the browser returns to the app straight away.
  const firstSync = syncUser(pending.user_id, 120).catch((e) => console.error("first sync", e));
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(firstSync);
  return back("connected");
}

async function disconnect(userId: string) {
  const rows = await db(`google_connections?user_id=eq.${userId}&select=refresh_token`);
  const token = rows?.[0]?.refresh_token;
  if (token) {
    await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(token)}`, { method: "POST" })
      .catch(() => {});
  }
  await db(`google_connections?user_id=eq.${userId}`, { method: "DELETE" });
  await db(`daily_records?user_id=eq.${userId}&source=eq.google_health`, { method: "DELETE" });
  return { disconnected: true };
}

async function googleToken(params: Record<string, string>): Promise<any> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: GOOGLE_CLIENT_ID, client_secret: GOOGLE_CLIENT_SECRET, ...params }),
  });
  const body = await response.json();
  if (!response.ok) {
    throw new HttpError(response.status === 400 ? 400 : 502, body.error_description ?? body.error ?? "Google token error");
  }
  return body;
}

/** A valid access token, refreshing it (and recording the outcome) when needed. */
async function accessToken(userId: string): Promise<string> {
  const rows = await db(`google_connections?user_id=eq.${userId}&select=*`);
  const connection = rows?.[0];
  if (!connection) throw new HttpError(404, "Google Health isn't connected.");
  if (connection.access_token && Date.parse(connection.access_token_expires_at) > Date.now()) {
    return connection.access_token;
  }
  try {
    const tokens = await googleToken({ grant_type: "refresh_token", refresh_token: connection.refresh_token });
    await db(`google_connections?user_id=eq.${userId}`, {
      method: "PATCH",
      body: JSON.stringify({
        access_token: tokens.access_token,
        access_token_expires_at: new Date(Date.now() + (tokens.expires_in - 60) * 1000).toISOString(),
      }),
    });
    return tokens.access_token;
  } catch (error) {
    const message = "Google access has expired. Reconnect Google Health in Settings.";
    await db(`google_connections?user_id=eq.${userId}`, {
      method: "PATCH",
      body: JSON.stringify({ last_error: message }),
    });
    throw new HttpError(401, error instanceof HttpError && error.status === 400 ? message : String(error));
  }
}

// ---------------------------------------------------------------------------------------
// Syncing

async function syncAll() {
  const connections = await db("google_connections?select=user_id");
  const results: Record<string, unknown> = {};
  for (const { user_id } of connections ?? []) {
    try {
      results[user_id] = await syncUser(user_id, 3);
    } catch (error) {
      results[user_id] = { error: error instanceof Error ? error.message : String(error) };
    }
  }
  return { users: Object.keys(results).length, results };
}

type Day = Record<string, unknown> & { date: string };

/** Pulls `days` days (plus tomorrow, for time zones ahead of UTC) and upserts daily_records. */
async function syncUser(userId: string, days: number) {
  const granted = (await db(`google_connections?user_id=eq.${userId}&select=scopes`))?.[0]?.scopes;
  if (missingScopes(granted).length > 0) {
    await db(`google_connections?user_id=eq.${userId}`, {
      method: "PATCH",
      body: JSON.stringify({ last_error: MISSING_ACCESS_MESSAGE }),
    });
    throw new HttpError(403, MISSING_ACCESS_MESSAGE);
  }
  const token = await accessToken(userId);
  const end = addDays(todayUTC(), 2); // exclusive
  const start = addDays(todayUTC(), -days);
  const records = new Map<string, Day>();
  const day = (date: string): Day => {
    if (!records.has(date)) records.set(date, { date });
    return records.get(date)!;
  };

  try {
    // Daily totals.
    for (const point of await rollUp(token, "steps", start, end, 90)) {
      day(civilDate(point.civilStartTime)).steps = Number(point.steps?.countSum ?? 0);
    }
    for (const point of await rollUp(token, "active-energy-burned", start, end, 90)) {
      day(civilDate(point.civilStartTime)).active_kcal = point.activeEnergyBurned?.kcalSum ?? null;
    }
    for (const point of await rollUp(token, "time-in-heart-rate-zone", start, end, 90)) {
      const zones: Record<string, number> = {};
      for (const entry of point.timeInHeartRateZone?.timeInHeartRateZones ?? []) {
        zones[entry.heartRateZone] = (zones[entry.heartRateZone] ?? 0) + seconds(entry.duration);
      }
      day(civilDate(point.civilStartTime)).zone_seconds = zones;
    }
    for (const point of await rollUp(token, "heart-rate", start, end, 14)) {
      const record = day(civilDate(point.civilStartTime));
      record.hr_avg = point.heartRate?.beatsPerMinuteAvg ?? null;
      record.hr_max = point.heartRate?.beatsPerMinuteMax ?? null;
      record.hr_min = point.heartRate?.beatsPerMinuteMin ?? null;
    }

    // Overnight vitals, one point per day.
    const daily: Array<[string, string, (value: any) => Record<string, unknown>]> = [
      ["daily-resting-heart-rate", "dailyRestingHeartRate", (v) => ({ resting_hr: Number(v.beatsPerMinute) })],
      ["daily-heart-rate-variability", "dailyHeartRateVariability", (v) => ({
        hrv: v.averageHeartRateVariabilityMilliseconds ?? v.deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds ?? null,
      })],
      ["daily-oxygen-saturation", "dailyOxygenSaturation", (v) => ({ spo2: v.averagePercentage ?? null })],
      ["daily-respiratory-rate", "dailyRespiratoryRate", (v) => ({ respiratory_rate: v.breathsPerMinute ?? null })],
      ["daily-sleep-temperature-derivations", "dailySleepTemperatureDerivations", (v) => ({ skin_temp: v.nightlyTemperatureCelsius ?? null })],
      ["daily-vo2-max", "dailyVo2Max", (v) => ({ vo2max: v.vo2Max ?? null })],
    ];
    for (const [type, field, map] of daily) {
      const points = await list(token, type, `${field}.date >= "${start}"`, 10000);
      for (const point of points) {
        const value = point[field];
        if (!value?.date) continue;
        Object.assign(day(dateString(value.date)), map(value));
      }
    }

    // Sleep: the main sleep that ended on each morning.
    const sleeps = await list(token, "sleep", `sleep.interval.civil_end_time >= "${start}"`, 25);
    const chosen = new Map<string, any>();
    for (const point of sleeps) {
      const sleep = point.sleep;
      if (!sleep?.interval || sleep.metadata?.nap) continue;
      const morning = civilDate(sleep.interval.civilEndTime);
      const asleep = Number(sleep.summary?.minutesAsleep ?? 0);
      const current = chosen.get(morning);
      const currentAsleep = Number(current?.summary?.minutesAsleep ?? -1);
      if (!current || (sleep.metadata?.mainSleep && !current.metadata?.mainSleep) || asleep > currentAsleep) {
        chosen.set(morning, sleep);
      }
    }
    for (const [morning, sleep] of chosen) {
      const stages = (sleep.stages ?? []).map((stage: any) => ({
        type: stage.type,
        start: stage.startTime,
        end: stage.endTime,
      }));
      const asleepMinutes = Number(sleep.summary?.minutesAsleep ?? NaN);
      const stageAsleepSeconds = stages
        .filter((s: any) => s.type !== "AWAKE" && s.type !== "RESTLESS")
        .reduce((total: number, s: any) => total + (Date.parse(s.end) - Date.parse(s.start)) / 1000, 0);
      const record = day(morning);
      record.sleep = {
        start: sleep.interval.startTime,
        end: sleep.interval.endTime,
        start_offset_seconds: seconds(sleep.interval.startUtcOffset),
        type: sleep.type,
        stages,
        minutes_asleep: Number.isFinite(asleepMinutes) ? asleepMinutes : Math.round(stageAsleepSeconds / 60),
        minutes_to_fall_asleep: Number(sleep.summary?.minutesToFallAsleep ?? 0),
      };
      record.sleep_seconds = Number.isFinite(asleepMinutes) ? asleepMinutes * 60 : stageAsleepSeconds;
      record.bedtime_minutes = minutesAfterSixPM(sleep.interval.startTime, sleep.interval.startUtcOffset);
    }

    // Workouts.
    const exercises = await list(token, "exercise", `exercise.interval.civil_start_time >= "${start}T00:00:00"`, 25);
    for (const point of exercises) {
      const exercise = point.exercise;
      if (!exercise?.interval) continue;
      const record = day(civilDate(exercise.interval.civilStartTime));
      const durationSeconds = exercise.activeDuration
        ? seconds(exercise.activeDuration)
        : (Date.parse(exercise.interval.endTime) - Date.parse(exercise.interval.startTime)) / 1000;
      const summary = exercise.metricsSummary ?? {};
      const sessions = (record.exercises as unknown[] | undefined) ?? [];
      sessions.push({
        id: point.name ?? `${exercise.interval.startTime}`,
        type: exercise.exerciseType,
        name: exercise.displayName,
        start: exercise.interval.startTime,
        end: exercise.interval.endTime,
        seconds: durationSeconds,
        kcal: summary.caloriesKcal ?? null,
        distance_m: summary.distanceMillimeters ? Number(summary.distanceMillimeters) / 1000 : null,
        avg_hr: summary.averageHeartRateBeatsPerMinute ? Number(summary.averageHeartRateBeatsPerMinute) : null,
      });
      record.exercises = sessions;
      record.exercise_seconds = Number(record.exercise_seconds ?? 0) + durationSeconds;
    }
  } catch (error) {
    // Don't overwrite good rows with a partial pull.
    const message = error instanceof Error ? error.message : String(error);
    await db(`google_connections?user_id=eq.${userId}`, {
      method: "PATCH",
      body: JSON.stringify({ last_error: `Sync failed: ${message}`.slice(0, 500) }),
    });
    throw error;
  }

  const columns = [
    "steps", "active_kcal", "hr_avg", "hr_max", "hr_min", "zone_seconds", "resting_hr", "hrv",
    "respiratory_rate", "spo2", "skin_temp", "vo2max", "sleep", "sleep_seconds", "bedtime_minutes",
    "exercises", "exercise_seconds",
  ];
  const rows = [...records.values()]
    .filter((record) => record.date >= start && record.date < end)
    .map((record) => {
      const row: Record<string, unknown> = {
        user_id: userId,
        date: record.date,
        source: "google_health",
        synced_at: new Date().toISOString(),
      };
      for (const column of columns) row[column] = record[column] ?? null;
      return row;
    });
  if (rows.length > 0) {
    await db("daily_records?on_conflict=user_id,date,source", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify(rows),
    });
  }
  await db(`google_connections?user_id=eq.${userId}`, {
    method: "PATCH",
    body: JSON.stringify({ last_synced_at: new Date().toISOString(), last_error: null }),
  });
  return { days: rows.length, from: start, to: addDays(end, -1) };
}

// ---------------------------------------------------------------------------------------
// Google Health API

async function google(token: string, url: string, init: RequestInit = {}): Promise<any> {
  const response = await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json", ...(init.headers ?? {}) },
  });
  const text = await response.text();
  if (!response.ok) {
    let message = text;
    try {
      message = JSON.parse(text).error?.message ?? text;
    } catch { /* not JSON */ }
    if (response.status === 403 && /insufficient authentication scopes/i.test(message)) {
      throw new HttpError(403, MISSING_ACCESS_MESSAGE);
    }
    throw new Error(`Google Health ${response.status}: ${message}`.slice(0, 400));
  }
  return text ? JSON.parse(text) : {};
}

/** Daily totals between two dates (end exclusive), in windows the API allows. */
async function rollUp(token: string, type: string, start: string, end: string, maxDays: number) {
  const points: any[] = [];
  for (let from = start; from < end; from = addDays(from, maxDays)) {
    const to = minDate(addDays(from, maxDays), end);
    let pageToken: string | undefined;
    do {
      const body: Record<string, unknown> = {
        range: { start: { date: dateObject(from) }, end: { date: dateObject(to) } },
        windowSizeDays: 1,
        pageSize: maxDays,
      };
      if (pageToken) body.pageToken = pageToken;
      const response = await google(token, `${HEALTH_API}/${type}/dataPoints:dailyRollUp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      points.push(...(response.rollupDataPoints ?? []));
      pageToken = response.nextPageToken || undefined;
    } while (pageToken);
  }
  return points;
}

/** Every data point matching `filter`, following pages. */
async function list(token: string, type: string, filter: string, pageSize: number) {
  const points: any[] = [];
  let pageToken: string | undefined;
  do {
    const params = new URLSearchParams({ filter, pageSize: String(pageSize) });
    if (pageToken) params.set("pageToken", pageToken);
    const response = await google(token, `${HEALTH_API}/${type}/dataPoints?${params}`);
    points.push(...(response.dataPoints ?? []));
    pageToken = response.nextPageToken || undefined;
  } while (pageToken && points.length < 5000);
  return points;
}

// ---------------------------------------------------------------------------------------
// Dates and durations

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10);
}

function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function minDate(a: string, b: string): string {
  return a < b ? a : b;
}

function dateObject(date: string) {
  const [year, month, day] = date.split("-").map(Number);
  return { year, month, day };
}

function dateString(date: { year: number; month: number; day: number }): string {
  return `${date.year}-${String(date.month).padStart(2, "0")}-${String(date.day).padStart(2, "0")}`;
}

function civilDate(civil: any): string {
  return dateString(civil?.date ?? civil);
}

/** "3600s" or "-1.5s" → seconds. */
function seconds(duration: string | undefined): number {
  if (!duration) return 0;
  const value = Number.parseFloat(duration.replace(/s$/, ""));
  return Number.isFinite(value) ? value : 0;
}

/** Local clock time of an instant as minutes after 6 PM (11 PM → 300, 12:30 AM → 390). */
function minutesAfterSixPM(instant: string, utcOffset: string): number {
  const local = new Date(Date.parse(instant) + seconds(utcOffset) * 1000);
  let minutes = local.getUTCHours() * 60 + local.getUTCMinutes() - 18 * 60;
  if (minutes < 0) minutes += 24 * 60;
  return minutes;
}
