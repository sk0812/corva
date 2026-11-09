-- Head-to-head partners can't read each other's profiles, so a pact carries its creator's
-- display name for the friend who joins. Filled in when the pact is created.

alter table public.pacts
  add column creator_name text check (char_length(creator_name) <= 80);

create or replace function public.prepare_new_pact()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.status := case when new.mode = 'headToHead' then 'pending' else 'active' end;
  -- Runs as the creator, who can read their own profile.
  select left(p.display_name, 80) into new.creator_name
  from public.profiles p
  where p.id = new.creator_id;
  return new;
end;
$$;
