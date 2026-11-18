-- RLS of public.user_settings: only the owner, also within the household.
-- Invented users: Anna (a) and Bruno (b) in "Casa di prova".
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

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

-- Bruno already read the notice.
insert into public.user_settings (user_id, privacy_notice_version, privacy_notice_read_at)
values ('00000000-0000-4000-8000-00000000000b', '1', now());

-- Structure
select has_table('public', 'user_settings', 'user_settings exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_settings'::regclass),
  'RLS is enabled on user_settings'
);
select policies_are(
  'public', 'user_settings',
  array['user_settings_all_own'],
  'user_settings has only the own-row policy'
);

-- Anna, signed in
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');

select lives_ok(
  $$insert into public.user_settings (user_id, privacy_notice_version, privacy_notice_read_at)
    values ('00000000-0000-4000-8000-00000000000a', '1', now())$$,
  'a user saves the privacy notice read'
);
select results_eq(
  $$select show_income, preferences from public.user_settings
    where user_id = '00000000-0000-4000-8000-00000000000a'$$,
  $$values (true, '{}'::jsonb)$$,
  'own income is visible by default and the preferences start empty'
);
select results_eq(
  'select user_id from public.user_settings',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid)$$,
  'a member does not see the settings of the other members'
);
select throws_ok(
  $$insert into public.user_settings (user_id)
    values ('00000000-0000-4000-8000-00000000000b')$$,
  '42501', null,
  'a user cannot create the settings of another user'
);
select lives_ok(
  $$update public.user_settings set show_income = false, preferences = '{"unlock_after": "1m"}'
    where user_id = '00000000-0000-4000-8000-00000000000a'$$,
  'a user changes their own settings'
);
select is(
  (select version from public.user_settings where user_id = '00000000-0000-4000-8000-00000000000a'),
  2,
  'every update bumps the version'
);
select throws_ok(
  $$update public.user_settings set privacy_notice_read_at = null
    where user_id = '00000000-0000-4000-8000-00000000000a'$$,
  '23514', null,
  'notice version and date are saved together'
);
select throws_ok(
  $$update public.user_settings set preferences = '[]'
    where user_id = '00000000-0000-4000-8000-00000000000a'$$,
  '23514', null,
  'the preferences are an object'
);
update public.user_settings set show_income = false
  where user_id = '00000000-0000-4000-8000-00000000000b';
delete from public.user_settings
  where user_id = '00000000-0000-4000-8000-00000000000b';

reset role;
select results_eq(
  $$select show_income, privacy_notice_version from public.user_settings
    where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values (true, '1'::text)$$,
  'a user cannot change or delete the settings of another user'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$delete from public.user_settings
    where user_id = '00000000-0000-4000-8000-00000000000a'$$,
  'a user deletes their own settings'
);
select is_empty(
  'select 1 from public.user_settings',
  'the deleted settings are gone'
);

-- Not signed in
reset role;
set local role anon;
select throws_ok(
  'select user_id from public.user_settings',
  '42501', null,
  'anon cannot read user_settings'
);
select throws_ok(
  $$insert into public.user_settings (user_id)
    values ('00000000-0000-4000-8000-00000000000a')$$,
  '42501', null,
  'anon cannot create user_settings'
);

select * from finish();
rollback;
