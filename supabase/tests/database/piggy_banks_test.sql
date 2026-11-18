-- Piggy banks: the creator joins it, every member manages it, deposits only
-- by the member on their own accounts, members see the deposits and never
-- the accounts, member ids of the household and active. Invented users:
-- Anna (a1), Bruno (b1) and Carla (c1) in "Casa di prova", with a former
-- member (e9); Dario (d1) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

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

create function pg_temp.cash_of(member_id uuid)
returns uuid
language sql
security definer
as $$
  select a.id from public.accounts a where a.owner_member_id = cash_of.member_id and a.kind = 'cash'
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
insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Banca di Prova');
-- A saving of Bruno, from his cash.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values (
  '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000f1',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
  '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', current_date - 1, -5000, 'EUR'
);

select has_table('public', 'piggy_banks', 'piggy_banks exists');
select has_table('public', 'piggy_bank_members', 'piggy_bank_members exists');
select has_table('public', 'piggy_bank_entries', 'piggy_bank_entries exists');

-- Anna creates a piggy bank and shares it with Bruno.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$insert into public.piggy_banks (id, household_id, name, target_cents, created_by_member_id)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000f1',
            'Vacanze di prova', 100000, '00000000-0000-4000-8000-0000000000a1')$$,
  'a member creates a piggy bank with the id generated on the device'
);
select results_eq(
  'select member_id from public.piggy_bank_members',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid)$$,
  'whoever creates it is its first member'
);
select throws_ok(
  $$insert into public.piggy_banks (household_id, name, created_by_member_id)
    values ('00000000-0000-4000-8000-0000000000f1', 'Altro', '00000000-0000-4000-8000-0000000000a1')
    returning id$$,
  '42501', null,
  'the app creates it without reading the row back'
);
select lives_ok(
  $$insert into public.piggy_bank_members (piggy_bank_id, member_id)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000b1')$$,
  'a member adds another member'
);
select throws_ok(
  $$insert into public.piggy_bank_members (piggy_bank_id, member_id)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000d1')$$,
  'P0001', 'member_not_eligible',
  'Dario, of another household, does not join it'
);
select throws_ok(
  $$insert into public.piggy_bank_members (piggy_bank_id, member_id)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000e9')$$,
  'P0001', 'member_not_eligible',
  'nor a member who left'
);
select lives_ok(
  $$insert into public.piggy_bank_entries (id, piggy_bank_id, member_id, account_id, kind, amount_cents, entry_date)
    values ('00000000-0000-4000-8000-000000000711', '00000000-0000-4000-8000-000000000701',
            '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000e2',
            'virtual', 20000, current_date)$$,
  'a member puts money aside on her own account'
);
select throws_ok(
  $$insert into public.piggy_bank_entries (piggy_bank_id, member_id, kind, amount_cents, entry_date)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000b1',
            'virtual', 1000, current_date)$$,
  '42501', null,
  'a deposit only by the member'
);
select throws_ok(
  $$insert into public.piggy_bank_entries (piggy_bank_id, member_id, account_id, kind, amount_cents, entry_date)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000a1',
            pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'virtual', 1000, current_date)$$,
  '23514', null,
  'only on her own accounts'
);

-- Bruno, member of the piggy bank
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  'select name from public.piggy_banks',
  $$values ('Vacanze di prova'::text)$$,
  'a member sees the piggy bank'
);
select results_eq(
  'select member_id, amount_cents from public.piggy_bank_entries',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 20000::bigint)$$,
  'and how much each one put in'
);
select is_empty(
  $$select 1 from public.accounts where id = '00000000-0000-4000-8000-0000000000e2'$$,
  'but not the account of the deposit'
);
select lives_ok(
  $$insert into public.piggy_bank_entries (piggy_bank_id, member_id, kind, transaction_id, amount_cents, entry_date)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000b1',
            'real', '00000000-0000-4000-8000-000000000101', 5000, current_date - 1)$$,
  'a member links a saving movement of his own'
);
select lives_ok(
  $$insert into public.piggy_bank_entries (piggy_bank_id, member_id, kind, amount_cents, entry_date)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000b1',
            'virtual', -3000, current_date)$$,
  'and takes money out'
);
select lives_ok(
  $$update public.piggy_banks set name = 'Vacanze estive' where id = '00000000-0000-4000-8000-000000000701'$$,
  'any member renames the piggy bank'
);
update public.piggy_bank_entries set amount_cents = 1
  where id = '00000000-0000-4000-8000-000000000711';

-- Carla, not a member
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is_empty('select 1 from public.piggy_banks', 'a member of the household outside the piggy bank does not see it');
select is_empty('select 1 from public.piggy_bank_entries', 'nor its deposits');
select throws_ok(
  $$insert into public.piggy_bank_entries (piggy_bank_id, member_id, kind, amount_cents, entry_date)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000c1',
            'virtual', 1000, current_date)$$,
  'P0001', 'member_not_eligible',
  'nor puts money in it'
);
select throws_ok(
  $$insert into public.piggy_bank_members (piggy_bank_id, member_id)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000c1')$$,
  '42501', null,
  'nor joins it alone'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is_empty('select 1 from public.piggy_banks', 'Dario does not see it');

-- The server neither writes member ids of other households.
reset role;
select is(
  (select amount_cents from public.piggy_bank_entries where id = '00000000-0000-4000-8000-000000000711'),
  20000::bigint,
  'Bruno did not change the deposit of Anna'
);
select throws_ok(
  $$insert into public.piggy_banks (household_id, name, created_by_member_id)
    values ('00000000-0000-4000-8000-0000000000f1', 'Di Dario', '00000000-0000-4000-8000-0000000000d1')$$,
  'P0001', 'member_not_eligible',
  'a piggy bank is created by a member of its household'
);
select throws_ok(
  $$insert into public.piggy_bank_entries (piggy_bank_id, member_id, kind, amount_cents, entry_date)
    values ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000d1',
            'virtual', 1000, current_date)$$,
  'P0001', 'member_not_eligible',
  'a deposit is of a member of the household'
);

-- Anna removes Bruno.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$delete from public.piggy_bank_members
    where piggy_bank_id = '00000000-0000-4000-8000-000000000701'
      and member_id = '00000000-0000-4000-8000-0000000000b1'$$,
  'a member removes another member'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is_empty('select 1 from public.piggy_banks', 'who is removed no longer sees the piggy bank');

select * from finish();
rollback;
