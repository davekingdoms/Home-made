-- RLS of public.profiles, seen by the owner, by another user and by anon.
-- Invented users: Anna (a), Bruno (b), Carla (c).
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated');

-- Bruno already has a profile.
insert into public.profiles (id, display_name)
values ('00000000-0000-4000-8000-00000000000b', 'Bruno');

-- Structure
select has_table('public', 'profiles', 'profiles exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'RLS is enabled on profiles'
);
select policies_are(
  'public', 'profiles',
  array['profiles_select_own', 'profiles_insert_own', 'profiles_update_own'],
  'profiles has only the own-row policies'
);

-- Anna, signed in
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000000a', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

select lives_ok(
  $$insert into public.profiles (id, display_name, privacy_notice_version, privacy_notice_read_at)
    values ('00000000-0000-4000-8000-00000000000a', 'Anna', '1', now())$$,
  'a user creates their own profile'
);
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('00000000-0000-4000-8000-00000000000c', 'Carla')$$,
  '42501', null,
  'a user cannot create the profile of another user'
);
select results_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid)$$,
  'a user sees only their own profile'
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
  $$update public.profiles set privacy_notice_read_at = null
    where id = '00000000-0000-4000-8000-00000000000a'$$,
  '23514', null,
  'notice version and date are saved together'
);

-- Back to the owner of the table: Bruno's profile did not change.
reset role;
select is(
  (select display_name from public.profiles where id = '00000000-0000-4000-8000-00000000000b'),
  'Bruno',
  'a user cannot change the profile of another user'
);

-- Not signed in
set local role anon;
select throws_ok(
  'select id from public.profiles',
  '42501', null,
  'anon cannot read profiles'
);
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('00000000-0000-4000-8000-00000000000c', 'Carla')$$,
  '42501', null,
  'anon cannot create profiles'
);

select * from finish();
rollback;
