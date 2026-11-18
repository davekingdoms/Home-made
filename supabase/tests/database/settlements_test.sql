-- Settlements: seen and changed only by the two members, manual from the
-- app, members of the same household and active, dates, sides linked by the
-- server. Invented users: Anna (a1) and Bruno (b1) from 60 days ago, Carla
-- (c1) from 10 days ago, a former member (e9) in "Casa di prova"; Dario
-- (d1) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

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
   '00000000-0000-4000-8000-00000000000c', current_date - 10);
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000e9', '00000000-0000-4000-8000-0000000000f1',
   null, current_date - 60, now());
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60);

-- Movements of Anna and Bruno, for the sides.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), 'manual',
   '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1', current_date - 1, 1500, 'EUR'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
   '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', current_date - 1, -1500, 'EUR');

select has_table('public', 'settlements', 'settlements exists');
select policies_are(
  'public', 'settlements',
  array['settlements_select_pair', 'settlements_insert_pair', 'settlements_update_pair'],
  'settlements has the select, insert and update of the two members'
);

-- Bruno marks as paid 15,00 to Anna.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$insert into public.settlements (
      id, household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-0000000000f1',
      '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1',
      1500, 'EUR', current_date - 1, 'manual', '00000000-0000-4000-8000-0000000000b1'
    )$$,
  'a member marks a settlement as paid'
);
select results_eq(
  'select amount_cents from public.settlements',
  $$values (1500::bigint)$$,
  'the payer sees it'
);
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b1',
      '00000000-0000-4000-8000-0000000000a1', 1500, 'EUR', current_date, 'paypal',
      '00000000-0000-4000-8000-0000000000b1'
    )$$,
  '42501', null,
  'the settlements of PayPal and of the bank come from the server'
);
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b1',
      '00000000-0000-4000-8000-0000000000b1', 1500, 'EUR', current_date, 'manual',
      '00000000-0000-4000-8000-0000000000b1'
    )$$,
  '23514', null,
  'payer and payee are two members'
);
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b1',
      '00000000-0000-4000-8000-0000000000a1', 0, 'EUR', current_date, 'manual',
      '00000000-0000-4000-8000-0000000000b1'
    )$$,
  '23514', null,
  'the amount is positive'
);
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b1',
      '00000000-0000-4000-8000-0000000000d1', 1500, 'EUR', current_date, 'manual',
      '00000000-0000-4000-8000-0000000000b1'
    )$$,
  'P0001', 'member_not_eligible',
  'no settlement with Dario, of another household'
);
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b1',
      '00000000-0000-4000-8000-0000000000e9', 1500, 'EUR', current_date, 'manual',
      '00000000-0000-4000-8000-0000000000b1'
    )$$,
  'P0001', 'member_not_eligible',
  'no settlement with a member who left'
);
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b1',
      '00000000-0000-4000-8000-0000000000c1', 1500, 'EUR', current_date - 20, 'manual',
      '00000000-0000-4000-8000-0000000000b1'
    )$$,
  'P0001', 'member_not_eligible',
  'no settlement before the start date of one of the two'
);
select throws_ok(
  $$update public.settlements set payer_transaction_id = '00000000-0000-4000-8000-000000000102'
    where id = '00000000-0000-4000-8000-000000000501'$$,
  '42501', null,
  'the sides are linked by the server'
);
select throws_ok(
  $$update public.settlements set payee_member_id = '00000000-0000-4000-8000-0000000000c1'
    where id = '00000000-0000-4000-8000-000000000501'$$,
  '42501', null,
  'the two members do not change'
);

-- Anna, the payee
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$update public.settlements set amount_cents = 1600
    where id = '00000000-0000-4000-8000-000000000501'$$,
  'the payee corrects the amount'
);
select results_eq(
  'select amount_cents, version from public.settlements',
  $$values (1600::bigint, 2)$$,
  'the payee sees the settlement, with the new version'
);

-- Carla, not involved
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is_empty('select 1 from public.settlements', 'a third member does not see the settlement');
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin, created_by_member_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b1',
      '00000000-0000-4000-8000-0000000000a1', 1500, 'EUR', current_date, 'manual',
      '00000000-0000-4000-8000-0000000000c1'
    )$$,
  '42501', null,
  'nor creates one between two other members'
);

-- The server links the sides.
reset role;
select throws_ok(
  $$update public.settlements set payer_transaction_id = '00000000-0000-4000-8000-000000000101'
    where id = '00000000-0000-4000-8000-000000000501'$$,
  '23514', null,
  'the side of the payer is a movement of the payer'
);
select lives_ok(
  $$update public.settlements
    set payer_transaction_id = '00000000-0000-4000-8000-000000000102',
        payee_transaction_id = '00000000-0000-4000-8000-000000000101'
    where id = '00000000-0000-4000-8000-000000000501'$$,
  'the server links both sides'
);
select throws_ok(
  $$insert into public.settlements (
      household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin
    ) values (
      '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000d1',
      '00000000-0000-4000-8000-0000000000a1', 1500, 'EUR', current_date, 'paypal'
    )$$,
  'P0001', 'member_not_eligible',
  'not even the server settles with Dario'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$update public.settlements set deleted_at = now() where id = '00000000-0000-4000-8000-000000000501'$$,
  'the payer deletes the settlement with deleted_at'
);

reset role;
set local role anon;
select throws_ok(
  'select id from public.settlements',
  '42501', null,
  'anon cannot read settlements'
);

select * from finish();
rollback;
