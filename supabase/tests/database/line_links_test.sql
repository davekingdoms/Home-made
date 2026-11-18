-- Links of the lines to settlements, transfers and installment plans
-- (docs/spec/schema.md, 5): only objects of the household that concern the
-- line, from the app and from the server (line_link_not_valid). Invented
-- users: Anna (a1) with a bank account, a card and her cash, Bruno (b1) and
-- Carla (c1) in "Casa di prova"; Dario (d1) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

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
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60);

insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Banca di Prova'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Carta di Prova');

-- Movements: Anna's withdrawal (bank -> cash) and a card payment; one
-- cash movement each for Bruno, Carla and Dario.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000e2', 'bank', '00000000-0000-4000-8000-0000000000a1', null,
   current_date - 3, -1000, 'EUR'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), 'manual', '00000000-0000-4000-8000-0000000000a1',
   '00000000-0000-4000-8000-0000000000a1', current_date - 3, 1000, 'EUR'),
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000e3', 'bank', '00000000-0000-4000-8000-0000000000a1', null,
   current_date - 2, -3000, 'EUR'),
  ('00000000-0000-4000-8000-000000000104', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual', '00000000-0000-4000-8000-0000000000b1',
   '00000000-0000-4000-8000-0000000000b1', current_date - 1, -1500, 'EUR'),
  ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000c1'), 'manual', '00000000-0000-4000-8000-0000000000c1',
   '00000000-0000-4000-8000-0000000000c1', current_date - 1, -500, 'EUR'),
  ('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-0000000000f2',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000d1'), 'manual', '00000000-0000-4000-8000-0000000000d1',
   '00000000-0000-4000-8000-0000000000d1', current_date - 1, -700, 'EUR');

-- In "Casa di prova": a settlement from Bruno to Anna, Anna's withdrawal as
-- a transfer, an installment plan on Anna's card.
insert into public.settlements (
  id, household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
) values (
  '00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1',
  1500, 'EUR', current_date - 1, 'manual', '00000000-0000-4000-8000-0000000000b1'
);
insert into public.transfers (id, household_id, from_account_id, to_account_id, out_transaction_id, in_transaction_id, origin)
values ('00000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-0000000000f1',
        '00000000-0000-4000-8000-0000000000e2', pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'),
        '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102', 'manual');
insert into public.installment_plans (
  id, household_id, account_id, merchant, total_cents, installments_count, purchase_date
) values (
  '00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000e3', 'Negozio di prova', 9000, 3, current_date - 2
);

set local role authenticated;

-- settlement_id
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$update public.transaction_lines set kind = 'settlement', settlement_id = '00000000-0000-4000-8000-000000000501'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000104')$$,
  'the payer links his line to the settlement'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select throws_ok(
  $$update public.transaction_lines set kind = 'settlement', settlement_id = '00000000-0000-4000-8000-000000000501'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000105')$$,
  'P0001', 'line_link_not_valid',
  'Carla does not link her line to the settlement between Anna and Bruno'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select throws_ok(
  $$update public.transaction_lines set kind = 'settlement', settlement_id = '00000000-0000-4000-8000-000000000501'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000106')$$,
  'P0001', 'line_link_not_valid',
  'Dario does not link his line to a settlement of "Casa di prova"'
);

-- transfer_id
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$update public.transaction_lines set kind = 'transfer', transfer_id = '00000000-0000-4000-8000-000000000301'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000101')$$,
  'the owner links the line of an account of the transfer'
);
select throws_ok(
  $$update public.transaction_lines set kind = 'transfer', transfer_id = '00000000-0000-4000-8000-000000000301'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000103')$$,
  'P0001', 'line_link_not_valid',
  'not a line of another account'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select throws_ok(
  $$update public.transaction_lines set kind = 'transfer', transfer_id = '00000000-0000-4000-8000-000000000301'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000106')$$,
  'P0001', 'line_link_not_valid',
  'Dario does not link his line to a transfer of "Casa di prova"'
);

-- installment_plan_id
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$update public.transaction_lines set installment_plan_id = '00000000-0000-4000-8000-000000000401'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000103')$$,
  'the owner links a line of the card to its plan'
);
select throws_ok(
  $$update public.transaction_lines set installment_plan_id = '00000000-0000-4000-8000-000000000401'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000102')$$,
  'P0001', 'line_link_not_valid',
  'not a line of another account'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select throws_ok(
  $$update public.transaction_lines set installment_plan_id = '00000000-0000-4000-8000-000000000401'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000106')$$,
  'P0001', 'line_link_not_valid',
  'Dario does not link his line to a plan of "Casa di prova"'
);

-- The server neither.
reset role;
select throws_ok(
  $$update public.transaction_lines set kind = 'settlement', settlement_id = '00000000-0000-4000-8000-000000000501'
    where id = pg_temp.line('00000000-0000-4000-8000-000000000106')$$,
  'P0001', 'line_link_not_valid',
  'not even the server links a line of Dario to "Casa di prova"'
);
select throws_ok(
  $$insert into public.transactions (
      household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency, installment_plan_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e2', 'bank',
      '00000000-0000-4000-8000-0000000000a1', current_date, -3000, 'EUR', '00000000-0000-4000-8000-000000000401'
    )$$,
  'P0001', 'line_link_not_valid',
  'an installment on another account than its plan gets no line'
);

select * from finish();
rollback;
