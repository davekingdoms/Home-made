-- Scheduled jobs of the bank sync (docs/spec/sincronizzazione.md, 10): the
-- three pg_cron jobs, the scheduled syncs, the expired consents, the
-- cleanup, permissions. Invented users: Anna (a1) in "Casa di prova", with
-- Bruno (b1), who left it; Dario (d1) in another household. Invented URL of
-- the project; the secret of the jobs is never compared or shown.
begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

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

insert into auth.users (id, aud, role, email) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'anna@example.com'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', 'bruno@example.com'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated', 'dario@example.com');
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
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60);
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 60, now() - interval '5 days');

-- The connections, in the order of their ids:
--   e1 Anna, active                                    → synced
--   e2 Anna, expired                                   → not synced
--   e3 Anna, revoked                                   → not synced
--   e4 Anna, pending                                   → not synced
--   e5 Bruno, who left, active                         → not synced
--   e6 Dario, active, a sync started an hour ago       → not synced
--   e7 Dario, active, a sync started 3 hours ago       → synced
--   e8 Anna, active, a skipped row 10 minutes ago      → synced
-- e7 is also past its consent, e3 and e4 too, e8 has no end of the consent.
insert into public.bank_connections (
  id, member_id, aspsp_name, aspsp_country, session_id, uses_global_app, status,
  valid_until, last_sync_at, last_success_at, last_error
) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', '0000000000-0001', false, 'active',
   '2031-06-01 00:00+00', null, null, null),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000a1',
   'Altra Banca di Prova', 'IT', '0000000000-0002', false, 'expired',
   now() - interval '10 days', null, null, 'consent_expired'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000a1',
   'Terza Banca di Prova', 'IT', '0000000000-0003', false, 'revoked',
   now() - interval '1 day', null, null, 'consent_revoked'),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000a1',
   'Quarta Banca di Prova', 'IT', null, false, 'pending',
   now() - interval '1 day', null, null, null),
  ('00000000-0000-4000-8000-0000000000e5', '00000000-0000-4000-8000-0000000000b1',
   'Banca di Prova', 'IT', '0000000000-0005', false, 'active',
   '2031-06-01 00:00+00', null, null, null),
  ('00000000-0000-4000-8000-0000000000e6', '00000000-0000-4000-8000-0000000000d1',
   'Banca di Prova', 'IT', '0000000000-0006', true, 'active',
   '2031-06-01 00:00+00', null, null, null),
  ('00000000-0000-4000-8000-0000000000e7', '00000000-0000-4000-8000-0000000000d1',
   'Altra Banca di Prova', 'IT', '0000000000-0007', false, 'active',
   now() - interval '1 day', now() - interval '3 hours', now() - interval '2 days', 'rate_limited'),
  ('00000000-0000-4000-8000-0000000000e8', '00000000-0000-4000-8000-0000000000a1',
   'Quinta Banca di Prova', 'IT', '0000000000-0008', false, 'active',
   null, null, null, null);
insert into public.sync_runs (connection_id, trigger, status, error_code, started_at, finished_at) values
  ('00000000-0000-4000-8000-0000000000e6', 'link', 'ok', null,
   now() - interval '1 hour', now() - interval '55 minutes'),
  ('00000000-0000-4000-8000-0000000000e7', 'manual', 'error', 'bank_error',
   now() - interval '3 hours', now() - interval '175 minutes'),
  ('00000000-0000-4000-8000-0000000000e8', 'manual', 'skipped', 'already_running',
   now() - interval '10 minutes', now() - interval '10 minutes');

-- Jobs
select results_eq(
  $$select j.jobname, j.schedule, j.command
    from cron.job j
    where j.jobname like 'bank-%'
    order by j.jobname$$,
  $$values
    ('bank-cleanup'::text, '30 3 * * 0'::text, 'select public.cleanup_bank_sync()'::text),
    ('bank-consents', '0 6 * * *', 'select public.expire_bank_consents()'),
    ('bank-sync', '10 6,12,19 * * *', 'select public.schedule_bank_syncs()')$$,
  'three jobs, each a select of its function at its time in UTC'
);
select is(
  (select count(*)::int
   from cron.job j
   where j.jobname like 'bank-%'
     and j.active
     and j.username = 'postgres'
     and j.database = current_database()),
  3,
  'the jobs are active and run as postgres in this database'
);

create temp table jobs_before as
  select j.jobid, j.jobname, j.schedule, j.command from cron.job j;
select lives_ok(
  $$select cron.schedule('bank-consents', '0 6 * * *', 'select public.expire_bank_consents()');
    select cron.schedule('bank-sync', '10 6,12,19 * * *', 'select public.schedule_bank_syncs()');
    select cron.schedule('bank-cleanup', '30 3 * * 0', 'select public.cleanup_bank_sync()')$$,
  'the jobs are scheduled again'
);
select results_eq(
  'select j.jobid, j.jobname, j.schedule, j.command from cron.job j order by j.jobid',
  'select b.jobid, b.jobname, b.schedule, b.command from jobs_before b order by b.jobid',
  'scheduled again by name, the jobs are the same: none is added'
);

select is_empty(
  $$select p.oid::regprocedure
    from pg_proc p
    where p.oid in (
        'public.schedule_bank_syncs()'::regprocedure,
        'public.expire_bank_consents()'::regprocedure,
        'public.cleanup_bank_sync()'::regprocedure
      )
      and not (p.prosecdef and p.proconfig = array['search_path=""'])$$,
  'the three functions are security definer with an empty search path'
);

-- Scheduled syncs.
-- The attempts of request_bank_sync are counted by a sequence: unlike a
-- table, a sequence keeps its count when the block of a failed request is
-- rolled back. For this file only, the function gets two statements at the
-- start of its own body: the count, and a failure, with a message that is
-- not a key, for the connection named in test.fail_connection.
create temp sequence attempts;
create function pg_temp.attempt_count()
returns bigint
language sql
as $$
  select case when s.is_called then s.last_value else 0 end from pg_temp.attempts s
$$;
do $$
declare
  v_body text;
begin
  select p.prosrc into strict v_body
  from pg_proc p
  where p.oid = 'public.request_bank_sync(uuid, text)'::regprocedure;
  if v_body !~ '\mbegin\M' then
    raise exception 'request_bank_sync without a begin: update this test';
  end if;
  execute format(
    $f$create or replace function public.request_bank_sync(connection_id uuid, trigger text)
      returns void language plpgsql security definer set search_path = '' as %L$f$,
    regexp_replace(
      v_body,
      '\mbegin\M',
      'begin
  perform nextval(''pg_temp.attempts'');
  if request_bank_sync.connection_id::text = current_setting(''test.fail_connection'', true) then
    raise exception ''Errore di prova con un valore: %'', request_bank_sync.connection_id;
  end if;'
    )
  );
end;
$$;

create temp table queue_start as
  select coalesce(max(q.id), 0) as id from net.http_request_queue q;
create temp view queued as
  select (convert_from(q.body, 'utf8')::jsonb ->> 'connection_id')::uuid as connection_id,
         q.method::text as method,
         q.url,
         convert_from(q.body, 'utf8')::jsonb as body,
         q.headers
  from net.http_request_queue q
  where q.id > (select s.id from queue_start s);

-- As in CI: no URL of the project in Vault. The warnings carry only codes.
delete from vault.secrets where name in ('project_url', 'sync_cron_secret');
set local client_min_messages to error;
select is(
  public.schedule_bank_syncs(),
  0,
  'without the URL of the project no request is queued, and no error'
);
select is(
  pg_temp.attempt_count(),
  3::bigint,
  'every chosen connection is tried, also after the failure of the first'
);
select is_empty('select 1 from queued', 'nothing is in the queue of pg_net');

select vault.create_secret('https://progetto-di-prova.example.com', 'project_url');
select public.ensure_sync_cron_secret();
select setval('attempts', 1, false);

set local role service_role;
select is(
  public.schedule_bank_syncs(),
  3,
  'one request for each chosen connection'
);
reset role;
select results_eq(
  $$select q.connection_id, q.method, q.url, q.body ->> 'trigger', q.body - 'connection_id' - 'trigger'
    from queued q
    order by q.connection_id$$,
  $$values
    ('00000000-0000-4000-8000-0000000000e1'::uuid, 'POST'::text,
     'https://progetto-di-prova.example.com/functions/v1/eb-sync'::text, 'schedule'::text, '{}'::jsonb),
    ('00000000-0000-4000-8000-0000000000e7', 'POST',
     'https://progetto-di-prova.example.com/functions/v1/eb-sync', 'schedule', '{}'),
    ('00000000-0000-4000-8000-0000000000e8', 'POST',
     'https://progetto-di-prova.example.com/functions/v1/eb-sync', 'schedule', '{}')$$,
  'a POST to eb-sync with the connection and the trigger schedule, in the order of the ids'
);
select is_empty(
  $$select 1 from queued q where coalesce(q.headers ->> 'x-sync-secret', '') = ''$$,
  'every request carries the header of the secret of the jobs'
);
select is_empty(
  $$select 1 from queued q
    where q.connection_id in (
      '00000000-0000-4000-8000-0000000000e2',
      '00000000-0000-4000-8000-0000000000e3',
      '00000000-0000-4000-8000-0000000000e4'
    )$$,
  'expired, revoked and pending connections are not synced'
);
select is_empty(
  $$select 1 from queued q where q.connection_id = '00000000-0000-4000-8000-0000000000e5'$$,
  'the connection of a member who left is not synced'
);
select is_empty(
  $$select 1 from queued q where q.connection_id = '00000000-0000-4000-8000-0000000000e6'$$,
  'a sync started an hour ago skips the scheduled one'
);
select set_eq(
  $$select q.connection_id from queued q
    where q.connection_id in (
      '00000000-0000-4000-8000-0000000000e7',
      '00000000-0000-4000-8000-0000000000e8'
    )$$,
  $$values ('00000000-0000-4000-8000-0000000000e7'::uuid), ('00000000-0000-4000-8000-0000000000e8')$$,
  'a sync started 3 hours ago and a recent skipped row do not skip it'
);

-- The failure of one connection does not stop the others.
truncate queue_start;
insert into queue_start select coalesce(max(q.id), 0) from net.http_request_queue q;
select set_config('test.fail_connection', '00000000-0000-4000-8000-0000000000e1', true);
select is(
  public.schedule_bank_syncs(),
  2,
  'a failed request is skipped, without an error'
);
select results_eq(
  'select q.connection_id from queued q order by q.connection_id',
  $$values ('00000000-0000-4000-8000-0000000000e7'::uuid), ('00000000-0000-4000-8000-0000000000e8')$$,
  'the connections after the failed one are requested'
);
select set_config('test.fail_connection', '', true);
reset client_min_messages;

-- Expired consents
create temp table e7_before as
  select c.member_id, c.aspsp_name, c.aspsp_country, c.session_id, c.uses_global_app,
         c.valid_until, c.last_sync_at, c.last_success_at, c.created_at
  from public.bank_connections c
  where c.id = '00000000-0000-4000-8000-0000000000e7';

select is(public.expire_bank_consents(), 1, 'one consent has expired');
select results_eq(
  'select c.id, c.status, c.last_error from public.bank_connections c order by c.id',
  $$values
    ('00000000-0000-4000-8000-0000000000e1'::uuid, 'active'::text, null::text),
    ('00000000-0000-4000-8000-0000000000e2', 'expired', 'consent_expired'),
    ('00000000-0000-4000-8000-0000000000e3', 'revoked', 'consent_revoked'),
    ('00000000-0000-4000-8000-0000000000e4', 'pending', null),
    ('00000000-0000-4000-8000-0000000000e5', 'active', null),
    ('00000000-0000-4000-8000-0000000000e6', 'active', null),
    ('00000000-0000-4000-8000-0000000000e7', 'expired', 'consent_expired'),
    ('00000000-0000-4000-8000-0000000000e8', 'active', null)$$,
  'only the active connection past its consent expires; without an end it stays active'
);
select results_eq(
  $$select c.member_id, c.aspsp_name, c.aspsp_country, c.session_id, c.uses_global_app,
           c.valid_until, c.last_sync_at, c.last_success_at, c.created_at
    from public.bank_connections c
    where c.id = '00000000-0000-4000-8000-0000000000e7'$$,
  'select * from e7_before',
  'no other column of the expired connection changes'
);
set local role service_role;
select is(public.expire_bank_consents(), 0, 'run again, nothing expires');
reset role;
select is(
  (select count(*)::int from public.bank_connections c where c.status = 'expired'),
  2,
  'run again, the connections stay as they were'
);

-- Cleanup.
-- Anna's first connection has a bank account (x1) and a card (x2). Syncs:
--   101  200 days ago  ok       x1 ok, x2 ok     kept: last ok of x2
--   102  190 days ago  partial  x1 ok, x2 error  deleted with its rows
--   103   10 days ago  partial  x1 ok, x2 error  kept: recent
--   104  185 days ago  skipped                   deleted
--   105  181 days ago  error    (Dario)          deleted
--   106  179 days ago  error    (Dario)          kept: not old enough
insert into public.accounts (
  id, household_id, owner_member_id, kind, connection_id, provider_account_id, cash_account_type, currency, display_name
) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1',
   '0000000000-conto-1', 'CACC', 'EUR', 'Banca di Prova …0000'),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1',
   '0000000000-carta-1', 'CARD', 'EUR', 'Carta …0000');
insert into public.sync_runs (id, connection_id, trigger, status, error_code, started_at, finished_at) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000e1',
   'schedule', 'ok', null, now() - interval '200 days', now() - interval '200 days'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000e1',
   'schedule', 'partial', 'bank_error', now() - interval '190 days', now() - interval '190 days'),
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000e1',
   'schedule', 'partial', 'bank_error', now() - interval '10 days', now() - interval '10 days'),
  ('00000000-0000-4000-8000-000000000104', '00000000-0000-4000-8000-0000000000e1',
   'schedule', 'skipped', 'already_running', now() - interval '185 days', now() - interval '185 days'),
  ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-0000000000e6',
   'schedule', 'error', 'bank_unavailable', now() - interval '181 days', now() - interval '181 days'),
  ('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-0000000000e6',
   'schedule', 'error', 'bank_unavailable', now() - interval '179 days', now() - interval '179 days');
insert into public.sync_runs (
  id, connection_id, account_id, run_id, trigger, status, error_code, started_at, finished_at
) values
  ('00000000-0000-4000-8000-000000000111', '00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-000000000101',
   'schedule', 'ok', null, now() - interval '200 days', now() - interval '200 days'),
  ('00000000-0000-4000-8000-000000000112', '00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-000000000101',
   'schedule', 'ok', null, now() - interval '200 days', now() - interval '200 days'),
  ('00000000-0000-4000-8000-000000000121', '00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-000000000102',
   'schedule', 'ok', null, now() - interval '190 days', now() - interval '190 days'),
  ('00000000-0000-4000-8000-000000000122', '00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-000000000102',
   'schedule', 'error', 'bank_error', now() - interval '190 days', now() - interval '190 days'),
  ('00000000-0000-4000-8000-000000000131', '00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-000000000103',
   'schedule', 'ok', null, now() - interval '10 days', now() - interval '10 days'),
  ('00000000-0000-4000-8000-000000000132', '00000000-0000-4000-8000-0000000000e1',
   '00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-000000000103',
   'schedule', 'error', 'bank_error', now() - interval '10 days', now() - interval '10 days');

-- Link requests of 8 and 6 days ago.
insert into public.bank_link_requests (
  id, member_id, aspsp_name, aspsp_country, psu_type, uses_global_app, expires_at, used_at, result, created_at
) values
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', false,
   now() - interval '8 days' + interval '30 minutes', now() - interval '8 days', 'ok',
   now() - interval '8 days'),
  ('00000000-0000-4000-8000-000000000202', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', false,
   now() - interval '6 days' + interval '30 minutes', null, null,
   now() - interval '6 days');

-- Runs of the jobs: ended 31 days ago, failed to start 40 days ago (only
-- an end), ended 29 days ago. Negative ids, never used by pg_cron: a real
-- run during the test does not get in the way.
delete from cron.job_run_details;
insert into cron.job_run_details (runid, jobid, database, username, command, status, start_time, end_time) values
  (-1, (select j.jobid from cron.job j where j.jobname = 'bank-sync'), current_database(), current_user,
   'select public.schedule_bank_syncs()', 'succeeded',
   now() - interval '31 days' - interval '1 minute', now() - interval '31 days'),
  (-2, (select j.jobid from cron.job j where j.jobname = 'bank-sync'), current_database(), current_user,
   'select public.schedule_bank_syncs()', 'failed',
   null, now() - interval '40 days'),
  (-3, (select j.jobid from cron.job j where j.jobname = 'bank-consents'), current_database(), current_user,
   'select public.expire_bank_consents()', 'succeeded',
   now() - interval '29 days' - interval '1 minute', now() - interval '29 days');

set local role service_role;
select is(
  public.cleanup_bank_sync(),
  '{"link_requests": 1, "connection_runs": 3, "account_runs": 2, "job_runs": 2}'::jsonb,
  'the counts of what is deleted'
);
reset role;
select results_eq(
  'select r.id from public.bank_link_requests r order by r.id',
  $$values ('00000000-0000-4000-8000-000000000202'::uuid)$$,
  'the link request older than 7 days is deleted, the newer one stays'
);
select set_eq(
  $$select sr.id from public.sync_runs sr
    where sr.id::text like '00000000-0000-4000-8000-0000000001%'$$,
  $$values
    ('00000000-0000-4000-8000-000000000101'::uuid), ('00000000-0000-4000-8000-000000000111'),
    ('00000000-0000-4000-8000-000000000112'), ('00000000-0000-4000-8000-000000000103'),
    ('00000000-0000-4000-8000-000000000131'), ('00000000-0000-4000-8000-000000000132'),
    ('00000000-0000-4000-8000-000000000106')$$,
  'the old syncs are deleted with the rows of their accounts; the recent ones stay'
);
select results_eq(
  $$select sr.account_id, sr.status from public.sync_runs sr
    where sr.run_id = '00000000-0000-4000-8000-000000000101'
    order by sr.account_id$$,
  $$values
    ('00000000-0000-4000-8000-0000000000c1'::uuid, 'ok'::text),
    ('00000000-0000-4000-8000-0000000000c2', 'ok')$$,
  'the old sync with the last ok row of an account stays, with all its rows'
);
select results_eq(
  'select d.runid from cron.job_run_details d where d.runid < 0',
  $$values (-3::bigint)$$,
  'the runs of the jobs older than 30 days are deleted, the newer one stays'
);
select is(
  public.cleanup_bank_sync(),
  '{"link_requests": 0, "connection_runs": 0, "account_runs": 0, "job_runs": 0}'::jsonb,
  'run again, nothing more is deleted'
);

-- Permissions
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  'select public.schedule_bank_syncs()',
  '42501', null,
  'the app does not schedule syncs'
);
select throws_ok(
  'select public.expire_bank_consents()',
  '42501', null,
  'the app does not expire consents'
);
select throws_ok(
  'select public.cleanup_bank_sync()',
  '42501', null,
  'the app does not clean up'
);

set local role anon;
select throws_ok(
  'select public.schedule_bank_syncs()',
  '42501', null,
  'anon does not schedule syncs'
);
select throws_ok(
  'select public.expire_bank_consents()',
  '42501', null,
  'anon does not expire consents'
);
select throws_ok(
  'select public.cleanup_bank_sync()',
  '42501', null,
  'anon does not clean up'
);

reset role;
select ok(
  has_function_privilege('service_role', 'public.schedule_bank_syncs()', 'execute')
    and has_function_privilege('service_role', 'public.expire_bank_consents()', 'execute')
    and has_function_privilege('service_role', 'public.cleanup_bank_sync()', 'execute'),
  'the service role executes the three functions'
);

select * from finish();
rollback;
