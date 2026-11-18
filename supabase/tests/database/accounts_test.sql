-- Accounts and data of the banks: cash account with the member, opening
-- balance, constraints, RLS of connections, accounts and balances,
-- credentials and raw data out of reach of the app, deduplication of the
-- raw rows. Invented users: Anna (a) and Bruno (b) in "Casa di prova",
-- Dario (d) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

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

-- Active member of a user, read without the policies.
create function pg_temp.member_of(user_id uuid)
returns uuid
language sql
security definer
as $$
  select m.id from public.members m where m.user_id = member_of.user_id and m.left_at is null
$$;

create temp table invite_codes (who text primary key, code text, token text);
grant select, insert on invite_codes to authenticated;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000d', 'Dario');

-- Structure
select has_table('public', 'eb_credentials', 'eb_credentials exists');
select has_table('public', 'bank_connections', 'bank_connections exists');
select has_table('public', 'accounts', 'accounts exists');
select has_table('public', 'account_balances', 'account_balances exists');
select has_table('public', 'bank_raw_transactions', 'bank_raw_transactions exists');
select has_extension('supabase_vault', 'Supabase Vault is available for the private keys');

-- Anna creates "Casa di prova" today with 50,00 of cash; Bruno joins today
-- with 20,00; Dario's household started 10 days ago.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select public.create_household('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date, 5000);
insert into invite_codes select 'bruno', code, token from public.create_invite('per Bruno');

select results_eq(
  'select kind, display_name, currency, opening_balance_cents from public.accounts',
  $$values ('cash'::text, 'Contanti'::text, 'EUR'::char(3), 5000::bigint)$$,
  'starting today, the cash of create_household is the opening balance'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select public.redeem_invite(
  code => (select code from invite_codes where who = 'bruno'),
  cash_opening_cents => 2000
);
select results_eq(
  'select kind, opening_balance_cents from public.accounts',
  $$values ('cash'::text, 2000::bigint)$$,
  'starting today, the cash of redeem_invite is the opening balance'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 10, 3000);
select results_eq(
  'select kind, opening_balance_cents from public.accounts',
  $$values ('cash'::text, null::bigint)$$,
  'with a past start date the cash is asked later, with its date'
);

-- The server links Anna's bank: a connection, a bank account, a balance.
reset role;
insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', pg_temp.member_of('00000000-0000-4000-8000-00000000000a'),
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (
  id, household_id, owner_member_id, kind, connection_id, provider_account_id, currency, display_name, identifier
) values (
  '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
  pg_temp.member_of('00000000-0000-4000-8000-00000000000a'), 'bank',
  '00000000-0000-4000-8000-0000000000e1', 'conto-di-prova-1', 'EUR', 'Banca di Prova …0000',
  'IT00X0000000000000000000000'
);
insert into public.account_balances (account_id, currency, balance_type, amount_cents) values
  ('00000000-0000-4000-8000-0000000000e2', 'EUR', 'ITAV', 123456);

select throws_ok(
  $$insert into public.accounts (household_id, owner_member_id, kind, currency, display_name)
    values ('00000000-0000-4000-8000-0000000000f1',
            pg_temp.member_of('00000000-0000-4000-8000-00000000000a'), 'cash', 'EUR', 'Altri contanti')$$,
  '23505', null,
  'one cash account for each member'
);
select throws_ok(
  $$insert into public.accounts (household_id, owner_member_id, kind, currency, display_name)
    values ('00000000-0000-4000-8000-0000000000f1',
            pg_temp.member_of('00000000-0000-4000-8000-00000000000a'), 'bank', 'EUR', 'Conto senza banca')$$,
  '23514', null,
  'a bank account needs its connection'
);
select throws_ok(
  $$update public.accounts set opening_balance_cents = 100
    where id = '00000000-0000-4000-8000-0000000000e2'$$,
  '23514', null,
  'only cash and manual accounts have an opening balance'
);
select throws_ok(
  $$insert into public.accounts (household_id, owner_member_id, kind, connection_id, provider_account_id, currency, display_name)
    values ('00000000-0000-4000-8000-0000000000f1', pg_temp.member_of('00000000-0000-4000-8000-00000000000a'),
            'bank', '00000000-0000-4000-8000-0000000000e1', 'conto-di-prova-1', 'EUR', 'Doppione')$$,
  '23505', null,
  'an account of the bank appears once for each connection'
);

-- Visibility
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select is(
  (select count(*)::int from public.accounts),
  2,
  'Anna sees her two accounts: cash and bank'
);
select ok(
  public.is_account_owner('00000000-0000-4000-8000-0000000000e2'),
  'is_account_owner is true for the owner'
);
select results_eq(
  'select id from public.bank_connections',
  $$values ('00000000-0000-4000-8000-0000000000e1'::uuid)$$,
  'Anna sees her connection'
);
select results_eq(
  'select amount_cents from public.account_balances',
  $$values (123456::bigint)$$,
  'Anna sees the balance of her account'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  'select kind from public.accounts',
  $$values ('cash'::text)$$,
  'Bruno, in the same household, sees only his own account'
);
select ok(
  not public.is_account_owner('00000000-0000-4000-8000-0000000000e2'),
  'is_account_owner is false for another member'
);
select is_empty('select 1 from public.bank_connections', 'Bruno does not see the connections of Anna');
select is_empty('select 1 from public.account_balances', 'Bruno does not see the balances of Anna');
update public.accounts set display_name = 'Cambiato da Bruno'
  where id = '00000000-0000-4000-8000-0000000000e2';

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select results_eq(
  'select kind from public.accounts',
  $$values ('cash'::text)$$,
  'Dario sees only his own account'
);

-- Writes from the app
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$insert into public.accounts (id, household_id, owner_member_id, kind, currency, display_name, opening_balance_cents)
    values ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000f1',
            public.current_member_id(), 'manual', 'EUR', 'Libretto di prova', 10000)$$,
  'a member creates a manual account'
);
select throws_ok(
  $$insert into public.accounts (household_id, owner_member_id, kind, connection_id, currency, display_name)
    values ('00000000-0000-4000-8000-0000000000f1', public.current_member_id(), 'bank',
            '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Conto a mano')$$,
  '42501', null,
  'the accounts of the banks come only from the server'
);
select throws_ok(
  $$insert into public.accounts (household_id, owner_member_id, kind, currency, display_name)
    values ('00000000-0000-4000-8000-0000000000f1',
            pg_temp.member_of('00000000-0000-4000-8000-00000000000b'), 'manual', 'EUR', 'Per Bruno')$$,
  '42501', null,
  'a member creates accounts only for themselves'
);
select lives_ok(
  $$update public.accounts set display_name = 'Conto di casa', excluded_from_total = true
    where id = '00000000-0000-4000-8000-0000000000e2'$$,
  'the owner renames an account and leaves it out of the total'
);
select results_eq(
  $$select display_name, excluded_from_total, version from public.accounts
    where id = '00000000-0000-4000-8000-0000000000e2'$$,
  $$values ('Conto di casa'::text, true, 2)$$,
  'the change is saved, the version bumped, and Bruno changed nothing'
);
select throws_ok(
  $$update public.accounts set kind = 'manual' where id = '00000000-0000-4000-8000-0000000000e2'$$,
  '42501', null,
  'the kind of an account does not change from the app'
);
select throws_ok(
  $$update public.accounts set owner_member_id = pg_temp.member_of('00000000-0000-4000-8000-00000000000b')
    where id = '00000000-0000-4000-8000-0000000000e2'$$,
  '42501', null,
  'the owner of an account does not change from the app'
);
select throws_ok(
  'select user_id from public.eb_credentials',
  '42501', null,
  'the app does not read the credentials'
);
select throws_ok(
  $$insert into public.eb_credentials (user_id, app_id, private_key_secret_id)
    values ('00000000-0000-4000-8000-00000000000a', 'app-di-prova', gen_random_uuid())$$,
  '42501', null,
  'the app does not write the credentials'
);
select throws_ok(
  'select id from public.bank_raw_transactions',
  '42501', null,
  'the app does not read the raw data of the banks'
);

-- Deduplication of the raw rows (the server writes them).
reset role;
insert into public.bank_raw_transactions (
  account_id, dedup_hash, dedup_ordinal, status, booking_date, value_date, amount_cents, currency, payload
) values (
  '00000000-0000-4000-8000-0000000000e2', 'hash-di-prova', 1, 'BOOK',
  current_date - 2, current_date - 3, -250, 'EUR', '{"remittance_information": ["Caffe di prova"]}'
);
select lives_ok(
  $$insert into public.bank_raw_transactions (
      account_id, dedup_hash, dedup_ordinal, status, booking_date, value_date, amount_cents, currency, payload
    ) values (
      '00000000-0000-4000-8000-0000000000e2', 'hash-di-prova', 2, 'BOOK',
      current_date - 2, current_date - 3, -250, 'EUR', '{"remittance_information": ["Caffe di prova"]}'
    )$$,
  'two identical rows without reference are both saved'
);
select throws_ok(
  $$insert into public.bank_raw_transactions (
      account_id, dedup_hash, dedup_ordinal, status, booking_date, value_date, amount_cents, currency, payload
    ) values (
      '00000000-0000-4000-8000-0000000000e2', 'hash-di-prova', 1, 'BOOK',
      current_date - 2, current_date - 3, -250, 'EUR', '{"remittance_information": ["Caffe di prova"]}'
    )$$,
  '23505', null,
  'the same row downloaded twice is saved once'
);
insert into public.bank_raw_transactions (
  account_id, entry_reference, dedup_hash, dedup_ordinal, status, booking_date, amount_cents, currency, payload
) values (
  '00000000-0000-4000-8000-0000000000e2', 'RIF-0001', 'hash-con-riferimento', 1, 'BOOK',
  current_date - 1, -990, 'EUR', '{}'
);
select throws_ok(
  $$insert into public.bank_raw_transactions (
      account_id, entry_reference, dedup_hash, dedup_ordinal, status, booking_date, amount_cents, currency, payload
    ) values (
      '00000000-0000-4000-8000-0000000000e2', 'RIF-0001', 'hash-diverso', 1, 'BOOK',
      current_date - 1, -990, 'EUR', '{}'
    )$$,
  '23505', null,
  'with an entry reference, the reference decides'
);
select results_eq(
  $$select movement_date from public.bank_raw_transactions
    where dedup_hash in ('hash-di-prova', 'hash-con-riferimento')
    order by dedup_hash, dedup_ordinal$$,
  $$values (current_date - 1), (current_date - 3), (current_date - 3)$$,
  'the movement date is the value date, else the booking date'
);

-- Not signed in
set local role anon;
select throws_ok(
  'select id from public.accounts',
  '42501', null,
  'anon cannot read accounts'
);
select throws_ok(
  'select id from public.bank_connections',
  '42501', null,
  'anon cannot read connections'
);

select * from finish();
rollback;
