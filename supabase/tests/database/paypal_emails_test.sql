-- PayPal emails: lower case, one person for each email, only the owner,
-- also within the household. Invented users: Anna (a) and Bruno (b) in
-- "Casa di prova", Carla (c) without a household; invented addresses on
-- example.com.
begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

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
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 30);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 30);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 30);

select has_table('public', 'paypal_emails', 'paypal_emails exists');

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$insert into public.paypal_emails (id, user_id, email, source)
    values ('00000000-0000-4000-8000-000000000801', '00000000-0000-4000-8000-00000000000a',
            ' Anna.Prova@Example.com ', 'manual')$$,
  'a user adds a PayPal email'
);
select is(
  (select email from public.paypal_emails),
  'anna.prova@example.com',
  'saved in lower case, without spaces'
);
select throws_ok(
  $$insert into public.paypal_emails (user_id, email, source)
    values ('00000000-0000-4000-8000-00000000000b', 'bruno.prova@example.com', 'manual')$$,
  '42501', null,
  'a user does not add emails of others'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select isnt_empty(
  $$select 1 from public.profiles where id = '00000000-0000-4000-8000-00000000000a'$$,
  'Bruno sees the profile of Anna: they are in the same household'
);
select is_empty('select 1 from public.paypal_emails', 'but not her PayPal emails');
select throws_ok(
  $$insert into public.paypal_emails (user_id, email, source)
    values ('00000000-0000-4000-8000-00000000000b', 'ANNA.PROVA@example.com', 'linked_account')$$,
  '23505', null,
  'one person for each email'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is_empty('select 1 from public.paypal_emails', 'nor does a user outside the household');

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$delete from public.paypal_emails where id = '00000000-0000-4000-8000-000000000801'$$,
  'the owner removes it'
);

reset role;
set local role anon;
select throws_ok(
  'select id from public.paypal_emails',
  '42501', null,
  'anon cannot read paypal_emails'
);

select * from finish();
rollback;
