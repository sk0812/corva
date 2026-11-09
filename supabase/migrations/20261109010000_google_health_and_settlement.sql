-- Google Health data, and server-side pact settlement.
--
-- - google_connections: each user's Google tokens. Only the server (service role) can read
--   them; the app sees status through google_health_status().
-- - oauth_states: short-lived nonces linking a Google consent screen back to the user.
-- - daily_records: one row per user per day, normalised from Google Health by the
--   google-health Edge Function. The app builds recovery, strain and sleep from these.
-- - settle_pacts(): scores pact days from daily_records, excuses sick days, finishes
--   pacts and writes the ledger. Runs hourly with pg_cron, alongside an hourly sync.

-- Connections -----------------------------------------------------------------------------

create table public.google_connections (
  user_id uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null,
  access_token text,
  access_token_expires_at timestamptz,
  -- Google expires refresh tokens after 7 days while the OAuth app is in Testing.
  refresh_token_expires_at timestamptz,
  scopes text,
  connected_at timestamptz not null default now(),
  last_synced_at timestamptz,
  last_error text
);

alter table public.google_connections enable row level security;
revoke all on public.google_connections from anon, authenticated;

create table public.oauth_states (
  state text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.oauth_states enable row level security;
revoke all on public.oauth_states from anon, authenticated;

-- What the app may know about its own connection: never the tokens.
create function public.google_health_status()
returns table (
  connected boolean,
  connected_at timestamptz,
  last_synced_at timestamptz,
  last_error text,
  refresh_token_expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select true, c.connected_at, c.last_synced_at, c.last_error, c.refresh_token_expires_at
  from public.google_connections c
  where c.user_id = (select auth.uid());
$$;

revoke execute on function public.google_health_status() from public, anon;
grant execute on function public.google_health_status() to authenticated;

-- Daily records ---------------------------------------------------------------------------

create table public.daily_records (
  user_id uuid not null references auth.users (id) on delete cascade,
  -- The user's local calendar day. Sleep on this row is the night that ended this morning.
  date date not null,
  source text not null default 'google_health',
  steps integer,
  active_kcal double precision,
  hr_avg double precision,
  hr_max double precision,
  hr_min double precision,
  -- Seconds per Google heart-rate zone: {"LIGHT": s, "MODERATE": s, "VIGOROUS": s, "PEAK": s}.
  zone_seconds jsonb,
  resting_hr double precision,
  hrv double precision,
  respiratory_rate double precision,
  spo2 double precision,
  skin_temp double precision,
  vo2max double precision,
  -- Main sleep ending this morning: {start, end, stages: [{type, start, end}], minutes_asleep, ...}.
  sleep jsonb,
  sleep_seconds double precision,
  -- Bedtime of that sleep as minutes after 6 PM local, for bedtime pacts.
  bedtime_minutes double precision,
  -- [{type, name, start, end, kcal, distance_m, avg_hr}]
  exercises jsonb,
  exercise_seconds double precision,
  synced_at timestamptz not null default now(),
  primary key (user_id, date, source)
);

alter table public.daily_records enable row level security;

create policy "Owners can read their daily records"
  on public.daily_records for select to authenticated
  using ((select auth.uid()) = user_id);

-- Pact maths ------------------------------------------------------------------------------

-- Strain from Google zone seconds, matching the app's Scoring.strain: Google's four zones map
-- to Corva zones 2-5 (weights 2-5), and strain = 100 * (1 - e^(-load / 250)).
create function public.strain_from_zones(zones jsonb)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select case when zones is null then null else
    100 * (1 - exp(-(
      2 * coalesce((zones ->> 'LIGHT')::double precision, 0) +
      3 * coalesce((zones ->> 'MODERATE')::double precision, 0) +
      4 * coalesce((zones ->> 'VIGOROUS')::double precision, 0) +
      5 * coalesce((zones ->> 'PEAK')::double precision, 0)
    ) / 60 / 250))
  end;
$$;

-- A record's value for a pact goal, in the app's storage units.
create function public.pact_goal_value(goal text, rec public.daily_records)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select case goal
    when 'steps' then rec.steps::double precision
    when 'sleep' then rec.sleep_seconds
    when 'exercise' then rec.exercise_seconds
    when 'strain' then public.strain_from_zones(rec.zone_seconds)
    when 'bedtime' then rec.bedtime_minutes
  end;
$$;

-- Three or more vitals off in the direction illness pushes them, against the 30 days before.
-- Matches the app's DailySummary.isLikelyUnwell.
create function public.is_likely_unwell(target_user uuid, target_date date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with today as (
    select * from public.daily_records
    where user_id = target_user and date = target_date
    limit 1
  ),
  history as (
    select * from public.daily_records
    where user_id = target_user and date >= target_date - 30 and date < target_date
  ),
  stats as (
    select
      avg(hrv) as hrv_mean, stddev_samp(hrv) as hrv_sd, count(hrv) as hrv_n,
      avg(resting_hr) as rhr_mean, stddev_samp(resting_hr) as rhr_sd, count(resting_hr) as rhr_n,
      avg(respiratory_rate) as rr_mean, stddev_samp(respiratory_rate) as rr_sd, count(respiratory_rate) as rr_n,
      avg(spo2) as spo2_mean, stddev_samp(spo2) as spo2_sd, count(spo2) as spo2_n,
      avg(skin_temp) as temp_mean, stddev_samp(skin_temp) as temp_sd, count(skin_temp) as temp_n
    from history
  )
  select coalesce((
    (case when s.hrv_n >= 7 and t.hrv < s.hrv_mean - 1.5 * s.hrv_sd then 1 else 0 end) +
    (case when s.rhr_n >= 7 and t.resting_hr > s.rhr_mean + 1.5 * s.rhr_sd then 1 else 0 end) +
    (case when s.rr_n >= 7 and t.respiratory_rate > s.rr_mean + 1.5 * s.rr_sd then 1 else 0 end) +
    (case when s.spo2_n >= 7 and t.spo2 < s.spo2_mean - 1.5 * s.spo2_sd then 1 else 0 end) +
    (case when s.temp_n >= 7 and t.skin_temp > s.temp_mean + 1.5 * s.temp_sd then 1 else 0 end)
  ) >= 3, false)
  from today t cross join stats s;
$$;

revoke execute on function public.is_likely_unwell(uuid, date) from public, anon, authenticated;

-- Scores every pact day that can be scored, then finishes pacts whose outcome is decided.
--
-- - A met day settles as soon as the data shows it (steps only go up).
-- - A missed day waits a full day after its settling date, so late syncs can still land.
-- - A day with no data at all counts as missed after two days: the wearable is the referee.
create function public.settle_pacts()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.pacts%rowtype;
  member uuid;
  i integer;
  pact_day date;
  settle_on date;
  rec public.daily_records%rowtype;
  found_record boolean;
  goal_value double precision;
  is_met boolean;
begin
  for p in select * from public.pacts where status = 'active' loop
    for member in select pp.user_id from public.pact_participants pp where pp.pact_id = p.id loop
      for i in 0 .. p.length_days - 1 loop
        pact_day := p.start_date + i;
        settle_on := pact_day + case when p.goal in ('sleep', 'bedtime') then 1 else 0 end;
        continue when settle_on > current_date;
        continue when exists (
          select 1 from public.pact_days d
          where d.pact_id = p.id and d.user_id = member and d.day = pact_day
        );

        select * into rec from public.daily_records r
        where r.user_id = member and r.date = settle_on
        limit 1;
        found_record := found;
        goal_value := case when found_record then public.pact_goal_value(p.goal, rec) end;

        if goal_value is null then
          if settle_on < current_date - 2 then
            insert into public.pact_days (pact_id, user_id, day, value, status)
            values (p.id, member, pact_day, null, 'missed');
          end if;
          continue;
        end if;

        is_met := case when p.goal = 'bedtime' then goal_value <= p.target else goal_value >= p.target end;
        if is_met then
          insert into public.pact_days (pact_id, user_id, day, value, status)
          values (p.id, member, pact_day, goal_value, 'met');
        elsif settle_on < current_date - 1 then
          insert into public.pact_days (pact_id, user_id, day, value, status)
          values (
            p.id, member, pact_day, goal_value,
            case when p.sick_day_pass and public.is_likely_unwell(member, settle_on) then 'excused' else 'missed' end
          );
        end if;
      end loop;
    end loop;

    perform public.finish_pact_if_decided(p.id);
  end loop;
end;
$$;

revoke execute on function public.settle_pacts() from public, anon, authenticated;

-- Kept: met >= required. Broken: met + days left < required. Required drops by excused days.
-- Finishes the pact once every member's outcome is decided (or its last day has settled),
-- and records who owes whom.
create function public.finish_pact_if_decided(target_pact uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.pacts%rowtype;
  outcome record;
  outcomes jsonb := '{}'::jsonb;
  all_decided boolean := true;
  creator_outcome text;
  opponent uuid;
  opponent_outcome text;
begin
  select * into p from public.pacts where id = target_pact;
  if not found or p.status <> 'active' then return; end if;

  for outcome in
    select
      pp.user_id,
      count(*) filter (where d.status = 'met') as met,
      count(*) filter (where d.status = 'excused') as excused,
      count(d.day) as settled
    from public.pact_participants pp
    left join public.pact_days d on d.pact_id = pp.pact_id and d.user_id = pp.user_id
    where pp.pact_id = target_pact
    group by pp.user_id
  loop
    declare
      required integer := least(p.required_days, p.length_days - outcome.excused);
      remaining integer := p.length_days - outcome.settled;
      verdict text;
    begin
      verdict := case
        when outcome.met >= required then 'kept'
        when outcome.met + remaining < required then 'broken'
        else 'open'
      end;
      outcomes := outcomes || jsonb_build_object(outcome.user_id::text, verdict);
      if verdict = 'open' then all_decided := false; end if;
    end;
  end loop;

  -- Head to head waits for both outcomes; solo only needs the creator's.
  if not all_decided then return; end if;

  update public.pacts set status = 'finished' where id = target_pact;
  creator_outcome := outcomes ->> p.creator_id::text;

  if p.mode = 'solo' then
    if creator_outcome = 'broken' then
      insert into public.ledger_entries (pact_id, from_user, recipient_name, amount, currency)
      values (p.id, p.creator_id, p.recipient_name, p.stake, p.currency);
    end if;
  else
    select pp.user_id into opponent
    from public.pact_participants pp
    where pp.pact_id = p.id and pp.user_id <> p.creator_id
    limit 1;
    if opponent is null then return; end if;
    opponent_outcome := outcomes ->> opponent::text;
    if creator_outcome = 'broken' and opponent_outcome = 'kept' then
      insert into public.ledger_entries (pact_id, from_user, to_user, amount, currency)
      values (p.id, p.creator_id, opponent, p.stake, p.currency);
    elsif creator_outcome = 'kept' and opponent_outcome = 'broken' then
      insert into public.ledger_entries (pact_id, from_user, to_user, amount, currency)
      values (p.id, opponent, p.creator_id, p.stake, p.currency);
    end if;
  end if;
end;
$$;

revoke execute on function public.finish_pact_if_decided(uuid) from public, anon, authenticated;

-- Live progress for everyone in a pact: each member's value for the pact's goal on each
-- day, plus the settled status where there is one. Only the goal metric is shared, never
-- the rest of anyone's health data.
create function public.pact_progress(target_pact uuid)
returns table (user_id uuid, day date, value double precision, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p public.pacts%rowtype;
  offset_days integer;
begin
  if not private.is_pact_member(target_pact) then
    return;
  end if;
  select * into p from public.pacts where id = target_pact;
  offset_days := case when p.goal in ('sleep', 'bedtime') then 1 else 0 end;

  return query
  select pp.user_id, gs.day::date,
         public.pact_goal_value(p.goal, r),
         d.status
  from public.pact_participants pp
  cross join generate_series(p.start_date, p.start_date + p.length_days - 1, interval '1 day') as gs(day)
  left join public.daily_records r
    on r.user_id = pp.user_id and r.date = gs.day::date + offset_days
  left join public.pact_days d
    on d.pact_id = p.id and d.user_id = pp.user_id and d.day = gs.day::date
  where pp.pact_id = target_pact;
end;
$$;

revoke execute on function public.pact_progress(uuid) from public, anon;
grant execute on function public.pact_progress(uuid) to authenticated;

-- Scheduling ------------------------------------------------------------------------------

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- Settle pacts every hour, at half past.
select cron.schedule('corva-settle-pacts', '30 * * * *', $$ select public.settle_pacts(); $$);

-- Sync everyone's Google Health data every hour. The shared secret lives in Vault (created
-- outside migrations, so it's never in the repository); without it the function refuses.
select cron.schedule(
  'corva-google-health-sync',
  '10 * * * *',
  $$
  select net.http_post(
    url := 'https://buzvrepbqfvungvcqwjl.supabase.co/functions/v1/google-health/sync-all',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-corva-cron', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'corva_cron_secret'), '')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);
