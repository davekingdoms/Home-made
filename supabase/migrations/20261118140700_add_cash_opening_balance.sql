-- Opening balance of the cash account at creation and join
-- (docs/spec/schema.md, 3 and 4; docs/spec/accesso.md, 10).
--
-- The triggers of the members now create the cash account, the default
-- shares and (for a new household) the categories. If the start date of the
-- new member is today, cash_opening_cents becomes the opening balance of
-- their cash account; otherwise it is asked later, with its date.

create or replace function public.create_household(
  id uuid,
  name text,
  start_date date,
  cash_opening_cents bigint default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_member_id uuid;
begin
  if not exists (select 1 from public.profiles p where p.id = v_user_id) then
    raise exception 'no_profile';
  end if;

  if exists (
    select 1
    from public.members m
    where m.household_id = create_household.id
      and m.user_id = v_user_id
      and m.left_at is null
  ) then
    return create_household.id;
  end if;

  if public.current_member_id() is not null then
    raise exception 'already_member';
  end if;

  -- From 90 days before today to 12 months after, with one day of tolerance
  -- for the time zones.
  if create_household.start_date is null
    or create_household.start_date < current_date - 91
    or create_household.start_date > (current_date + interval '12 months')::date + 1
  then
    raise exception 'start_date_out_of_range';
  end if;

  insert into public.households (id, name, start_date, created_by)
  values (
    create_household.id,
    create_household.name,
    create_household.start_date,
    v_user_id
  );

  insert into public.members (household_id, user_id, start_date)
  values (create_household.id, v_user_id, create_household.start_date)
  returning members.id into v_member_id;

  if create_household.cash_opening_cents is not null
    and create_household.start_date = current_date
  then
    update public.accounts a
    set opening_balance_cents = create_household.cash_opening_cents
    where a.owner_member_id = v_member_id
      and a.kind = 'cash';
  end if;

  return create_household.id;
end;
$$;

create or replace function public.redeem_invite(
  code text default null,
  token text default null,
  cash_opening_cents bigint default null
)
returns table (error text, member_id uuid, household_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_lookup record;
  v_invite public.invites%rowtype;
  v_household public.households%rowtype;
  v_member_id uuid;
  v_start_date date;
begin
  select l.invite_id, l.error into v_lookup
  from public.lookup_invite(redeem_invite.code, redeem_invite.token) l;

  -- A second call after a lost answer: the invite was used by this account.
  if v_lookup.error = 'invite_used' then
    select m.id, m.household_id into member_id, household_id
    from public.invites i
    join public.members m on m.id = i.used_by_member_id
    where i.id = v_lookup.invite_id
      and m.user_id = v_user_id
      and m.left_at is null;
    if found then
      return next;
      return;
    end if;
  end if;

  if v_lookup.error is not null then
    error := v_lookup.error;
    return next;
    return;
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_user_id) then
    error := 'no_profile';
    return next;
    return;
  end if;

  if public.current_member_id() is not null then
    error := 'already_member';
    return next;
    return;
  end if;

  -- Invite and household locked, then the invite checked again.
  select i.* into v_invite
  from public.invites i
  where i.id = v_lookup.invite_id
  for update;

  if v_invite.revoked_at is not null then
    error := 'invite_revoked';
  elsif v_invite.used_at is not null then
    error := 'invite_used';
  elsif v_invite.expires_at <= now() then
    error := 'invite_expired';
  end if;

  if error is not null then
    return next;
    return;
  end if;

  select h.* into v_household
  from public.households h
  where h.id = v_invite.household_id
  for update;

  -- The invite already holds a place: only the active members count here.
  if (
    select count(*)
    from public.members m
    where m.household_id = v_household.id
      and m.left_at is null
  ) >= public.max_household_members() then
    error := 'household_full';
    return next;
    return;
  end if;

  v_start_date := greatest(v_household.start_date, current_date);

  insert into public.members (household_id, user_id, start_date)
  values (v_household.id, v_user_id, v_start_date)
  returning members.id into v_member_id;

  if redeem_invite.cash_opening_cents is not null and v_start_date = current_date then
    update public.accounts a
    set opening_balance_cents = redeem_invite.cash_opening_cents
    where a.owner_member_id = v_member_id
      and a.kind = 'cash';
  end if;

  update public.invites i
  set used_by_member_id = v_member_id,
      used_at = now()
  where i.id = v_invite.id;

  member_id := v_member_id;
  household_id := v_household.id;
  return next;
end;
$$;
