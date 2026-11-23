-- RLS of public.profiles, seen by the owner, by the members of the same
-- household, by a user of another household, by a member who left and by
-- anon. Invented users: Anna (a), Bruno (b), Carla (c) in "Casa di prova";
-- Dario (d) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- Signs in as a user for the rest of the transaction.
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
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated');

-- Bruno, Carla and Dario already have a profile.
insert into public.profiles (id, display_name, avatar_url, paypal_me) values
  ('00000000-0000-4000-8000-00000000000b', 'Bruno', 'https://example.com/bruno.png', 'brunoprova'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla', null, null),
  ('00000000-0000-4000-8000-00000000000d', 'Dario', null, null);

-- Structure
select has_table('public', 'profiles', 'profiles exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'RLS is enabled on profiles'
);
select policies_are(
  'public', 'profiles',
  array['profiles_select_household', 'profiles_insert_own', 'profiles_update_own'],
  'profiles has the household select and the own-row insert and update'
);
select columns_are(
  'public', 'profiles',
  array['id', 'display_name', 'avatar_url', 'paypal_me', 'is_demo', 'version', 'created_at', 'updated_at'],
  'the privacy notice moved to user_settings'
);

-- Anna, signed in, not yet in a household
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');

select lives_ok(
  $$insert into public.profiles (id, display_name, avatar_url, paypal_me)
    values ('00000000-0000-4000-8000-00000000000a', 'Anna', 'https://example.com/anna.png', 'annaprova')$$,
  'a user creates their own profile'
);
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('00000000-0000-4000-8000-0000000000ee', 'Nessuno')$$,
  '42501', null,
  'a user cannot create the profile of another user'
);
select results_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid)$$,
  'without a household a user sees only their own profile'
);
select lives_ok(
  $$update public.profiles set display_name = 'Anna B.'
    where id = '00000000-0000-4000-8000-00000000000a'$$,
  'a user renames their own profile'
);
select is(
  (select display_name from public.profiles where id = '00000000-0000-4000-8000-00000000000a'),
  'Anna B.',
  'the new name is saved'
);
select is(
  (select version from public.profiles where id = '00000000-0000-4000-8000-00000000000a'),
  2,
  'every update bumps the version'
);
update public.profiles set display_name = 'Changed by Anna'
  where id = '00000000-0000-4000-8000-00000000000b';
select throws_ok(
  $$delete from public.profiles where id = '00000000-0000-4000-8000-00000000000a'$$,
  '42501', null,
  'a user cannot delete a profile'
);
select throws_ok(
  $$update public.profiles set display_name = '   '
    where id = '00000000-0000-4000-8000-00000000000a'$$,
  '23514', null,
  'an empty display name is rejected'
);
select throws_ok(
  $$update public.profiles set paypal_me = 'anna.prova'
    where id = '00000000-0000-4000-8000-00000000000a'$$,
  '23514', null,
  'a PayPal.Me name has only letters and digits'
);
select throws_ok(
  $$update public.profiles set paypal_me = 'annaprovaannaprovaann'
    where id = '00000000-0000-4000-8000-00000000000a'$$,
  '23514', null,
  'a PayPal.Me name has at most 20 characters'
);

-- Back to the owner of the table: Bruno's profile did not change.
reset role;
select is(
  (select display_name from public.profiles where id = '00000000-0000-4000-8000-00000000000b'),
  'Bruno',
  'a user cannot change the profile of another user'
);

-- Anna, Bruno and Carla in "Casa di prova"; Dario alone in his household.
insert into public.households (id, name, start_date, created_by) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30, '00000000-0000-4000-8000-00000000000a'),
  ('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 30, '00000000-0000-4000-8000-00000000000d');
insert into public.members (household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a', current_date - 30),
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000b', current_date),
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000c', current_date),
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-00000000000d', current_date - 30);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select set_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid),
           ('00000000-0000-4000-8000-00000000000b'::uuid),
           ('00000000-0000-4000-8000-00000000000c'::uuid)$$,
  'a member sees the profiles of the members of the household, not of other households'
);
select results_eq(
  $$select display_name, avatar_url, paypal_me from public.profiles
    where id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values ('Bruno'::text, 'https://example.com/bruno.png'::text, 'brunoprova'::text)$$,
  'name, photo and PayPal.Me are visible to the household'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select results_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-00000000000d'::uuid)$$,
  'Dario sees only his own profile'
);

-- Carla leaves the household.
reset role;
update public.members set left_at = now()
  where user_id = '00000000-0000-4000-8000-00000000000c';

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select set_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid),
           ('00000000-0000-4000-8000-00000000000b'::uuid)$$,
  'a member who left is no longer visible in the profiles'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select results_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-00000000000c'::uuid)$$,
  'a member who left sees only their own profile'
);

-- Not signed in
reset role;
set local role anon;
select throws_ok(
  'select id from public.profiles',
  '42501', null,
  'anon cannot read profiles'
);
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('00000000-0000-4000-8000-0000000000ee', 'Nessuno')$$,
  '42501', null,
  'anon cannot create profiles'
);

select * from finish();
rollback;
