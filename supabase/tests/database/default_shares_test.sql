-- Default shares (docs/spec/schema.md, 6; docs/spec/accesso.md, A10): the
-- version of the household, the equal version of every new member from
-- their start date, which moves with it, the manual versions. Invented
-- users: Anna (a) creates "Casa di prova" 30 days ago; Bruno (b) and Carla
-- (c) join today; Dario (d) lives alone.
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

create function pg_temp.member_of(user_id uuid)
returns uuid
language sql
security definer
as $$
  select m.id from public.members m where m.user_id = member_of.user_id and m.left_at is null
$$;

-- Versions of "Casa di prova": start date, reason and members by name.
create function pg_temp.versions()
returns table (valid_from date, reason text, members text)
language sql
security definer
as $$
  select s.valid_from, s.reason,
         string_agg(p.display_name || ':' || w.weight::int, ' ' order by p.display_name)
  from public.default_share_sets s
  join public.default_share_weights w on w.set_id = s.id
  join public.members m on m.id = w.member_id
  join public.profiles p on p.id = m.user_id
  where s.household_id = '00000000-0000-4000-8000-0000000000f1'
  group by s.id, s.valid_from, s.reason
  order by s.valid_from
$$;

create temp table invite_codes (who text primary key, code text, token text);
grant select, insert on invite_codes to authenticated;

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

select has_table('public', 'default_share_sets', 'default_share_sets exists');
select has_table('public', 'default_share_weights', 'default_share_weights exists');

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 30);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select public.create_household('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30);
insert into invite_codes select 'bruno', code, token from public.create_invite('per Bruno');
insert into invite_codes select 'carla', code, token from public.create_invite('per Carla');

select results_eq(
  'select * from pg_temp.versions()',
  $$values (current_date - 30, 'household_created'::text, 'Anna:1'::text)$$,
  'a new household has a version with its creator'
);

-- Bruno joins today, then moves his start date back 10 days.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select public.redeem_invite(code => (select code from invite_codes where who = 'bruno'));
select results_eq(
  'select * from pg_temp.versions()',
  $$values (current_date - 30, 'household_created'::text, 'Anna:1'::text),
           (current_date, 'member_joined', 'Anna:1 Bruno:1')$$,
  'a new member brings equal weights for all, from their start date'
);
select public.set_my_start_date(current_date - 10);
select results_eq(
  'select * from pg_temp.versions()',
  $$values (current_date - 30, 'household_created'::text, 'Anna:1'::text),
           (current_date - 10, 'member_joined', 'Anna:1 Bruno:1')$$,
  'the version moves with the start date of the member'
);
select results_eq(
  $$select member_id from public.default_shares_at(current_date - 11)$$,
  $$values (pg_temp.member_of('00000000-0000-4000-8000-00000000000a'))$$,
  'an expense before the new start date of Bruno: Anna alone'
);
select set_eq(
  $$select member_id from public.default_shares_at(current_date - 10)$$,
  $$values (pg_temp.member_of('00000000-0000-4000-8000-00000000000a')),
           (pg_temp.member_of('00000000-0000-4000-8000-00000000000b'))$$,
  'an expense from that date: Anna and Bruno'
);

-- Carla joins today and moves her start date to the household's. In a
-- single test transaction now() does not move: the version of Bruno is
-- dated one day back, as made before Carla joined.
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select public.redeem_invite(code => (select code from invite_codes where who = 'carla'));
reset role;
update public.default_share_sets set created_at = now() - interval '1 day'
  where member_id = pg_temp.member_of('00000000-0000-4000-8000-00000000000b');
set local role authenticated;
select public.set_my_start_date(current_date - 30);
select results_eq(
  'select * from pg_temp.versions()',
  $$values (current_date - 30, 'member_joined'::text, 'Anna:1 Bruno:1 Carla:1'::text),
           (current_date - 10, 'member_joined', 'Anna:1 Bruno:1 Carla:1')$$,
  'a version moved on the date of another replaces it; the member joins the later versions made before'
);
-- Created, moved with Bruno, dated back by this test, then given Carla.
select is(
  (select version from public.default_share_sets
   where member_id = pg_temp.member_of('00000000-0000-4000-8000-00000000000b')),
  4,
  'the version that gained a member is bumped'
);
select set_eq(
  $$select member_id from public.default_shares_at(current_date - 20)$$,
  $$values (pg_temp.member_of('00000000-0000-4000-8000-00000000000a')),
           (pg_temp.member_of('00000000-0000-4000-8000-00000000000c'))$$,
  'members who start later have no default share'
);

-- Manual versions
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$select public.set_default_shares(current_date - 5, jsonb_build_array(
      jsonb_build_object('member_id', pg_temp.member_of('00000000-0000-4000-8000-00000000000a'), 'weight', 2),
      jsonb_build_object('member_id', pg_temp.member_of('00000000-0000-4000-8000-00000000000b'), 'weight', 1)))$$,
  'a member sets a new version from a date'
);
select lives_ok(
  $$select public.set_default_shares(current_date - 5, jsonb_build_array(
      jsonb_build_object('member_id', pg_temp.member_of('00000000-0000-4000-8000-00000000000a'), 'weight', 3),
      jsonb_build_object('member_id', pg_temp.member_of('00000000-0000-4000-8000-00000000000c'), 'weight', 1)))$$,
  'a second change on the same day'
);
select results_eq(
  'select * from pg_temp.versions()',
  $$values (current_date - 30, 'member_joined'::text, 'Anna:1 Bruno:1 Carla:1'::text),
           (current_date - 10, 'member_joined', 'Anna:1 Bruno:1 Carla:1'),
           (current_date - 5, 'manual', 'Anna:3 Carla:1')$$,
  'replaces the first'
);
select results_eq(
  $$select weight from public.default_shares_at(current_date) order by weight desc$$,
  $$values (3::numeric), (1::numeric)$$,
  'default_shares_at gives the version valid at the date of the expense'
);
select throws_ok(
  $$select public.set_default_shares(current_date, '[]')$$,
  'P0001', 'no_members',
  'a version has at least one member'
);
select throws_ok(
  $$select public.set_default_shares(current_date, jsonb_build_array(
      jsonb_build_object('member_id', pg_temp.member_of('00000000-0000-4000-8000-00000000000d'), 'weight', 1)))$$,
  'P0001', 'member_not_eligible',
  'only members of the household'
);
select throws_ok(
  $$insert into public.default_share_sets (household_id, valid_from, reason, created_by_member_id)
    values ('00000000-0000-4000-8000-0000000000f1', current_date, 'manual', public.current_member_id())$$,
  '42501', null,
  'versions are written only by the functions'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select results_eq(
  'select reason from public.default_share_sets',
  $$values ('household_created'::text)$$,
  'Dario sees only the versions of his household'
);

select * from finish();
rollback;
