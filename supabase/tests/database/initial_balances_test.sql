-- Initial balance between the members: only who starts with the household,
-- zero sum, "Nessun saldo da riportare" as zeros, active members of the
-- household only. Invented users: Anna (a1) and Bruno (b1) start with
-- "Casa di prova"; Carla (c1) joined later; a former member (e9); Dario
-- (d1) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

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

-- Balances as JSON: amounts of Anna, Bruno and a third member (null: none).
create function pg_temp.balances(anna bigint, bruno bigint, other_id uuid, other bigint)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(jsonb_build_object('member_id', m, 'amount_cents', a)), '[]'::jsonb)
  from (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, anna),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, bruno),
    (other_id, other)
  ) as t (m, a)
  where m is not null and a is not null
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
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30),
  ('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 30);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 30);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 30);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date);
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000e9', '00000000-0000-4000-8000-0000000000f1',
   null, current_date - 30, now());
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 30);

select has_table('public', 'initial_balances', 'initial_balances exists');

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$select public.set_initial_balances(pg_temp.balances(1000, -500, null, null))$$,
  'P0001', 'initial_balance_not_zero_sum',
  'an initial balance with a total other than zero is refused'
);
select throws_ok(
  $$select public.set_initial_balances(
      pg_temp.balances(1000, null, '00000000-0000-4000-8000-0000000000c1', -1000))$$,
  'P0001', 'member_not_eligible',
  'a member who started after the household has no initial balance'
);
select throws_ok(
  $$select public.set_initial_balances(
      pg_temp.balances(1000, null, '00000000-0000-4000-8000-0000000000d1', -1000))$$,
  'P0001', 'member_not_eligible',
  'Dario, of another household, has no initial balance here'
);
select throws_ok(
  $$select public.set_initial_balances(
      pg_temp.balances(1000, null, '00000000-0000-4000-8000-0000000000e9', -1000))$$,
  'P0001', 'member_not_eligible',
  'a member who left has no initial balance'
);
select throws_ok(
  $$select public.set_initial_balances(
      pg_temp.balances(1000, null, '00000000-0000-4000-8000-0000000000a1', -1000))$$,
  'P0001', 'invalid_balances',
  'a member appears once in the list'
);
select throws_ok(
  $$select public.set_initial_balances('{"member_id": "00000000-0000-4000-8000-0000000000a1"}')$$,
  'P0001', 'invalid_balances',
  'the balances are a list'
);
select lives_ok(
  $$select public.set_initial_balances(pg_temp.balances(1000, -1000, null, null))$$,
  'Anna saves the initial balance: Bruno owes her 10,00'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select results_eq(
  'select member_id, amount_cents from public.initial_balances order by member_id',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1000::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -1000::bigint)$$,
  'every active member reads it; it concerns only who starts with the household'
);

-- Bruno: "Nessun saldo da riportare"
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$select public.set_initial_balances('[]')$$,
  'Bruno saves "Nessun saldo da riportare"'
);
select results_eq(
  'select member_id, amount_cents, set_by_member_id from public.initial_balances order by member_id',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 0::bigint, '00000000-0000-4000-8000-0000000000b1'::uuid),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 0::bigint, '00000000-0000-4000-8000-0000000000b1'::uuid)$$,
  'saved as zeros for every member who starts with the household'
);
select results_eq(
  'select distinct version from public.initial_balances',
  $$values (2)$$,
  'each call bumps every row once, for the rule of the conflicts'
);
select throws_ok(
  $$insert into public.initial_balances (household_id, member_id, amount_cents, set_by_member_id)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000c1', 0,
            '00000000-0000-4000-8000-0000000000b1')$$,
  '42501', null,
  'the initial balance is written only with the function'
);
select throws_ok(
  $$update public.initial_balances set amount_cents = 5
    where member_id = '00000000-0000-4000-8000-0000000000b1'$$,
  '42501', null,
  'nor changed directly'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is_empty('select 1 from public.initial_balances', 'Dario does not see the initial balance of "Casa di prova"');

reset role;
select throws_ok(
  $$insert into public.initial_balances (household_id, member_id, amount_cents, set_by_member_id)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000d1', 0,
            '00000000-0000-4000-8000-0000000000a1')$$,
  'P0001', 'member_not_eligible',
  'not even the server writes one for Dario'
);
update public.members set left_at = now() where id = '00000000-0000-4000-8000-0000000000c1';

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select throws_ok(
  $$select public.set_initial_balances('[]')$$,
  'P0001', 'not_member',
  'who left the household does not set it'
);

reset role;
set local role anon;
select throws_ok(
  $$select public.set_initial_balances('[]')$$,
  '42501', null,
  'anon cannot call set_initial_balances'
);

select * from finish();
rollback;
