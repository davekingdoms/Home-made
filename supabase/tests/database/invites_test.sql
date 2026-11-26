-- Invites: create_invite, invite_preview, redeem_invite, set_my_start_date
-- and the RLS of invites and invite_attempts, in a household that already
-- started; then the start dates of A10. Invented users: Anna (a) creates
-- "Casa di prova", Bruno (b) and Carla (c) join it; Dario (d) lives alone
-- in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(77);

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

-- Codes and tokens returned by create_invite, by name of the invite.
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

-- Structure
select has_table('public', 'invites', 'invites exists');
select has_table('public', 'invite_attempts', 'invite_attempts exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.invites'::regclass),
  'RLS is enabled on invites'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.invite_attempts'::regclass),
  'RLS is enabled on invite_attempts'
);
select policies_are(
  'public', 'invites',
  array['invites_select_household', 'invites_update_household'],
  'invites has the household select and update'
);
select is_empty(
  $$select 1 from pg_policies where schemaname = 'public' and tablename = 'invite_attempts'$$,
  'invite_attempts has no policy: no access from the app'
);

set local role authenticated;

-- Dario lives alone; Anna creates "Casa di prova", started 30 days ago.
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 10);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select public.create_household('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30);

-- Anna invites Bruno.
insert into invite_codes select 'bruno', code, token from public.create_invite('per Bruno');

select matches(
  (select code from invite_codes where who = 'bruno'),
  '^[2-9ABCDEFGHJKMNPQRSTUVWXYZ]{8}$',
  'the code has 8 characters without 0, O, 1, I, L'
);
select is(
  (select char_length(token) from invite_codes where who = 'bruno'),
  43,
  'the token has 32 random bytes in base64url'
);
select results_eq(
  $$select label, expires_at = created_at + interval '7 days', used_at from public.invites$$,
  $$values ('per Bruno'::text, true, null::timestamptz)$$,
  'the members see the invite, valid for 7 days'
);
select throws_ok(
  'select token_hash from public.invites',
  '42501', null,
  'the members do not read the hash of the token'
);

reset role;
select ok(
  (select i.token_hash = sha256(convert_to(c.token, 'UTF8'))
   from public.invites i
   join invite_codes c on c.code = i.code
   where c.who = 'bruno'),
  'only the SHA-256 hash of the token is saved'
);
set local role authenticated;

-- Bruno looks at the invite, then joins.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$select error, household_name, inviter_name, member_names
    from public.invite_preview(code => (
      select lower(substr(code, 1, 4) || ' ' || substr(code, 5)) from invite_codes where who = 'bruno'
    ))$$,
  $$values (null::text, 'Casa di prova'::text, 'Anna'::text, array['Anna'])$$,
  'the preview shows household, who invites and members; the code works with a space and in lower case'
);
select results_eq(
  $$select error, household_name
    from public.invite_preview(token => (select token from invite_codes where who = 'bruno'))$$,
  $$values (null::text, 'Casa di prova'::text)$$,
  'the preview works with the token of the link'
);
select is(
  (select error from public.invite_preview(code => 'AAAA 0000')),
  'invite_invalid',
  'a wrong code is invalid'
);
select results_eq(
  $$select error, household_id
    from public.redeem_invite(code => (select code from invite_codes where who = 'bruno'))$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'Bruno joins with the code'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values (current_date)$$,
  'in a household that already started, the new member starts today'
);
select results_eq(
  $$select error, household_id
    from public.redeem_invite(code => (select code from invite_codes where who = 'bruno'))$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'a second call with the same invite gives the same membership'
);
select is(
  (select count(*)::int from public.members where user_id = '00000000-0000-4000-8000-00000000000b'),
  1,
  'a second call creates no member'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  $$select used_by_member_id = (
      select id from public.members where user_id = '00000000-0000-4000-8000-00000000000b'
    ), used_at is not null
    from public.invites where label = 'per Bruno'$$,
  $$values (true, true)$$,
  'the invite is marked as used by Bruno'
);

-- A used invite lets nobody else in.
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is(
  (select error from public.invite_preview(code => (select code from invite_codes where who = 'bruno'))),
  'invite_used',
  'the preview of a used invite fails'
);
select is(
  (select error from public.redeem_invite(code => (select code from invite_codes where who = 'bruno'))),
  'invite_used',
  'a used invite cannot be used again'
);

-- Carla joins with the token of the link.
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
insert into invite_codes select 'carla', code, token from public.create_invite('per Carla');

select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select results_eq(
  $$select error, household_id
    from public.redeem_invite(token => (select token from invite_codes where who = 'carla'))$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'Carla joins with the token'
);
select set_eq(
  'select user_id from public.members',
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid),
           ('00000000-0000-4000-8000-00000000000b'::uuid),
           ('00000000-0000-4000-8000-00000000000c'::uuid)$$,
  '"Casa di prova" has three members'
);

-- Bruno moves his start date back, down to the one of the household.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select throws_ok(
  $$select public.set_my_start_date(current_date - 31)$$,
  'P0001', 'start_date_out_of_range',
  'a member does not start before the household'
);
select throws_ok(
  $$select public.set_my_start_date(current_date + 1)$$,
  'P0001', 'start_date_out_of_range',
  'the start date does not move forward'
);
select lives_ok(
  $$select public.set_my_start_date(current_date - 20)$$,
  'a member moves their start date back'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values (current_date - 20)$$,
  'the new start date is saved'
);
select throws_ok(
  $$select public.set_my_start_date(current_date - 10)$$,
  'P0001', 'start_date_out_of_range',
  'once moved back, it does not move forward again'
);
select lives_ok(
  $$select public.set_my_start_date(current_date - 30)$$,
  'a member moves their start date to the one of the household'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values (current_date - 30)$$,
  'the member now starts with the household'
);

-- Expired and revoked invites
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
insert into invite_codes select 'expired', code, token from public.create_invite('scaduto');
insert into invite_codes select 'revoked', code, token from public.create_invite('revocato');
insert into invite_codes select 'dario', code, token from public.create_invite('per Dario');

reset role;
update public.invites set expires_at = now() - interval '1 minute'
  where code = (select code from invite_codes where who = 'expired');
set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is(
  (select error from public.invite_preview(code => (select code from invite_codes where who = 'expired'))),
  'invite_expired',
  'the preview of an expired invite fails'
);
select is(
  (select error from public.redeem_invite(code => (select code from invite_codes where who = 'expired'))),
  'invite_expired',
  'an expired invite lets nobody in'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$update public.invites set revoked_at = now()
    where code = (select code from invite_codes where who = 'revoked')$$,
  'any member revokes an invite'
);
select throws_ok(
  $$update public.invites set revoked_at = null
    where code = (select code from invite_codes where who = 'revoked')$$,
  'P0001', 'invite_revoked',
  'a revoked invite does not come back'
);
select throws_ok(
  $$update public.invites set revoked_at = now() - interval '1 day'
    where code = (select code from invite_codes where who = 'revoked')$$,
  'P0001', 'invite_revoked',
  'the date of a revocation does not change'
);

reset role;
select throws_ok(
  $$update public.invites set revoked_at = null
    where code = (select code from invite_codes where who = 'revoked')$$,
  'P0001', 'invite_revoked',
  'not even the server brings a revoked invite back'
);
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select throws_ok(
  $$update public.invites set label = 'altro'
    where code = (select code from invite_codes where who = 'dario')$$,
  '42501', null,
  'the members change only revoked_at'
);
select throws_ok(
  $$insert into public.invites (household_id, created_by_member_id, token_hash, code, expires_at)
    values ('00000000-0000-4000-8000-0000000000f1', public.current_member_id(),
            sha256('x'::bytea), 'ABCDEFGH', now() + interval '7 days')$$,
  '42501', null,
  'invites are created only with create_invite'
);
select throws_ok(
  $$delete from public.invites where code = (select code from invite_codes where who = 'dario')$$,
  '42501', null,
  'invites are not deleted'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is(
  (select error from public.invite_preview(code => (select code from invite_codes where who = 'revoked'))),
  'invite_revoked',
  'a revoked invite lets nobody in'
);
select is_empty(
  'select 1 from public.invites',
  'Dario does not see the invites of "Casa di prova"'
);
update public.invites set revoked_at = now()
  where household_id = '00000000-0000-4000-8000-0000000000f1';
select results_eq(
  $$select error, household_name, inviter_name, array(select unnest(member_names) order by 1)
    from public.invite_preview(code => (select code from invite_codes where who = 'dario'))$$,
  $$values (null::text, 'Casa di prova'::text, 'Anna'::text, array['Anna', 'Bruno', 'Carla'])$$,
  'the preview lists the active members'
);
select is(
  (select error from public.redeem_invite(code => (select code from invite_codes where who = 'dario'))),
  'already_member',
  'an account in a household cannot join another one'
);

reset role;
select is(
  (select count(*)::int from public.invites
   where household_id = '00000000-0000-4000-8000-0000000000f1' and revoked_at is not null),
  1,
  'Dario cannot revoke the invites of another household'
);
set local role authenticated;

-- Full household: 3 members and the open invite for Dario take 4 places.
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
insert into invite_codes
select 'place ' || n, i.code, i.token
from generate_series(1, 4) n
cross join lateral public.create_invite('posto ' || n) i;

select is(
  (select count(*)::int from public.invites
   where used_at is null and revoked_at is null and expires_at > now()),
  5,
  'five invites are open'
);
select throws_ok(
  $$select * from public.create_invite('uno di troppo')$$,
  'P0001', 'household_full',
  'active members and open invites count: the household is full'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
update public.invites set revoked_at = now()
  where code = (select code from invite_codes where who = 'place 1');

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$select * from public.create_invite('di nuovo')$$,
  'a revoked invite frees its place'
);

-- Dario leaves his household; meanwhile "Casa di prova" reaches 8 members
-- (members whose account was deleted keep their place).
reset role;
update public.members set left_at = now()
  where user_id = '00000000-0000-4000-8000-00000000000d';
insert into public.members (household_id, user_id, start_date)
select '00000000-0000-4000-8000-0000000000f1', null, current_date
from generate_series(1, 5);
set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is(
  (select error from public.redeem_invite(code => (select code from invite_codes where who = 'dario'))),
  'household_full',
  'nobody joins a household with 8 active members'
);
select throws_ok(
  $$select * from public.create_invite('per nessuno')$$,
  'P0001', 'not_member',
  'only a member creates invites'
);
select throws_ok(
  $$select public.set_my_start_date(current_date)$$,
  'P0001', 'not_member',
  'only a member moves their start date'
);

-- At most 10 attempts an hour. Dario made 6 in this test; 3 more in the
-- last hour and 3 two hours ago.
reset role;
insert into public.invite_attempts (user_id, attempted_at)
select '00000000-0000-4000-8000-00000000000d', now() - interval '30 minutes'
from generate_series(1, 3);
insert into public.invite_attempts (user_id, attempted_at)
select '00000000-0000-4000-8000-00000000000d', now() - interval '2 hours'
from generate_series(1, 3);
set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is(
  (select error from public.invite_preview(code => 'AAAA 0000')),
  'invite_invalid',
  'the tenth attempt of the hour is checked'
);
select is(
  (select error from public.invite_preview(code => (select code from invite_codes where who = 'dario'))),
  'too_many_attempts',
  'the eleventh attempt is refused, even with a good code'
);
select is(
  (select error from public.redeem_invite(code => (select code from invite_codes where who = 'dario'))),
  'too_many_attempts',
  'redeem_invite counts the same attempts'
);
select throws_ok(
  'select * from public.invite_attempts',
  '42501', null,
  'the app does not read the attempts'
);
select throws_ok(
  $$select * from public.lookup_invite('AAAA0000', null)$$,
  '42501', null,
  'lookup_invite is internal: the app cannot call it'
);

reset role;
select is(
  (select count(*)::int from public.invite_attempts
   where user_id = '00000000-0000-4000-8000-00000000000d'
     and attempted_at > now() - interval '1 hour'),
  10,
  'failed attempts are saved; refused ones are not'
);

-- Start dates of A10. Elena (e1) creates "Casa di Elena", started 30 days
-- ago; Fabio (e2), Gaia (e3), Ivo (e4) and Luca (e5) join it from a start
-- date of their own. Marta (e6) creates "Casa di Marta", starting in 20
-- days; Nico (e7) joins it before then.
insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-0000000000e1', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e2', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e3', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e4', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e5', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e6', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000e7', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-0000000000e1', 'Elena'),
  ('00000000-0000-4000-8000-0000000000e2', 'Fabio'),
  ('00000000-0000-4000-8000-0000000000e3', 'Gaia'),
  ('00000000-0000-4000-8000-0000000000e4', 'Ivo'),
  ('00000000-0000-4000-8000-0000000000e5', 'Luca'),
  ('00000000-0000-4000-8000-0000000000e6', 'Marta'),
  ('00000000-0000-4000-8000-0000000000e7', 'Nico');
set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select public.create_household('00000000-0000-4000-8000-0000000000f3', 'Casa di Elena', current_date - 30);
insert into invite_codes select 'fabio', code, token from public.create_invite('per Fabio');
insert into invite_codes select 'gaia', code, token from public.create_invite('per Gaia');
insert into invite_codes select 'ivo', code, token from public.create_invite('per Ivo');
insert into invite_codes select 'luca', code, token from public.create_invite('per Luca');

select pg_temp.login('00000000-0000-4000-8000-0000000000e2');
select is(
  (select household_start_date
   from public.invite_preview(code => (select code from invite_codes where who = 'fabio'))),
  current_date - 30,
  'the preview gives the start date of the household'
);
select is(
  (select error from public.redeem_invite(
    code => (select code from invite_codes where who = 'fabio'),
    start_date => current_date - 31
  )),
  'start_date_out_of_range',
  'a new member does not start before the household'
);
select is(
  (select error from public.redeem_invite(
    code => (select code from invite_codes where who = 'fabio'),
    start_date => current_date + 2
  )),
  'start_date_out_of_range',
  'nor after tomorrow'
);
select is(public.current_member_id(), null, 'a start date out of the range makes no member');
select results_eq(
  $$select error, household_id from public.redeem_invite(
      code => (select code from invite_codes where who = 'fabio'),
      cash_opening_cents => 1500,
      start_date => current_date - 10
    )$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f3'::uuid)$$,
  'Fabio joins from a day in the past, the invite still unused'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-0000000000e2'$$,
  $$values (current_date - 10)$$,
  'the member is born with the start date chosen'
);
select results_eq(
  $$select valid_from from public.default_share_sets where member_id = public.current_member_id()$$,
  $$values (current_date - 10)$$,
  'the equal default shares of the join hold from that date'
);
select results_eq(
  'select opening_balance_cents from public.accounts',
  $$values (null::bigint)$$,
  'with a start date in the past the cash is not the opening balance'
);

select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select is(
  (select error from public.redeem_invite(
    code => (select code from invite_codes where who = 'gaia'),
    start_date => current_date - 30
  )),
  null,
  'Gaia joins from the start date of the household'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-0000000000e3'$$,
  $$values (current_date - 30)$$,
  'and starts with it'
);

select pg_temp.login('00000000-0000-4000-8000-0000000000e4');
select is(
  (select error from public.redeem_invite(
    token => (select token from invite_codes where who = 'ivo'),
    start_date => current_date + 1
  )),
  null,
  'Ivo joins from tomorrow: one day of tolerance for the time zones'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-0000000000e4'$$,
  $$values (current_date + 1)$$,
  'and starts tomorrow'
);

select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
select results_eq(
  $$select error, household_id from public.redeem_invite(
      code => (select code from invite_codes where who = 'luca'),
      cash_opening_cents => 750,
      start_date => current_date
    )$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f3'::uuid)$$,
  'Luca joins from today'
);
select results_eq(
  'select opening_balance_cents from public.accounts',
  $$values (750::bigint)$$,
  'starting today, the cash is the opening balance'
);
select results_eq(
  $$select error, household_id from public.redeem_invite(
      code => (select code from invite_codes where who = 'luca'),
      start_date => current_date - 5
    )$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f3'::uuid)$$,
  'a second call with the same invite gives the same membership, whatever the date'
);
select results_eq(
  $$select count(*)::int, min(start_date) from public.members
    where user_id = '00000000-0000-4000-8000-0000000000e5'$$,
  $$values (1, current_date)$$,
  'and neither makes a second member nor moves the date'
);

select pg_temp.login('00000000-0000-4000-8000-0000000000e6');
select public.create_household('00000000-0000-4000-8000-0000000000f4', 'Casa di Marta', current_date + 20);
insert into invite_codes select 'nico', code, token from public.create_invite('per Nico');

select pg_temp.login('00000000-0000-4000-8000-0000000000e7');
select is(
  (select household_start_date
   from public.invite_preview(code => (select code from invite_codes where who = 'nico'))),
  current_date + 20,
  'the preview gives the start date of a household that has not started'
);
select is(
  (select error from public.redeem_invite(
    code => (select code from invite_codes where who = 'nico'),
    start_date => current_date - 5
  )),
  null,
  'Nico joins before the household starts, with a start date of his own'
);
select results_eq(
  $$select start_date from public.members where user_id = '00000000-0000-4000-8000-0000000000e7'$$,
  $$values (current_date + 20)$$,
  'in a household that has not started the member starts with it, whatever the date sent'
);
reset role;

-- Not signed in
set local role anon;
select throws_ok(
  $$select * from public.invite_preview(code => 'AAAA 0000')$$,
  '42501', null,
  'anon cannot preview invites'
);
select throws_ok(
  'select id from public.invites',
  '42501', null,
  'anon cannot read invites'
);

select * from finish();
rollback;
