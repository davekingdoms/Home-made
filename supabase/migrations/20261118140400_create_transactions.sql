-- Transactions, lines, shares, tags of the lines and transfers
-- (docs/spec/schema.md, 5, 6, 7 and 9).
--
-- A transaction belongs to the owner of its account; it is split into lines,
-- each with a kind, a category and the shares of the members. Who is only
-- involved in a line (paid it or has a share) sees the line, never the
-- transaction. The sums are checked at the end of the database transaction
-- (deferred constraint triggers), so the functions can change several rows.

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  -- Null only for a manual movement entered for a member without account.
  account_id uuid references public.accounts (id),
  source text not null
    constraint transactions_source check (source in ('bank', 'manual')),
  raw_id uuid unique references public.bank_raw_transactions (id),
  -- Who paid (or received, for an income): one only.
  paid_by_member_id uuid not null references public.members (id),
  -- Who entered it; null for the imported ones.
  entered_by_member_id uuid references public.members (id),
  movement_date date not null,
  booking_date date,
  booking_status text not null default 'booked'
    constraint transactions_booking_status check (booking_status in ('booked', 'pending')),
  amount_cents bigint not null
    constraint transactions_amount_not_zero check (amount_cents <> 0),
  currency char(3) not null
    constraint transactions_currency_format check (currency ~ '^[A-Z]{3}$'),
  original_amount_cents bigint,
  original_currency char(3)
    constraint transactions_original_currency_format check (original_currency ~ '^[A-Z]{3}$'),
  exchange_rate numeric,
  -- Text of the bank.
  description text,
  counterparty text,
  -- PayPal email of the counterparty, to recognise the settlements.
  counterparty_email text,
  bank_code text,
  installment_plan_id uuid references public.installment_plans (id),
  deleted_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transactions_account_for_bank
    check (account_id is not null or source = 'manual'),
  constraint transactions_raw_for_bank
    check (raw_id is null or source = 'bank'),
  constraint transactions_entered_by_for_manual
    check ((entered_by_member_id is not null) = (source = 'manual')),
  constraint transactions_deleted_for_manual
    check (deleted_at is null or source = 'manual')
);

comment on table public.transactions is
  'Movements of an account (from the bank or manual), with sign; split into lines.';

create index transactions_account_id on public.transactions (account_id);
create index transactions_paid_by_member_id on public.transactions (paid_by_member_id);
create index transactions_entered_by_member_id on public.transactions (entered_by_member_id);
create index transactions_installment_plan_id on public.transactions (installment_plan_id);

create trigger transactions_touch_row
  before update on public.transactions
  for each row execute function public.touch_row();

alter table public.bank_raw_transactions
  add constraint bank_raw_transactions_transaction_id_fkey
  foreign key (transaction_id) references public.transactions (id);

create index bank_raw_transactions_transaction_id
  on public.bank_raw_transactions (transaction_id);

create table public.transaction_lines (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.transactions (id),
  household_id uuid not null references public.households (id),
  position smallint not null default 1,
  -- Same sign as the transaction.
  amount_cents bigint not null,
  -- Null: to classify.
  kind text
    constraint transaction_lines_kind
    check (kind in ('expense', 'income', 'saving', 'transfer', 'settlement', 'advance', 'refund')),
  category_id uuid references public.categories (id),
  excluded_from_budget boolean not null default false,
  -- Default from the category, can be changed.
  deductible_730 boolean not null default false,
  -- Copies of the transaction, so who is involved sees the line without
  -- reading the transaction.
  movement_date date not null,
  counterparty text,
  paid_by_member_id uuid not null references public.members (id),
  transfer_id uuid,
  -- Foreign key with the settlements.
  settlement_id uuid,
  installment_plan_id uuid references public.installment_plans (id),
  deleted_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transaction_lines_transfer_kind
    check (transfer_id is null or kind = 'transfer')
);

comment on table public.transaction_lines is
  'Lines of a transaction: amount, kind, category and the copies seen by who is involved.';

create index transaction_lines_transaction_id on public.transaction_lines (transaction_id);
create index transaction_lines_paid_by_member_id on public.transaction_lines (paid_by_member_id);
create index transaction_lines_category_id on public.transaction_lines (category_id);
create index transaction_lines_transfer_id on public.transaction_lines (transfer_id);
create index transaction_lines_installment_plan_id on public.transaction_lines (installment_plan_id);
create index transaction_lines_household_income
  on public.transaction_lines (household_id, movement_date)
  where kind = 'income';

create trigger transaction_lines_touch_row
  before update on public.transaction_lines
  for each row execute function public.touch_row();

create table public.line_shares (
  line_id uuid not null references public.transaction_lines (id),
  member_id uuid not null references public.members (id),
  household_id uuid not null references public.households (id),
  weight numeric(12, 4) not null
    constraint line_shares_weight_positive check (weight > 0),
  -- Computed by the server, same sign as the line.
  amount_cents bigint not null,
  primary key (line_id, member_id)
);

comment on table public.line_shares is
  'Shares of the members on a line: weight and cents. Mia, Condivisa, Per... come from them.';

create index line_shares_member_id on public.line_shares (member_id);

create table public.line_tags (
  line_id uuid not null references public.transaction_lines (id),
  tag_id uuid not null references public.tags (id),
  primary key (line_id, tag_id)
);

comment on table public.line_tags is 'Tags of a line.';

create index line_tags_tag_id on public.line_tags (tag_id);

create table public.transfers (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  from_account_id uuid not null references public.accounts (id),
  to_account_id uuid not null references public.accounts (id),
  -- Both optional, at least one (towards PayPal the income is missing).
  out_transaction_id uuid references public.transactions (id),
  in_transaction_id uuid references public.transactions (id),
  -- PayPal payment funded by the charge.
  funded_transaction_id uuid references public.transactions (id),
  origin text not null
    constraint transfers_origin check (origin in ('auto', 'manual')),
  -- To undo a transfer recognised automatically.
  deleted_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transfers_distinct_accounts check (from_account_id <> to_account_id),
  constraint transfers_one_side
    check (out_transaction_id is not null or in_transaction_id is not null)
);

comment on table public.transfers is
  'Transfers between two accounts of the same owner; their lines have kind transfer.';

create index transfers_from_account_id on public.transfers (from_account_id);
create index transfers_to_account_id on public.transfers (to_account_id);
create index transfers_out_transaction_id on public.transfers (out_transaction_id);
create index transfers_in_transaction_id on public.transfers (in_transaction_id);
create index transfers_funded_transaction_id on public.transfers (funded_transaction_id);

create trigger transfers_touch_row
  before update on public.transfers
  for each row execute function public.touch_row();

alter table public.transaction_lines
  add constraint transaction_lines_transfer_id_fkey
  foreign key (transfer_id) references public.transfers (id);

-- Support functions (section 2)

create function public.can_see_transaction(transaction_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.transactions t
    where t.id = can_see_transaction.transaction_id
      and (
        (t.account_id is not null and public.is_account_owner(t.account_id))
        or (
          t.account_id is null
          and (select public.current_member_id()) in (t.entered_by_member_id, t.paid_by_member_id)
        )
      )
  )
$$;

comment on function public.can_see_transaction(uuid) is
  'True for the owner of the account or, for a manual movement without account, for who entered or paid it.';

-- Section 7: who sees the transaction; who paid the line or has a share;
-- the other active members for an income line of a member who shows their
-- income, from the start date of who looks.
create function public.can_see_line(line_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.transaction_lines l
    join public.members me on me.id = (select public.current_member_id())
    where l.id = can_see_line.line_id
      and (
        public.can_see_transaction(l.transaction_id)
        or l.paid_by_member_id = me.id
        or exists (
          select 1 from public.line_shares s
          where s.line_id = l.id and s.member_id = me.id
        )
        or (
          l.kind = 'income'
          and l.household_id = me.household_id
          and l.movement_date >= me.start_date
          and coalesce((
            select us.show_income
            from public.members payer
            join public.user_settings us on us.user_id = payer.user_id
            where payer.id = l.paid_by_member_id
          ), true)
        )
      )
  )
$$;

comment on function public.can_see_line(uuid) is
  'True if the signed-in user sees the line (section 7 of the schema).';

-- Who can change a line: who sees the transaction (everything) and who is
-- involved in the line (only kind, category and flags).
create function public.can_edit_line(line_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.transaction_lines l
    where l.id = can_edit_line.line_id
      and (
        public.can_see_transaction(l.transaction_id)
        or l.paid_by_member_id = (select public.current_member_id())
        or exists (
          select 1 from public.line_shares s
          where s.line_id = l.id and s.member_id = (select public.current_member_id())
        )
      )
  )
$$;

comment on function public.can_edit_line(uuid) is
  'True for who sees the transaction of the line and for who is involved in it.';

-- Section 6. weights = [{member_id, weight}]. Each member gets the integer
-- part (towards zero) of amount x weight / sum of the weights; the missing
-- cents go one at a time to the largest remainders; on equal remainders
-- first the payer, then the oldest joined_at, then the smallest id. The
-- weights have 4 decimals, so the products are exact integers.
create function public.split_cents(amount bigint, weights jsonb, payer uuid)
returns table (member_id uuid, amount_cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with w as (
    select (e ->> 'member_id')::uuid as member_id,
           round((e ->> 'weight')::numeric, 4) * 10000 as units
    from jsonb_array_elements(split_cents.weights) as e
  ),
  q as (
    select w.member_id,
           div(abs(split_cents.amount) * w.units, sum(w.units) over ()) as base,
           mod(abs(split_cents.amount) * w.units, sum(w.units) over ()) as remainder
    from w
  ),
  r as (
    select q.member_id,
           q.base,
           abs(split_cents.amount) - sum(q.base) over () as missing,
           row_number() over (
             order by q.remainder desc,
                      (q.member_id = split_cents.payer) desc,
                      m.joined_at,
                      q.member_id
           ) as rank
    from q
    left join public.members m on m.id = q.member_id
  )
  select r.member_id,
         (sign(split_cents.amount::numeric)
           * (r.base + case when r.rank <= r.missing then 1 else 0 end))::bigint
  from r
$$;

comment on function public.split_cents(bigint, jsonb, uuid) is
  'Cents of each member for an amount and weights [{member_id, weight}]: largest remainders, ties to the payer.';

-- Triggers of the transactions

-- From the app: source and household never change; for a movement of the
-- bank also amount, currency, description, account and raw row stay. Not
-- security definer: current_user is the role of the caller.
create function public.restrict_transaction_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' then
    if new.source is distinct from old.source
      or new.household_id is distinct from old.household_id
    then
      raise exception 'source and household of a movement do not change'
        using errcode = 'insufficient_privilege';
    end if;
    if old.source = 'bank'
      and (new.amount_cents, new.currency, new.description, new.account_id, new.raw_id)
        is distinct from (old.amount_cents, old.currency, old.description, old.account_id, old.raw_id)
    then
      raise exception 'the bank data of a movement do not change from the app'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.restrict_transaction_update() from public, anon, authenticated;

create trigger transactions_restrict_update
  before update on public.transactions
  for each row execute function public.restrict_transaction_update();

-- The payer is a member of the household and, with an account, its owner.
-- No movement before the start date of the payer, also changing the date.
create function public.check_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payer public.members%rowtype;
  v_account public.accounts%rowtype;
begin
  select m.* into v_payer from public.members m where m.id = new.paid_by_member_id;
  if v_payer.household_id <> new.household_id then
    raise exception 'the payer is a member of the household'
      using errcode = 'check_violation';
  end if;

  if new.account_id is not null then
    select a.* into v_account from public.accounts a where a.id = new.account_id;
    if v_account.household_id <> new.household_id
      or v_account.owner_member_id <> new.paid_by_member_id
    then
      raise exception 'the payer is the owner of the account'
        using errcode = 'check_violation';
    end if;
  end if;

  if new.entered_by_member_id is not null and not exists (
    select 1 from public.members m
    where m.id = new.entered_by_member_id and m.household_id = new.household_id
  ) then
    raise exception 'who enters a movement is a member of the household'
      using errcode = 'check_violation';
  end if;

  if new.movement_date < v_payer.start_date then
    raise exception 'movement_before_start_date';
  end if;

  return new;
end;
$$;

revoke all on function public.check_transaction() from public, anon, authenticated;

create trigger transactions_check
  before insert or update on public.transactions
  for each row execute function public.check_transaction();

-- A new transaction gets one line with the whole amount and a share of 100%
-- to the payer: it is in the inbox (a line without kind). An installment
-- inherits the category of its plan.
create function public.create_initial_line()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line_id uuid;
  v_category_id uuid;
begin
  select p.category_id into v_category_id
  from public.installment_plans p
  where p.id = new.installment_plan_id;

  insert into public.transaction_lines (
    transaction_id, household_id, position, amount_cents, category_id, deductible_730,
    movement_date, counterparty, paid_by_member_id, installment_plan_id
  )
  values (
    new.id, new.household_id, 1, new.amount_cents, v_category_id,
    coalesce(
      (select c.deductible_730_default from public.categories c where c.id = v_category_id),
      false
    ),
    new.movement_date, new.counterparty, new.paid_by_member_id, new.installment_plan_id
  )
  returning id into v_line_id;

  insert into public.line_shares (line_id, member_id, household_id, weight, amount_cents)
  values (v_line_id, new.paid_by_member_id, new.household_id, 1, new.amount_cents);

  return null;
end;
$$;

revoke all on function public.create_initial_line() from public, anon, authenticated;

create trigger transactions_create_initial_line
  after insert on public.transactions
  for each row execute function public.create_initial_line();

-- Date, counterparty and payer are copied on the lines. A new amount moves
-- the only line of the transaction; with more lines the sum check refuses it.
create function public.sync_transaction_lines()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.movement_date, new.counterparty, new.paid_by_member_id)
    is distinct from (old.movement_date, old.counterparty, old.paid_by_member_id)
  then
    update public.transaction_lines l
    set movement_date = new.movement_date,
        counterparty = new.counterparty,
        paid_by_member_id = new.paid_by_member_id
    where l.transaction_id = new.id;
  end if;

  if new.amount_cents <> old.amount_cents and (
    select count(*) from public.transaction_lines l
    where l.transaction_id = new.id and l.deleted_at is null
  ) = 1 then
    update public.transaction_lines l
    set amount_cents = new.amount_cents
    where l.transaction_id = new.id and l.deleted_at is null;
  end if;

  return null;
end;
$$;

revoke all on function public.sync_transaction_lines() from public, anon, authenticated;

create trigger transactions_sync_lines
  after update on public.transactions
  for each row execute function public.sync_transaction_lines();

-- Triggers of the lines

-- Changes from the app. Who is only involved in a line changes kind,
-- category, 730 and budget flags; the rest needs the transaction. A new
-- category brings its 730 flag, unless the same change sets the flag. The
-- functions (merge, split) keep the flags they set. Not security definer:
-- current_user is the role of the caller.
create function public.check_app_line_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' then
    if not public.can_see_transaction(old.transaction_id)
      and (new.amount_cents, new.position, new.transfer_id, new.settlement_id,
           new.installment_plan_id, new.deleted_at)
        is distinct from
          (old.amount_cents, old.position, old.transfer_id, old.settlement_id,
           old.installment_plan_id, old.deleted_at)
    then
      raise exception 'who is involved in a line changes only kind, category and flags'
        using errcode = 'insufficient_privilege';
    end if;

    if new.category_id is distinct from old.category_id
      and new.deductible_730 = old.deductible_730
    then
      new.deductible_730 := coalesce(
        (select c.deductible_730_default from public.categories c where c.id = new.category_id),
        false
      );
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.check_app_line_update() from public, anon, authenticated;

create trigger transaction_lines_app_update
  before update on public.transaction_lines
  for each row execute function public.check_app_line_update();

-- Copies and household from the transaction, sign of the transaction.
create function public.prepare_transaction_line()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction public.transactions%rowtype;
begin
  if tg_op = 'UPDATE' and new.transaction_id <> old.transaction_id then
    raise exception 'a line does not move to another transaction'
      using errcode = 'check_violation';
  end if;

  select t.* into v_transaction from public.transactions t where t.id = new.transaction_id;

  new.household_id := v_transaction.household_id;
  new.movement_date := v_transaction.movement_date;
  new.counterparty := v_transaction.counterparty;
  new.paid_by_member_id := v_transaction.paid_by_member_id;

  if sign(new.amount_cents) <> sign(v_transaction.amount_cents) then
    raise exception 'a line has the sign of its transaction'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function public.prepare_transaction_line() from public, anon, authenticated;

create trigger transaction_lines_prepare
  before insert or update on public.transaction_lines
  for each row execute function public.prepare_transaction_line();

-- A new amount (or payer, who wins the ties) computes the cents again with
-- the same weights.
create function public.recompute_line_shares()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.line_shares s
  set amount_cents = c.amount_cents
  from public.split_cents(
    new.amount_cents,
    (select jsonb_agg(jsonb_build_object('member_id', x.member_id, 'weight', x.weight))
     from public.line_shares x where x.line_id = new.id),
    new.paid_by_member_id
  ) c
  where s.line_id = new.id
    and s.member_id = c.member_id;
  return null;
end;
$$;

revoke all on function public.recompute_line_shares() from public, anon, authenticated;

create trigger transaction_lines_recompute_shares
  after update of amount_cents, paid_by_member_id on public.transaction_lines
  for each row
  when (new.amount_cents <> old.amount_cents or new.paid_by_member_id <> old.paid_by_member_id)
  execute function public.recompute_line_shares();

-- Deferred checks, at the end of the database transaction

-- The lines not deleted add up to the transaction.
create function public.check_lines_sum(transaction_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
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

-- A line has at least one share and its shares add up to it; no share of a
-- member before their start date; with a share of a member other than the
-- payer, only a shared category and shared tags; a personal category or tag
-- only of the payer; Differenza di cassa only on lines of the payer alone.
create function public.check_line(line_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line public.transaction_lines%rowtype;
  v_category public.categories%rowtype;
  v_count int;
  v_sum bigint;
  v_shared boolean;
begin
  select l.* into v_line from public.transaction_lines l where l.id = check_line.line_id;
  if v_line.id is null then
    return;
  end if;

  select count(*), coalesce(sum(s.amount_cents), 0), coalesce(bool_or(s.member_id <> v_line.paid_by_member_id), false)
  into v_count, v_sum, v_shared
  from public.line_shares s
  where s.line_id = v_line.id;

  if v_count = 0 or v_sum <> v_line.amount_cents then
    raise exception 'line_shares_mismatch' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.line_shares s
    join public.members m on m.id = s.member_id
    where s.line_id = v_line.id
      and (m.household_id <> v_line.household_id or m.start_date > v_line.movement_date)
  ) then
    raise exception 'member_not_eligible';
  end if;

  if v_line.category_id is not null then
    select c.* into v_category from public.categories c where c.id = v_line.category_id;
    if v_category.household_id <> v_line.household_id then
      raise exception 'the category is of the household of the line'
        using errcode = 'check_violation';
    end if;
    if v_category.scope = 'personal' and v_shared then
      raise exception 'shared_line_personal_category';
    end if;
    if v_category.scope = 'personal' and v_category.owner_member_id <> v_line.paid_by_member_id then
      raise exception 'personal_category_not_owned';
    end if;
    if v_category.system_key = 'cash_difference' and v_shared then
      raise exception 'shared_line_cash_difference';
    end if;
  end if;

  if exists (
    select 1 from public.line_tags lt join public.tags t on t.id = lt.tag_id
    where lt.line_id = v_line.id and t.household_id <> v_line.household_id
  ) then
    raise exception 'the tag is of the household of the line'
      using errcode = 'check_violation';
  end if;
  if v_shared and exists (
    select 1 from public.line_tags lt join public.tags t on t.id = lt.tag_id
    where lt.line_id = v_line.id and t.scope = 'personal'
  ) then
    raise exception 'shared_line_personal_tag';
  end if;
  if exists (
    select 1 from public.line_tags lt join public.tags t on t.id = lt.tag_id
    where lt.line_id = v_line.id
      and t.scope = 'personal'
      and t.owner_member_id <> v_line.paid_by_member_id
  ) then
    raise exception 'personal_tag_not_owned';
  end if;
end;
$$;

revoke all on function public.check_lines_sum(uuid) from public, anon, authenticated;
revoke all on function public.check_line(uuid) from public, anon, authenticated;

create function public.check_lines_sum_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'transactions' then
    perform public.check_lines_sum(new.id);
  else
    if tg_op <> 'DELETE' then
      perform public.check_lines_sum(new.transaction_id);
    end if;
    if tg_op <> 'INSERT' and old.transaction_id is distinct from new.transaction_id then
      perform public.check_lines_sum(old.transaction_id);
    end if;
  end if;
  return null;
end;
$$;

create function public.check_line_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'transaction_lines' then
    perform public.check_line(new.id);
  elsif tg_op = 'DELETE' then
    perform public.check_line(old.line_id);
  else
    perform public.check_line(new.line_id);
  end if;
  return null;
end;
$$;

revoke all on function public.check_lines_sum_trigger() from public, anon, authenticated;
revoke all on function public.check_line_trigger() from public, anon, authenticated;

create constraint trigger transactions_check_lines_sum
  after insert or update of amount_cents on public.transactions
  deferrable initially deferred
  for each row execute function public.check_lines_sum_trigger();

create constraint trigger transaction_lines_check_sum
  after insert or update of amount_cents, deleted_at or delete on public.transaction_lines
  deferrable initially deferred
  for each row execute function public.check_lines_sum_trigger();

create constraint trigger transaction_lines_check_line
  after insert or update on public.transaction_lines
  deferrable initially deferred
  for each row execute function public.check_line_trigger();

create constraint trigger line_shares_check_line
  after insert or update or delete on public.line_shares
  deferrable initially deferred
  for each row execute function public.check_line_trigger();

create constraint trigger line_tags_check_line
  after insert or delete on public.line_tags
  deferrable initially deferred
  for each row execute function public.check_line_trigger();

-- Transfers: two accounts of the same owner; the outgoing movement on the
-- first, the incoming one on the second.
create function public.check_transfer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from public.accounts%rowtype;
  v_to public.accounts%rowtype;
begin
  select a.* into v_from from public.accounts a where a.id = new.from_account_id;
  select a.* into v_to from public.accounts a where a.id = new.to_account_id;

  if v_from.owner_member_id <> v_to.owner_member_id
    or v_from.household_id <> new.household_id
    or v_to.household_id <> new.household_id
  then
    raise exception 'a transfer is between two accounts of the same owner'
      using errcode = 'check_violation';
  end if;

  if new.out_transaction_id is not null and (
    select t.account_id from public.transactions t where t.id = new.out_transaction_id
  ) is distinct from new.from_account_id then
    raise exception 'the outgoing movement is on the first account'
      using errcode = 'check_violation';
  end if;

  if new.in_transaction_id is not null and (
    select t.account_id from public.transactions t where t.id = new.in_transaction_id
  ) is distinct from new.to_account_id then
    raise exception 'the incoming movement is on the second account'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function public.check_transfer() from public, anon, authenticated;

create trigger transfers_check
  before insert or update on public.transfers
  for each row execute function public.check_transfer();

revoke all on function public.can_see_transaction(uuid) from public, anon;
revoke all on function public.can_see_line(uuid) from public, anon;
revoke all on function public.can_edit_line(uuid) from public, anon;
revoke all on function public.split_cents(bigint, jsonb, uuid) from public, anon, authenticated;
grant execute on function public.can_see_transaction(uuid) to authenticated;
grant execute on function public.can_see_line(uuid) to authenticated;
grant execute on function public.can_edit_line(uuid) to authenticated;

-- RLS

alter table public.transactions enable row level security;
alter table public.transaction_lines enable row level security;
alter table public.line_shares enable row level security;
alter table public.line_tags enable row level security;
alter table public.transfers enable row level security;

revoke all on table public.transactions from anon, authenticated;
revoke all on table public.transaction_lines from anon, authenticated;
revoke all on table public.line_shares from anon, authenticated;
revoke all on table public.line_tags from anon, authenticated;
revoke all on table public.transfers from anon, authenticated;

-- Transactions: everything with can_see_transaction; from the app only
-- manual ones. Who is only involved in a line never reads the transaction.
grant select, insert, update on table public.transactions to authenticated;

create policy transactions_select_visible on public.transactions
  for select to authenticated
  using (public.can_see_transaction(id));

create policy transactions_insert_manual on public.transactions
  for insert to authenticated
  with check (
    source = 'manual'
    and household_id = (select public.current_household_id())
    and entered_by_member_id = (select public.current_member_id())
    and (account_id is null or public.is_account_owner(account_id))
  );

create policy transactions_update_visible on public.transactions
  for update to authenticated
  using (public.can_see_transaction(id))
  with check (
    household_id = (select public.current_household_id())
    and (
      (account_id is not null and public.is_account_owner(account_id))
      or (
        account_id is null
        and (select public.current_member_id()) in (entered_by_member_id, paid_by_member_id)
      )
    )
  );

-- Lines: seen with can_see_line; inserted (and deleted, with deleted_at) by
-- who sees the transaction; changed by who sees it or is involved.
grant select, insert, update on table public.transaction_lines to authenticated;

create policy transaction_lines_select_visible on public.transaction_lines
  for select to authenticated
  using (public.can_see_line(id));

create policy transaction_lines_insert_owner on public.transaction_lines
  for insert to authenticated
  with check (public.can_see_transaction(transaction_id));

create policy transaction_lines_update_involved on public.transaction_lines
  for update to authenticated
  using (public.can_edit_line(id))
  with check (public.can_edit_line(id));

-- Shares: seen with the line, written only by set_line_shares and the
-- triggers.
grant select on table public.line_shares to authenticated;

create policy line_shares_select_visible on public.line_shares
  for select to authenticated
  using (public.can_see_line(line_id));

-- Tags of a line: seen if the line and the tag are; added and removed by who
-- can change the line.
grant select, insert, delete on table public.line_tags to authenticated;

create policy line_tags_select_visible on public.line_tags
  for select to authenticated
  using (
    public.can_see_line(line_id)
    and exists (select 1 from public.tags t where t.id = tag_id)
  );

create policy line_tags_insert_editor on public.line_tags
  for insert to authenticated
  with check (
    public.can_edit_line(line_id)
    and exists (select 1 from public.tags t where t.id = tag_id)
  );

create policy line_tags_delete_editor on public.line_tags
  for delete to authenticated
  using (public.can_edit_line(line_id));

-- Transfers: everything for the owner of the first account.
grant select, insert, update on table public.transfers to authenticated;

create policy transfers_select_owner on public.transfers
  for select to authenticated
  using (public.is_account_owner(from_account_id));

create policy transfers_insert_owner on public.transfers
  for insert to authenticated
  with check (
    public.is_account_owner(from_account_id)
    and household_id = (select public.current_household_id())
  );

create policy transfers_update_owner on public.transfers
  for update to authenticated
  using (public.is_account_owner(from_account_id))
  with check (public.is_account_owner(from_account_id));
