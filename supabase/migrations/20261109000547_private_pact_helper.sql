-- Move the pact membership helper out of the API.
--
-- `public.is_pact_member` only exists for row-level security policies, but anything in the
-- `public` schema is callable through the REST API (`/rest/v1/rpc/...`). Supabase's security
-- advisor flagged it. The `private` schema isn't exposed by the API, and policies can still
-- call functions in it.

create schema if not exists private;
grant usage on schema private to authenticated;

create function private.is_pact_member(target_pact uuid)
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

revoke execute on function private.is_pact_member(uuid) from public, anon;
grant execute on function private.is_pact_member(uuid) to authenticated;

alter policy "Members can read their pacts" on public.pacts
  using (creator_id = (select auth.uid()) or private.is_pact_member(id));

alter policy "Members can see who is in their pacts" on public.pact_participants
  using (private.is_pact_member(pact_id));

alter policy "Members can read settled days" on public.pact_days
  using (private.is_pact_member(pact_id));

drop function public.is_pact_member(uuid);
