-- Bank sync (docs/spec/sincronizzazione.md, 2, 3, 4 and 9): Vault,
-- credentials, link requests, opening and closing of the syncs, the secret
-- of the jobs, permissions. Invented users: Anna (a1) and Bruno (b1) in
-- "Casa di prova", with a former member (e9); Dario (d1) alone; Carla (c),
-- an account without a household. Invented keys: plain texts, never PEM.
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

-- Ids returned by the functions, kept for the next checks.
create temp table ids (name text primary key, id uuid);
grant select, insert on ids to service_role, authenticated;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000d', 'Dario');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 60),
  ('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60),
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 60),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60);
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000e9', '00000000-0000-4000-8000-0000000000f1',
   null, current_date - 60, now());

-- Anna has two connections: a bank with a bank account and a card (e1), a
-- second bank with one account (e4). The former member had one too (e6).
insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status, last_error) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', false, 'active', 'rate_limited'),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000a1',
   'Altra Banca di Prova', 'IT', false, 'active', null),
  ('00000000-0000-4000-8000-0000000000e6', '00000000-0000-4000-8000-0000000000e9',
   'Banca di Prova', 'IT', true, 'active', null);
insert into public.accounts (
  id, household_id, owner_member_id, kind, connection_id, provider_account_id, cash_account_type, currency, display_name
) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1',
   'conto-di-prova-1', 'CACC', 'EUR', 'Banca di Prova …0000'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1',
   'carta-di-prova-1', 'CARD', 'EUR', 'Carta …0000'),
  ('00000000-0000-4000-8000-0000000000e5', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e4',
   'conto-di-prova-2', 'CACC', 'EUR', 'Altra Banca di Prova …0001');
insert into public.sync_runs (connection_id, trigger, status, finished_at) values
  ('00000000-0000-4000-8000-0000000000e6', 'schedule', 'ok', now());

-- Structure and Vault
select has_table('public', 'bank_link_requests', 'bank_link_requests exists');
select has_table('public', 'sync_runs', 'sync_runs exists');
select has_extension('supabase_vault', 'Supabase Vault is installed');
select has_extension('pg_cron', 'pg_cron is installed');
select has_extension('pg_net', 'pg_net is installed');
select lives_ok(
  $$select vault.create_secret('valore-di-prova', 'segreto-di-prova')$$,
  'vault.create_secret saves a secret'
);
select is(
  (select decrypted_secret from vault.decrypted_secrets where name = 'segreto-di-prova'),
  'valore-di-prova',
  'vault.decrypted_secrets gives the secret back'
);

-- Credentials (the Edge Functions call them with the service role)
set local role service_role;
select is_empty(
  $$select * from public.eb_get_credentials('00000000-0000-4000-8000-00000000000b')$$,
  'no credentials, no row'
);
select lives_ok(
  $$select public.eb_set_credentials('00000000-0000-4000-8000-00000000000a', 'app-di-prova-1', 'chiave-di-prova-1')$$,
  'the first call saves the credentials'
);

reset role;
insert into ids
  select 'anna_secret', private_key_secret_id
  from public.eb_credentials where user_id = '00000000-0000-4000-8000-00000000000a';
select results_eq(
  $$select c.app_id, s.name, s.decrypted_secret collate "default"
    from public.eb_credentials c
    join vault.decrypted_secrets s on s.id = c.private_key_secret_id$$,
  $$values ('app-di-prova-1'::text, 'eb_private_key:00000000-0000-4000-8000-00000000000a'::text,
            'chiave-di-prova-1'::text)$$,
  'one row, and the key in the secret with the name of the person'
);

set local role service_role;
select lives_ok(
  $$select public.eb_set_credentials('00000000-0000-4000-8000-00000000000a', 'app-di-prova-2', 'chiave-di-prova-2')$$,
  'the second call replaces the credentials'
);

reset role;
select is(
  (select private_key_secret_id from public.eb_credentials where user_id = '00000000-0000-4000-8000-00000000000a'),
  (select id from ids where name = 'anna_secret'),
  'the second call keeps the same secret'
);
select is(
  (select count(*)::int from vault.secrets where name = 'eb_private_key:00000000-0000-4000-8000-00000000000a'),
  1,
  'one secret with the name of the person'
);
select results_eq(
  $$select c.app_id, s.decrypted_secret collate "default"
    from public.eb_credentials c
    join vault.decrypted_secrets s on s.id = c.private_key_secret_id$$,
  $$values ('app-di-prova-2'::text, 'chiave-di-prova-2'::text)$$,
  'the new key in the secret and the new application id in the row'
);
select is_empty(
  $$select 1 from public.eb_credentials c where to_jsonb(c)::text like '%chiave-di-prova%'$$,
  'no column of eb_credentials holds the key'
);

set local role service_role;
select results_eq(
  $$select app_id, private_key from public.eb_get_credentials('00000000-0000-4000-8000-00000000000a')$$,
  $$values ('app-di-prova-2'::text, 'chiave-di-prova-2'::text)$$,
  'eb_get_credentials gives the application id and the key'
);

-- A secret with the name of Bruno but without its row is reused.
reset role;
insert into ids
  select 'bruno_orphan', vault.create_secret('chiave-orfana', 'eb_private_key:00000000-0000-4000-8000-00000000000b');
set local role service_role;
select public.eb_set_credentials('00000000-0000-4000-8000-00000000000b', 'app-di-prova-b', 'chiave-di-prova-b');
reset role;
select results_eq(
  $$select c.private_key_secret_id = (select id from ids where name = 'bruno_orphan'), s.decrypted_secret collate "default",
           (select count(*)::int from vault.secrets where name = 'eb_private_key:00000000-0000-4000-8000-00000000000b')
    from public.eb_credentials c
    join vault.decrypted_secrets s on s.id = c.private_key_secret_id
    where c.user_id = '00000000-0000-4000-8000-00000000000b'$$,
  $$values (true, 'chiave-di-prova-b'::text, 1)$$,
  'a secret left without its row is reused, with the new key'
);

-- A row whose secret is gone gets a secret again.
set local role service_role;
select public.eb_set_credentials('00000000-0000-4000-8000-00000000000d', 'app-di-prova-d', 'chiave-di-prova-d1');
reset role;
delete from vault.secrets
  where id = (select private_key_secret_id from public.eb_credentials where user_id = '00000000-0000-4000-8000-00000000000d');
set local role service_role;
select public.eb_set_credentials('00000000-0000-4000-8000-00000000000d', 'app-di-prova-d', 'chiave-di-prova-d2');
select results_eq(
  $$select app_id, private_key from public.eb_get_credentials('00000000-0000-4000-8000-00000000000d')$$,
  $$values ('app-di-prova-d'::text, 'chiave-di-prova-d2'::text)$$,
  'a row without its secret gets a new one'
);

select throws_ok(
  $$select public.eb_set_credentials('00000000-0000-4000-8000-00000000000a', ' ', 'chiave-di-prova-3')$$,
  'P0001', 'invalid_credentials',
  'an empty application id is refused'
);
select throws_ok(
  $$select public.eb_set_credentials('00000000-0000-4000-8000-00000000000a', 'app-di-prova-3', '')$$,
  'P0001', 'invalid_credentials',
  'an empty key is refused'
);
select throws_ok(
  $$select public.eb_set_credentials('00000000-0000-4000-8000-00000000000a', 'app-di-prova-3', null)$$,
  'P0001', 'invalid_credentials',
  'a missing key is refused'
);
select throws_ok(
  $$select public.eb_set_credentials('00000000-0000-4000-8000-00000000000a', 'app-di-prova-3', repeat('k', 16385))$$,
  'P0001', 'invalid_credentials',
  'a key over 16 KB is refused'
);

-- A deleted row takes its secret with it, also with the account.
reset role;
delete from public.eb_credentials where user_id = '00000000-0000-4000-8000-00000000000a';
select is_empty(
  $$select 1 from vault.secrets where id = (select id from ids where name = 'anna_secret')$$,
  'deleting the credentials deletes the secret'
);

set local role service_role;
select public.eb_set_credentials('00000000-0000-4000-8000-00000000000c', 'app-di-prova-c', 'chiave-di-prova-c');
reset role;
insert into ids
  select 'carla_secret', private_key_secret_id
  from public.eb_credentials where user_id = '00000000-0000-4000-8000-00000000000c';
delete from auth.users where id = '00000000-0000-4000-8000-00000000000c';
select is_empty(
  $$select 1 from vault.secrets where id = (select id from ids where name = 'carla_secret')$$,
  'deleting the account deletes the secret'
);

-- Link requests
set local role service_role;
insert into ids
  select 'request', public.create_link_request(
    '00000000-0000-4000-8000-0000000000a1', 'Banca di Prova', 'IT', 'personal', true
  );
select results_eq(
  $$select member_id, aspsp_name, aspsp_country, psu_type, uses_global_app,
           expires_at = now() + interval '30 minutes', used_at, result
    from public.bank_link_requests where id = (select id from ids where name = 'request')$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 'Banca di Prova'::text, 'IT'::text,
            'personal'::text, true, true, null::timestamptz, null::text)$$,
  'an active member gets a request that expires in 30 minutes'
);
select throws_ok(
  $$select public.create_link_request('00000000-0000-4000-8000-0000000000e9', 'Banca di Prova', 'IT', 'personal', true)$$,
  'P0001', 'member_not_eligible',
  'a former member gets no request'
);
select throws_ok(
  $$select public.create_link_request('00000000-0000-4000-8000-0000000000ff', 'Banca di Prova', 'IT', 'personal', true)$$,
  'P0001', 'member_not_eligible',
  'an unknown member gets no request'
);
select throws_ok(
  $$select public.create_link_request('00000000-0000-4000-8000-0000000000a1', 'Banca di Prova', 'it', 'personal', true)$$,
  '23514', null,
  'the country is a code of two capital letters'
);

select results_eq(
  $$select id, used_at = now() from public.claim_link_request((select id from ids where name = 'request'))$$,
  $$select id, true from ids where name = 'request'$$,
  'the first claim returns the request'
);
select is(
  (select used_at from public.bank_link_requests where id = (select id from ids where name = 'request')),
  now(),
  'the first claim marks the request as used'
);
select is_empty(
  $$select * from public.claim_link_request((select id from ids where name = 'request'))$$,
  'a used request returns nothing'
);
insert into ids
  select 'expired', public.create_link_request(
    '00000000-0000-4000-8000-0000000000a1', 'Banca di Prova', 'IT', 'business', false
  );
update public.bank_link_requests set expires_at = now() - interval '1 minute'
  where id = (select id from ids where name = 'expired');
select is_empty(
  $$select * from public.claim_link_request((select id from ids where name = 'expired'))$$,
  'an expired request returns nothing'
);
select is_empty(
  $$select * from public.claim_link_request('00000000-0000-4000-8000-0000000000ff')$$,
  'an unknown request returns nothing'
);

-- Opening of the syncs
insert into ids
  select 'run1', run_id from public.begin_sync_run('00000000-0000-4000-8000-0000000000e1', 'schedule');
select results_eq(
  $$select trigger, status, account_id, finished_at from public.sync_runs
    where id = (select id from ids where name = 'run1')$$,
  $$values ('schedule'::text, 'running'::text, null::uuid, null::timestamptz)$$,
  'the first call opens a running sync'
);
select results_eq(
  $$select status from public.begin_sync_run('00000000-0000-4000-8000-0000000000e1', 'manual')$$,
  $$values ('skipped'::text)$$,
  'a second call within 15 minutes is skipped'
);
select results_eq(
  $$select trigger, error_code, finished_at = now() from public.sync_runs
    where connection_id = '00000000-0000-4000-8000-0000000000e1' and status = 'skipped'$$,
  $$values ('manual'::text, 'already_running'::text, true)$$,
  'the skipped call leaves a closed row with already_running'
);
select throws_ok(
  $$select * from public.begin_sync_run('00000000-0000-4000-8000-0000000000ff', 'admin')$$,
  'P0001', 'connection_not_found',
  'an unknown connection is refused'
);

reset role;
select throws_ok(
  $$insert into public.sync_runs (connection_id, trigger, status)
    values ('00000000-0000-4000-8000-0000000000e1', 'admin', 'running')$$,
  '23505', null,
  'one running sync for each connection'
);
update public.sync_runs set started_at = now() - interval '16 minutes'
  where id = (select id from ids where name = 'run1');

set local role service_role;
insert into ids
  select 'run2', run_id from public.begin_sync_run('00000000-0000-4000-8000-0000000000e1', 'schedule');
select results_eq(
  $$select status, error_code, finished_at = now() from public.sync_runs
    where id = (select id from ids where name = 'run1')$$,
  $$values ('error'::text, 'internal'::text, true)$$,
  'a sync running for 16 minutes is closed as an error'
);
select results_eq(
  $$select status from public.sync_runs where id = (select id from ids where name = 'run2')$$,
  $$values ('running'::text)$$,
  'and a new sync starts'
);

-- Closing of the syncs
select lives_ok(
  $$select public.finish_sync_run(
      (select id from ids where name = 'run2'), 'ok', null,
      '{"strategy": "default", "matched_transfers": 1, "matched_settlements": 2, "matched_installments": 0,
        "accounts": [
          {"account_id": "00000000-0000-4000-8000-0000000000e2", "status": "ok", "strategy": "default",
           "date_from": "2031-03-01", "history_from": "2031-03-01", "history_incomplete": false,
           "rows_received": 10, "raw_inserted": 4, "transactions_created": 3, "skipped_before_start": 1,
           "skipped_status": 2, "groups_shrunk": 1, "booked_then_cancelled": 1, "purchase_already_classified": 0},
          {"account_id": "00000000-0000-4000-8000-0000000000e3", "status": "ok", "strategy": "longest",
           "date_from": "2031-01-01", "history_from": "2031-02-01", "history_incomplete": true,
           "rows_received": 5, "raw_inserted": 5, "transactions_created": 4, "purchase_already_classified": 1}
        ]}'
    )$$,
  'a sync closes with the counts of its accounts'
);
select results_eq(
  $$select account_id, connection_id, trigger, status, strategy, date_from, history_from, history_incomplete,
           rows_received, raw_inserted, transactions_created, skipped_before_start, skipped_status,
           groups_shrunk, booked_then_cancelled, purchase_already_classified, finished_at = now()
    from public.sync_runs where run_id = (select id from ids where name = 'run2')
    order by account_id$$,
  $$values
    ('00000000-0000-4000-8000-0000000000e2'::uuid, '00000000-0000-4000-8000-0000000000e1'::uuid,
     'schedule'::text, 'ok'::text, 'default'::text, '2031-03-01'::date, '2031-03-01'::date, false,
     10, 4, 3, 1, 2, 1, 1, 0, true),
    ('00000000-0000-4000-8000-0000000000e3'::uuid, '00000000-0000-4000-8000-0000000000e1'::uuid,
     'schedule'::text, 'ok'::text, 'longest'::text, '2031-01-01'::date, '2031-02-01'::date, true,
     5, 5, 4, 0, 0, 0, 0, 1, true)$$,
  'one row for each account, linked to the row of the connection'
);
select results_eq(
  $$select status, error_code, strategy, history_incomplete,
           rows_received, raw_inserted, transactions_created, skipped_before_start, skipped_status,
           groups_shrunk, booked_then_cancelled, purchase_already_classified,
           matched_transfers, matched_settlements, matched_installments, finished_at = now()
    from public.sync_runs where id = (select id from ids where name = 'run2')$$,
  $$values ('ok'::text, null::text, 'default'::text, true, 15, 9, 7, 1, 2, 1, 1, 1, 1, 2, 0, true)$$,
  'the row of the connection has the sums, the matches and the incomplete history'
);
select results_eq(
  $$select status, last_sync_at = now(), last_success_at = now(), last_error
    from public.bank_connections where id = '00000000-0000-4000-8000-0000000000e1'$$,
  $$values ('active'::text, true, true, null::text)$$,
  'a successful sync sets the times of the connection and clears its error'
);
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run2'), 'ok', null, '{}')$$,
  'P0001', 'run_not_running',
  'a sync closes once'
);

insert into ids
  select 'run3', run_id from public.begin_sync_run('00000000-0000-4000-8000-0000000000e4', 'manual');
select public.finish_sync_run((select id from ids where name = 'run3'), 'error', 'consent_expired', '{}');
select results_eq(
  $$select status, last_error, last_sync_at = now(), last_success_at
    from public.bank_connections where id = '00000000-0000-4000-8000-0000000000e4'$$,
  $$values ('expired'::text, 'consent_expired'::text, true, null::timestamptz)$$,
  'an expired consent marks the connection as expired'
);

insert into ids
  select 'run4', run_id from public.begin_sync_run('00000000-0000-4000-8000-0000000000e1', 'admin');
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run4'), 'ok', null,
      '{"accounts": [{"account_id": "00000000-0000-4000-8000-0000000000e5", "status": "ok"}]}')$$,
  'P0001', 'account_not_in_connection',
  'an account of another connection is refused'
);
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run4'), 'ok', null, '{"amount": 1}')$$,
  'P0001', 'invalid_result',
  'an unknown key of the result is refused'
);
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run4'), 'ok', null,
      '{"accounts": [{"account_id": "00000000-0000-4000-8000-0000000000e2", "status": "ok", "description": "x"}]}')$$,
  'P0001', 'invalid_result',
  'an unknown key of an account is refused'
);
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run4'), 'error', 'Consent expired', '{}')$$,
  'P0001', 'invalid_result',
  'a text of the bank as error code is refused'
);
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run4'), 'ok', null,
      '{"accounts": [{"account_id": "00000000-0000-4000-8000-0000000000e2", "status": "ok", "rows_received": -1}]}')$$,
  'P0001', 'invalid_result',
  'a negative count is refused'
);
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run4'), 'ok', null, '{"matched_transfers": 1.5}')$$,
  'P0001', 'invalid_result',
  'a count that is not a whole number is refused'
);
select throws_ok(
  $$select public.finish_sync_run((select id from ids where name = 'run4'), 'skipped', null, '{}')$$,
  'P0001', 'invalid_result',
  'a sync closes as ok, partial or error'
);
select results_eq(
  $$select status from public.sync_runs where id = (select id from ids where name = 'run4')$$,
  $$values ('running'::text)$$,
  'a refused closing leaves the sync running'
);

reset role;
select throws_ok(
  $$insert into public.sync_runs (connection_id, trigger, status, error_code)
    values ('00000000-0000-4000-8000-0000000000e4', 'admin', 'error', 'Consent expired')$$,
  '23514', null,
  'the error code of a sync is one of the codes'
);
select throws_ok(
  $$insert into public.sync_runs (connection_id, account_id, trigger, status)
    values ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000e2', 'admin', 'ok')$$,
  '23514', null,
  'the row of an account belongs to the row of its connection'
);

-- Secret of the jobs
select results_eq(
  $$select count(*)::int, bool_and(decrypted_secret ~ '^[0-9a-f]{64}$')
    from vault.decrypted_secrets where name = 'sync_cron_secret'$$,
  $$values (1, true)$$,
  'the migrations create one secret of the jobs, 32 bytes in hex'
);
create temp table cron_secret as
  select id, extensions.digest(decrypted_secret, 'sha256') as digest
  from vault.decrypted_secrets where name = 'sync_cron_secret';

set local role service_role;
select public.ensure_sync_cron_secret();
reset role;
select results_eq(
  $$select count(*)::int, bool_and(s.id = c.id and extensions.digest(s.decrypted_secret, 'sha256') = c.digest)
    from vault.decrypted_secrets s, cron_secret c
    where s.name = 'sync_cron_secret'$$,
  $$values (1, true)$$,
  'a second ensure_sync_cron_secret neither adds nor changes the secret'
);

set local role service_role;
select ok(
  public.sync_secret_matches((select decrypted_secret from vault.decrypted_secrets where name = 'sync_cron_secret')),
  'the secret in Vault matches'
);
select ok(not public.sync_secret_matches('valore-diverso'), 'another value does not match');
select ok(not public.sync_secret_matches(''), 'an empty value does not match');
select ok(not public.sync_secret_matches(null), 'a missing value does not match');

-- Permissions
reset role;
select is_empty(
  $$select r, t
    from unnest(array['anon', 'authenticated']) r,
         unnest(array['public.bank_link_requests', 'public.eb_credentials', 'vault.secrets', 'vault.decrypted_secrets']) t
    where has_table_privilege(r, t, 'select, insert, update, delete, truncate')
       or has_any_column_privilege(r, t, 'select, insert, update')$$,
  'the app and anon have no privilege on link requests, credentials and Vault'
);
select is_empty(
  $$select p.oid::regprocedure
    from pg_proc p
    where p.oid in (
        'public.eb_set_credentials(uuid, text, text)'::regprocedure,
        'public.eb_get_credentials(uuid)'::regprocedure,
        'public.delete_eb_credentials_secret()'::regprocedure,
        'public.check_link_request_member()'::regprocedure,
        'public.create_link_request(uuid, text, text, text, boolean)'::regprocedure,
        'public.claim_link_request(uuid)'::regprocedure,
        'public.begin_sync_run(uuid, text)'::regprocedure,
        'public.finish_sync_run(uuid, text, text, jsonb)'::regprocedure,
        'public.ensure_sync_cron_secret()'::regprocedure,
        'public.sync_secret_matches(text)'::regprocedure
      )
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))$$,
  'the app and anon execute none of the sync functions'
);
select set_eq(
  $$select p.proname::text
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in (
        'eb_set_credentials', 'eb_get_credentials', 'create_link_request', 'claim_link_request',
        'begin_sync_run', 'finish_sync_run', 'ensure_sync_cron_secret', 'sync_secret_matches'
      )
      and has_function_privilege('service_role', p.oid, 'execute')$$,
  array[
    'eb_set_credentials', 'eb_get_credentials', 'create_link_request', 'claim_link_request',
    'begin_sync_run', 'finish_sync_run', 'ensure_sync_cron_secret', 'sync_secret_matches'
  ],
  'the service role executes all of them'
);

create temp table own_runs as
  select count(*)::int as n from public.sync_runs
  where connection_id in ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000e4');
grant select on own_runs to authenticated;

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select is(
  (select count(*)::int from public.sync_runs),
  (select n from own_runs),
  'Anna sees the syncs of her connections'
);
select is_empty(
  $$select 1 from public.sync_runs where connection_id = '00000000-0000-4000-8000-0000000000e6'$$,
  'Anna does not see the syncs of a connection of another member'
);
select throws_ok(
  $$insert into public.sync_runs (connection_id, trigger, status)
    values ('00000000-0000-4000-8000-0000000000e4', 'manual', 'running')$$,
  '42501', null,
  'the app does not write the syncs'
);
select throws_ok(
  $$update public.sync_runs set status = 'ok'$$,
  '42501', null,
  'the app does not change the syncs'
);
select throws_ok(
  'select id from public.bank_link_requests',
  '42501', null,
  'the app does not read the link requests'
);
select throws_ok(
  'select decrypted_secret from vault.decrypted_secrets',
  '42501', null,
  'the app does not read Vault'
);
select throws_ok(
  $$select * from public.eb_get_credentials('00000000-0000-4000-8000-00000000000a')$$,
  '42501', null,
  'the app does not read the credentials through the functions'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is_empty('select 1 from public.sync_runs', 'Bruno does not see the syncs of Anna');

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is_empty('select 1 from public.sync_runs', 'Dario does not see the syncs of Anna');

set local role anon;
select throws_ok(
  'select id from public.sync_runs',
  '42501', null,
  'anon cannot read the syncs'
);
select throws_ok(
  $$select public.sync_secret_matches('valore-diverso')$$,
  '42501', null,
  'anon does not check the secret of the jobs'
);

-- Without the secret in Vault nothing matches.
reset role;
create temp table cron_value as
  select decrypted_secret as value from vault.decrypted_secrets where name = 'sync_cron_secret';
delete from vault.secrets where name = 'sync_cron_secret';
select ok(
  not public.sync_secret_matches((select value from cron_value)),
  'without the secret in Vault nothing matches'
);

select * from finish();
rollback;
