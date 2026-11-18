-- Contacts, advances and refunds: personal address book, advances seen as
-- their line, the refund inherits the shares of the advance, owners of the
-- household and active. Invented users: Anna (a1), Bruno (b1) and Carla
-- (c1) in "Casa di prova", with a former member (e9); Dario (d1) alone.
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

create function pg_temp.check_deferred()
returns void
language plpgsql
as $$
begin
  set constraints all immediate;
  set constraints all deferred;
end;
$$;

create function pg_temp.cash_of(member_id uuid)
returns uuid
language sql
security definer
as $$
  select a.id from public.accounts a where a.owner_member_id = cash_of.member_id and a.kind = 'cash'
$$;

create function pg_temp.line(transaction_id uuid)
returns uuid
language sql
security definer
as $$
  select l.id from public.transaction_lines l
  where l.transaction_id = line.transaction_id and l.position = 1
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
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 60),
  ('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 60);
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000e9', '00000000-0000-4000-8000-0000000000f1',
   null, current_date - 60, now());
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60);

-- Carla pays 50,00 for a friend, shared with Anna; the friend gives back 30,00.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values
  ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000c1'), 'manual',
   '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000c1', current_date - 8, -5000, 'EUR'),
  ('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000c1'), 'manual',
   '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000c1', current_date - 3, 3000, 'EUR');
select pg_temp.check_deferred();

select has_table('public', 'contacts', 'contacts exists');
select has_table('public', 'advances', 'advances exists');
select has_table('public', 'advance_repayments', 'advance_repayments exists');

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select public.set_line_shares(pg_temp.line('00000000-0000-4000-8000-000000000105'),
  '[{"member_id": "00000000-0000-4000-8000-0000000000a1", "weight": 1},
    {"member_id": "00000000-0000-4000-8000-0000000000c1", "weight": 1}]');
select lives_ok(
  $$insert into public.contacts (id, household_id, owner_member_id, name)
    values ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-0000000000f1',
            '00000000-0000-4000-8000-0000000000c1', 'Amica di prova')$$,
  'a member adds a person to her address book'
);
select lives_ok(
  $$insert into public.advances (id, line_id, contact_id, expected_cents)
    values ('00000000-0000-4000-8000-000000000602', pg_temp.line('00000000-0000-4000-8000-000000000105'),
            '00000000-0000-4000-8000-000000000601', 5000)$$,
  'she marks her line as an advance for that person'
);
select results_eq(
  'select contact_name, expected_cents from public.advances',
  $$values ('Amica di prova'::text, 5000::bigint)$$,
  'the name of the contact is copied on the advance'
);
select throws_ok(
  $$update public.advances set expected_cents = 0 where id = '00000000-0000-4000-8000-000000000602'$$,
  '23514', null,
  'the expected amount is positive'
);
select lives_ok(
  $$insert into public.advance_repayments (advance_id, line_id, amount_cents)
    values ('00000000-0000-4000-8000-000000000602', pg_temp.line('00000000-0000-4000-8000-000000000106'), 3000);
    select pg_temp.check_deferred()$$,
  'she links the refund to the advance'
);
select results_eq(
  $$select member_id, weight, amount_cents from public.line_shares
    where line_id = pg_temp.line('00000000-0000-4000-8000-000000000106') order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::numeric, 1500::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 1::numeric, 1500::bigint)$$,
  'the refund inherits the shares of the advance'
);

-- Anna, with a share on the advance
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  'select contact_name from public.advances',
  $$values ('Amica di prova'::text)$$,
  'who is involved in the line sees the advance and the name'
);
select is_empty('select 1 from public.contacts', 'but not the address book of Carla');
select results_eq(
  'select amount_cents from public.advance_repayments',
  $$values (3000::bigint)$$,
  'and sees the refunds'
);

-- Bruno, not involved
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is_empty('select 1 from public.advances', 'who is not involved does not see the advance');
select throws_ok(
  $$insert into public.contacts (household_id, owner_member_id, name)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000c1', 'Per Carla')$$,
  '42501', null,
  'a member does not write in the address book of another'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select lives_ok(
  $$update public.advances set written_off_at = now() where id = '00000000-0000-4000-8000-000000000602'$$,
  'the rest of the advance becomes a normal expense'
);

reset role;
select throws_ok(
  $$insert into public.contacts (household_id, owner_member_id, name)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000d1', 'Di Dario')$$,
  'P0001', 'member_not_eligible',
  'a contact belongs to a member of its household'
);
select throws_ok(
  $$insert into public.contacts (household_id, owner_member_id, name)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000e9', 'Di un ex membro')$$,
  'P0001', 'member_not_eligible',
  'not to a member who left'
);

set local role anon;
select throws_ok(
  'select id from public.contacts',
  '42501', null,
  'anon cannot read contacts'
);

select * from finish();
rollback;
