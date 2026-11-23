-- Demo accounts (docs/spec/accesso.md, 12; docs/spec/schema.md, 3): the
-- switch in Vault, the flag of the profile, households all demo or all real
-- and delete_my_demo_account. Invented users: Anna (a) and Bruno (b), demo,
-- in "Casa demo"; Carla (c), real, in "Casa di prova"; Dario (d), real,
-- without a household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(41);

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

-- The switch, on as on dev or off as on prod.
create function pg_temp.switch(enabled boolean)
returns void
language plpgsql
security definer
as $$
begin
  delete from vault.secrets where name = 'demo_accounts';
  if enabled then
    perform vault.create_secret('enabled', 'demo_accounts');
  end if;
end;
$$;

create function pg_temp.member(user_id uuid)
returns uuid
language sql
security definer
as $$
  select m.id from public.members m where m.user_id = member.user_id and m.left_at is null
$$;

create function pg_temp.cash(user_id uuid)
returns uuid
language sql
security definer
as $$
  select a.id from public.accounts a
  where a.owner_member_id = pg_temp.member(cash.user_id) and a.kind = 'cash'
$$;

create function pg_temp.line(transaction_id uuid)
returns uuid
language sql
security definer
as $$
  select l.id from public.transaction_lines l
  where l.transaction_id = line.transaction_id and l.position = 1
$$;

-- A shared subcategory of the expenses of Casa demo.
create function pg_temp.category()
returns uuid
language sql
security definer
as $$
  select c.id from public.categories c
  where c.household_id = '00000000-0000-4000-8000-0000000000f1'
    and c.parent_id is not null and c.kind = 'expense' and c.scope = 'shared'
    and c.system_key is null
  order by c.name
  limit 1
$$;

create temp table invite_codes (who text primary key, code text);
grant select, insert on invite_codes to authenticated;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated');

-- Structure and permissions
select has_column('public', 'profiles', 'is_demo', 'profiles has is_demo');
select col_not_null('public', 'profiles', 'is_demo', 'is_demo is not null');
select col_default_is('public', 'profiles', 'is_demo', 'false'::text, 'an account is real by default');
select ok(
  has_function_privilege('authenticated', 'public.delete_my_demo_account()', 'execute'),
  'the app calls delete_my_demo_account'
);
select ok(
  not has_function_privilege('anon', 'public.delete_my_demo_account()', 'execute'),
  'anon cannot execute delete_my_demo_account'
);
select ok(
  not has_function_privilege('authenticated', 'public.demo_accounts_enabled()', 'execute')
    and not has_function_privilege('anon', 'public.demo_accounts_enabled()', 'execute'),
  'the app cannot read the switch'
);

-- The switch off, as on prod
select is(public.demo_accounts_enabled(), false, 'without the secret the switch is off');
select vault.create_secret('disabled', 'demo_accounts');
select is(public.demo_accounts_enabled(), false, 'a value other than enabled keeps it off');
select pg_temp.switch(false);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$insert into public.profiles (id, display_name, is_demo)
    values ('00000000-0000-4000-8000-00000000000a', 'Anna', true)$$,
  'P0001', 'demo_disabled',
  'with the switch off a demo profile is refused'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select lives_ok(
  $$insert into public.profiles (id, display_name)
    values ('00000000-0000-4000-8000-00000000000c', 'Carla')$$,
  'a real profile is created as before'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
insert into public.profiles (id, display_name) values ('00000000-0000-4000-8000-00000000000d', 'Dario');
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select throws_ok(
  'select public.delete_my_demo_account()',
  'P0001', 'demo_disabled',
  'with the switch off the deletion is refused'
);

-- The switch on, as on dev
select pg_temp.switch(true);
reset role;
select is(public.demo_accounts_enabled(), true, 'with the secret enabled the switch is on');
set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$insert into public.profiles (id, display_name, is_demo)
    values ('00000000-0000-4000-8000-00000000000a', 'Anna', true)$$,
  'with the switch on a demo profile is created'
);
select lives_ok(
  $$insert into public.profiles (id, display_name, avatar_url, is_demo)
    values ('00000000-0000-4000-8000-00000000000a', 'Anna', null, true)
    on conflict (id) do update
    set display_name = excluded.display_name, avatar_url = excluded.avatar_url, is_demo = excluded.is_demo$$,
  'saving the first access again keeps the flag'
);
select throws_ok(
  $$update public.profiles set is_demo = false where id = '00000000-0000-4000-8000-00000000000a'$$,
  'P0001', 'demo_immutable',
  'a demo account does not become real'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select throws_ok(
  $$update public.profiles set is_demo = true where id = '00000000-0000-4000-8000-00000000000c'$$,
  'P0001', 'demo_immutable',
  'a real account does not become demo'
);
select throws_ok(
  'select public.delete_my_demo_account()',
  'P0001', 'not_demo',
  'a real account cannot delete itself'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
insert into public.profiles (id, display_name, is_demo) values ('00000000-0000-4000-8000-00000000000b', 'Bruno', true);

select pg_temp.switch(false);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  'select public.delete_my_demo_account()',
  'P0001', 'demo_disabled',
  'with the switch off not even a demo account deletes itself'
);
select pg_temp.switch(true);

-- Households all demo or all real
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select public.create_household('00000000-0000-4000-8000-0000000000f2', 'Casa di prova', current_date);
insert into invite_codes select 'prova', code from public.create_invite('per Anna');

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select results_eq(
  $$select error from public.redeem_invite(code => (select code from invite_codes where who = 'prova'))$$,
  $$values ('invite_demo_mismatch'::text)$$,
  'a demo account does not join a real household'
);
select is(public.current_member_id(), null, 'and does not become a member');

select public.create_household('00000000-0000-4000-8000-0000000000f1', 'Casa demo', current_date);
insert into invite_codes select 'demo', code from public.create_invite('per Bruno');

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select results_eq(
  $$select error from public.redeem_invite(code => (select code from invite_codes where who = 'demo'))$$,
  $$values ('invite_demo_mismatch'::text)$$,
  'a real account does not join a demo household'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$select error, household_id from public.redeem_invite(code => (select code from invite_codes where who = 'demo'))$$,
  $$values (null::text, '00000000-0000-4000-8000-0000000000f1'::uuid)$$,
  'a demo account joins a demo household, with the invite the refusal left unused'
);

-- Data in every table that points to Casa demo, and a movement of Carla in
-- Casa di prova.
reset role;

insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values (
  '00000000-0000-4000-8000-000000000c01', '00000000-0000-4000-8000-0000000000f2',
  pg_temp.cash('00000000-0000-4000-8000-00000000000c'), 'manual',
  pg_temp.member('00000000-0000-4000-8000-00000000000c'), pg_temp.member('00000000-0000-4000-8000-00000000000c'),
  current_date, -700, 'EUR'
);

-- Anna's bank: connection, account and card, balance, raw rows, a sync, a
-- link request.
insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', pg_temp.member('00000000-0000-4000-8000-00000000000a'),
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.member('00000000-0000-4000-8000-00000000000a'), 'bank',
   '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Banca di Prova'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.member('00000000-0000-4000-8000-00000000000a'), 'card',
   '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Carta di Prova');
insert into public.account_balances (account_id, currency, balance_type, amount_cents) values
  ('00000000-0000-4000-8000-0000000000e2', 'EUR', 'CLBD', 150000);
insert into public.bank_raw_transactions (
  id, account_id, dedup_hash, dedup_ordinal, status, booking_date, amount_cents, currency, payload
) values
  ('00000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-0000000000e2',
   'hash-spesa', 1, 'BOOK', current_date, -4500, 'EUR', '{}'),
  ('00000000-0000-4000-8000-000000000302', '00000000-0000-4000-8000-0000000000e2',
   'hash-acquisto', 1, 'BOOK', current_date, -9000, 'EUR', '{}');
insert into public.sync_runs (id, connection_id, trigger, status, finished_at) values
  ('00000000-0000-4000-8000-000000000c11', '00000000-0000-4000-8000-0000000000e1', 'admin', 'ok', now());
insert into public.sync_runs (connection_id, account_id, run_id, trigger, status, finished_at) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000e2',
   '00000000-0000-4000-8000-000000000c11', 'admin', 'ok', now());
insert into public.bank_link_requests (member_id, aspsp_name, aspsp_country, psu_type, uses_global_app) values
  (pg_temp.member('00000000-0000-4000-8000-00000000000a'), 'Banca di Prova', 'IT', 'personal', true);

-- A personal category of Bruno; a shared tag and a personal one of Anna.
insert into public.categories (id, household_id, parent_id, name, kind, scope, owner_member_id)
select '00000000-0000-4000-8000-000000000903', c.household_id, c.parent_id, 'Hobby di Bruno',
  'expense', 'personal', pg_temp.member('00000000-0000-4000-8000-00000000000b')
from public.categories c
where c.id = pg_temp.category();
insert into public.tags (id, household_id, name, scope, owner_member_id) values
  ('00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-0000000000f1', 'Vacanze', 'shared', null),
  ('00000000-0000-4000-8000-000000000902', '00000000-0000-4000-8000-0000000000f1', 'Solo mio', 'personal',
   pg_temp.member('00000000-0000-4000-8000-00000000000a'));

-- An installment plan of Anna, shared with Bruno.
insert into public.installment_plans (
  id, household_id, account_id, merchant, total_cents, installments_count, purchase_date, purchase_raw_id, category_id
) values (
  '00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000e2', 'Negozio di prova', 9000, 3, current_date,
  '00000000-0000-4000-8000-000000000302', pg_temp.category()
);
insert into public.installment_plan_shares (plan_id, member_id, weight) values
  ('00000000-0000-4000-8000-000000000701', pg_temp.member('00000000-0000-4000-8000-00000000000a'), 1),
  ('00000000-0000-4000-8000-000000000701', pg_temp.member('00000000-0000-4000-8000-00000000000b'), 1);

-- Anna: a shared expense from the bank, a transfer to her card, an
-- installment, a saving in cash. Bruno: an advance, its refund and a
-- settlement, in cash.
insert into public.transactions (
  id, household_id, account_id, source, raw_id, paid_by_member_id, entered_by_member_id,
  movement_date, amount_cents, currency, installment_plan_id
)
select t.id, '00000000-0000-4000-8000-0000000000f1', t.account_id, t.source, t.raw_id,
  pg_temp.member(t.user_id), case when t.source = 'manual' then pg_temp.member(t.user_id) end,
  current_date, t.amount, 'EUR', t.plan_id
from (values
  ('00000000-0000-4000-8000-000000000101'::uuid, '00000000-0000-4000-8000-00000000000a'::uuid,
   '00000000-0000-4000-8000-0000000000e2'::uuid, 'bank', '00000000-0000-4000-8000-000000000301'::uuid, -4500, null::uuid),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-00000000000a',
   '00000000-0000-4000-8000-0000000000e2', 'bank', null, -10000, null),
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-00000000000a',
   '00000000-0000-4000-8000-0000000000e3', 'bank', null, 10000, null),
  ('00000000-0000-4000-8000-000000000104', '00000000-0000-4000-8000-00000000000a',
   '00000000-0000-4000-8000-0000000000e2', 'bank', null, -3000, '00000000-0000-4000-8000-000000000701'),
  ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-00000000000a',
   pg_temp.cash('00000000-0000-4000-8000-00000000000a'), 'manual', null, -500, null),
  ('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-00000000000b',
   pg_temp.cash('00000000-0000-4000-8000-00000000000b'), 'manual', null, -2000, null),
  ('00000000-0000-4000-8000-000000000107', '00000000-0000-4000-8000-00000000000b',
   pg_temp.cash('00000000-0000-4000-8000-00000000000b'), 'manual', null, 1000, null),
  ('00000000-0000-4000-8000-000000000108', '00000000-0000-4000-8000-00000000000b',
   pg_temp.cash('00000000-0000-4000-8000-00000000000b'), 'manual', null, -1500, null)
) as t (id, user_id, account_id, source, raw_id, amount, plan_id);
update public.bank_raw_transactions set transaction_id = '00000000-0000-4000-8000-000000000101'
  where id = '00000000-0000-4000-8000-000000000301';

insert into public.transfers (id, household_id, from_account_id, to_account_id, out_transaction_id, in_transaction_id, origin) values
  ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000e3',
   '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000103', 'manual');
update public.transaction_lines set kind = 'transfer', transfer_id = '00000000-0000-4000-8000-000000000401'
  where transaction_id in ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000103');

insert into public.settlements (
  id, household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin,
  payer_transaction_id, created_by_member_id
) values (
  '00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-0000000000f1',
  pg_temp.member('00000000-0000-4000-8000-00000000000b'), pg_temp.member('00000000-0000-4000-8000-00000000000a'),
  1500, 'EUR', current_date, 'manual', '00000000-0000-4000-8000-000000000108',
  pg_temp.member('00000000-0000-4000-8000-00000000000b')
);
update public.transaction_lines set kind = 'settlement', settlement_id = '00000000-0000-4000-8000-000000000501'
  where transaction_id = '00000000-0000-4000-8000-000000000108';

insert into public.piggy_banks (id, household_id, name, created_by_member_id) values
  ('00000000-0000-4000-8000-000000000801', '00000000-0000-4000-8000-0000000000f1', 'Vacanze',
   pg_temp.member('00000000-0000-4000-8000-00000000000a'));
insert into public.piggy_bank_members (piggy_bank_id, member_id) values
  ('00000000-0000-4000-8000-000000000801', pg_temp.member('00000000-0000-4000-8000-00000000000b'));
update public.transaction_lines set kind = 'saving'
  where transaction_id = '00000000-0000-4000-8000-000000000105';
insert into public.piggy_bank_entries (piggy_bank_id, member_id, account_id, kind, transaction_id, amount_cents, entry_date) values
  ('00000000-0000-4000-8000-000000000801', pg_temp.member('00000000-0000-4000-8000-00000000000a'),
   '00000000-0000-4000-8000-0000000000e2', 'virtual', null, 1000, current_date),
  ('00000000-0000-4000-8000-000000000801', pg_temp.member('00000000-0000-4000-8000-00000000000a'),
   pg_temp.cash('00000000-0000-4000-8000-00000000000a'), 'real', '00000000-0000-4000-8000-000000000105', 500, current_date);

-- What is only of the accounts: settings, devices, PayPal emails, the
-- credentials of Anna with their secret in Vault.
insert into public.user_settings (user_id, privacy_notice_version, privacy_notice_read_at) values
  ('00000000-0000-4000-8000-00000000000a', 'p1', now()),
  ('00000000-0000-4000-8000-00000000000b', 'p1', now()),
  ('00000000-0000-4000-8000-00000000000c', 'p1', now());
insert into public.devices (id, user_id, platform) values
  ('00000000-0000-4000-8000-000000000d01', '00000000-0000-4000-8000-00000000000a', 'android'),
  ('00000000-0000-4000-8000-000000000d02', '00000000-0000-4000-8000-00000000000b', 'android'),
  ('00000000-0000-4000-8000-000000000d03', '00000000-0000-4000-8000-00000000000c', 'android');
insert into public.paypal_emails (user_id, email, source) values
  ('00000000-0000-4000-8000-00000000000a', 'anna@example.com', 'manual'),
  ('00000000-0000-4000-8000-00000000000b', 'bruno@example.com', 'manual');
set local role service_role;
select public.eb_set_credentials('00000000-0000-4000-8000-00000000000a', 'app-di-prova', 'chiave-di-prova');
reset role;

-- Anna shares her expense with Bruno and tags two lines.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transaction_lines set kind = 'expense', category_id = pg_temp.category()
  where transaction_id = '00000000-0000-4000-8000-000000000101';
select public.set_line_shares(
  pg_temp.line('00000000-0000-4000-8000-000000000101'),
  jsonb_build_array(
    jsonb_build_object('member_id', pg_temp.member('00000000-0000-4000-8000-00000000000a'), 'weight', 1),
    jsonb_build_object('member_id', pg_temp.member('00000000-0000-4000-8000-00000000000b'), 'weight', 1)
  )
);
insert into public.line_tags (line_id, tag_id) values
  (pg_temp.line('00000000-0000-4000-8000-000000000101'), '00000000-0000-4000-8000-000000000901'),
  (pg_temp.line('00000000-0000-4000-8000-000000000105'), '00000000-0000-4000-8000-000000000902');
select public.set_initial_balances(jsonb_build_array(
  jsonb_build_object('member_id', pg_temp.member('00000000-0000-4000-8000-00000000000a'), 'amount_cents', 500),
  jsonb_build_object('member_id', pg_temp.member('00000000-0000-4000-8000-00000000000b'), 'amount_cents', -500)
));
-- Bruno: the advance for a friend and its refund.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
update public.transaction_lines set kind = 'advance'
  where transaction_id = '00000000-0000-4000-8000-000000000106';
update public.transaction_lines set kind = 'refund'
  where transaction_id = '00000000-0000-4000-8000-000000000107';
insert into public.contacts (id, household_id, owner_member_id, name) values
  ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.member('00000000-0000-4000-8000-00000000000b'), 'Amica di prova');
insert into public.advances (id, line_id, contact_id, expected_cents) values
  ('00000000-0000-4000-8000-000000000602', pg_temp.line('00000000-0000-4000-8000-000000000106'),
   '00000000-0000-4000-8000-000000000601', 2000);
insert into public.advance_repayments (advance_id, line_id, amount_cents) values
  ('00000000-0000-4000-8000-000000000602', pg_temp.line('00000000-0000-4000-8000-000000000107'), 1000);

reset role;
select lives_ok('select pg_temp.check_deferred()', 'the data of Casa demo hold');

-- The ids of Casa demo, kept to look for its rows after the deletion.
create temp table demo_ids (kind text, id uuid);
insert into demo_ids
  select 'member', m.id from public.members m where m.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'account', a.id from public.accounts a where a.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'connection', c.id from public.bank_connections c
    join public.members m on m.id = c.member_id
    where m.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'line', l.id from public.transaction_lines l where l.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'plan', p.id from public.installment_plans p where p.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'set', s.id from public.default_share_sets s where s.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'piggy_bank', p.id from public.piggy_banks p where p.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'contact', c.id from public.contacts c where c.household_id = '00000000-0000-4000-8000-0000000000f1'
  union all
  select 'bruno', pg_temp.member('00000000-0000-4000-8000-00000000000b');

-- Rows of Casa demo in each table that points to it, directly or not.
create function pg_temp.demo_rows()
returns table (name text, n bigint)
language sql
as $$
  with h (id) as (values ('00000000-0000-4000-8000-0000000000f1'::uuid))
  select 'households', count(*) from public.households where id = (select id from h)
  union all select 'members', count(*) from public.members where household_id = (select id from h)
  union all select 'invites', count(*) from public.invites where household_id = (select id from h)
  union all select 'accounts', count(*) from public.accounts where household_id = (select id from h)
  union all select 'account_balances', count(*) from public.account_balances
    where account_id in (select id from pg_temp.demo_ids where kind = 'account')
  union all select 'bank_raw_transactions', count(*) from public.bank_raw_transactions
    where account_id in (select id from pg_temp.demo_ids where kind = 'account')
  union all select 'bank_connections', count(*) from public.bank_connections
    where member_id in (select id from pg_temp.demo_ids where kind = 'member')
  union all select 'bank_link_requests', count(*) from public.bank_link_requests
    where member_id in (select id from pg_temp.demo_ids where kind = 'member')
  union all select 'sync_runs', count(*) from public.sync_runs
    where connection_id in (select id from pg_temp.demo_ids where kind = 'connection')
  union all select 'categories', count(*) from public.categories where household_id = (select id from h)
  union all select 'tags', count(*) from public.tags where household_id = (select id from h)
  union all select 'installment_plans', count(*) from public.installment_plans where household_id = (select id from h)
  union all select 'installment_plan_shares', count(*) from public.installment_plan_shares
    where plan_id in (select id from pg_temp.demo_ids where kind = 'plan')
  union all select 'transactions', count(*) from public.transactions where household_id = (select id from h)
  union all select 'transaction_lines', count(*) from public.transaction_lines where household_id = (select id from h)
  union all select 'line_shares', count(*) from public.line_shares where household_id = (select id from h)
  union all select 'line_tags', count(*) from public.line_tags
    where line_id in (select id from pg_temp.demo_ids where kind = 'line')
  union all select 'transfers', count(*) from public.transfers where household_id = (select id from h)
  union all select 'default_share_sets', count(*) from public.default_share_sets where household_id = (select id from h)
  union all select 'default_share_weights', count(*) from public.default_share_weights
    where set_id in (select id from pg_temp.demo_ids where kind = 'set')
  union all select 'settlements', count(*) from public.settlements where household_id = (select id from h)
  union all select 'initial_balances', count(*) from public.initial_balances where household_id = (select id from h)
  union all select 'piggy_banks', count(*) from public.piggy_banks where household_id = (select id from h)
  union all select 'piggy_bank_members', count(*) from public.piggy_bank_members
    where piggy_bank_id in (select id from pg_temp.demo_ids where kind = 'piggy_bank')
  union all select 'piggy_bank_entries', count(*) from public.piggy_bank_entries
    where piggy_bank_id in (select id from pg_temp.demo_ids where kind = 'piggy_bank')
  union all select 'contacts', count(*) from public.contacts where household_id = (select id from h)
  union all select 'advances', count(*) from public.advances
    where contact_id in (select id from pg_temp.demo_ids where kind = 'contact')
  union all select 'advance_repayments', count(*) from public.advance_repayments
    where line_id in (select id from pg_temp.demo_ids where kind = 'line')
$$;

-- Rows of Casa di prova and of Carla, to compare after the deletions.
create function pg_temp.prova_rows()
returns table (name text, n bigint)
language sql
as $$
  with h (id) as (values ('00000000-0000-4000-8000-0000000000f2'::uuid))
  select 'households', count(*) from public.households where id = (select id from h)
  union all select 'members', count(*) from public.members where household_id = (select id from h)
  union all select 'invites', count(*) from public.invites where household_id = (select id from h)
  union all select 'accounts', count(*) from public.accounts where household_id = (select id from h)
  union all select 'categories', count(*) from public.categories where household_id = (select id from h)
  union all select 'transactions', count(*) from public.transactions where household_id = (select id from h)
  union all select 'transaction_lines', count(*) from public.transaction_lines where household_id = (select id from h)
  union all select 'line_shares', count(*) from public.line_shares where household_id = (select id from h)
  union all select 'default_share_sets', count(*) from public.default_share_sets where household_id = (select id from h)
  union all select 'carla', count(*) from public.profiles p
    join public.user_settings s on s.user_id = p.id
    join public.devices d on d.user_id = p.id
    where p.id = '00000000-0000-4000-8000-00000000000c'
$$;

create temp table prova_before as select * from pg_temp.prova_rows();

select set_eq(
  $$with recursive reach (oid) as (
      select 'public.households'::regclass::oid
      union
      select c.conrelid from pg_constraint c join reach r on c.confrelid = r.oid
      where c.contype = 'f'
    )
    select cl.relname::text from reach join pg_class cl on cl.oid = reach.oid
    where cl.oid <> 'public.households'::regclass$$,
  array[
    'members', 'invites', 'accounts', 'account_balances', 'bank_raw_transactions',
    'bank_connections', 'bank_link_requests', 'sync_runs', 'categories', 'tags',
    'installment_plans', 'installment_plan_shares', 'transactions', 'transaction_lines',
    'line_shares', 'line_tags', 'transfers', 'default_share_sets', 'default_share_weights',
    'settlements', 'initial_balances', 'piggy_banks', 'piggy_bank_members',
    'piggy_bank_entries', 'contacts', 'advances', 'advance_repayments'
  ],
  'the tables that point to a household, directly or not, are the ones delete_my_demo_account empties'
);
select is_empty(
  'select name from pg_temp.demo_rows() where n = 0',
  'Casa demo has rows in every one of them'
);

-- Bruno deletes his demo account: Anna stays, so Casa demo stays.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok('select public.delete_my_demo_account()', 'Bruno deletes his demo account');
reset role;
select lives_ok('select pg_temp.check_deferred()', 'his deletion leaves nothing to check');
select is_empty(
  'select name from pg_temp.demo_rows() where n = 0',
  'with Anna still a member, Casa demo keeps all its data'
);
select results_eq(
  $$select user_id, left_at is not null from public.members
    where id = (select id from pg_temp.demo_ids where kind = 'bruno')$$,
  $$values (null::uuid, true)$$,
  'Bruno is an ex member, without an account'
);
select isnt_empty(
  $$select 1 from public.transactions
    where paid_by_member_id = (select id from pg_temp.demo_ids where kind = 'bruno')$$,
  'his movements stay, as for any member who left'
);
select is_empty(
  $$select 'users' from auth.users where id = '00000000-0000-4000-8000-00000000000b'
    union all select 'profiles' from public.profiles where id = '00000000-0000-4000-8000-00000000000b'
    union all select 'user_settings' from public.user_settings where user_id = '00000000-0000-4000-8000-00000000000b'
    union all select 'devices' from public.devices where user_id = '00000000-0000-4000-8000-00000000000b'
    union all select 'paypal_emails' from public.paypal_emails where user_id = '00000000-0000-4000-8000-00000000000b'
    union all select 'invite_attempts' from public.invite_attempts where user_id = '00000000-0000-4000-8000-00000000000b'$$,
  'Bruno is gone, with profile, settings, devices, PayPal emails and invite attempts'
);
select results_eq(
  $$select m.user_id from public.members m
    where m.household_id = '00000000-0000-4000-8000-0000000000f1' and m.left_at is null$$,
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid)$$,
  'Anna is still the active member of Casa demo'
);

-- Anna, now alone, deletes hers: Casa demo goes with all its data.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok('select public.delete_my_demo_account()', 'Anna, alone in Casa demo, deletes her demo account');
reset role;
select lives_ok('select pg_temp.check_deferred()', 'the deletion of the household leaves nothing to check');
select is_empty('select name from pg_temp.demo_rows() where n > 0', 'no row of Casa demo is left');
select is_empty(
  $$select 'users' from auth.users where id = '00000000-0000-4000-8000-00000000000a'
    union all select 'profiles' from public.profiles where id = '00000000-0000-4000-8000-00000000000a'
    union all select 'user_settings' from public.user_settings where user_id = '00000000-0000-4000-8000-00000000000a'
    union all select 'devices' from public.devices where user_id = '00000000-0000-4000-8000-00000000000a'
    union all select 'paypal_emails' from public.paypal_emails where user_id = '00000000-0000-4000-8000-00000000000a'
    union all select 'invite_attempts' from public.invite_attempts where user_id = '00000000-0000-4000-8000-00000000000a'
    union all select 'eb_credentials' from public.eb_credentials where user_id = '00000000-0000-4000-8000-00000000000a'$$,
  'Anna is gone, with profile, settings, devices, PayPal emails, invite attempts and credentials'
);
select is_empty(
  $$select 1 from vault.secrets where name = 'eb_private_key:00000000-0000-4000-8000-00000000000a'$$,
  'her private key leaves Vault'
);
select set_eq(
  'select * from pg_temp.prova_rows()',
  'select * from prova_before',
  'Casa di prova and Carla are untouched'
);
select isnt_empty(
  $$select 1 from public.profiles where id = '00000000-0000-4000-8000-00000000000d'$$,
  'and so is Dario'
);

-- A second call after a lost answer: the account is already gone.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok('select public.delete_my_demo_account()', 'a second call after the deletion does nothing');

reset role;
set local role anon;
select throws_ok(
  'select public.delete_my_demo_account()',
  '42501', null,
  'anon cannot call delete_my_demo_account'
);

select * from finish();
rollback;
