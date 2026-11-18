-- Initial balance between the members and net balances (docs/spec/schema.md,
-- 10; docs/spec/accesso.md, 10).
--
-- The initial balance concerns only the members who start with the
-- household; it adds up to zero. "Nessun saldo da riportare" saves zeros.
-- member_balances gives every member of the household their net balance
-- without making any row visible.

create table public.initial_balances (
  household_id uuid not null references public.households (id),
  member_id uuid not null references public.members (id),
  -- Positive: credit.
  amount_cents bigint not null,
  set_by_member_id uuid not null references public.members (id),
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (household_id, member_id)
);

comment on table public.initial_balances is
  'What each member owes or gets at the start date of the household; adds up to zero.';

create index initial_balances_member_id on public.initial_balances (member_id);
create index initial_balances_set_by_member_id on public.initial_balances (set_by_member_id);

create trigger initial_balances_touch_row
  before update on public.initial_balances
  for each row execute function public.touch_row();

create function public.check_initial_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_active_member(new.member_id, new.household_id);
  perform public.check_active_member(new.set_by_member_id, new.household_id);
  return new;
end;
$$;

revoke all on function public.check_initial_balance() from public, anon, authenticated;

create trigger initial_balances_check
  before insert or update of household_id, member_id, set_by_member_id on public.initial_balances
  for each row execute function public.check_initial_balance();

-- balances = [{member_id, amount_cents}] for the members who start with the
-- household; the missing ones are zero, and the total is zero. Every call
-- rewrites the row of each of those members, so each version goes up by
-- one: the app applies the rule of the conflicts on it.
create function public.set_initial_balances(balances jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_id uuid := public.current_member_id();
  v_household public.households%rowtype;
  v_balances jsonb := coalesce(set_initial_balances.balances, '[]'::jsonb);
begin
  if v_member_id is null then
    raise exception 'not_member';
  end if;

  select h.* into v_household
  from public.households h
  where h.id = public.current_household_id();

  -- A list, with each member once.
  if jsonb_typeof(v_balances) <> 'array' then
    raise exception 'invalid_balances';
  end if;
  if (
    select count(*) <> count(distinct e ->> 'member_id')
    from jsonb_array_elements(v_balances) as e
  ) then
    raise exception 'invalid_balances';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_balances) as e
    left join public.members m on m.id = (e ->> 'member_id')::uuid
    where m.id is null
      or m.household_id <> v_household.id
      or m.left_at is not null
      or m.start_date <> v_household.start_date
  ) then
    raise exception 'member_not_eligible';
  end if;

  if (
    select coalesce(sum(coalesce((e ->> 'amount_cents')::bigint, 0)), 0)
    from jsonb_array_elements(v_balances) as e
  ) <> 0 then
    raise exception 'initial_balance_not_zero_sum';
  end if;

  insert into public.initial_balances as ib (household_id, member_id, amount_cents, set_by_member_id)
  select v_household.id, m.id, coalesce(b.amount_cents, 0), v_member_id
  from public.members m
  left join (
    select (e ->> 'member_id')::uuid as member_id,
           coalesce((e ->> 'amount_cents')::bigint, 0) as amount_cents
    from jsonb_array_elements(v_balances) as e
  ) b on b.member_id = m.id
  where m.household_id = v_household.id
    and m.left_at is null
    and m.start_date = v_household.start_date
  on conflict (household_id, member_id) do update
    set amount_cents = excluded.amount_cents,
        set_by_member_id = excluded.set_by_member_id;
end;
$$;

comment on function public.set_initial_balances(jsonb) is
  'Saves the initial balance [{member_id, amount_cents}] of the members who start with the household. Errors: not_member, invalid_balances, member_not_eligible, initial_balance_not_zero_sum.';

-- Net balance of every member of the household of the caller. Positive is
-- credit. Lines and transactions not deleted, in EUR; settlements not
-- deleted, in EUR; the initial balance. The lines of one member alone cancel
-- out, so inbox, transfers and settlement lines do not move a balance.
create function public.member_balances()
returns table (member_id uuid, net_cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with household as (
    select public.current_household_id() as id
  ),
  counted_lines as (
    select l.id, l.paid_by_member_id, l.amount_cents
    from public.transaction_lines l
    join public.transactions t on t.id = l.transaction_id
    where l.household_id = (select h.id from household h)
      and l.deleted_at is null
      and t.deleted_at is null
      and t.currency = 'EUR'
  ),
  counted_settlements as (
    select s.payer_member_id, s.payee_member_id, s.amount_cents
    from public.settlements s
    where s.household_id = (select h.id from household h)
      and s.deleted_at is null
      and s.currency = 'EUR'
  ),
  parts as (
    -- Lines paid: -amount.
    select cl.paid_by_member_id as member_id, -cl.amount_cents as cents
    from counted_lines cl
    union all
    -- Own shares: +amount.
    select ls.member_id, ls.amount_cents
    from public.line_shares ls
    join counted_lines cl on cl.id = ls.line_id
    union all
    -- Settlements paid: +amount; received: -amount.
    select cs.payer_member_id, cs.amount_cents from counted_settlements cs
    union all
    select cs.payee_member_id, -cs.amount_cents from counted_settlements cs
    union all
    select ib.member_id, ib.amount_cents
    from public.initial_balances ib
    where ib.household_id = (select h.id from household h)
  )
  select m.id, coalesce(sum(p.cents), 0)::bigint
  from public.members m
  left join parts p on p.member_id = m.id
  where m.household_id = (select h.id from household h)
  group by m.id
  order by m.joined_at, m.id
$$;

comment on function public.member_balances() is
  'Net balance of every member of the household of the caller; positive is credit; the total is zero.';

revoke all on function public.set_initial_balances(jsonb) from public, anon;
revoke all on function public.member_balances() from public, anon;
grant execute on function public.set_initial_balances(jsonb) to authenticated;
grant execute on function public.member_balances() to authenticated;

-- RLS: the active members read the initial balance; writes only with the
-- function.

alter table public.initial_balances enable row level security;

revoke all on table public.initial_balances from anon, authenticated;

grant select on table public.initial_balances to authenticated;

create policy initial_balances_select_household on public.initial_balances
  for select to authenticated
  using (household_id = (select public.current_household_id()));
