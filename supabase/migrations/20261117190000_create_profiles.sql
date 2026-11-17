-- Profile of each account (docs/spec/accesso.md, A3): the display name
-- and the version and date of the privacy notice the user has read.
--
-- First table of the project, made to try the whole flow (migration, RLS,
-- pgTAP, CI). Until the data schema is specified it is applied only in
-- local and in CI, never to the remote projects, so it can still change.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null
    constraint profiles_display_name_length
    check (char_length(btrim(display_name)) between 1 and 80),
  privacy_notice_version text,
  privacy_notice_read_at timestamptz,
  created_at timestamptz not null default now(),
  -- Version and date of the notice are saved together.
  constraint profiles_privacy_notice_pair
    check ((privacy_notice_version is null) = (privacy_notice_read_at is null))
);

comment on table public.profiles is
  'One row per account: display name and privacy notice read.';

alter table public.profiles enable row level security;

-- Only signed-in users reach the table, and nobody deletes a profile:
-- it goes with the account (on delete cascade).
revoke all on table public.profiles from anon, authenticated;
grant select, insert, update on table public.profiles to authenticated;

-- Each user sees and changes only their own profile. The other members of
-- the household will see the display name with the household tables.
create policy profiles_select_own on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_update_own on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
