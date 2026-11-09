-- Corva: initial schema.
--
-- What has to sync between devices and, for pacts, between people:
--   profiles · experiments and their tags · pacts, participants, settled days, invites · ledger
-- Health data tables come in a later migration, alongside the Google Health sync.
--
-- Every table has row-level security on:
-- - Users only see their own rows.
-- - A pact partner sees that pact's settled days, never anyone's raw health data.
-- - Settled pact days and ledger entries are written only by the server (service role, which
--   bypasses RLS), so a phone can never mark its own day as met.
-- - Pacts can't be edited after creation. Status changes only through the functions below or
--   the server.
--
-- Text values match the app's Swift raw values (e.g. 'headToHead', 'restingHeartRate').

-- Helpers --------------------------------------------------------------------------------

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Profiles -------------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),
  birth_year integer check (birth_year between 1900 and 2100),
  sex text not null default 'notSet' check (sex in ('notSet', 'female', 'male')),
  currency text not null default 'GBP' check (currency in ('GBP', 'USD', 'EUR')),
  appearance text not null default 'system' check (appearance in ('system', 'light', 'dark')),
  temperature_unit text not null default 'celsius' check (temperature_unit in ('celsius', 'fahrenheit')),
  distance_unit text not null default 'kilometers' check (distance_unit in ('kilometers', 'miles')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Owners can read their profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Owners can update their profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- A profile row appears as soon as someone signs up, named from their sign-in provider.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'), 80));
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Experiments ----------------------------------------------------------------------------

create table public.experiments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  design text not null check (design in ('beforeAfter', 'onOff')),
  -- The first evening of the experiment.
  start_date date not null,
  length_days integer not null check (length_days between 1 and 365),
  outcomes text[] not null default '{}' check (
    outcomes <@ array['recovery', 'strain', 'sleep', 'hrv', 'restingHeartRate',
                      'respiratoryRate', 'bloodOxygen', 'skinTemperature']
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Soft delete, so other devices learn about deletions when they sync.
  deleted_at timestamptz
);

create index experiments_user_updated on public.experiments (user_id, updated_at);

alter table public.experiments enable row level security;

create policy "Owners manage their experiments"
  on public.experiments for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create trigger experiments_set_updated_at
  before update on public.experiments
  for each row execute function public.set_updated_at();

create table public.experiment_tags (
  experiment_id uuid not null references public.experiments (id) on delete cascade,
  evening date not null,
  created_at timestamptz not null default now(),
  primary key (experiment_id, evening)
);

alter table public.experiment_tags enable row level security;

create policy "Owners manage their experiment tags"
  on public.experiment_tags for all to authenticated
  using (exists (
    select 1 from public.experiments e
    where e.id = experiment_id and e.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.experiments e
    where e.id = experiment_id and e.user_id = (select auth.uid())
  ));

-- Pacts ----------------------------------------------------------------------------------

create table public.pacts (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  goal text not null check (goal in ('steps', 'sleep', 'exercise', 'strain', 'bedtime')),
  -- Storage units match the app: steps; seconds; seconds; strain; minutes after 6 PM.
  target double precision not null,
  start_date date not null,
  length_days integer not null check (length_days between 1 and 90),
  required_days integer not null,
  -- Whole units of currency.
  stake integer not null check (stake between 0 and 1000),
  currency text not null check (currency in ('GBP', 'USD', 'EUR')),
  mode text not null check (mode in ('solo', 'headToHead')),
  -- Solo pacts: who gets the stake on a miss.
  recipient_kind text check (recipient_kind in ('friend', 'charity')),
  recipient_name text check (char_length(recipient_name) <= 80),
  -- Head-to-head pacts: the friend's name as typed, until they accept and join.
  opponent_name text check (char_length(opponent_name) <= 80),
  sick_day_pass boolean not null default true,
  -- Set by triggers and functions, never by the app directly.
  status text not null default 'active' check (status in ('pending', 'active', 'finished', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (required_days between 1 and length_days),
  check ((mode = 'solo') = (recipient_kind is not null))
);

create table public.pact_participants (
  pact_id uuid not null references public.pacts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('creator', 'opponent')),
  joined_at timestamptz not null default now(),
  primary key (pact_id, user_id)
);

create index pact_participants_user on public.pact_participants (user_id);

-- Membership check used by policies. Security definer so policies on pacts and participants
-- don't recurse into each other.
create function public.is_pact_member(target_pact uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.pact_participants p
    where p.pact_id = target_pact and p.user_id = (select auth.uid())
  );
$$;

alter table public.pacts enable row level security;
alter table public.pact_participants enable row level security;

create policy "Members can read their pacts"
  on public.pacts for select to authenticated
  using (creator_id = (select auth.uid()) or public.is_pact_member(id));

create policy "Anyone signed in can create a pact as themselves"
  on public.pacts for insert to authenticated
  with check (creator_id = (select auth.uid()));

-- A head-to-head pact can be withdrawn until the friend accepts. Nothing else is editable.
create policy "Creators can delete pending pacts"
  on public.pacts for delete to authenticated
  using (creator_id = (select auth.uid()) and status = 'pending');

create policy "Members can see who is in their pacts"
  on public.pact_participants for select to authenticated
  using (public.is_pact_member(pact_id));

create trigger pacts_set_updated_at
  before update on public.pacts
  for each row execute function public.set_updated_at();

-- Solo pacts start straight away; head-to-head pacts wait for the friend.
create function public.prepare_new_pact()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.status := case when new.mode = 'headToHead' then 'pending' else 'active' end;
  return new;
end;
$$;

create trigger pacts_prepare
  before insert on public.pacts
  for each row execute function public.prepare_new_pact();

-- The creator is always the first participant.
create function public.add_pact_creator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.pact_participants (pact_id, user_id, role)
  values (new.id, new.creator_id, 'creator');
  return new;
end;
$$;

revoke execute on function public.add_pact_creator() from public, anon, authenticated;

create trigger pacts_add_creator
  after insert on public.pacts
  for each row execute function public.add_pact_creator();

-- Settled days, written by the server's settlement job from source data.
create table public.pact_days (
  pact_id uuid not null references public.pacts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  value double precision,
  status text not null check (status in ('met', 'missed', 'excused')),
  settled_at timestamptz not null default now(),
  primary key (pact_id, user_id, day)
);

create index pact_days_user on public.pact_days (user_id);

alter table public.pact_days enable row level security;

create policy "Members can read settled days"
  on public.pact_days for select to authenticated
  using (public.is_pact_member(pact_id));

-- Invites --------------------------------------------------------------------------------

create table public.pact_invites (
  code text primary key default substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
  pact_id uuid not null unique references public.pacts (id) on delete cascade,
  inviter_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_by uuid references auth.users (id) on delete set null,
  accepted_at timestamptz
);

alter table public.pact_invites enable row level security;

create policy "Inviters can read their invites"
  on public.pact_invites for select to authenticated
  using (inviter_id = (select auth.uid()));

create policy "Creators can invite to their pending head-to-head pacts"
  on public.pact_invites for insert to authenticated
  with check (
    inviter_id = (select auth.uid())
    and exists (
      select 1 from public.pacts p
      where p.id = pact_id
        and p.creator_id = (select auth.uid())
        and p.mode = 'headToHead'
        and p.status = 'pending'
    )
  );

-- What an invite link shows before accepting: the terms and who sent it.
create function public.preview_pact_invite(invite_code text)
returns table (
  pact_id uuid,
  goal text,
  target double precision,
  start_date date,
  length_days integer,
  required_days integer,
  stake integer,
  currency text,
  sick_day_pass boolean,
  inviter_name text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.goal, p.target, p.start_date, p.length_days, p.required_days,
         p.stake, p.currency, p.sick_day_pass, pr.display_name, i.expires_at
  from public.pact_invites i
  join public.pacts p on p.id = i.pact_id
  left join public.profiles pr on pr.id = i.inviter_id
  where i.code = invite_code
    and i.accepted_at is null
    and i.expires_at > now()
    and p.status = 'pending';
$$;

revoke execute on function public.preview_pact_invite(text) from public, anon;
grant execute on function public.preview_pact_invite(text) to authenticated;

-- Accepting joins the pact and starts it.
create function public.accept_pact_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite public.pact_invites%rowtype;
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Sign in to accept a pact';
  end if;

  select * into invite from public.pact_invites where code = invite_code for update;
  if not found then
    raise exception 'Invite not found';
  end if;
  if invite.accepted_at is not null then
    raise exception 'This invite has already been used';
  end if;
  if invite.expires_at < now() then
    raise exception 'This invite has expired';
  end if;
  if invite.inviter_id = me then
    raise exception 'You can''t accept your own invite';
  end if;

  insert into public.pact_participants (pact_id, user_id, role)
  values (invite.pact_id, me, 'opponent');

  update public.pact_invites
  set accepted_by = me, accepted_at = now()
  where code = invite_code;

  update public.pacts
  set status = 'active'
  where id = invite.pact_id and status = 'pending';

  return invite.pact_id;
end;
$$;

revoke execute on function public.accept_pact_invite(text) from public, anon;
grant execute on function public.accept_pact_invite(text) to authenticated;

-- Ledger ---------------------------------------------------------------------------------

-- Who owes whom after a pact settles. Written by the server; no money moves yet.
create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  pact_id uuid not null references public.pacts (id) on delete cascade,
  from_user uuid not null references auth.users (id) on delete cascade,
  -- A Corva user, or a name (a friend not on Corva, or a charity).
  to_user uuid references auth.users (id) on delete set null,
  recipient_name text check (char_length(recipient_name) <= 80),
  amount integer not null check (amount >= 0),
  currency text not null check (currency in ('GBP', 'USD', 'EUR')),
  state text not null default 'owed' check (state in ('owed', 'paid', 'waived')),
  created_at timestamptz not null default now(),
  check (to_user is not null or recipient_name is not null)
);

create index ledger_entries_from on public.ledger_entries (from_user);
create index ledger_entries_to on public.ledger_entries (to_user);

alter table public.ledger_entries enable row level security;

create policy "Payers and payees can read their entries"
  on public.ledger_entries for select to authenticated
  using ((select auth.uid()) in (from_user, to_user));
