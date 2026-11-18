-- RLS of public.devices: only the owner, also within the household.
-- Invented users: Anna (a) and Bruno (b) in "Casa di prova".
begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

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

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30);
insert into public.members (household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a', current_date - 30),
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000b', current_date - 30);

-- Bruno already has a phone.
insert into public.devices (id, user_id, platform, name) values
  ('00000000-0000-4000-8000-0000000000db', '00000000-0000-4000-8000-00000000000b', 'android', 'Telefono di prova');

-- Structure
select has_table('public', 'devices', 'devices exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.devices'::regclass),
  'RLS is enabled on devices'
);
select policies_are(
  'public', 'devices',
  array['devices_all_own'],
  'devices has only the own-row policy'
);

-- Anna, signed in
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');

select lives_ok(
  $$insert into public.devices (id, user_id, platform, name)
    values ('00000000-0000-4000-8000-0000000000da', '00000000-0000-4000-8000-00000000000a', 'android', 'Tablet di prova')$$,
  'a user registers a device with the id generated on the device'
);
select results_eq(
  'select id from public.devices',
  $$values ('00000000-0000-4000-8000-0000000000da'::uuid)$$,
  'a member does not see the devices of the other members'
);
select results_eq(
  $$select preferences from public.devices
    where id = '00000000-0000-4000-8000-0000000000da'$$,
  $$values ('{}'::jsonb)$$,
  'the preferences of a device start empty'
);
select throws_ok(
  $$insert into public.devices (id, user_id, platform)
    values ('00000000-0000-4000-8000-0000000000dc', '00000000-0000-4000-8000-00000000000b', 'android')$$,
  '42501', null,
  'a user cannot register a device of another user'
);
select throws_ok(
  $$insert into public.devices (id, user_id, platform)
    values ('00000000-0000-4000-8000-0000000000dc', '00000000-0000-4000-8000-00000000000a', 'web')$$,
  '23514', null,
  'only Android and iOS devices'
);
select lives_ok(
  $$update public.devices set fcm_token = 'token-di-prova', preferences = '{"theme": "dark"}'
    where id = '00000000-0000-4000-8000-0000000000da'$$,
  'a user changes their own device'
);
select is(
  (select version from public.devices where id = '00000000-0000-4000-8000-0000000000da'),
  2,
  'every update bumps the version'
);
update public.devices set name = 'Changed by Anna'
  where id = '00000000-0000-4000-8000-0000000000db';
delete from public.devices
  where id = '00000000-0000-4000-8000-0000000000db';

reset role;
select results_eq(
  $$select name from public.devices where id = '00000000-0000-4000-8000-0000000000db'$$,
  $$values ('Telefono di prova'::text)$$,
  'a user cannot change or delete the device of another user'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$delete from public.devices where id = '00000000-0000-4000-8000-0000000000da'$$,
  'a user removes their own device'
);
select is_empty(
  'select 1 from public.devices',
  'the removed device is gone'
);

-- Not signed in
reset role;
set local role anon;
select throws_ok(
  'select id from public.devices',
  '42501', null,
  'anon cannot read devices'
);
select throws_ok(
  $$insert into public.devices (id, user_id, platform)
    values ('00000000-0000-4000-8000-0000000000dc', '00000000-0000-4000-8000-00000000000a', 'android')$$,
  '42501', null,
  'anon cannot register devices'
);

select * from finish();
rollback;
