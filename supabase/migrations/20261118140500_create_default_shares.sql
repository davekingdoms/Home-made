-- Default shares of the household (docs/spec/schema.md, 6; docs/spec/
-- accesso.md, A10).
--
-- Versions with a start date: the one valid at the date of an expense gives
-- its default weights. A new household gets a version with its creator; a
-- new member a version with equal weights for all the active members, valid
-- from their start date, which moves with it. A second version on the same
-- day replaces the first.

create table public.default_share_sets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  valid_from date not null,
  reason text not null
    constraint default_share_sets_reason
    check (reason in ('household_created', 'member_joined', 'manual')),
  -- The new member, for member_joined.
  member_id uuid references public.members (id),
  created_by_member_id uuid not null references public.members (id),
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint default_share_sets_member_by_reason
    check ((member_id is not null) = (reason = 'member_joined')),
  constraint default_share_sets_one_a_day unique (household_id, valid_from)
);

comment on table public.default_share_sets is
  'Versions of the default shares of a household, each valid from a date.';

create index default_share_sets_member_id on public.default_share_sets (member_id);
create index default_share_sets_created_by_member_id
  on public.default_share_sets (created_by_member_id);

create trigger default_share_sets_touch_row
  before update on public.default_share_sets
  for each row execute function public.touch_row();

create table public.default_share_weights (
  set_id uuid not null references public.default_share_sets (id) on delete cascade,
  member_id uuid not null references public.members (id),
  weight numeric(12, 4) not null
    constraint default_share_weights_weight_positive check (weight > 0),
  primary key (set_id, member_id)
);

comment on table public.default_share_weights is 'Weights of a version of the default shares.';

create index default_share_weights_member_id on public.default_share_weights (member_id);

-- Saves a version: a second one on the same day replaces the first.
-- weights = [{member_id, weight}]. Internal.
create function public.save_default_share_set(
  p_household_id uuid,
  p_valid_from date,
  p_reason text,
  p_member_id uuid,
  p_created_by_member_id uuid,
  p_weights jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_set_id uuid;
begin
  insert into public.default_share_sets as s (
    household_id, valid_from, reason, member_id, created_by_member_id
  )
  values (p_household_id, p_valid_from, p_reason, p_member_id, p_created_by_member_id)
  on conflict (household_id, valid_from) do update
    set reason = excluded.reason,
        member_id = excluded.member_id,
        created_by_member_id = excluded.created_by_member_id
  returning s.id into v_set_id;

  delete from public.default_share_weights w where w.set_id = v_set_id;

  insert into public.default_share_weights (set_id, member_id, weight)
  select v_set_id, (e ->> 'member_id')::uuid, (e ->> 'weight')::numeric
  from jsonb_array_elements(p_weights) as e;

  return v_set_id;
end;
$$;

revoke all on function public.save_default_share_set(uuid, date, text, uuid, uuid, jsonb)
  from public, anon, authenticated;

-- The first member creates the household version; every other member a
-- version with equal weights for all the active members.
create function public.create_default_share_set()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.members m
    where m.household_id = new.household_id and m.id <> new.id
  ) then
    perform public.save_default_share_set(
      new.household_id, new.start_date, 'member_joined', new.id, new.id,
      (select jsonb_agg(jsonb_build_object('member_id', m.id, 'weight', 1))
       from public.members m
       where m.household_id = new.household_id and m.left_at is null)
    );
  else
    perform public.save_default_share_set(
      new.household_id, new.start_date, 'household_created', null, new.id,
      jsonb_build_array(jsonb_build_object('member_id', new.id, 'weight', 1))
    );
  end if;
  return null;
end;
$$;

revoke all on function public.create_default_share_set() from public, anon, authenticated;

create trigger members_create_default_share_set
  after insert on public.members
  for each row execute function public.create_default_share_set();

-- The version born with a member moves with their start date, replacing a
-- version already on the new date. The member also gets weight 1 in the
-- later versions created before they joined, which could not include them.
create function public.move_default_share_set()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_set_id uuid;
begin
  select s.id into v_set_id
  from public.default_share_sets s
  where s.member_id = new.id and s.reason = 'member_joined';

  if v_set_id is not null then
    delete from public.default_share_sets s
    where s.household_id = new.household_id
      and s.valid_from = new.start_date
      and s.id <> v_set_id;

    update public.default_share_sets s
    set valid_from = new.start_date
    where s.id = v_set_id;
  end if;

  with added as (
    insert into public.default_share_weights (set_id, member_id, weight)
    select s.id, new.id, 1
    from public.default_share_sets s
    where s.household_id = new.household_id
      and s.valid_from > new.start_date
      and s.created_at < new.joined_at
      and not exists (
        select 1 from public.default_share_weights w
        where w.set_id = s.id and w.member_id = new.id
      )
    returning set_id
  )
  -- touch_row bumps the version of the changed versions.
  update public.default_share_sets s
  set updated_at = now()
  where s.id in (select a.set_id from added a);

  return null;
end;
$$;

revoke all on function public.move_default_share_set() from public, anon, authenticated;

create trigger members_move_default_share_set
  after update of start_date on public.members
  for each row
  when (new.start_date <> old.start_date)
  execute function public.move_default_share_set();

-- Default weights of the household of the caller valid at a date (the date
-- of the expense). Members who left or start after that date have no share,
-- so they are left out.
create function public.default_shares_at(on_date date)
returns table (member_id uuid, weight numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select w.member_id, w.weight
  from public.default_share_weights w
  join public.members m on m.id = w.member_id
  where w.set_id = (
      select s.id
      from public.default_share_sets s
      where s.household_id = (select public.current_household_id())
        and s.valid_from <= default_shares_at.on_date
      order by s.valid_from desc
      limit 1
    )
    and m.left_at is null
    and m.start_date <= default_shares_at.on_date
  order by m.joined_at, m.id
$$;

comment on function public.default_shares_at(date) is
  'Default weights of the household valid at a date, for the members who can have a share then.';

-- New version of the default shares from a date. weights = [{member_id, weight}].
create function public.set_default_shares(valid_from date, weights jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_id uuid := public.current_member_id();
  v_household_id uuid := public.current_household_id();
begin
  if v_member_id is null then
    raise exception 'not_member';
  end if;

  if set_default_shares.valid_from is null then
    raise exception 'a version has a start date' using errcode = 'check_violation';
  end if;

  if set_default_shares.weights is null
    or jsonb_typeof(set_default_shares.weights) <> 'array'
    or jsonb_array_length(set_default_shares.weights) = 0
  then
    raise exception 'no_members';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(set_default_shares.weights) as e
    left join public.members m on m.id = (e ->> 'member_id')::uuid
    where m.id is null
      or m.household_id <> v_household_id
      or m.left_at is not null
  ) then
    raise exception 'member_not_eligible';
  end if;

  return public.save_default_share_set(
    v_household_id, set_default_shares.valid_from, 'manual', null, v_member_id,
    set_default_shares.weights
  );
end;
$$;

comment on function public.set_default_shares(date, jsonb) is
  'New version of the default shares from a date; replaces one on the same day. Errors: not_member, no_members, member_not_eligible.';

revoke all on function public.default_shares_at(date) from public, anon;
revoke all on function public.set_default_shares(date, jsonb) from public, anon;
grant execute on function public.default_shares_at(date) to authenticated;
grant execute on function public.set_default_shares(date, jsonb) to authenticated;

-- RLS: the active members read the versions; writes only with the
-- functions and the triggers.

alter table public.default_share_sets enable row level security;
alter table public.default_share_weights enable row level security;

revoke all on table public.default_share_sets from anon, authenticated;
revoke all on table public.default_share_weights from anon, authenticated;

grant select on table public.default_share_sets to authenticated;
grant select on table public.default_share_weights to authenticated;

create policy default_share_sets_select_household on public.default_share_sets
  for select to authenticated
  using (household_id = (select public.current_household_id()));

create policy default_share_weights_select_household on public.default_share_weights
  for select to authenticated
  using (exists (select 1 from public.default_share_sets s where s.id = set_id));
