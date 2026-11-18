-- Invites to a household and attempts to use them (docs/spec/schema.md, 3;
-- docs/spec/accesso.md, A9 and A10).
--
-- The token of the link is saved only as its SHA-256 hash. The short code
-- has 8 characters from an alphabet without 0, O, 1, I, L. Invites are
-- created and used only with the functions of the household migration.

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  created_by_member_id uuid not null references public.members (id),
  -- "For whom", optional.
  label text,
  token_hash bytea not null unique
    constraint invites_token_hash_length check (octet_length(token_hash) = 32),
  -- Saved without the space and in capitals; shown in two groups of 4.
  code text not null unique
    constraint invites_code_format check (code ~ '^[2-9ABCDEFGHJKMNPQRSTUVWXYZ]{8}$'),
  expires_at timestamptz not null,
  used_by_member_id uuid references public.members (id),
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint invites_used_pair
    check ((used_by_member_id is null) = (used_at is null))
);

comment on table public.invites is
  'Single-use invites: hash of the link token, short code, expiry, use, revocation.';

create index invites_household_id on public.invites (household_id);
create index invites_created_by_member_id on public.invites (created_by_member_id);
create index invites_used_by_member_id on public.invites (used_by_member_id);

-- Attempts of invite_preview and redeem_invite: at most 10 an hour for each
-- account. No access from the app.
create table public.invite_attempts (
  user_id uuid not null references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now()
);

comment on table public.invite_attempts is
  'One row for each use of an invite code or token, for the hourly limit.';

create index invite_attempts_user_id_attempted_at
  on public.invite_attempts (user_id, attempted_at);

-- RLS

alter table public.invites enable row level security;
alter table public.invite_attempts enable row level security;

revoke all on table public.invites from anon, authenticated;
revoke all on table public.invite_attempts from anon, authenticated;

-- Active members of the household read its invites without token_hash
-- (column permissions) and revoke them.
grant select (
  id, household_id, created_by_member_id, label, code, expires_at,
  used_by_member_id, used_at, revoked_at, created_at
) on table public.invites to authenticated;
grant update (revoked_at) on table public.invites to authenticated;

create policy invites_select_household on public.invites
  for select to authenticated
  using (household_id = (select public.current_household_id()));

create policy invites_update_household on public.invites
  for update to authenticated
  using (household_id = (select public.current_household_id()))
  with check (household_id = (select public.current_household_id()));
