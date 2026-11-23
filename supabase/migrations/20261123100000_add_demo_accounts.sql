-- Demo accounts, a development tool (docs/spec/accesso.md, section 12;
-- docs/spec/schema.md, 3).
--
-- They exist only in an environment whose Vault holds the secret
-- demo_accounts with the value enabled: put there by hand on dev, never on
-- prod, and no value in the repository. There, an account created as demo
-- deletes itself from the app with everything it owns, so the first start
-- can be tried again from the beginning. A household is all demo or all
-- real.

-- The switch: true only with the secret demo_accounts = enabled in Vault.
-- Internal: the app never calls it.
create function public.demo_accounts_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from vault.decrypted_secrets s
    where s.name = 'demo_accounts'
      and s.decrypted_secret = 'enabled'
  )
$$;

comment on function public.demo_accounts_enabled() is
  'Internal: true if the secret demo_accounts in Vault is enabled.';

revoke all on function public.demo_accounts_enabled() from public, anon, authenticated;

-- The flag of the account, set once when the profile is created.
alter table public.profiles
  add column is_demo boolean not null default false;

comment on column public.profiles.is_demo is
  'Demo account (development only): it can delete itself. Set at insert, never changed.';

-- A demo profile is created only with the switch on; the flag never changes,
-- so a real account never becomes demo and a demo one never becomes real.
-- Security definer: it reads the switch, which the app cannot call.
create function public.check_profile_demo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.is_demo then
      if not public.demo_accounts_enabled() then
        raise exception 'demo_disabled';
      end if;
    end if;
  elsif new.is_demo is distinct from old.is_demo then
    raise exception 'demo_immutable';
  end if;
  return new;
end;
$$;

revoke all on function public.check_profile_demo() from public, anon, authenticated;

create trigger profiles_check_demo
  before insert or update on public.profiles
  for each row execute function public.check_profile_demo();

-- A transaction deleted together with its lines has nothing left to check:
-- the foreign key keeps a line from outliving its transaction. Without this,
-- deleting a household would fail at commit with lines_sum_mismatch.
create or replace function public.check_lines_sum(transaction_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.transactions t where t.id = check_lines_sum.transaction_id
  ) then
    return;
  end if;

  if (
    select t.amount_cents from public.transactions t where t.id = check_lines_sum.transaction_id
  ) is distinct from (
    select coalesce(sum(l.amount_cents), 0)
    from public.transaction_lines l
    where l.transaction_id = check_lines_sum.transaction_id
      and l.deleted_at is null
  ) then
    raise exception 'lines_sum_mismatch' using errcode = 'check_violation';
  end if;
end;
$$;

-- As before, plus invite_demo_mismatch: whoever joins has the flag of the
-- active members of the household.
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

comment on function public.redeem_invite(text, text, bigint) is
  'Joins the household of the invite. Errors in the error column: as invite_preview, plus no_profile, already_member, invite_demo_mismatch, household_full.';

-- Deletes the demo account of the caller. In its household: with no other
-- active member, the household goes with all its data, in the order of the
-- foreign keys; otherwise the member leaves and its rows stay, as for any
-- member who left. Then the user goes from auth.users, and the cascades take
-- profile, settings, devices, PayPal emails and credentials (with their
-- secret in Vault).
create function public.delete_my_demo_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_is_demo boolean;
  v_member record;
  v_household_id uuid;
begin
  if not public.demo_accounts_enabled() then
    raise exception 'demo_disabled';
  end if;

  -- A second call after a lost answer: the account is already gone.
  if v_user_id is not null
    and not exists (select 1 from auth.users u where u.id = v_user_id)
  then
    return;
  end if;

  select p.is_demo into v_is_demo
  from public.profiles p
  where p.id = v_user_id
  for update;

  if not coalesce(v_is_demo, false) then
    raise exception 'not_demo';
  end if;

  for v_member in
    select m.id, m.household_id
    from public.members m
    where m.user_id = v_user_id
      and m.left_at is null
  loop
    v_household_id := v_member.household_id;

    -- Locked as redeem_invite and create_invite lock it: nobody joins while
    -- the other members are counted.
    perform 1 from public.households h where h.id = v_household_id for update;

    if exists (
      select 1
      from public.members m
      where m.household_id = v_household_id
        and m.left_at is null
        and m.id <> v_member.id
    ) then
      update public.members m
      set left_at = now()
      where m.id = v_member.id;
      continue;
    end if;

    -- Movements and raw rows point to each other: the raw rows let go first.
    update public.bank_raw_transactions r
    set transaction_id = null
    where r.account_id in (
      select a.id from public.accounts a where a.household_id = v_household_id
    );

    delete from public.advance_repayments ar
    where ar.line_id in (
        select l.id from public.transaction_lines l where l.household_id = v_household_id
      )
      or ar.advance_id in (
        select ad.id
        from public.advances ad
        join public.contacts c on c.id = ad.contact_id
        where c.household_id = v_household_id
      );

    delete from public.advances ad
    where ad.line_id in (
        select l.id from public.transaction_lines l where l.household_id = v_household_id
      )
      or ad.contact_id in (
        select c.id from public.contacts c where c.household_id = v_household_id
      );

    delete from public.line_tags lt
    where lt.line_id in (
      select l.id from public.transaction_lines l where l.household_id = v_household_id
    );

    delete from public.line_shares s where s.household_id = v_household_id;
    delete from public.transaction_lines l where l.household_id = v_household_id;
    delete from public.transfers t where t.household_id = v_household_id;
    delete from public.settlements s where s.household_id = v_household_id;

    delete from public.piggy_bank_entries e
    where e.piggy_bank_id in (
      select pb.id from public.piggy_banks pb where pb.household_id = v_household_id
    );
    delete from public.piggy_bank_members pm
    where pm.piggy_bank_id in (
      select pb.id from public.piggy_banks pb where pb.household_id = v_household_id
    );
    delete from public.piggy_banks pb where pb.household_id = v_household_id;

    delete from public.transactions t where t.household_id = v_household_id;

    delete from public.installment_plan_shares ps
    where ps.plan_id in (
      select ip.id from public.installment_plans ip where ip.household_id = v_household_id
    );
    delete from public.installment_plans ip where ip.household_id = v_household_id;

    delete from public.bank_raw_transactions r
    where r.account_id in (
      select a.id from public.accounts a where a.household_id = v_household_id
    );
    delete from public.account_balances b
    where b.account_id in (
      select a.id from public.accounts a where a.household_id = v_household_id
    );
    -- The rows of the accounts in sync_runs go in cascade.
    delete from public.accounts a where a.household_id = v_household_id;

    -- The rows of the connections in sync_runs go in cascade.
    delete from public.bank_connections c
    where c.member_id in (
      select m.id from public.members m where m.household_id = v_household_id
    );
    delete from public.bank_link_requests r
    where r.member_id in (
      select m.id from public.members m where m.household_id = v_household_id
    );

    delete from public.contacts c where c.household_id = v_household_id;
    delete from public.initial_balances b where b.household_id = v_household_id;
    -- The weights go in cascade.
    delete from public.default_share_sets s where s.household_id = v_household_id;
    delete from public.tags t where t.household_id = v_household_id;
    delete from public.categories c where c.household_id = v_household_id;
    delete from public.invites i where i.household_id = v_household_id;
    delete from public.members m where m.household_id = v_household_id;
    delete from public.households h where h.id = v_household_id;
  end loop;

  delete from auth.users u where u.id = v_user_id;
end;
$$;

comment on function public.delete_my_demo_account() is
  'Deletes the demo account of the caller and the households left without members, with all their data. Errors: demo_disabled, not_demo.';

revoke all on function public.delete_my_demo_account() from public, anon;
grant execute on function public.delete_my_demo_account() to authenticated;
