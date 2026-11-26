-- The start dates of A10 (docs/spec/schema.md, 3; docs/spec/accesso.md, A10).
--
-- invite_preview also returns the start date of the household: A10 shows it,
-- limits the start date of the new member to it and knows when the household
-- has not started yet. redeem_invite receives the start date the new member
-- chose, so the member is born with it and the default shares the trigger
-- creates hold from it: the join stays one call.
--
-- Both change their signature, so they are dropped and created again, with
-- the same permissions.

drop function public.invite_preview(text, text);

-- Before joining: name and start date of the household, who invites, active
-- members. Pass the code or the token.
create function public.invite_preview(code text default null, token text default null)
returns table (
  error text,
  household_name text,
  inviter_name text,
  member_names text[],
  household_start_date date
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lookup record;
begin
  select l.invite_id, l.error into v_lookup
  from public.lookup_invite(invite_preview.code, invite_preview.token) l;

  if v_lookup.error is not null then
    error := v_lookup.error;
    return next;
    return;
  end if;

  return query
  select
    null::text,
    h.name,
    ip.display_name,
    array(
      select mp.display_name
      from public.members am
      join public.profiles mp on mp.id = am.user_id
      where am.household_id = h.id
        and am.left_at is null
      order by am.joined_at, am.id
    ),
    h.start_date
  from public.invites i
  join public.households h on h.id = i.household_id
  join public.members im on im.id = i.created_by_member_id
  left join public.profiles ip on ip.id = im.user_id
  where i.id = v_lookup.invite_id;
end;
$$;

comment on function public.invite_preview(text, text) is
  'Preview of an invite, with the start date of the household. Errors in the error column: invite_invalid, invite_expired, invite_used, invite_revoked, too_many_attempts.';

drop function public.redeem_invite(text, text, bigint);

-- Joins the household of the invite. In a household that has not started
-- yet the new member starts with it, whatever start_date says. Otherwise the
-- member starts on start_date, from the start date of the household to
-- tomorrow (one day of tolerance for the time zones); without it, today.
create function public.redeem_invite(
  code text default null,
  token text default null,
  cash_opening_cents bigint default null,
  start_date date default null
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
  v_is_demo boolean;
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

  select p.is_demo into v_is_demo
  from public.profiles p
  where p.id = v_user_id;

  if not found then
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

  -- A household is all demo or all real.
  if exists (
    select 1
    from public.members m
    join public.profiles p on p.id = m.user_id
    where m.household_id = v_household.id
      and m.left_at is null
      and p.is_demo <> v_is_demo
  ) then
    error := 'invite_demo_mismatch';
    return next;
    return;
  end if;

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

  if v_household.start_date > current_date or redeem_invite.start_date is null then
    v_start_date := greatest(v_household.start_date, current_date);
  elsif redeem_invite.start_date < v_household.start_date
    or redeem_invite.start_date > current_date + 1
  then
    error := 'start_date_out_of_range';
    return next;
    return;
  else
    v_start_date := redeem_invite.start_date;
  end if;

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

comment on function public.redeem_invite(text, text, bigint, date) is
  'Joins the household of the invite from a start date. Errors in the error column: as invite_preview, plus no_profile, already_member, invite_demo_mismatch, household_full, start_date_out_of_range.';

revoke all on function public.invite_preview(text, text) from public, anon;
revoke all on function public.redeem_invite(text, text, bigint, date) from public, anon;
grant execute on function public.invite_preview(text, text) to authenticated;
grant execute on function public.redeem_invite(text, text, bigint, date) to authenticated;
