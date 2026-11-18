-- Functions of households and invites (docs/spec/schema.md, 3;
-- docs/spec/accesso.md, A8-A10).
--
-- The cash account, the default shares and the categories of a new member
-- come with the tables of the accounts and of the shares; cash_opening_cents
-- is already in the signatures and is used from then on.
--
-- invite_preview and redeem_invite do not raise their errors: they return
-- the error key in the error column. A raised error would roll back the row
-- of invite_attempts, and the failed attempts, the ones the hourly limit is
-- for, would never count.

-- Creates the household and its creator as first member, with the start date
-- of the household. A second call with the same id creates nothing.
create function public.create_household(
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
  values (create_household.id, v_user_id, create_household.start_date);

  return create_household.id;
end;
$$;

comment on function public.create_household(uuid, text, date, bigint) is
  'Creates a household with the caller as first member. Errors: no_profile, already_member, start_date_out_of_range.';

-- Creates an invite to the household of the caller. The token exists in
-- clear only in the answer: the table keeps its SHA-256 hash.
create function public.create_invite(label text default null)
returns table (invite_id uuid, token text, code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_id uuid := public.current_member_id();
  v_household_id uuid;
  v_alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_byte int;
begin
  if v_member_id is null then
    raise exception 'not_member';
  end if;

  -- The household is locked: invites and joins count the places one at a time.
  select h.id into v_household_id
  from public.households h
  join public.members m on m.household_id = h.id
  where m.id = v_member_id
  for update of h;

  -- Active members and open invites take a place.
  if (
    select count(*)
    from public.members m
    where m.household_id = v_household_id
      and m.left_at is null
  ) + (
    select count(*)
    from public.invites i
    where i.household_id = v_household_id
      and i.used_at is null
      and i.revoked_at is null
      and i.expires_at > now()
  ) >= public.max_household_members() then
    raise exception 'household_full';
  end if;

  -- 32 random bytes in base64url.
  token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  -- 8 characters from 31. Bytes from 248 (8 x 31) up are dropped, so every
  -- character has the same chance.
  loop
    code := '';
    while char_length(code) < 8 loop
      v_byte := get_byte(extensions.gen_random_bytes(1), 0);
      if v_byte < 248 then
        code := code || substr(v_alphabet, v_byte % 31 + 1, 1);
      end if;
    end loop;
    exit when not exists (
      select 1 from public.invites i where i.code = create_invite.code
    );
  end loop;

  invite_id := gen_random_uuid();

  insert into public.invites (
    id, household_id, created_by_member_id, label, token_hash, code, expires_at
  )
  values (
    invite_id,
    v_household_id,
    v_member_id,
    create_invite.label,
    sha256(convert_to(token, 'UTF8')),
    create_invite.code,
    now() + interval '7 days'
  );

  return next;
end;
$$;

comment on function public.create_invite(text) is
  'Creates an invite valid 7 days; returns its id, the token of the link and the code. Errors: not_member, household_full.';

-- Shared by invite_preview and redeem_invite, not callable from the app.
-- Counts the attempt, then finds the invite by token or by code (with or
-- without spaces, any case). Returns the invite, when found, and the error.
create function public.lookup_invite(
  code text,
  token text,
  out invite_id uuid,
  out error text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(regexp_replace(lookup_invite.code, '\s', '', 'g'));
  v_invite public.invites%rowtype;
begin
  -- One check at a time for each account.
  perform pg_advisory_xact_lock(hashtextextended('invite_attempts:' || v_user_id::text, 0));

  if (
    select count(*)
    from public.invite_attempts a
    where a.user_id = v_user_id
      and a.attempted_at > now() - interval '1 hour'
  ) >= 10 then
    error := 'too_many_attempts';
    return;
  end if;

  insert into public.invite_attempts (user_id) values (v_user_id);

  if lookup_invite.token is not null then
    select i.* into v_invite
    from public.invites i
    where i.token_hash = sha256(convert_to(lookup_invite.token, 'UTF8'));
  elsif v_code is not null then
    select i.* into v_invite
    from public.invites i
    where i.code = v_code;
  end if;

  if v_invite.id is null then
    error := 'invite_invalid';
    return;
  end if;

  invite_id := v_invite.id;

  if v_invite.revoked_at is not null then
    error := 'invite_revoked';
  elsif v_invite.used_at is not null then
    error := 'invite_used';
  elsif v_invite.expires_at <= now() then
    error := 'invite_expired';
  end if;
end;
$$;

comment on function public.lookup_invite(text, text) is
  'Internal: counts the attempt and finds the invite by token or code.';

-- Before joining: name of the household, who invites, active members.
-- Pass the code or the token.
create function public.invite_preview(code text default null, token text default null)
returns table (
  error text,
  household_name text,
  inviter_name text,
  member_names text[]
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
    )
  from public.invites i
  join public.households h on h.id = i.household_id
  join public.members im on im.id = i.created_by_member_id
  left join public.profiles ip on ip.id = im.user_id
  where i.id = v_lookup.invite_id;
end;
$$;

comment on function public.invite_preview(text, text) is
  'Preview of an invite. Errors in the error column: invite_invalid, invite_expired, invite_used, invite_revoked, too_many_attempts.';

-- Joins the household of the invite. The start date of the new member is
-- the later of the start date of the household and today.
create function public.redeem_invite(
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

  insert into public.members (household_id, user_id, start_date)
  values (v_household.id, v_user_id, greatest(v_household.start_date, current_date))
  returning members.id into v_member_id;

  update public.invites i
  set used_by_member_id = v_member_id,
      used_at = now()
  where i.id = v_invite.id;

  member_id := v_member_id;
  household_id := v_household.id;
  return next;
end;
$$;

comment on function public.redeem_invite(text, text, bigint) is
  'Joins the household of the invite. Errors in the error column: as invite_preview, plus no_profile, already_member, household_full.';

-- Moves the start date of the caller back, down to the one of the household.
-- Not allowed while the household has not started: the date stays the one
-- of the household.
create function public.set_my_start_date(start_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.members%rowtype;
  v_household_start date;
begin
  select m.* into v_member
  from public.members m
  where m.id = public.current_member_id()
  for update;

  if v_member.id is null then
    raise exception 'not_member';
  end if;

  select h.start_date into v_household_start
  from public.households h
  where h.id = v_member.household_id;

  if v_household_start > current_date then
    raise exception 'household_not_started';
  end if;

  if set_my_start_date.start_date is null
    or set_my_start_date.start_date < v_household_start
    or set_my_start_date.start_date > v_member.start_date
  then
    raise exception 'start_date_out_of_range';
  end if;

  if set_my_start_date.start_date < v_member.start_date then
    update public.members m
    set start_date = set_my_start_date.start_date
    where m.id = v_member.id;
  end if;
end;
$$;

comment on function public.set_my_start_date(date) is
  'Moves the start date of the caller back, down to the one of the household. Errors: not_member, household_not_started, start_date_out_of_range.';

-- Only signed-in users call them; lookup_invite only from the functions above.
revoke all on function public.create_household(uuid, text, date, bigint) from public, anon;
revoke all on function public.create_invite(text) from public, anon;
revoke all on function public.lookup_invite(text, text) from public, anon, authenticated;
revoke all on function public.invite_preview(text, text) from public, anon;
revoke all on function public.redeem_invite(text, text, bigint) from public, anon;
revoke all on function public.set_my_start_date(date) from public, anon;
grant execute on function public.create_household(uuid, text, date, bigint) to authenticated;
grant execute on function public.create_invite(text) to authenticated;
grant execute on function public.invite_preview(text, text) to authenticated;
grant execute on function public.redeem_invite(text, text, bigint) to authenticated;
grant execute on function public.set_my_start_date(date) to authenticated;
