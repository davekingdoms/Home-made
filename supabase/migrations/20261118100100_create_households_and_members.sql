-- Households and their members (docs/spec/schema.md, 2 and 3), with the
-- support functions every policy uses to find the member of the user.
--
-- An account is in one household at a time. Households and members are
-- created only by the functions of the household migration; the app reads
-- them and renames its household.

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null
    constraint households_name_length
    check (char_length(btrim(name)) between 1 and 80),
  start_date date not null,
  -- Who created it: information only, no extra permission.
  created_by uuid references public.profiles (id) on delete set null,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.households is
  'A household: name and start date (the app counts movements from it).';

create index households_created_by on public.households (created_by);

create trigger households_touch_row
  before update on public.households
  for each row execute function public.touch_row();

create table public.members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  -- Nullable: with the account deleted the member stays as "Ex membro".
  -- In phase 1 every member has an account: the functions ensure it.
  user_id uuid references public.profiles (id) on delete set null,
  joined_at timestamptz not null default now(),
  start_date date not null,
  left_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.members is
  'Members of a household, with their own start date; left_at when they leave.';

-- One account in one household.
create unique index members_one_household_per_user
  on public.members (user_id)
  where left_at is null;

create index members_household_id on public.members (household_id);

create trigger members_touch_row
  before update on public.members
  for each row execute function public.touch_row();

-- The start date of a member is never before the one of the household.
create function public.check_member_start_date()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.start_date < (
    select h.start_date from public.households h where h.id = new.household_id
  ) then
    raise exception 'start_date_out_of_range';
  end if;
  return new;
end;
$$;

revoke all on function public.check_member_start_date()
  from public, anon, authenticated;

create trigger members_check_start_date
  before insert or update of start_date, household_id on public.members
  for each row execute function public.check_member_start_date();

-- Support functions (section 2). Security definer: they read members
-- without the policies, so the policies that call them do not recurse.

create function public.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.members m
  where m.user_id = (select auth.uid())
    and m.left_at is null
$$;

comment on function public.current_member_id() is
  'Active member of the signed-in user, or null.';

create function public.current_household_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.household_id
  from public.members m
  where m.user_id = (select auth.uid())
    and m.left_at is null
$$;

comment on function public.current_household_id() is
  'Household of the active member of the signed-in user, or null.';

create function public.is_household_member(household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.members m
    where m.household_id = is_household_member.household_id
      and m.user_id = (select auth.uid())
      and m.left_at is null
  )
$$;

comment on function public.is_household_member(uuid) is
  'True if the signed-in user is an active member of the household.';

-- Reads no table, so it needs no security definer. Active members and open
-- invites count; changing the limit takes a one-line migration.
create function public.max_household_members()
returns int
language sql
immutable
set search_path = ''
as $$
  select 8
$$;

comment on function public.max_household_members() is
  'Most members of a household, counting active members and open invites.';

revoke all on function public.current_member_id() from public, anon;
revoke all on function public.current_household_id() from public, anon;
revoke all on function public.is_household_member(uuid) from public, anon;
revoke all on function public.max_household_members() from public, anon;
grant execute on function public.current_member_id() to authenticated;
grant execute on function public.current_household_id() to authenticated;
grant execute on function public.is_household_member(uuid) to authenticated;
grant execute on function public.max_household_members() to authenticated;

-- RLS

alter table public.households enable row level security;
alter table public.members enable row level security;

revoke all on table public.households from anon, authenticated;
revoke all on table public.members from anon, authenticated;

-- Active members read their household and change only its name; the start
-- date changes with a future function (Impostazioni > Casa). Households are
-- created only by create_household.
grant select on table public.households to authenticated;
grant update (name) on table public.households to authenticated;

create policy households_select_member on public.households
  for select to authenticated
  using (id = (select public.current_household_id()));

create policy households_update_member on public.households
  for update to authenticated
  using (id = (select public.current_household_id()))
  with check (id = (select public.current_household_id()));

-- Active members read all the members of their household, also the ones
-- who left (shown as "Ex membro"). No direct writes.
grant select on table public.members to authenticated;

create policy members_select_household on public.members
  for select to authenticated
  using (household_id = (select public.current_household_id()));
