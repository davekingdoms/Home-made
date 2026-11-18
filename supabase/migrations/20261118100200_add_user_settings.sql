-- Profiles as the public card of the account in the household, and the
-- private settings of the account (docs/spec/schema.md, 3).
--
-- The privacy notice moves from profiles to user_settings: the other
-- members of the household now read the profile.

alter table public.profiles
  add column avatar_url text,
  add column paypal_me text
    constraint profiles_paypal_me_format
    check (paypal_me ~ '^[A-Za-z0-9]{1,20}$'),
  add column version int not null default 1,
  add column updated_at timestamptz not null default now();

comment on table public.profiles is
  'One row per account: name, photo and PayPal.Me, seen by the household.';
comment on column public.profiles.avatar_url is 'Photo of the Google account.';
comment on column public.profiles.paypal_me is
  'PayPal.Me name: 1 to 20 letters and digits (to check with PayPal.Me).';

create trigger profiles_touch_row
  before update on public.profiles
  for each row execute function public.touch_row();

create table public.user_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  privacy_notice_version text,
  privacy_notice_read_at timestamptz,
  -- Own income lines visible to the other members.
  show_income boolean not null default true,
  preferences jsonb not null default '{}'
    constraint user_settings_preferences_object
    check (jsonb_typeof(preferences) = 'object'),
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Version and date of the notice are saved together.
  constraint user_settings_privacy_notice_pair
    check ((privacy_notice_version is null) = (privacy_notice_read_at is null))
);

comment on table public.user_settings is
  'Private settings of the account: privacy notice read, income visibility, preferences.';

create trigger user_settings_touch_row
  before update on public.user_settings
  for each row execute function public.touch_row();

-- The notice already read moves with the profile.
insert into public.user_settings (user_id, privacy_notice_version, privacy_notice_read_at)
select p.id, p.privacy_notice_version, p.privacy_notice_read_at
from public.profiles p;

alter table public.profiles
  drop constraint profiles_privacy_notice_pair,
  drop column privacy_notice_version,
  drop column privacy_notice_read_at;

-- RLS of profiles: the owner, and the active members of the same household
-- if the profile is of an active member (who left shows as "Ex membro").
-- Insert and update stay with the owner; no delete (it goes with the account).
drop policy profiles_select_own on public.profiles;

create policy profiles_select_household on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.members m
      where m.user_id = profiles.id
        and m.left_at is null
        and m.household_id = (select public.current_household_id())
    )
  );

-- RLS of user_settings: everything, only the owner. can_see_line reads
-- show_income as security definer.
alter table public.user_settings enable row level security;

revoke all on table public.user_settings from anon, authenticated;
grant select, insert, update, delete on table public.user_settings to authenticated;

create policy user_settings_all_own on public.user_settings
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
