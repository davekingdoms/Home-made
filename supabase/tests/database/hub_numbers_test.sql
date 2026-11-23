-- Numbers of the hub (docs/spec/schema.md, 10): unclassified_count() and
-- my_accounts_total(), security invoker, and my_spending_by_month(),
-- security definer, on the active member of the caller only. Invented
-- users: Anna (a1) and Bruno (b1)
-- in "Casa di prova" from 2031-01-01, Carla (c1) joining it on 2031-05-01;
-- Dario (d1), first without a household, then alone in "Casa di Dario".
--
-- "Le tue spese", today 2031-06-15, the last 6 months (cents, positive;
-- shared / personal):
--
--   Anna      2031-01      0 /    0
--             2031-02   1500 / 1000   212 50/50 of 30,00; 211 Mia 10,00
--             2031-03    800 /  100   213 paid by Bruno for Anna alone;
--                                     231 Mia 1,00 on the last day
--             2031-04      0 / 3810   225 50,00 (its deleted part out);
--                                     226 refund +12,00; 232 Mia 0,10 on
--                                     the first day
--             2031-05    833 /    0   241 2:1:1 of 10,00 (5,00); 242 1:1:1
--                                     of 10,00 paid by Carla (3,33)
--             2031-06      0 /   50   233 Mia 0,50 on the last day
--             out: 214 (Anna for Bruno alone), 221 (out of the budget),
--             222-224 (saving, income, to classify), 227 (deleted),
--             228 (in USD), 234 (2031-07-01), the lines of "Casa di Dario"
--   Bruno     2031-02 1500 / 0; 2031-03 600 / 700 (214; 215 Mia);
--             2031-04 0 / 0 (227 deleted and 228 in USD, shared with him,
--             do not count for him either); 2031-05 583 / 0 (2,50 + 3,33)
--   Carla     2031-05 584 / 0 (2,50 + 3,34, the cent of the payer)
--   Dario     2031-03 0 / 1500; 2031-06 0 / 500 (alone: all personal)
begin;

create extension if not exists pgtap with schema extensions;

select plan(73);

create function pg_temp.login(user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create function pg_temp.check_deferred()
returns void
language plpgsql
as $$
begin
  set constraints all immediate;
  set constraints all deferred;
end;
$$;

create function pg_temp.cash_of(member_id uuid)
returns uuid
language sql
security definer
as $$
  select a.id from public.accounts a where a.owner_member_id = cash_of.member_id and a.kind = 'cash'
$$;

create function pg_temp.line(transaction_id uuid)
returns uuid
language sql
security definer
as $$
  select l.id from public.transaction_lines l
  where l.transaction_id = line.transaction_id and l.position = 1
$$;

create function pg_temp.shares(anna numeric, bruno numeric, carla numeric)
returns jsonb
language sql
as $$
  select jsonb_agg(jsonb_build_object('member_id', m, 'weight', w))
  from (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, anna),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, bruno),
    ('00000000-0000-4000-8000-0000000000c1'::uuid, carla)
  ) as t (m, w)
  where w is not null
$$;

-- A shared expense category of "Casa di prova", from the initial list.
create function pg_temp.category()
returns uuid
language sql
security definer
as $$
  select c.id from public.categories c
  where c.household_id = '00000000-0000-4000-8000-0000000000f1'
    and c.kind = 'expense' and c.scope = 'shared'
    and c.parent_id is not null and c.system_key is null
  order by c.position, c.name
  limit 1
$$;

-- A movement of the bank in EUR, written by the server; an installment
-- with the id of its plan.
create function pg_temp.bank_movement(id uuid, account_id uuid, movement_date date, amount bigint, plan_id uuid)
returns void
language sql
security definer
as $$
  insert into public.transactions (
    id, household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency,
    installment_plan_id
  )
  select bank_movement.id, a.household_id, a.id, 'bank', a.owner_member_id, bank_movement.movement_date,
         bank_movement.amount, 'EUR', bank_movement.plan_id
  from public.accounts a
  where a.id = bank_movement.account_id
$$;

-- A manual movement entered by the signed-in member on an own account.
create function pg_temp.manual_movement(id uuid, account_id uuid, movement_date date, amount bigint, currency text)
returns void
language sql
as $$
  insert into public.transactions (
    id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date,
    amount_cents, currency
  ) values (
    manual_movement.id, public.current_household_id(), manual_movement.account_id, 'manual',
    public.current_member_id(), public.current_member_id(), manual_movement.movement_date,
    manual_movement.amount, manual_movement.currency
  )
$$;

-- An installment plan, written by the server.
create function pg_temp.plan(id uuid, account_id uuid, purchase_date date, category_id uuid, status text, before_start int)
returns void
language sql
security definer
as $$
  insert into public.installment_plans (
    id, household_id, account_id, merchant, total_cents, installments_count, purchase_date,
    installments_before_start, category_id, status
  )
  select plan.id, a.household_id, a.id, 'Negozio Esempio', 3000, 3, plan.purchase_date,
         plan.before_start, plan.category_id, plan.status
  from public.accounts a
  where a.id = plan.account_id
$$;

-- Balances read from the bank, written and removed by the server.
create function pg_temp.balance(account_id uuid, currency text, balance_type text, amount bigint)
returns void
language sql
security definer
as $$
  insert into public.account_balances (account_id, currency, balance_type, amount_cents)
  values (balance.account_id, balance.currency, balance.balance_type, balance.amount)
$$;

create function pg_temp.drop_balance(account_id uuid, balance_type text)
returns void
language sql
security definer
as $$
  delete from public.account_balances b
  where b.account_id = drop_balance.account_id
    and b.currency = 'EUR'
    and b.balance_type = drop_balance.balance_type
$$;

-- Shared and personal cents of one month.
create function pg_temp.month_of(today date, month date)
returns table (shared_cents bigint, personal_cents bigint)
language sql
as $$
  select s.shared_cents, s.personal_cents
  from public.my_spending_by_month(month_of.today) s
  where s.month = month_of.month
$$;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla'),
  ('00000000-0000-4000-8000-00000000000d', 'Dario');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', '2031-01-01'),
  ('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', '2031-01-01');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', '2031-01-01', now() - interval '2 days');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', '2031-01-01', now() - interval '1 day');
insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', true, 'active'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000b1',
   'Banca di Prova', 'IT', true, 'active'),
  ('00000000-0000-4000-8000-0000000000e5', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, provider_account_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1', 'uid-1', 'EUR',
   'Banca di Prova …0001'),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000b1', 'bank', '00000000-0000-4000-8000-0000000000e3', 'uid-2', 'EUR',
   'Banca di Prova …0002'),
  ('00000000-0000-4000-8000-0000000000e6', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'paypal', '00000000-0000-4000-8000-0000000000e5', 'uid-3', 'XXX',
   'anna@example.com');

-- Permissions

select has_function('public', 'unclassified_count', array[]::text[], 'unclassified_count() exists');
select has_function('public', 'my_spending_by_month', array['date', 'integer'], 'my_spending_by_month(date, integer) exists');
select has_function('public', 'my_accounts_total', array[]::text[], 'my_accounts_total() exists');
select results_eq(
  $$select p.proname::text collate "default", p.prosecdef, p.provolatile = 's', p.proconfig = array['search_path=""']
    from pg_proc p
    where p.oid in (
        'public.unclassified_count()'::regprocedure,
        'public.my_spending_by_month(date, integer)'::regprocedure,
        'public.my_accounts_total()'::regprocedure
      )
    order by p.proname$$,
  $$values ('my_accounts_total', false, true, true),
           ('my_spending_by_month', true, true, true),
           ('unclassified_count', false, true, true)$$,
  'unclassified_count and my_accounts_total are security invoker, my_spending_by_month security definer; all stable, with an empty search path'
);
select results_eq(
  $$select has_function_privilege('authenticated', f, 'execute'), has_function_privilege('anon', f, 'execute')
    from unnest(array['public.unclassified_count()', 'public.my_spending_by_month(date, integer)',
                      'public.my_accounts_total()']) as f$$,
  $$values (true, false), (true, false), (true, false)$$,
  'authenticated executes the three functions, anon none'
);

set local role anon;
select throws_ok('select public.unclassified_count()', '42501', null, 'anon cannot call unclassified_count');
select throws_ok(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  '42501', null, 'anon cannot call my_spending_by_month'
);
select throws_ok('select public.my_accounts_total()', '42501', null, 'anon cannot call my_accounts_total');
reset role;

-- Dario without a household

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is(public.unclassified_count(), 0, 'Dario without a household has nothing to classify');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  $$values ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 0::bigint, 0::bigint),
           ('2031-03-01'::date, 0::bigint, 0::bigint), ('2031-04-01'::date, 0::bigint, 0::bigint),
           ('2031-05-01'::date, 0::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 0::bigint)$$,
  'nor any spending: six months at zero'
);
select is(public.my_accounts_total(), 0::bigint, 'nor a total of the accounts');
reset role;

insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', '2031-01-01');

-- unclassified_count()

set local role authenticated;
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000e2',
                             '2031-09-01', -1000, null);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select is(public.unclassified_count(), 1, 'a transaction with a line without kind counts 1');

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000e2',
                             '2031-09-02', -2000, null);
select public.split_line(pg_temp.line('00000000-0000-4000-8000-000000000102'),
  '[{"id": "00000000-0000-4000-8000-000000000401", "amount_cents": -500}]');
select is(public.unclassified_count(), 2, 'a transaction with two lines without kind counts 1');
update public.transaction_lines set kind = 'saving'
  where id = pg_temp.line('00000000-0000-4000-8000-000000000102');
select is(public.unclassified_count(), 2, 'split in two lines, one still without kind: it counts 1');
update public.transaction_lines set kind = 'saving'
  where id = '00000000-0000-4000-8000-000000000401';
select is(public.unclassified_count(), 1, 'all its lines classified: it no longer counts');

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000e2',
                             '2031-09-03', -3000, null);
select public.split_line(pg_temp.line('00000000-0000-4000-8000-000000000103'),
  '[{"id": "00000000-0000-4000-8000-000000000402", "amount_cents": -1000}]');
update public.transaction_lines set kind = 'saving'
  where id = pg_temp.line('00000000-0000-4000-8000-000000000103');
select is(public.unclassified_count(), 2, 'a line without kind next to a classified one');
update public.transaction_lines set deleted_at = now()
  where id = '00000000-0000-4000-8000-000000000402';
update public.transaction_lines set amount_cents = -3000
  where id = pg_temp.line('00000000-0000-4000-8000-000000000103');
select is(public.unclassified_count(), 1, 'deleted, the line without kind no longer counts');

select pg_temp.manual_movement('00000000-0000-4000-8000-000000000104',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), '2031-09-04', -500, 'EUR');
select is(public.unclassified_count(), 2, 'a manual movement counts too');
update public.transactions set deleted_at = now() where id = '00000000-0000-4000-8000-000000000104';
select is(public.unclassified_count(), 1, 'a deleted manual movement no longer counts');

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-0000000000e4',
                             '2031-09-05', -700, null);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is(public.unclassified_count(), 1, 'Bruno counts his own transaction');
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select is(public.unclassified_count(), 1, 'Anna does not count the transaction of Bruno');

-- Anna enters a movement for Bruno, without an account: it is his.
insert into public.transactions (
  id, household_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values (
  '00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-0000000000f1', 'manual',
  '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', '2031-09-06', -400, 'EUR'
);
select is(public.unclassified_count(), 1, 'nor a movement she entered for Bruno');
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is(public.unclassified_count(), 2, 'which counts for Bruno, who paid it');

-- Installment plans of the PayPal account of Anna.
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select pg_temp.plan('00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-0000000000e6',
                    '2031-08-20', null, 'active', 0);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000111', '00000000-0000-4000-8000-0000000000e6',
                             '2031-08-20', -1000, '00000000-0000-4000-8000-000000000501');
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000112', '00000000-0000-4000-8000-0000000000e6',
                             '2031-09-19', -1000, '00000000-0000-4000-8000-000000000501');
select is(public.unclassified_count(), 2, 'a plan without category counts 1, not its two installments without kind');

select pg_temp.plan('00000000-0000-4000-8000-000000000502', '00000000-0000-4000-8000-0000000000e6',
                    '2031-08-21', pg_temp.category(), 'active', 0);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000113', '00000000-0000-4000-8000-0000000000e6',
                             '2031-08-21', -1000, '00000000-0000-4000-8000-000000000502');
select is(public.unclassified_count(), 3, 'a plan with a category does not count; its installment without kind does');

select pg_temp.plan('00000000-0000-4000-8000-000000000503', '00000000-0000-4000-8000-0000000000e6',
                    '2031-08-22', null, 'active', 0);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000114', '00000000-0000-4000-8000-0000000000e6',
                             '2031-08-22', -1000, '00000000-0000-4000-8000-000000000503');
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000115', '00000000-0000-4000-8000-0000000000e6',
                             '2031-09-21', -1000, '00000000-0000-4000-8000-000000000503');
select is(public.unclassified_count(), 4, 'another plan without category: 1 more');
update public.installment_plans set deleted_at = now() where id = '00000000-0000-4000-8000-000000000503';
select is(public.unclassified_count(), 5, 'deleted, the plan no longer counts; its two installments without kind do');

select pg_temp.plan('00000000-0000-4000-8000-000000000504', '00000000-0000-4000-8000-0000000000e6',
                    '2031-06-01', null, 'completed', 0);
select is(public.unclassified_count(), 6, 'a completed plan never classified still counts');

select pg_temp.plan('00000000-0000-4000-8000-000000000505', '00000000-0000-4000-8000-0000000000e6',
                    '2030-12-10', null, 'active', 2);
select is(public.unclassified_count(), 7, 'a plan born before the start date counts too');

select pg_temp.plan('00000000-0000-4000-8000-000000000506', '00000000-0000-4000-8000-0000000000e4',
                    '2031-08-25', null, 'active', 0);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is(public.unclassified_count(), 3, 'Bruno counts his own plan');
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select is(public.unclassified_count(), 7, 'Anna never counts the plans of Bruno');
select pg_temp.check_deferred();

-- my_spending_by_month(): one member

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000201',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000d1'), '2031-03-10', -1500, 'EUR');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000202',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000d1'), '2031-06-01', -500, 'EUR');
update public.transaction_lines set kind = 'expense'
  where transaction_id in ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  $$values ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 0::bigint, 0::bigint),
           ('2031-03-01'::date, 0::bigint, 1500::bigint), ('2031-04-01'::date, 0::bigint, 0::bigint),
           ('2031-05-01'::date, 0::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 500::bigint)$$,
  'one member alone: everything in Personali'
);

-- Two members

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000211', '00000000-0000-4000-8000-0000000000e2',
                             '2031-02-10', -1000, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000212', '00000000-0000-4000-8000-0000000000e2',
                             '2031-02-15', -3000, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000213', '00000000-0000-4000-8000-0000000000e4',
                             '2031-03-05', -800, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-0000000000e2',
                             '2031-03-08', -600, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000215', '00000000-0000-4000-8000-0000000000e4',
                             '2031-03-09', -700, null);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transaction_lines set kind = 'expense'
  where transaction_id in ('00000000-0000-4000-8000-000000000211', '00000000-0000-4000-8000-000000000212',
                           '00000000-0000-4000-8000-000000000214');
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000212'), pg_temp.shares(1, 1, null));
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000214'), pg_temp.shares(null, 1, null));
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
update public.transaction_lines set kind = 'expense'
  where transaction_id in ('00000000-0000-4000-8000-000000000213', '00000000-0000-4000-8000-000000000215');
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000213'), pg_temp.shares(1, null, null));

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  $$values ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 1500::bigint, 1000::bigint),
           ('2031-03-01'::date, 800::bigint, 0::bigint), ('2031-04-01'::date, 0::bigint, 0::bigint),
           ('2031-05-01'::date, 0::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 0::bigint)$$,
  'two members: Mia in Personali; shared 50/50 and paid by Bruno for Anna alone in Condivise; paid by Anna for Bruno alone: nothing'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  $$values ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 1500::bigint, 0::bigint),
           ('2031-03-01'::date, 600::bigint, 700::bigint), ('2031-04-01'::date, 0::bigint, 0::bigint),
           ('2031-05-01'::date, 0::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 0::bigint)$$,
  'Bruno: his half, the line Anna paid for him alone in Condivise, his Mia in Personali'
);

-- What does not count, in April

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000221', '00000000-0000-4000-8000-0000000000e2',
                             '2031-04-02', -900, null);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transaction_lines set kind = 'expense', excluded_from_budget = true
  where transaction_id = '00000000-0000-4000-8000-000000000221';
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 0::bigint)$$,
  'an expense out of the budget does not count'
);

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000222', '00000000-0000-4000-8000-0000000000e2',
                             '2031-04-03', -400, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000223', '00000000-0000-4000-8000-0000000000e2',
                             '2031-04-04', 2500, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000224', '00000000-0000-4000-8000-0000000000e2',
                             '2031-04-05', -200, null);
update public.transaction_lines set kind = 'saving'
  where transaction_id = '00000000-0000-4000-8000-000000000222';
update public.transaction_lines set kind = 'income'
  where transaction_id = '00000000-0000-4000-8000-000000000223';
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 0::bigint)$$,
  'nor the lines of another kind: saving, income, to classify'
);

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000225', '00000000-0000-4000-8000-0000000000e2',
                             '2031-04-06', -5000, null);
update public.transaction_lines set kind = 'expense'
  where transaction_id = '00000000-0000-4000-8000-000000000225';
select public.split_line(pg_temp.line('00000000-0000-4000-8000-000000000225'),
  '[{"id": "00000000-0000-4000-8000-000000000403", "amount_cents": -1000}]');
update public.transaction_lines set deleted_at = now()
  where id = '00000000-0000-4000-8000-000000000403';
update public.transaction_lines set amount_cents = -5000
  where id = pg_temp.line('00000000-0000-4000-8000-000000000225');
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 5000::bigint)$$,
  'a deleted line does not count: 50,00, not 60,00'
);

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000226', '00000000-0000-4000-8000-0000000000e2',
                             '2031-04-10', 1200, null);
update public.transaction_lines set kind = 'expense'
  where transaction_id = '00000000-0000-4000-8000-000000000226';
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 3800::bigint)$$,
  'a refund classified as an expense lowers the spending'
);

select pg_temp.manual_movement('00000000-0000-4000-8000-000000000227',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), '2031-04-12', -2000, 'EUR');
update public.transaction_lines set kind = 'expense'
  where transaction_id = '00000000-0000-4000-8000-000000000227';
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000227'), pg_temp.shares(1, 1, null));
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (1000::bigint, 3800::bigint)$$,
  'a manual movement of cash shared with Bruno'
);
update public.transactions set deleted_at = now() where id = '00000000-0000-4000-8000-000000000227';
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 3800::bigint)$$,
  'deleted, it no longer counts for Anna, who paid it'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 0::bigint)$$,
  'nor for Bruno, who has only a share and does not read the transaction'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000228',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), '2031-04-13', -3000, 'USD');
update public.transaction_lines set kind = 'expense'
  where transaction_id = '00000000-0000-4000-8000-000000000228';
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000228'), pg_temp.shares(1, 1, null));
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 3800::bigint)$$,
  'a movement in another currency does not count'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$select * from pg_temp.month_of('2031-06-15', '2031-04-01')$$,
  $$values (0::bigint, 0::bigint)$$,
  'nor for Bruno, who has a share in it'
);

-- Edges of the months

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000231', '00000000-0000-4000-8000-0000000000e2',
                             '2031-03-31', -100, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000232', '00000000-0000-4000-8000-0000000000e2',
                             '2031-04-01', -10, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000233', '00000000-0000-4000-8000-0000000000e2',
                             '2031-06-30', -50, null);
select pg_temp.bank_movement('00000000-0000-4000-8000-000000000234', '00000000-0000-4000-8000-0000000000e2',
                             '2031-07-01', -70, null);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transaction_lines set kind = 'expense'
  where transaction_id in ('00000000-0000-4000-8000-000000000231', '00000000-0000-4000-8000-000000000232',
                           '00000000-0000-4000-8000-000000000233', '00000000-0000-4000-8000-000000000234');

-- Three members: Carla joins on 2031-05-01.

reset role;
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', '2031-05-01', now());
set local role authenticated;

select pg_temp.bank_movement('00000000-0000-4000-8000-000000000241', '00000000-0000-4000-8000-0000000000e2',
                             '2031-05-10', -1000, null);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transaction_lines set kind = 'expense'
  where transaction_id = '00000000-0000-4000-8000-000000000241';
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000241'), pg_temp.shares(2, 1, 1));
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000242',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000c1'), '2031-05-20', -1000, 'EUR');
update public.transaction_lines set kind = 'expense'
  where transaction_id = '00000000-0000-4000-8000-000000000242';
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000242'), pg_temp.shares(1, 1, 1));

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  $$values ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 1500::bigint, 1000::bigint),
           ('2031-03-01'::date, 800::bigint, 100::bigint), ('2031-04-01'::date, 0::bigint, 3810::bigint),
           ('2031-05-01'::date, 833::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 50::bigint)$$,
  'Anna, six months by default: the last day in its month, the first day in the new one, the month of today to its end, January at zero, never the lines of "Casa di Dario"'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  $$values ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 1500::bigint, 0::bigint),
           ('2031-03-01'::date, 600::bigint, 700::bigint), ('2031-04-01'::date, 0::bigint, 0::bigint),
           ('2031-05-01'::date, 583::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 0::bigint)$$,
  'three members with different shares: Bruno 2,50 and 3,33 in May'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15')$$,
  $$values ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 0::bigint, 0::bigint),
           ('2031-03-01'::date, 0::bigint, 0::bigint), ('2031-04-01'::date, 0::bigint, 0::bigint),
           ('2031-05-01'::date, 584::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 0::bigint)$$,
  'Carla from her start date: 2,50 and 3,34, the cent of who paid'
);

-- How many months

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15', 1)$$,
  $$values ('2031-06-01'::date, 0::bigint, 50::bigint)$$,
  'months = 1: the month of today only'
);
select results_eq(
  $$select * from public.my_spending_by_month('2031-06-15', 12)$$,
  $$values ('2030-07-01'::date, 0::bigint, 0::bigint), ('2030-08-01'::date, 0::bigint, 0::bigint),
           ('2030-09-01'::date, 0::bigint, 0::bigint), ('2030-10-01'::date, 0::bigint, 0::bigint),
           ('2030-11-01'::date, 0::bigint, 0::bigint), ('2030-12-01'::date, 0::bigint, 0::bigint),
           ('2031-01-01'::date, 0::bigint, 0::bigint), ('2031-02-01'::date, 1500::bigint, 1000::bigint),
           ('2031-03-01'::date, 800::bigint, 100::bigint), ('2031-04-01'::date, 0::bigint, 3810::bigint),
           ('2031-05-01'::date, 833::bigint, 0::bigint), ('2031-06-01'::date, 0::bigint, 50::bigint)$$,
  'months = 12: twelve months from the oldest, also before the start date, at zero'
);
select results_eq(
  $$select * from public.my_spending_by_month('2031-07-01', 1)$$,
  $$values ('2031-07-01'::date, 0::bigint, 70::bigint)$$,
  'the month is the one of the date the app passes'
);
select throws_ok(
  $$select * from public.my_spending_by_month('2031-06-15', 0)$$,
  'P0001', 'invalid_months', 'months = 0 is refused'
);
select throws_ok(
  $$select * from public.my_spending_by_month('2031-06-15', 13)$$,
  'P0001', 'invalid_months', 'months = 13 is refused'
);
select throws_ok(
  $$select * from public.my_spending_by_month('2031-06-15', null)$$,
  'P0001', 'invalid_months', 'months is required'
);
select throws_ok(
  $$select * from public.my_spending_by_month(null)$$,
  'P0001', 'invalid_date', 'the date is required'
);
select lives_ok('select pg_temp.check_deferred()', 'every movement, line and share holds');

-- my_accounts_total()

select is(
  public.my_accounts_total(), 0::bigint,
  'accounts of the bank without balances count 0; the deleted cash movements do not count'
);

select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'EUR', 'ITAV', 300);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'EUR', 'CLAV', 400);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'EUR', 'XPCD', 500);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'EUR', 'ITBD', 600);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'EUR', 'CLBD', 700);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'EUR', 'PRCD', 900);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'EUR', 'OTHR', 800);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e2', 'USD', 'ITAV', 99900);
select is(public.my_accounts_total(), 300::bigint, 'without a preferred type, ITAV first; never a balance in another currency');

update public.accounts set preferred_balance_type = 'CLBD' where id = '00000000-0000-4000-8000-0000000000e2';
select is(public.my_accounts_total(), 700::bigint, 'the preferred type wins');

update public.accounts set preferred_balance_type = null where id = '00000000-0000-4000-8000-0000000000e2';
select pg_temp.drop_balance('00000000-0000-4000-8000-0000000000e2', 'ITAV');
select is(public.my_accounts_total(), 400::bigint, 'then CLAV');
select pg_temp.drop_balance('00000000-0000-4000-8000-0000000000e2', 'CLAV');
select is(public.my_accounts_total(), 500::bigint, 'then XPCD');
select pg_temp.drop_balance('00000000-0000-4000-8000-0000000000e2', 'XPCD');
select is(public.my_accounts_total(), 600::bigint, 'then ITBD');
select pg_temp.drop_balance('00000000-0000-4000-8000-0000000000e2', 'ITBD');
select is(public.my_accounts_total(), 700::bigint, 'then CLBD');
select pg_temp.drop_balance('00000000-0000-4000-8000-0000000000e2', 'CLBD');
select is(public.my_accounts_total(), 800::bigint, 'then any other type in alphabetical order');

update public.accounts set preferred_balance_type = 'ITAV' where id = '00000000-0000-4000-8000-0000000000e2';
select is(public.my_accounts_total(), 800::bigint, 'a preferred type without a balance in EUR: the default order');

reset role;
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, provider_account_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e7', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1', 'uid-4', 'EUR',
   'Carta …0001');
set local role authenticated;
select pg_temp.balance('00000000-0000-4000-8000-0000000000e7', 'EUR', 'CLBD', -5000);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e7', 'EUR', 'OTHR', 145000);
select is(public.my_accounts_total(), -4200::bigint, 'a credit card counts its debt, negative');

select pg_temp.balance('00000000-0000-4000-8000-0000000000e6', 'EUR', 'XPCD', 2500);
select pg_temp.balance('00000000-0000-4000-8000-0000000000e6', 'USD', 'XPCD', 1000);
select is(public.my_accounts_total(), -1700::bigint, 'PayPal: only the balance in EUR');

update public.accounts set excluded_from_total = true where id = '00000000-0000-4000-8000-0000000000e2';
select is(public.my_accounts_total(), -2500::bigint, 'an account excluded from the total does not count');
update public.accounts set archived_at = now() where id = '00000000-0000-4000-8000-0000000000e7';
select is(public.my_accounts_total(), 2500::bigint, 'nor an archived one');

update public.accounts set opening_balance_cents = 10000
  where id = pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000301',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), '2031-06-02', -2000, 'EUR');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000302',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), '2031-06-03', 500, 'EUR');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000303',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), '2031-06-04', -700, 'EUR');
update public.transactions set deleted_at = now() where id = '00000000-0000-4000-8000-000000000303';
select is(public.my_accounts_total(), 11000::bigint, 'cash: the opening balance plus the movements not deleted');

insert into public.accounts (id, household_id, owner_member_id, kind, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e8', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'manual', 'EUR', 'Conto di prova');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000304',
  '00000000-0000-4000-8000-0000000000e8', '2031-06-05', -300, 'EUR');
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000305',
  '00000000-0000-4000-8000-0000000000e8', '2031-06-06', -100, 'USD');
select is(public.my_accounts_total(), 10700::bigint, 'a manual account without opening balance: its movements in EUR');

insert into public.accounts (id, household_id, owner_member_id, kind, currency, display_name, opening_balance_cents) values
  ('00000000-0000-4000-8000-0000000000e9', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'manual', 'USD', 'Conto in dollari di prova', 5000);
select pg_temp.manual_movement('00000000-0000-4000-8000-000000000306',
  '00000000-0000-4000-8000-0000000000e9', '2031-06-07', -100, 'USD');
select is(public.my_accounts_total(), 10700::bigint, 'a manual account in another currency counts 0');

select pg_temp.balance('00000000-0000-4000-8000-0000000000e4', 'EUR', 'CLBD', 4242);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is(public.my_accounts_total(), 4242::bigint, 'Bruno counts his own accounts');
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select is(public.my_accounts_total(), 10700::bigint, 'Anna never counts those of Bruno');
select lives_ok('select pg_temp.check_deferred()', 'every account and movement holds');

select * from finish();
rollback;
