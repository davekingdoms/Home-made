-- Devices of an account (docs/spec/schema.md, 3).
--
-- The id is generated on the device at the first launch. The location for
-- the weather is never saved here nor anywhere else on the server.

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null
    constraint devices_platform check (platform in ('android', 'ios')),
  -- Model, for the list of devices.
  name text,
  -- Arrives with the push notifications.
  fcm_token text,
  -- Wins over the preferences of the account for the same keys.
  preferences jsonb not null default '{}'
    constraint devices_preferences_object
    check (jsonb_typeof(preferences) = 'object'),
  last_seen_at timestamptz not null default now(),
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.devices is
  'Devices of an account: platform, model, push token, preferences.';

create index devices_user_id on public.devices (user_id);

create trigger devices_touch_row
  before update on public.devices
  for each row execute function public.touch_row();

-- RLS: everything, only the owner.
alter table public.devices enable row level security;

revoke all on table public.devices from anon, authenticated;
grant select, insert, update, delete on table public.devices to authenticated;

create policy devices_all_own on public.devices
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
