-- Transactions: the line of a new transaction, visibility, start date,
-- bank data that the app does not change, manual movements, the amount
-- of a movement with one or more lines. Invented users: Anna (a1), Bruno
-- (b1) and Carla (c1) in "Casa di prova", Dario (d1) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(36);

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

-- Runs the deferred checks now, as at the end of an API call.
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

create function pg_temp.first_line(transaction_id uuid)
returns uuid
language sql
security definer
as $$
  select l.id from public.transaction_lines l
  where l.transaction_id = first_line.transaction_id and l.position = 1
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
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 60),
  ('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 60);
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60, now() - interval '60 days');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 30, now() - interval '30 days');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 10, now() - interval '10 days');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60, now() - interval '60 days');

-- Anna's bank, and a movement imported by the server.
insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Banca di Prova');
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency,
  description, counterparty
) values (
  '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000e2', 'bank', '00000000-0000-4000-8000-0000000000a1',
  current_date - 5, -5000, 'EUR', 'PAGAMENTO POS SUPERMERCATO DI PROVA', 'Supermercato di prova'
);

-- Structure
select has_table('public', 'transactions', 'transactions exists');
select has_table('public', 'transaction_lines', 'transaction_lines exists');
select has_table('public', 'line_shares', 'line_shares exists');
select has_table('public', 'line_tags', 'line_tags exists');
select has_table('public', 'transfers', 'transfers exists');

-- A new transaction
select results_eq(
  $$select position, amount_cents, kind, paid_by_member_id, movement_date, counterparty
    from public.transaction_lines where transaction_id = '00000000-0000-4000-8000-000000000101'$$,
  $$values (1::smallint, -5000::bigint, null::text, '00000000-0000-4000-8000-0000000000a1'::uuid,
            current_date - 5, 'Supermercato di prova'::text)$$,
  'a new transaction has one line with the whole amount and the copies'
);
select results_eq(
  $$select s.member_id, s.weight, s.amount_cents
    from public.line_shares s
    where s.line_id = pg_temp.first_line('00000000-0000-4000-8000-000000000101')$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::numeric, -5000::bigint)$$,
  'with a share of 100% to the payer'
);
select ok(
  exists (
    select 1 from public.transaction_lines
    where transaction_id = '00000000-0000-4000-8000-000000000101' and kind is null
  ),
  'and it is to classify'
);
select lives_ok('select pg_temp.check_deferred()', 'the sums of a new transaction hold');

-- Visibility
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  'select id from public.transactions',
  $$values ('00000000-0000-4000-8000-000000000101'::uuid)$$,
  'the owner of the account sees the transaction'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is_empty('select 1 from public.transactions', 'another member does not see it');
select is_empty('select 1 from public.transaction_lines', 'nor its lines');
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is_empty('select 1 from public.transactions', 'Dario sees nothing of "Casa di prova"');

-- No movement before the start date of the payer
reset role;
select throws_ok(
  $$insert into public.transactions (
      household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2', 'bank',
      '00000000-0000-4000-8000-0000000000a1', current_date - 61, -100, 'EUR'
    )$$,
  'P0001', 'movement_before_start_date',
  'no movement of the bank before the start date of the owner'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select throws_ok(
  $$insert into public.transactions (
      id, household_id, account_id, source, paid_by_member_id, entered_by_member_id,
      movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000f1',
      pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
      '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1',
      current_date - 31, -1200, 'EUR'
    )$$,
  'P0001', 'movement_before_start_date',
  'no manual movement before the start date'
);
select lives_ok(
  $$insert into public.transactions (
      id, household_id, account_id, source, paid_by_member_id, entered_by_member_id,
      movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000f1',
      pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
      '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1',
      current_date - 1, -1200, 'EUR'
    );
    select pg_temp.check_deferred()$$,
  'a member enters a manual movement with the id generated on the device'
);
select throws_ok(
  $$insert into public.transactions (
      household_id, account_id, source, paid_by_member_id, entered_by_member_id,
      movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-0000000000f1', pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
      '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', current_date, -100, 'EUR'
    ) returning id$$,
  '42501', null,
  'the app inserts without reading the row back: the read policy finds it by id'
);
select throws_ok(
  $$update public.transactions set movement_date = current_date - 31
    where id = '00000000-0000-4000-8000-000000000102'$$,
  'P0001', 'movement_before_start_date',
  'not even changing the date'
);

-- The only line follows the amount and the copies.
select lives_ok(
  $$update public.transactions set amount_cents = -1500, counterparty = 'Bar di prova'
    where id = '00000000-0000-4000-8000-000000000102';
    select pg_temp.check_deferred()$$,
  'the amount of a manual movement with one line changes'
);
select results_eq(
  $$select l.amount_cents, l.counterparty, s.amount_cents
    from public.transaction_lines l join public.line_shares s on s.line_id = l.id
    where l.transaction_id = '00000000-0000-4000-8000-000000000102'$$,
  $$values (-1500::bigint, 'Bar di prova'::text, -1500::bigint)$$,
  'its line, its share and the copy of the counterparty follow'
);

-- What the app does not change
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$insert into public.transactions (
      household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2', 'bank',
      '00000000-0000-4000-8000-0000000000a1', current_date, -100, 'EUR'
    )$$,
  '42501', null,
  'the app inserts only manual movements'
);
select throws_ok(
  $$update public.transactions set amount_cents = -4000
    where id = '00000000-0000-4000-8000-000000000101'$$,
  '42501', null,
  'the amount of a movement of the bank does not change from the app'
);
select throws_ok(
  $$update public.transactions set description = 'Altro'
    where id = '00000000-0000-4000-8000-000000000101'$$,
  '42501', null,
  'nor its description'
);
select lives_ok(
  $$update public.transactions set counterparty = 'Supermercato Prova'
    where id = '00000000-0000-4000-8000-000000000101'$$,
  'the owner corrects the counterparty of a movement of the bank'
);
select throws_ok(
  $$update public.transactions set deleted_at = now()
    where id = '00000000-0000-4000-8000-000000000101'$$,
  '42501', null,
  'Anna cannot delete her imported movement'
);

reset role;
select lives_ok(
  $$update public.transactions set amount_cents = -5500
    where id = '00000000-0000-4000-8000-000000000101';
    select pg_temp.check_deferred()$$,
  'the server changes the amount of a movement of the bank'
);
select results_eq(
  $$select amount_cents, counterparty from public.transaction_lines
    where transaction_id = '00000000-0000-4000-8000-000000000101'$$,
  $$values (-5500::bigint, 'Supermercato Prova'::text)$$,
  'its line follows'
);

-- Payer, account and who enters
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$insert into public.transactions (
      household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2', 'manual',
      '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', current_date, -100, 'EUR'
    )$$,
  '23514', null,
  'with an account, the payer is its owner'
);
select throws_ok(
  $$insert into public.transactions (
      household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-0000000000f1', pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
      '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', current_date, -100, 'EUR'
    )$$,
  '42501', null,
  'a member does not enter movements on the accounts of others'
);
select lives_ok(
  $$insert into public.transactions (
      id, household_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
    ) values (
      '00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000f1', 'manual',
      '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', current_date - 2, -800, 'EUR'
    );
    select pg_temp.check_deferred()$$,
  'a member enters a manual movement for another member, without account'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select isnt_empty(
  $$select 1 from public.transactions where id = '00000000-0000-4000-8000-000000000103'$$,
  'who paid sees the manual movement without account'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is_empty(
  $$select 1 from public.transactions where id = '00000000-0000-4000-8000-000000000103'$$,
  'a third member does not'
);

-- A movement with more lines: the amount does not change alone.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$select public.split_line(
      pg_temp.first_line('00000000-0000-4000-8000-000000000102'),
      '[{"id": "00000000-0000-4000-8000-000000000201", "amount_cents": -500}]');
    select pg_temp.check_deferred()$$,
  'the owner splits a line'
);
select throws_ok(
  $$update public.transactions set amount_cents = -2000
    where id = '00000000-0000-4000-8000-000000000102';
    select pg_temp.check_deferred()$$,
  '23514', 'lines_sum_mismatch',
  'with more lines the amount does not change: the lines no longer add up'
);
select lives_ok(
  $$update public.transactions set deleted_at = now()
    where id = '00000000-0000-4000-8000-000000000102'$$,
  'a manual movement is deleted with deleted_at'
);

-- Not signed in
reset role;
set local role anon;
select throws_ok(
  'select id from public.transactions',
  '42501', null,
  'anon cannot read transactions'
);

select * from finish();
rollback;
