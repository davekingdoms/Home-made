-- Service functions of the bank sync (docs/spec/sincronizzazione.md, 2, 3,
-- 4 and 9): credentials in Vault, link requests, opening and closing of the
-- syncs, the secret of the jobs.
--
-- All of them run only for the service role (Edge Functions and the service
-- script): the app and anon execute none. Their errors are only keys,
-- without any value received: a private key, a state or a text of the bank
-- never ends up in an error or in a log.

-- Credentials

-- Creates or replaces the Enable Banking application of a person: the
-- private key in the Vault secret eb_private_key:<user_id>, the application
-- id in eb_credentials. The key is not checked here: eb-credentials proves
-- it first by signing a JWT.
create function public.eb_set_credentials(user_id uuid, app_id text, private_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := 'eb_private_key:' || eb_set_credentials.user_id::text;
  v_secret_id uuid;
  v_has_row boolean;
begin
  if eb_set_credentials.app_id is null
    or btrim(eb_set_credentials.app_id) = ''
    or eb_set_credentials.private_key is null
    or btrim(eb_set_credentials.private_key) = ''
    or octet_length(eb_set_credentials.private_key) > 16384
  then
    raise exception 'invalid_credentials';
  end if;

  -- One call at a time for each person: two first calls would both create
  -- the secret.
  perform pg_advisory_xact_lock(hashtextextended(v_name, 0));

  select c.private_key_secret_id into v_secret_id
  from public.eb_credentials c
  where c.user_id = eb_set_credentials.user_id
  for update;
  v_has_row := found;

  -- vault.update_secret changes nothing for an unknown id: a row whose
  -- secret is gone gets a secret again.
  if v_has_row and not exists (select 1 from vault.secrets s where s.id = v_secret_id) then
    v_secret_id := null;
  end if;

  -- Without a secret of the row, a secret with the name left without its
  -- row is reused: the names are unique in Vault.
  if v_secret_id is null then
    select s.id into v_secret_id from vault.secrets s where s.name = v_name;
  end if;

  if v_secret_id is null then
    v_secret_id := vault.create_secret(
      eb_set_credentials.private_key, v_name, 'Enable Banking private key'
    );
  else
    perform vault.update_secret(v_secret_id, eb_set_credentials.private_key);
  end if;

  if v_has_row then
    update public.eb_credentials c
    set app_id = eb_set_credentials.app_id,
        private_key_secret_id = v_secret_id
    where c.user_id = eb_set_credentials.user_id;
  else
    insert into public.eb_credentials (user_id, app_id, private_key_secret_id)
    values (eb_set_credentials.user_id, eb_set_credentials.app_id, v_secret_id);
  end if;
end;
$$;

comment on function public.eb_set_credentials(uuid, text, text) is
  'Creates or replaces the Enable Banking application of a person (key in Vault). Errors: invalid_credentials.';

-- Application id and private key of a person; no row without credentials.
create function public.eb_get_credentials(user_id uuid)
returns table (app_id text, private_key text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.app_id, s.decrypted_secret
  from public.eb_credentials c
  join vault.decrypted_secrets s on s.id = c.private_key_secret_id
  where c.user_id = eb_get_credentials.user_id
$$;

comment on function public.eb_get_credentials(uuid) is
  'Application id and private key of a person, from Vault; no row without credentials.';

-- A deleted row of eb_credentials (also with the account of the person)
-- takes its secret with it: the private key is not left without an owner.
create function public.delete_eb_credentials_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets s where s.id = old.private_key_secret_id;
  return null;
end;
$$;

create trigger eb_credentials_delete_secret
  after delete on public.eb_credentials
  for each row execute function public.delete_eb_credentials_secret();

-- Link requests

-- New link request of an active member (bank_link_requests_check_member);
-- the id is the state, valid for 30 minutes.
create function public.create_link_request(
  member_id uuid,
  aspsp_name text,
  aspsp_country text,
  psu_type text,
  uses_global_app boolean
)
returns uuid
language sql
security definer
set search_path = ''
as $$
  insert into public.bank_link_requests (
    member_id, aspsp_name, aspsp_country, psu_type, uses_global_app
  )
  values (
    create_link_request.member_id,
    create_link_request.aspsp_name,
    create_link_request.aspsp_country,
    create_link_request.psu_type,
    create_link_request.uses_global_app
  )
  returning id
$$;

comment on function public.create_link_request(uuid, text, text, text, boolean) is
  'New link request; returns its id, the state. Errors: member_not_eligible.';

-- Marks the request as used in a single statement: of two callbacks with
-- the same state only one gets the row. Nothing for an unknown, expired or
-- used request.
create function public.claim_link_request(id uuid)
returns setof public.bank_link_requests
language sql
security definer
set search_path = ''
as $$
  update public.bank_link_requests r
  set used_at = now()
  where r.id = claim_link_request.id
    and r.used_at is null
    and r.expires_at > now()
  returning r.*
$$;

comment on function public.claim_link_request(uuid) is
  'Takes a link request once, if not expired: the row, or nothing.';

-- Syncs

-- Opens the row of a sync. With a sync of the connection running for less
-- than 15 minutes, a skipped row (already_running) instead; one running for
-- 15 minutes or more is closed as an error (internal) first.
create function public.begin_sync_run(connection_id uuid, trigger text)
returns table (run_id uuid, status text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The lock of the connection lets one call at a time decide.
  perform 1
  from public.bank_connections c
  where c.id = begin_sync_run.connection_id
  for update;
  if not found then
    raise exception 'connection_not_found';
  end if;

  if exists (
    select 1
    from public.sync_runs sr
    where sr.connection_id = begin_sync_run.connection_id
      and sr.account_id is null
      and sr.status = 'running'
      and sr.started_at > now() - interval '15 minutes'
  ) then
    insert into public.sync_runs (connection_id, trigger, status, error_code, finished_at)
    values (begin_sync_run.connection_id, begin_sync_run.trigger, 'skipped', 'already_running', now())
    returning id into begin_sync_run.run_id;
    begin_sync_run.status := 'skipped';
    return next;
    return;
  end if;

  update public.sync_runs sr
  set status = 'error', error_code = 'internal', finished_at = now()
  where sr.connection_id = begin_sync_run.connection_id
    and sr.account_id is null
    and sr.status = 'running';

  insert into public.sync_runs (connection_id, trigger, status)
  values (begin_sync_run.connection_id, begin_sync_run.trigger, 'running')
  returning id into begin_sync_run.run_id;
  begin_sync_run.status := 'running';
  return next;
end;
$$;

comment on function public.begin_sync_run(uuid, text) is
  'Opens a sync of a connection: running, or skipped if one is already running. Errors: connection_not_found.';

-- Closes a running sync. result:
--   {strategy, matched_transfers, matched_settlements, matched_installments,
--    accounts: [{account_id, status, error_code, strategy, date_from,
--                history_from, history_incomplete, <counts of the account>}]}
-- One row for each account, the sums on the row of the connection, the
-- outcome on the connection.
create function public.finish_sync_run(run_id uuid, status text, error_code text, result jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_counts constant text[] := array[
    'rows_received', 'raw_inserted', 'transactions_created', 'skipped_before_start',
    'skipped_status', 'groups_shrunk', 'booked_then_cancelled', 'purchase_already_classified'
  ];
  v_run public.sync_runs%rowtype;
  v_result jsonb := coalesce(finish_sync_run.result, '{}');
  v_accounts jsonb;
  v_account record;
  v_last_error text;
begin
  -- The connection first, then the run: the same order as begin_sync_run.
  perform 1
  from public.bank_connections c
  where c.id = (
    select sr.connection_id from public.sync_runs sr where sr.id = finish_sync_run.run_id
  )
  for update;

  select sr.* into v_run
  from public.sync_runs sr
  where sr.id = finish_sync_run.run_id
    and sr.account_id is null
    and sr.status = 'running'
  for update;
  if not found then
    raise exception 'run_not_running';
  end if;

  if finish_sync_run.status is null or finish_sync_run.status not in ('ok', 'partial', 'error') then
    raise exception 'invalid_result';
  end if;

  -- Wrong shapes, types and codes end in invalid_result, without the
  -- details of the error, which would show the values received.
  begin
    if exists (
      select 1
      from jsonb_object_keys(v_result) as k (key)
      where k.key not in (
        'strategy', 'matched_transfers', 'matched_settlements', 'matched_installments', 'accounts'
      )
    ) then
      raise exception 'invalid_result';
    end if;

    v_accounts := coalesce(v_result -> 'accounts', '[]');

    if exists (
      select 1
      from jsonb_array_elements(v_accounts) as e (account),
        jsonb_object_keys(e.account) as k (key)
      where k.key not in (
        'account_id', 'status', 'error_code', 'strategy', 'date_from', 'history_from',
        'history_incomplete'
      )
        and k.key <> all (v_counts)
    ) then
      raise exception 'invalid_result';
    end if;

    for v_account in
      select *
      from jsonb_to_recordset(v_accounts) as a (
        account_id uuid,
        status text,
        error_code text,
        strategy text,
        date_from date,
        history_from date,
        history_incomplete boolean,
        rows_received int,
        raw_inserted int,
        transactions_created int,
        skipped_before_start int,
        skipped_status int,
        groups_shrunk int,
        booked_then_cancelled int,
        purchase_already_classified int
      )
    loop
      if v_account.account_id is null
        or v_account.status is null
        or v_account.status not in ('ok', 'partial', 'error', 'skipped')
      then
        raise exception 'invalid_result';
      end if;

      if not exists (
        select 1
        from public.accounts a
        where a.id = v_account.account_id
          and a.connection_id = v_run.connection_id
      ) then
        raise exception 'account_not_in_connection';
      end if;

      insert into public.sync_runs (
        connection_id, account_id, run_id, trigger, status, error_code, strategy,
        date_from, history_from, history_incomplete,
        rows_received, raw_inserted, transactions_created, skipped_before_start,
        skipped_status, groups_shrunk, booked_then_cancelled, purchase_already_classified,
        started_at, finished_at
      )
      values (
        v_run.connection_id, v_account.account_id, v_run.id, v_run.trigger,
        v_account.status, v_account.error_code, v_account.strategy,
        v_account.date_from, v_account.history_from, coalesce(v_account.history_incomplete, false),
        coalesce(v_account.rows_received, 0),
        coalesce(v_account.raw_inserted, 0),
        coalesce(v_account.transactions_created, 0),
        coalesce(v_account.skipped_before_start, 0),
        coalesce(v_account.skipped_status, 0),
        coalesce(v_account.groups_shrunk, 0),
        coalesce(v_account.booked_then_cancelled, 0),
        coalesce(v_account.purchase_already_classified, 0),
        v_run.started_at, now()
      );
    end loop;

    update public.sync_runs sr
    set status = finish_sync_run.status,
        error_code = finish_sync_run.error_code,
        strategy = v_result ->> 'strategy',
        matched_transfers = coalesce((v_result ->> 'matched_transfers')::int, 0),
        matched_settlements = coalesce((v_result ->> 'matched_settlements')::int, 0),
        matched_installments = coalesce((v_result ->> 'matched_installments')::int, 0),
        finished_at = now(),
        (
          history_incomplete, rows_received, raw_inserted, transactions_created,
          skipped_before_start, skipped_status, groups_shrunk, booked_then_cancelled,
          purchase_already_classified
        ) = (
          select
            coalesce(bool_or(a.history_incomplete), false),
            coalesce(sum(a.rows_received), 0),
            coalesce(sum(a.raw_inserted), 0),
            coalesce(sum(a.transactions_created), 0),
            coalesce(sum(a.skipped_before_start), 0),
            coalesce(sum(a.skipped_status), 0),
            coalesce(sum(a.groups_shrunk), 0),
            coalesce(sum(a.booked_then_cancelled), 0),
            coalesce(sum(a.purchase_already_classified), 0)
          from public.sync_runs a
          where a.run_id = v_run.id
        )
    where sr.id = v_run.id;
  exception
    when data_exception or check_violation or not_null_violation or unique_violation then
      raise exception 'invalid_result';
  end;

  v_last_error := case when finish_sync_run.status = 'ok' then null else finish_sync_run.error_code end;

  update public.bank_connections c
  set last_sync_at = now(),
      last_success_at = case when finish_sync_run.status = 'ok' then now() else c.last_success_at end,
      last_error = v_last_error,
      status = case v_last_error
        when 'consent_expired' then 'expired'
        when 'consent_revoked' then 'revoked'
        else c.status
      end
  where c.id = v_run.connection_id;
end;
$$;

comment on function public.finish_sync_run(uuid, text, text, jsonb) is
  'Closes a running sync with its outcome and the counts of the accounts. Errors: run_not_running, invalid_result, account_not_in_connection.';

-- Secret of the jobs

-- Creates the Vault secret sync_cron_secret, 32 random bytes in hex, if it
-- is not there. Nobody sees it or copies it: the jobs read it from Vault and
-- eb-sync checks it with sync_secret_matches.
create function public.ensure_sync_cron_secret()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from vault.secrets s where s.name = 'sync_cron_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'sync_cron_secret',
      'Secret of the sync jobs, checked by eb-sync'
    );
  end if;
end;
$$;

comment on function public.ensure_sync_cron_secret() is
  'Creates the Vault secret sync_cron_secret if it is missing; never returns it.';

-- True if the secret received is the one in Vault. The SHA-256 digests are
-- compared, not the strings. False without a secret on either side.
create function public.sync_secret_matches(secret text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sync_secret_matches.secret, '') <> ''
    and coalesce((
      select extensions.digest(s.decrypted_secret, 'sha256')
        = extensions.digest(sync_secret_matches.secret, 'sha256')
      from vault.decrypted_secrets s
      where s.name = 'sync_cron_secret'
    ), false)
$$;

comment on function public.sync_secret_matches(text) is
  'True if the secret matches sync_cron_secret in Vault; never returns the secret.';

-- Only the service role.

revoke all on function public.eb_set_credentials(uuid, text, text) from public, anon, authenticated;
revoke all on function public.eb_get_credentials(uuid) from public, anon, authenticated;
revoke all on function public.delete_eb_credentials_secret() from public, anon, authenticated;
revoke all on function public.create_link_request(uuid, text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.claim_link_request(uuid) from public, anon, authenticated;
revoke all on function public.begin_sync_run(uuid, text) from public, anon, authenticated;
revoke all on function public.finish_sync_run(uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.ensure_sync_cron_secret() from public, anon, authenticated;
revoke all on function public.sync_secret_matches(text) from public, anon, authenticated;

grant execute on function public.eb_set_credentials(uuid, text, text) to service_role;
grant execute on function public.eb_get_credentials(uuid) to service_role;
grant execute on function public.create_link_request(uuid, text, text, text, boolean) to service_role;
grant execute on function public.claim_link_request(uuid) to service_role;
grant execute on function public.begin_sync_run(uuid, text) to service_role;
grant execute on function public.finish_sync_run(uuid, text, text, jsonb) to service_role;
grant execute on function public.ensure_sync_cron_secret() to service_role;
grant execute on function public.sync_secret_matches(text) to service_role;

-- The secret is born in every environment with the migrations.
select public.ensure_sync_cron_secret();
