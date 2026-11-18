-- create_household, the support functions and the RLS of households and
-- members. Invented users: Anna (a), Bruno (b) and Carla (c) in
-- "Casa di prova", which grows from 1 to 3 members; Dario (d) alone in his
-- household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

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

-- Bruno has no profile yet.
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla'),
  ('00000000-0000-4000-8000-00000000000d', 'Dario');

-- Structure
select has_table('public', 'households', 'households exists');
select has_table('public', 'members', 'members exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.households'::regclass),
  'RLS is enabled on households'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.members'::regclass),
  'RLS is enabled on members'
);
select policies_are(
  'public', 'households',
  array['households_select_member', 'households_update_member'],
  'households has the member select and update'
);
select policies_are(
  'public', 'members',
  array['members_select_household'],
  'members has only the household select'
);
select is(public.max_household_members(), 8, 'a household has at most 8 members');

-- Anna creates "Casa di prova", started 30 days ago.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');

select is(
  public.create_household('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30),
  '00000000-0000-4000-8000-0000000000f1'::uuid,
  'create_household returns the id generated on the device'
);
select results_eq(
  'select name, start_date, created_by from public.households',
  $$values ('Casa di prova'::text, current_date - 30, '00000000-0000-4000-8000-00000000000a'::uuid)$$,
  'the household has name, start date and creator'
);
select results_eq(
  'select user_id, start_date, left_at from public.members',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid, current_date - 30, null::timestamptz)$$,
  'the creator is the first member, with the start date of the household'
);
select is(
  public.current_member_id(),
  (select id from public.members where user_id = '00000000-0000-4000-8000-00000000000a'),
  'current_member_id is the member of the user'
);
select is(
  public.current_household_id(),
  '00000000-0000-4000-8000-0000000000f1'::uuid,
  'current_household_id is the household of the member'
);
select ok(
  public.is_household_member('00000000-0000-4000-8000-0000000000f1'),
  'is_household_member is true for the own household'
);
select results_eq(
  'select kind, display_name, currency, opening_balance_cents from public.accounts',
  $$values ('cash'::text, 'Contanti'::text, 'EUR'::char(3), null::bigint)$$,
  'the first member gets the cash account; no opening balance for a past start date'
);
select results_eq(
  $$select s.reason, s.valid_from, w.member_id = public.current_member_id(), w.weight
    from public.default_share_sets s join public.default_share_weights w on w.set_id = s.id$$,
  $$values ('household_created'::text, current_date - 30, true, 1::numeric)$$,
  'the household gets a version of the default shares with its creator only'
);
select is(
  (select count(*)::int from public.categories),
  72,
  'the household gets the initial categories'
);
select is(
  public.create_household('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30),
  '00000000-0000-4000-8000-0000000000f1'::uuid,
  'a second call with the same id succeeds'
);
select is(
  (select count(*)::int from public.members),
  1,
  'a second call with the same id creates nothing'
);
select throws_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f9', 'Seconda casa', current_date)$$,
  'P0001', 'already_member',
  'an account does not enter a second household'
);

-- Bruno, without a profile
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select throws_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f9', 'Casa di Bruno', current_date)$$,
  'P0001', 'no_profile',
  'a household needs the profile of its creator'
);

-- Dario: the start date goes from 90 days ago to 12 months ahead, one day
-- of tolerance on each side.
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select throws_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 92)$$,
  'P0001', 'start_date_out_of_range',
  'a start date more than 90 days ago (plus one day) is rejected'
);
select throws_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario',
      (current_date + interval '12 months')::date + 2)$$,
  'P0001', 'start_date_out_of_range',
  'a start date more than 12 months ahead (plus one day) is rejected'
);
select throws_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', null)$$,
  'P0001', 'start_date_out_of_range',
  'a start date is required'
);
select lives_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 91)$$,
  'the oldest start date is accepted'
);

-- Carla tries the latest start date, then leaves that household.
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select lives_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f3', 'Casa futura',
      (current_date + interval '12 months')::date + 1)$$,
  'the latest start date is accepted'
);

reset role;
update public.members set left_at = now()
  where household_id = '00000000-0000-4000-8000-0000000000f3';

-- Bruno and Carla join "Casa di prova" (invites have their own test).
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000b', 'Bruno');
insert into public.members (household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000b', current_date),
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000c', current_date);

select throws_ok(
  $$update public.members set start_date = current_date - 31
    where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  'P0001', 'start_date_out_of_range',
  'a member never starts before the household'
);

-- Visibility
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  'select id from public.households',
  $$values ('00000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'a member sees only their own household'
);
select set_eq(
  'select user_id from public.members',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid),
           ('00000000-0000-4000-8000-00000000000b'::uuid),
           ('00000000-0000-4000-8000-00000000000c'::uuid)$$,
  'a member sees the members of their household'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select results_eq(
  'select id from public.households',
  $$values ('00000000-0000-4000-8000-0000000000f2'::uuid)$$,
  'Dario does not see "Casa di prova"'
);
select results_eq(
  'select user_id from public.members',
  $$values ('00000000-0000-4000-8000-00000000000d'::uuid)$$,
  'Dario does not see the members of "Casa di prova"'
);
select ok(
  not public.is_household_member('00000000-0000-4000-8000-0000000000f1'),
  'is_household_member is false for another household'
);

-- Writes
update public.households set name = 'Cambiata da Dario'
  where id = '00000000-0000-4000-8000-0000000000f1';

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$update public.households set name = 'Casa di prova 2'
    where id = '00000000-0000-4000-8000-0000000000f1'$$,
  'a member renames the household'
);
select results_eq(
  'select name, version from public.households',
  $$values ('Casa di prova 2'::text, 2)$$,
  'the new name is saved and the version bumped; Dario changed nothing'
);
select throws_ok(
  $$update public.households set name = ''
    where id = '00000000-0000-4000-8000-0000000000f1'$$,
  '23514', null,
  'an empty household name is rejected'
);
select throws_ok(
  $$update public.households set start_date = current_date
    where id = '00000000-0000-4000-8000-0000000000f1'$$,
  '42501', null,
  'the start date of the household does not change from the app'
);
select throws_ok(
  $$insert into public.households (name, start_date) values ('Casa a mano', current_date)$$,
  '42501', null,
  'households are created only with create_household'
);
select throws_ok(
  $$insert into public.members (household_id, user_id, start_date)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000d', current_date)$$,
  '42501', null,
  'members are not inserted from the app'
);
select throws_ok(
  $$update public.members set start_date = current_date - 30
    where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  '42501', null,
  'members are not changed from the app'
);
select throws_ok(
  $$delete from public.members where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  '42501', null,
  'members are not deleted from the app'
);

-- Carla leaves "Casa di prova".
reset role;
update public.members set left_at = now()
  where user_id = '00000000-0000-4000-8000-00000000000c' and left_at is null;

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is(public.current_member_id(), null, 'a member who left has no current member');
select is_empty('select 1 from public.households', 'a member who left sees no household');
select is_empty('select 1 from public.members', 'a member who left sees no member');

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  $$select left_at is not null from public.members
    where user_id = '00000000-0000-4000-8000-00000000000c'$$,
  $$values (true)$$,
  'the others still see who left, as "Ex membro"'
);

-- Not signed in
reset role;
set local role anon;
select throws_ok(
  'select id from public.households',
  '42501', null,
  'anon cannot read households'
);
select throws_ok(
  $$select public.create_household('00000000-0000-4000-8000-0000000000f9', 'Casa anonima', current_date)$$,
  '42501', null,
  'anon cannot create households'
);

select * from finish();
rollback;
