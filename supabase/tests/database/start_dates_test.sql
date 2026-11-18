-- Joining a household that has not started yet: the start date of the new
-- member is the one of the household and does not move. Invented users:
-- Anna (a) creates "Casa di prova", starting in 15 days; Bruno (b) and
-- Carla (c) join it before then.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

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

create temp table invite_codes (who text primary key, code text, token text);
grant select, insert on invite_codes to authenticated;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla');

set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select public.create_household('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date + 15);
insert into invite_codes select 'bruno', code, token from public.create_invite('per Bruno');
insert into invite_codes select 'carla', code, token from public.create_invite('per Carla');

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$select error, household_id
    from public.redeem_invite(code => (select code from invite_codes where who = 'bruno'),
                              cash_opening_cents => 2000)$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'Bruno joins before the household starts'
);
select results_eq(
  'select kind, opening_balance_cents from public.accounts',
  $$values ('cash'::text, null::bigint)$$,
  'his cash waits for his start date: no opening balance yet'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values (current_date + 15)$$,
  'the new member starts with the household, not today'
);
select throws_ok(
  $$select public.set_my_start_date(current_date + 15)$$,
  'P0001', 'household_not_started',
  'the start date does not change before the household starts'
);
select throws_ok(
  $$select public.set_my_start_date(current_date)$$,
  'P0001', 'household_not_started',
  'not even to an earlier date'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$select public.set_my_start_date(current_date + 15)$$,
  'P0001', 'household_not_started',
  'the same for the creator'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select results_eq(
  $$select error, household_id
    from public.redeem_invite(token => (select token from invite_codes where who = 'carla'))$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'Carla joins before the household starts'
);
select is(
  (select count(*)::int from public.members),
  3,
  '"Casa di prova" has three members'
);
select results_eq(
  'select distinct start_date from public.members',
  $$values (current_date + 15)$$,
  'all three start with the household'
);

select * from finish();
rollback;
