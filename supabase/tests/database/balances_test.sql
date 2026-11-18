-- member_balances() on a case computed by hand (docs/spec/schema.md, 10).
-- Invented users: Anna (a1), Bruno (b1) and Carla (c1), all from the start
-- of "Casa di prova"; Dario (d1) alone in his household.
--
-- net = sum of the lines paid (-amount) + sum of own shares (amount)
--     + settlements paid - settlements received + initial balance
-- (cents; positive = credit)
--
--   1. Anna pays the supermarket -90,00, shared 1:1:1 (-30,00 each)
--        Anna +9000 - 3000 = +6000   Bruno -3000   Carla -3000
--   2. Bruno pays the electricity -60,00, shared Anna:Bruno 1:1
--        Anna -3000   Bruno +6000 - 3000 = +3000
--   3. Anna pays -20,00 "Per Carla" (only Carla has a share)
--        Anna +2000   Carla -2000
--   4. Bruno receives +30,00 of shared income, 1:1:1
--        Anna +1000   Bruno -3000 + 1000 = -2000   Carla +1000
--   5. Carla advances -50,00 for a friend, shared Anna:Carla 1:1
--        Anna -2500   Carla +5000 - 2500 = +2500
--      the friend gives back +30,00 to Carla; the refund inherits 1:1
--        Anna +1500   Carla -3000 + 1500 = -1500
--   6. Bruno pays Anna a settlement of 15,00
--        Anna -1500   Bruno +1500
--   7. Initial balance: Anna +5,00, Bruno -2,00, Carla -3,00
--        Anna +500    Bruno -200    Carla -300
--
--   Anna  = 6000 - 3000 + 2000 + 1000 - 2500 + 1500 - 1500 + 500 = +4000
--   Bruno = -3000 + 3000 - 2000 + 1500 - 200                     =  -700
--   Carla = -3000 - 2000 + 1000 + 2500 - 1500 - 300              = -3300
--   Total = 4000 - 700 - 3300 = 0
--
-- And what must not move anything: a line in the inbox (Mia), a settlement
-- line of Bruno (Mia), a deleted movement, a movement in USD, a deleted
-- settlement.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

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

-- A movement entered by the server (bank) or by its member (cash).
create function pg_temp.movement(id uuid, member_id uuid, days_ago int, amount bigint, currency text)
returns void
language sql
as $$
  insert into public.transactions (
    id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
  ) values (
    movement.id, '00000000-0000-4000-8000-0000000000f1',
    case when movement.member_id = '00000000-0000-4000-8000-0000000000a1'
      then '00000000-0000-4000-8000-0000000000e2'::uuid
      else pg_temp.cash_of(movement.member_id) end,
    case when movement.member_id = '00000000-0000-4000-8000-0000000000a1' then 'bank' else 'manual' end,
    movement.member_id,
    case when movement.member_id = '00000000-0000-4000-8000-0000000000a1' then null else movement.member_id end,
    current_date - days_ago, amount, movement.currency
  )
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
   '00000000-0000-4000-8000-00000000000b', current_date - 60, now() - interval '59 days');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 60, now() - interval '58 days');
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60);
insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Banca di Prova');

-- The movements
select pg_temp.movement('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000a1', 20, -9000, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000b1', 15, -6000, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000a1', 10, -2000, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000104', '00000000-0000-4000-8000-0000000000b1', 9, 3000, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-0000000000c1', 8, -5000, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-0000000000c1', 3, 3000, 'EUR');
-- What must not move anything
select pg_temp.movement('00000000-0000-4000-8000-000000000107', '00000000-0000-4000-8000-0000000000a1', 1, -1234, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000108', '00000000-0000-4000-8000-0000000000b1', 2, -1500, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000109', '00000000-0000-4000-8000-0000000000b1', 5, -10000, 'EUR');
select pg_temp.movement('00000000-0000-4000-8000-000000000110', '00000000-0000-4000-8000-0000000000a1', 4, -4000, 'USD');
select pg_temp.check_deferred();

set local role authenticated;

-- Anna: 1 and 3; the USD movement shared with Bruno.
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transaction_lines set kind = 'expense'
  where transaction_id in ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000103',
                           '00000000-0000-4000-8000-000000000110');
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000101'), pg_temp.shares(1, 1, 1));
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000103'), pg_temp.shares(null, null, 1));
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000110'), pg_temp.shares(1, 1, null));

-- Bruno: 2 and 4; a shared movement he then deletes.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
update public.transaction_lines set kind = 'expense'
  where transaction_id in ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000109');
update public.transaction_lines set kind = 'income'
  where transaction_id = '00000000-0000-4000-8000-000000000104';
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000102'), pg_temp.shares(1, 1, null));
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000104'), pg_temp.shares(1, 1, 1));
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000109'), pg_temp.shares(1, 1, null));
update public.transactions set deleted_at = now() where id = '00000000-0000-4000-8000-000000000109';

-- Carla: 5, the advance, and its refund.
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
update public.transaction_lines set kind = 'advance'
  where transaction_id = '00000000-0000-4000-8000-000000000105';
update public.transaction_lines set kind = 'refund'
  where transaction_id = '00000000-0000-4000-8000-000000000106';
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000105'), pg_temp.shares(1, null, 1));
insert into public.contacts (id, household_id, owner_member_id, name) values
  ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000c1', 'Amica di prova');
insert into public.advances (id, line_id, contact_id, expected_cents) values
  ('00000000-0000-4000-8000-000000000602', pg_temp.line('00000000-0000-4000-8000-000000000105'),
   '00000000-0000-4000-8000-000000000601', 5000);
insert into public.advance_repayments (advance_id, line_id, amount_cents) values
  ('00000000-0000-4000-8000-000000000602', pg_temp.line('00000000-0000-4000-8000-000000000106'), 3000);

-- Bruno: 6, the settlement, with its line of his alone; a deleted one.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
insert into public.settlements (
  id, household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
) values
  ('00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1',
   1500, 'EUR', current_date - 2, 'manual', '00000000-0000-4000-8000-0000000000b1'),
  ('00000000-0000-4000-8000-000000000502', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1',
   999, 'EUR', current_date - 2, 'manual', '00000000-0000-4000-8000-0000000000b1');
update public.settlements set deleted_at = now() where id = '00000000-0000-4000-8000-000000000502';
update public.transaction_lines
  set kind = 'settlement', settlement_id = '00000000-0000-4000-8000-000000000501'
  where transaction_id = '00000000-0000-4000-8000-000000000108';

-- Anna: 7, the initial balance.
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select public.set_initial_balances(jsonb_build_array(
  jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000a1', 'amount_cents', 500),
  jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000b1', 'amount_cents', -200),
  jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000c1', 'amount_cents', -300)
));
select lives_ok('select pg_temp.check_deferred()', 'every movement, share and refund holds');

-- Carla looks at the balances.
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select results_eq(
  'select member_id, net_cents from public.member_balances()',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 4000::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -700::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, -3300::bigint)$$,
  'the net balances of the case computed by hand'
);
select is(
  (select sum(net_cents)::bigint from public.member_balances()),
  0::bigint,
  'the net balances of the household add up to zero'
);
select is_empty('select 1 from public.settlements', 'Carla does not see the settlement of Bruno and Anna, only its effect');
select is_empty(
  $$select 1 from public.transaction_lines where transaction_id = '00000000-0000-4000-8000-000000000102'$$,
  'nor the lines she is not involved in'
);

-- Anna deletes the settlement: the balances move, the total stays zero.
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.settlements set deleted_at = now() where id = '00000000-0000-4000-8000-000000000501';
select results_eq(
  'select member_id, net_cents from public.member_balances()',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 5500::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -2200::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, -3300::bigint)$$,
  'a deleted settlement no longer counts'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select results_eq(
  'select member_id, net_cents from public.member_balances()',
  $$values ('00000000-0000-4000-8000-0000000000d1'::uuid, 0::bigint)$$,
  'Dario gets only his own household'
);

reset role;
set local role anon;
select throws_ok(
  'select * from public.member_balances()',
  '42501', null,
  'anon cannot call member_balances'
);

select * from finish();
rollback;
