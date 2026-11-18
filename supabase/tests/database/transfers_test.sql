-- Transfers and installment plans (docs/spec/schema.md, 9). Invented users:
-- Anna (a1) with a bank account and her cash; Bruno (b1) and Carla (c1) in
-- the same household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

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

create function pg_temp.category(kind text, parent_name text, name text)
returns uuid
language sql
security definer
as $$
  select c.id
  from public.categories c
  left join public.categories p on p.id = c.parent_id
  where c.kind = category.kind
    and c.name = category.name
    and p.name is not distinct from category.parent_name
    and c.archived_at is null
$$;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 60);

insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Banca di Prova'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Carta di Prova');

-- A withdrawal: out of the bank account, into the cash.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency
) values (
  '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000e2', 'bank', '00000000-0000-4000-8000-0000000000a1',
  current_date - 3, -10000, 'EUR'
);
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values (
  '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000f1',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), 'manual', '00000000-0000-4000-8000-0000000000a1',
  '00000000-0000-4000-8000-0000000000a1', current_date - 3, 10000, 'EUR'
);
select pg_temp.check_deferred();

-- Transfers
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$insert into public.transfers (id, household_id, from_account_id, to_account_id,
                                  out_transaction_id, in_transaction_id, origin)
    values ('00000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-0000000000f1',
            '00000000-0000-4000-8000-0000000000e2', pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'),
            '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102', 'manual');
    update public.transaction_lines
    set kind = 'transfer', transfer_id = '00000000-0000-4000-8000-000000000301'
    where transaction_id in ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102');
    select pg_temp.check_deferred()$$,
  'the owner links a withdrawal to her cash as a transfer'
);
select results_eq(
  $$select count(*)::int from public.transaction_lines
    where transfer_id = '00000000-0000-4000-8000-000000000301' and kind = 'transfer'$$,
  $$values (2)$$,
  'both lines have kind transfer and the transfer'
);
select throws_ok(
  $$update public.transaction_lines set kind = 'expense'
    where transaction_id = '00000000-0000-4000-8000-000000000101'$$,
  '23514', null,
  'a line of a transfer has kind transfer'
);
select throws_ok(
  $$insert into public.transfers (household_id, from_account_id, to_account_id, out_transaction_id, origin)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2',
            '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-000000000101', 'manual')$$,
  '23514', null,
  'a transfer is between two different accounts'
);
select throws_ok(
  $$insert into public.transfers (household_id, from_account_id, to_account_id, origin)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2',
            pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), 'manual')$$,
  '23514', null,
  'a transfer has at least one movement'
);
select throws_ok(
  $$insert into public.transfers (household_id, from_account_id, to_account_id, out_transaction_id, origin)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2',
            pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), '00000000-0000-4000-8000-000000000101', 'manual')$$,
  '23514', null,
  'a transfer is between two accounts of the same owner'
);
select throws_ok(
  $$insert into public.transfers (household_id, from_account_id, to_account_id, out_transaction_id, origin)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e3',
            '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-000000000101', 'manual')$$,
  '23514', null,
  'the outgoing movement is on the first account'
);
select lives_ok(
  $$update public.transfers set deleted_at = now() where id = '00000000-0000-4000-8000-000000000301'$$,
  'the owner undoes a transfer'
);
select throws_ok(
  $$delete from public.transfers where id = '00000000-0000-4000-8000-000000000301'$$,
  '42501', null,
  'transfers are deleted only with deleted_at'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is_empty('select 1 from public.transfers', 'another member does not see the transfers');
select throws_ok(
  $$insert into public.transfers (household_id, from_account_id, to_account_id, out_transaction_id, origin)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2',
            pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), '00000000-0000-4000-8000-000000000101', 'manual')$$,
  '42501', null,
  'nor creates transfers on the accounts of others'
);

-- An installment plan on Anna's card, shared with Bruno.
reset role;
insert into public.installment_plans (
  id, household_id, account_id, merchant, total_cents, installments_count, purchase_date,
  installments_before_start, category_id
) values (
  '00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000e3', 'Negozio di prova', 30000, 3, current_date - 70, 1,
  pg_temp.category('expense', 'Casa', 'Arredo ed elettrodomestici')
);
insert into public.installment_plan_shares (plan_id, member_id, weight) values
  ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000000a1', 1),
  ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000000b1', 1);
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency, installment_plan_id
) values (
  '00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000e3', 'bank', '00000000-0000-4000-8000-0000000000a1',
  current_date - 1, -10000, 'EUR', '00000000-0000-4000-8000-000000000401'
);
select pg_temp.check_deferred();

select results_eq(
  $$select category_id = pg_temp.category('expense', 'Casa', 'Arredo ed elettrodomestici'), installment_plan_id
    from public.transaction_lines where transaction_id = '00000000-0000-4000-8000-000000000103'$$,
  $$values (true, '00000000-0000-4000-8000-000000000401'::uuid)$$,
  'an installment inherits the category of its plan'
);
select throws_ok(
  $$update public.installment_plans set installments_before_start = 4
    where id = '00000000-0000-4000-8000-000000000401'$$,
  '23514', null,
  'the installments before the start date are not more than the installments'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  'select merchant from public.installment_plans',
  $$values ('Negozio di prova'::text)$$,
  'a member with a weight sees the plan'
);
select is(
  (select count(*)::int from public.installment_plan_shares),
  2,
  'and its weights'
);
update public.installment_plans set category_id = null
  where id = '00000000-0000-4000-8000-000000000401';
select throws_ok(
  $$insert into public.installment_plan_shares (plan_id, member_id, weight)
    values ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000000c1', 1)$$,
  '42501', null,
  'only the owner of the account changes the weights'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is_empty('select 1 from public.installment_plans', 'a member without a weight does not see the plan');

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$update public.installment_plans set category_id = pg_temp.category('expense', 'Casa', 'Manutenzione e riparazioni')
    where id = '00000000-0000-4000-8000-000000000401'$$,
  'the owner of the account changes the category of the plan'
);
select is(
  (select category_id from public.installment_plans where id = '00000000-0000-4000-8000-000000000401'),
  pg_temp.category('expense', 'Casa', 'Manutenzione e riparazioni'),
  'Bruno, with a weight but not the owner, changed nothing'
);
select lives_ok(
  $$insert into public.installment_plan_shares (plan_id, member_id, weight)
    values ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000000c1', 1)$$,
  'the owner adds a weight to the plan'
);

select * from finish();
rollback;
