# Corva: plan for linking a backend

**Status (9 Nov 2026):**
- **Supabase project `corva`** (London) has a schema with row-level security on every table,
  in `supabase/migrations`.
- **Sign-in:** Google, or email with a one-time code. The session is kept in the Keychain.
- **Sync:** profile, experiments, tags and pacts; head-to-head pacts join by invite code.
- **Google Health:** the `google-health` Edge Function holds the OAuth tokens and normalises
  Google's data into `daily_records`, one row per day. It syncs hourly (pg_cron), when the app
  opens, and on demand.
  - **Pulled per day:** steps, active energy, heart-rate zones, average and max heart rate,
    resting heart rate, HRV, SpO₂, breathing rate, nightly skin temperature, VO2 max, the main
    sleep with stages, and workouts.
- **Real data in the app:** a signed-in user with Google Health connected sees their own
  numbers everywhere (`RemoteHealthDataProvider`), scored with the same Swift code as the demo.
- **Pact settlement:** `settle_pacts()` runs hourly in Postgres. It scores days from
  `daily_records`, excuses unwell days, finishes pacts and writes `ledger_entries`.
  `pact_progress()` shares only the goal metric with a pact partner.
- **Not yet built:** Apple Health, payments, push notifications.

A draft for discussion. It covers what the backend is for, a recommended shape, how the
existing app code plugs in, the data model, and a phased order of work. Decisions that are
yours to make are collected at the end.

---

## What needs a backend, and what doesn't

| Need | Backend? | Why |
|---|---|---|
| Apple Health data | **No** (to start) | HealthKit is on-device only. The app reads it directly. |
| Google Health / Fitbit data | **Yes** | OAuth tokens and API calls belong on a server, and a server can sync while the app is closed. |
| Saving experiments, tags, pacts, settings | Not at first | SwiftData on the device covers one phone. A server is needed for a second device or a reinstall. |
| Accounts | **Yes** | Needed for sync and for friends. |
| Head-to-head pacts | **Yes** | Your friend's progress has to come from their account, and the server must be the referee. |
| Money | **Yes**, and last | Stakes held by a payment provider. Needs legal review first. |

So the plan starts with what works without a server (Apple Health and local saving), then
adds the server for Google Health, sync and friends, and leaves money until last.

---

## Recommended shape

```
iPhone app
├── HealthKitProvider ──────────────┐   reads Apple Health on the phone
├── RemoteHealthDataProvider ───────┤   reads Google Health summaries from the API
├── CompositeHealthDataProvider ◄───┘   merges both; the only provider views see
├── ExperimentStore / PactStore  ─── SyncService ─── local SwiftData cache + API
└── CorvaCore (Swift package): models, Scoring, Insights, BioAge, ExperimentAnalysis, PactEvaluation

Backend
├── Auth: Sign in with Apple, Google sign-in
├── Postgres: users, connections, daily data, experiments, pacts, ledger
├── API: profile, sync, invites, pacts
├── Workers (Swift, using CorvaCore)
│   ├── Google Health sync: pulls new data, writes daily records
│   ├── Pact settlement: scores pact days once each day is final
│   └── Notifications: pact reminders and results via APNs
└── Payments (later): payment provider for stakes and payouts
```

### The key idea: share one copy of the maths

Everything in `Core/` is already pure, `nonisolated` Swift with no UI. It compiles on its own
as a command-line tool, which I've been doing to check the mock data. Move it into a Swift
package, `CorvaCore`, and both the app and a Swift server can depend on it. Then:

- Recovery, strain, sleep, bio age and pact outcomes are computed by **the same code** on the
  phone and on the server. They can't drift apart.
- The server can **settle pacts itself**. It can't trust a number the phone reports.

### Stack recommendation

**Recommended: Supabase plus a small Swift worker.**
- **Supabase provides:** hosted Postgres, auth (Apple and Google built in), row-level security
  so each user can only read their own rows, storage, and scheduled jobs. That's most of the
  backend without writing it.
- **The Swift worker provides:** a small service using `CorvaCore`, which runs Google Health
  sync, scoring and pact settlement against the same Postgres database.
- **Hosting:** the worker can run on Fly.io, Render, or AWS.

**Alternatives:**
- **All Supabase, with TypeScript functions.** Fewer moving parts, but the scoring and pact
  logic would have to be rewritten in TypeScript and kept in step with the Swift version by
  hand. That's risky where money depends on it.
- **All Swift (Vapor) with Postgres.** One language end to end, but you'd build auth, admin and
  migrations yourself.
- **Firebase.** Quick to start, but a document store is a poor fit for daily time series and
  the queries the Lab screens make.

---

## How the existing app code plugs in

The skeleton was built for this, so most of the UI doesn't change.

| Today | With a backend |
|---|---|
| `HealthDataProvider` protocol | **Unchanged.** Views keep depending on it. |
| `MockHealthDataProvider` | Kept for previews and tests. |
| — | `HealthKitProvider`: builds `DailySummary` from HealthKit samples on the phone. |
| — | `RemoteHealthDataProvider`: fetches daily data from the API. |
| — | `CompositeHealthDataProvider`: merges sources per metric. It is what `CorvaApp` injects. |
| `ExperimentStore`, `PactStore` (in memory) | Same methods, backed by a `SyncService`: SwiftData locally, pushed to the API. |
| `AppSettings` (in memory) | Persisted locally; profile fields synced to the account. |
| Settings › Data sources (placeholder) | Real connect and disconnect flows and real sync times. |
| `PactStore.MockFriend` | Replaced by the friend's real, server-verified days. |

### Merging two sources

When both Apple Health and Google Health report a metric for the same day, choose one source per
metric rather than averaging:
- **Sleep and overnight vitals:** prefer the device the user wore that night. With a Fitbit
  Air, that's Google Health.
- **Steps:** take the source with the larger count. The phone and the wearable often both
  count, and adding them double-counts.
- **Workouts:** remove duplicates by overlapping time.

Store which source each number came from. The app should be able to show it, and pacts need it
(see "Trust" below).

---

## Data model (Postgres, first cut)

```
users              id, created_at, display_name
profiles           user_id, birth_year, sex, currency, appearance, units
connections        user_id, source (google_health|apple_health), status, scopes,
                   refresh_token_encrypted, last_synced_at
daily_records      user_id, date, source, timezone,
                   steps, active_energy, avg_hr, max_hr, zone_minutes[5],
                   resting_hr, hrv, respiratory_rate, spo2, skin_temp, vo2max,
                   is_final (bool), updated_at
sleep_sessions     user_id, night_of, source, bedtime, wake_time, segments (jsonb)
activities         user_id, source, external_id, kind, start, duration, zones (jsonb), energy, distance
daily_summaries    user_id, date, recovery, strain, sleep_score, need, baseline (jsonb), computed_with (CorvaCore version)
experiments        id, user_id, title, design, start, length, outcomes[]
experiment_tags    experiment_id, evening
pacts              id, creator_id, goal, target, start, length, required_days, stake, currency,
                   mode (solo|head_to_head), recipient_kind, recipient_name, sick_day_pass, status
pact_participants  pact_id, user_id, accepted_at
pact_days          pact_id, user_id, date, value, status (met|missed|excused), settled_at
ledger_entries     pact_id, from_user, to_user|charity, amount, currency, state (owed|paid|waived)
invites            code, pact_id, inviter_id, expires_at, accepted_by
```

Notes:
- **Store daily totals, sleep sessions and workouts, not every heartbeat.** That's all
  `DailySummary` needs, and it keeps the most sensitive data off the server.
- **`computed_with`** records the `CorvaCore` version, so a score can be recomputed or explained
  later. It's the same idea as storing each day's baseline today.
- **Row-level security** means a user can only read their own rows. A pact partner can see only
  the `pact_days` for that pact, never raw health data.

---

## API sketch

```
POST /auth/apple, /auth/google           exchange identity token for a session
GET  /me  ·  PATCH /me/profile

GET  /connections                         source status, last sync
POST /connections/google/start            returns the Google consent URL
GET  /connections/google/callback         stores tokens, kicks off the first sync
DELETE /connections/{source}              disconnect and delete that source's data

GET  /days?from=&to=                      daily records + summaries (feeds RemoteHealthDataProvider)
POST /days/apple-health                   optional: upload HealthKit daily totals (for pacts and other devices)

GET/PUT/DELETE /experiments/{id}  ·  PUT /experiments/{id}/tags
GET/POST /pacts  ·  GET /pacts/{id}
POST /pacts/{id}/invite  ·  POST /invites/{code}/accept
GET  /pacts/{id}/days                     both participants' settled days

POST /me/export  ·  DELETE /me            data export and full deletion
```

The app keeps a local cache and syncs with these endpoints, so every screen still works
offline.

---

## Trust: making pacts hard to fake

Pacts only work if the numbers can't be faked.

- **Google Health:** the server pulls the data itself. The phone never reports it, so it's
  trustworthy.
- **Apple Health:** anyone can type steps into the Health app. For pacts:
  - count only samples from a wearable or the phone's own sensors;
  - drop samples HealthKit marks as entered by the user;
  - upload with the source attached, so the server can apply the same rule.
- **Settlement runs on the server:**
  - A day is **final** once the source has synced past midnight in the user's time zone,
    plus a grace period.
  - The server then writes `pact_days` using `CorvaCore.PactEvaluation`.
  - The phone shows "in progress" until then, as it does now.
- **Sick-day pass:** the server computes it from the same vitals, so it can't be claimed falsely.
- **Disputes:** a route for "my wearable died", so a dead battery doesn't turn into a debt.

---

## Order of work

Each phase ships something usable on its own. Durations assume one developer and are rough.

**Phase 0: foundations (about 1 week)**
- Move `Core/` into a `CorvaCore` Swift package.
- Add unit tests for `Scoring`, `PactEvaluation` and `ExperimentAnalysis` before anything
  depends on them remotely.
- Save experiments, tags, pacts and settings locally with SwiftData.
- *Done when:* everything survives a relaunch.

**Phase 1: Apple Health, on the phone (1–2 weeks)**
- Build `HealthKitProvider`: permissions screen, read queries, build `DailySummary`, and
  background delivery so data is fresh on open.
- Use `CompositeHealthDataProvider` with the mock as a fallback when a day is empty.
- *Done when:* the app shows your own real data with no backend at all.

**Phase 2: accounts and sync (1–2 weeks)**
- Set up Supabase: project, schema above, row-level security.
- Sign in with Apple and Google. Apple requires Sign in with Apple whenever another
  third-party sign-in is offered.
- Build `SyncService` for profile, experiments, tags and pacts.
- *Done when:* you can sign in on a second device and see the same Lab and Pacts.

**Phase 3: Google Health / Fitbit (2–3 weeks, plus Google's review time)**
- Build the server-side OAuth flow, opened from the app in an `ASWebAuthenticationSession`.
- Store refresh tokens encrypted.
- Build the sync worker, using push notifications if Google offers them and polling if not.
- Build `RemoteHealthDataProvider` and the source-merging rules.
- *Done when:* Fitbit Air data shows up in Today within minutes of syncing.
- **Start Google's app verification early:** health scopes are treated as sensitive, and the
  review can take weeks.

**Phase 4: social pacts, no money (about 2 weeks)**
- Invites by universal link.
- Acceptance before a head-to-head pact starts.
- Nightly settlement worker.
- Push notifications: "2 days left, no misses to spare", "Sam missed today".
- *Done when:* two real people can run a pact and both see verified dots.

**Phase 5: money (only after legal review)**
- Start with charity-only stakes (commitment contracts), through a payment provider.
- Add head-to-head payouts only if legal advice says they're not regulated betting in
  your markets.

**Phase 6: hardening (ongoing)**
- **Privacy:** privacy policy, data export and deletion.
- **Operations:** monitoring, rate limits, and backups with tested restores.

---

## Privacy and compliance checklist

- **UK GDPR:** health data is *special category* data. You need explicit consent, a data
  protection impact assessment, and a clear legal basis. Collect only what you need, encrypt it
  at rest, and give users a real delete button.
- **App Store:**
  - HealthKit data may not be used for advertising.
  - HealthKit data may not be stored in iCloud.
  - The app needs a privacy policy and accurate privacy labels.
- **Google:** health scopes need app verification, and possibly a security assessment, before
  public launch.
- **Data location:** choose a UK or EU region for the database if most users are there.

---

## Decisions for you

1. **Stack:** Supabase plus a Swift worker (recommended), all-Swift, or all-TypeScript?
2. **First data source:** Apple Health first (fastest to real data, no review) or Fitbit Air
   first (your main device, but waits on Google's review)?
3. **Money:** charity-only stakes to start, or wait for advice on head-to-head?
4. **Where scores are computed:** on the phone for display and on the server for pacts (the
   recommendation), or only on the server?
5. **Hosting region and budget:** this decides UK/EU data residency and which tiers to use.

Once these are settled, Phase 0 can start straight away. It doesn't depend on any of them.
