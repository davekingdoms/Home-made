-- Piggy banks (docs/spec/schema.md, 11; docs/spec/categorie.md, 11).
--
-- Personal or shared with chosen members. Whoever creates one becomes its
-- member; every member renames or archives it and adds or removes members.
-- Each member puts money aside from their own accounts: the members see how
-- much each one put, never the balances of the accounts.

create table public.piggy_banks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  name text not null
    constraint piggy_banks_name_not_empty check (char_length(btrim(name)) > 0),
  target_cents bigint
    constraint piggy_banks_target_positive check (target_cents > 0),
  created_by_member_id uuid not null references public.members (id),
  archived_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.piggy_banks is 'Piggy banks of the household, personal or shared.';

create index piggy_banks_household_id on public.piggy_banks (household_id);
create index piggy_banks_created_by_member_id on public.piggy_banks (created_by_member_id);

create trigger piggy_banks_touch_row
  before update on public.piggy_banks
  for each row execute function public.touch_row();

create table public.piggy_bank_members (
  piggy_bank_id uuid not null references public.piggy_banks (id),
  member_id uuid not null references public.members (id),
  primary key (piggy_bank_id, member_id)
);

comment on table public.piggy_bank_members is 'Members of a piggy bank.';

create index piggy_bank_members_member_id on public.piggy_bank_members (member_id);

create table public.piggy_bank_entries (
  id uuid primary key default gen_random_uuid(),
  piggy_bank_id uuid not null references public.piggy_banks (id),
  member_id uuid not null references public.members (id),
  account_id uuid references public.accounts (id),
  -- virtual: put aside on the same account; real: a movement of kind saving.
  kind text not null
    constraint piggy_bank_entries_kind check (kind in ('virtual', 'real')),
  transaction_id uuid references public.transactions (id),
  -- Negative: taken out of the piggy bank.
  amount_cents bigint not null
    constraint piggy_bank_entries_amount_not_zero check (amount_cents <> 0),
  entry_date date not null,
  deleted_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint piggy_bank_entries_transaction_by_kind
    check ((transaction_id is not null) = (kind = 'real'))
);

comment on table public.piggy_bank_entries is
  'Money put in or taken out of a piggy bank by a member, virtual or with a movement.';

create index piggy_bank_entries_piggy_bank_id on public.piggy_bank_entries (piggy_bank_id);
create index piggy_bank_entries_member_id on public.piggy_bank_entries (member_id);
create index piggy_bank_entries_account_id on public.piggy_bank_entries (account_id);
create index piggy_bank_entries_transaction_id on public.piggy_bank_entries (transaction_id);

create trigger piggy_bank_entries_touch_row
  before update on public.piggy_bank_entries
  for each row execute function public.touch_row();

-- True if the signed-in user is a member of the piggy bank. Security
-- definer: the policies of the three tables read the members without
-- their own policies.
create function public.is_piggy_bank_member(piggy_bank_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.piggy_bank_members pm
    where pm.piggy_bank_id = is_piggy_bank_member.piggy_bank_id
      and pm.member_id = (select public.current_member_id())
  )
$$;

comment on function public.is_piggy_bank_member(uuid) is
  'True if the signed-in user is a member of the piggy bank.';

revoke all on function public.is_piggy_bank_member(uuid) from public, anon;
grant execute on function public.is_piggy_bank_member(uuid) to authenticated;

-- Member ids: active members of the household of the piggy bank.

create function public.check_piggy_bank()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_active_member(new.created_by_member_id, new.household_id);
  return new;
end;
$$;

create trigger piggy_banks_check
  before insert or update of household_id, created_by_member_id on public.piggy_banks
  for each row execute function public.check_piggy_bank();

-- Whoever creates a piggy bank is its first member.
create function public.add_piggy_bank_creator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.piggy_bank_members (piggy_bank_id, member_id)
  values (new.id, new.created_by_member_id);
  return null;
end;
$$;

create trigger piggy_banks_add_creator
  after insert on public.piggy_banks
  for each row execute function public.add_piggy_bank_creator();

create function public.check_piggy_bank_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_active_member(
    new.member_id,
    (select p.household_id from public.piggy_banks p where p.id = new.piggy_bank_id)
  );
  return new;
end;
$$;

create trigger piggy_bank_members_check
  before insert or update on public.piggy_bank_members
  for each row execute function public.check_piggy_bank_member();

-- A deposit is of an active member of the household who is a member of the
-- piggy bank, on an account and with a movement of their own.
create function public.check_piggy_bank_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
    or (new.piggy_bank_id, new.member_id) is distinct from (old.piggy_bank_id, old.member_id)
  then
    perform public.check_active_member(
      new.member_id,
      (select p.household_id from public.piggy_banks p where p.id = new.piggy_bank_id)
    );
    if not exists (
      select 1 from public.piggy_bank_members pm
      where pm.piggy_bank_id = new.piggy_bank_id and pm.member_id = new.member_id
    ) then
      raise exception 'member_not_eligible';
    end if;
  end if;

  if new.account_id is not null and (
    select a.owner_member_id from public.accounts a where a.id = new.account_id
  ) is distinct from new.member_id then
    raise exception 'a deposit is on an account of the member'
      using errcode = 'check_violation';
  end if;

  if new.transaction_id is not null and (
    select t.paid_by_member_id from public.transactions t where t.id = new.transaction_id
  ) is distinct from new.member_id then
    raise exception 'a deposit is a movement of the member'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger piggy_bank_entries_check
  before insert or update on public.piggy_bank_entries
  for each row execute function public.check_piggy_bank_entry();

revoke all on function public.check_piggy_bank() from public, anon, authenticated;
revoke all on function public.add_piggy_bank_creator() from public, anon, authenticated;
revoke all on function public.check_piggy_bank_member() from public, anon, authenticated;
revoke all on function public.check_piggy_bank_entry() from public, anon, authenticated;

-- RLS: the members of a piggy bank see it, its members and its deposits
-- (the id of an account gives no access to the account).

alter table public.piggy_banks enable row level security;
alter table public.piggy_bank_members enable row level security;
alter table public.piggy_bank_entries enable row level security;

revoke all on table public.piggy_banks from anon, authenticated;
revoke all on table public.piggy_bank_members from anon, authenticated;
revoke all on table public.piggy_bank_entries from anon, authenticated;

grant select on table public.piggy_banks to authenticated;
grant insert (id, household_id, name, target_cents, created_by_member_id)
  on table public.piggy_banks to authenticated;
grant update (name, target_cents, archived_at) on table public.piggy_banks to authenticated;

create policy piggy_banks_select_member on public.piggy_banks
  for select to authenticated
  using (public.is_piggy_bank_member(id));

create policy piggy_banks_insert_member on public.piggy_banks
  for insert to authenticated
  with check (
    household_id = (select public.current_household_id())
    and created_by_member_id = (select public.current_member_id())
  );

create policy piggy_banks_update_member on public.piggy_banks
  for update to authenticated
  using (public.is_piggy_bank_member(id))
  with check (public.is_piggy_bank_member(id));

grant select, insert, delete on table public.piggy_bank_members to authenticated;

create policy piggy_bank_members_select_member on public.piggy_bank_members
  for select to authenticated
  using (public.is_piggy_bank_member(piggy_bank_id));

create policy piggy_bank_members_insert_member on public.piggy_bank_members
  for insert to authenticated
  with check (public.is_piggy_bank_member(piggy_bank_id));

create policy piggy_bank_members_delete_member on public.piggy_bank_members
  for delete to authenticated
  using (public.is_piggy_bank_member(piggy_bank_id));

-- A deposit only by the member, on their own accounts and movements.
grant select on table public.piggy_bank_entries to authenticated;
grant insert (
  id, piggy_bank_id, member_id, account_id, kind, transaction_id, amount_cents, entry_date
) on table public.piggy_bank_entries to authenticated;
grant update (account_id, amount_cents, entry_date, deleted_at)
  on table public.piggy_bank_entries to authenticated;

create policy piggy_bank_entries_select_member on public.piggy_bank_entries
  for select to authenticated
  using (public.is_piggy_bank_member(piggy_bank_id));

create policy piggy_bank_entries_insert_own on public.piggy_bank_entries
  for insert to authenticated
  with check (
    member_id = (select public.current_member_id())
    and public.is_piggy_bank_member(piggy_bank_id)
    and (account_id is null or public.is_account_owner(account_id))
    and (transaction_id is null or public.can_see_transaction(transaction_id))
  );

create policy piggy_bank_entries_update_own on public.piggy_bank_entries
  for update to authenticated
  using (member_id = (select public.current_member_id()))
  with check (
    member_id = (select public.current_member_id())
    and public.is_piggy_bank_member(piggy_bank_id)
    and (account_id is null or public.is_account_owner(account_id))
  );
