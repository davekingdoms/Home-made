-- Import of the bank rows and requests of the syncs
-- (docs/spec/sincronizzazione.md, 4, 5, 6 and 9): the atomic import of the
-- rows of an account with their movements, the HTTP request that starts
-- eb-sync, two new counts of the syncs.
--
-- All of them run only for the service role (eb-sync, eb-callback and the
-- jobs): the app and anon execute none. Their errors are only keys, without
-- any value received: a row of the bank never ends up in an error or in a
-- log.

-- Counts of the syncs

-- Rows whose amount had more than two decimals (6.3) and rows refused by the
-- normalization (invalid_row), left out of the raw rows.
alter table public.sync_runs
  add column amounts_rounded int not null default 0,
  add column rows_invalid int not null default 0;

alter table public.sync_runs drop constraint sync_runs_counts_not_negative;

alter table public.sync_runs add constraint sync_runs_counts_not_negative check (
  least(
    rows_received, raw_inserted, transactions_created, skipped_before_start,
    skipped_status, groups_shrunk, booked_then_cancelled,
    purchase_already_classified, matched_transfers, matched_settlements,
    matched_installments, amounts_rounded, rows_invalid
  ) >= 0
);

-- The first sync of an account looks for any of its raw rows.
create index bank_raw_transactions_account_id on public.bank_raw_transactions (account_id);

-- Closes a running sync. result:
--   {strategy, matched_transfers, matched_settlements, matched_installments,
--    accounts: [{account_id, status, error_code, strategy, date_from,
--                history_from, history_incomplete, <counts of the account>}]}
-- One row for each account, the sums on the row of the connection, the
-- outcome on the connection. Same as before, with amounts_rounded and
-- rows_invalid among the counts of the accounts.
create or replace function public.finish_sync_run(run_id uuid, status text, error_code text, result jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_counts constant text[] := array[
    'rows_received', 'raw_inserted', 'transactions_created', 'skipped_before_start',
    'skipped_status', 'groups_shrunk', 'booked_then_cancelled', 'purchase_already_classified',
    'amounts_rounded', 'rows_invalid'
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
        purchase_already_classified int,
        amounts_rounded int,
        rows_invalid int
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
        amounts_rounded, rows_invalid,
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
        coalesce(v_account.amounts_rounded, 0),
        coalesce(v_account.rows_invalid, 0),
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
          purchase_already_classified, amounts_rounded, rows_invalid
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
            coalesce(sum(a.purchase_already_classified), 0),
            coalesce(sum(a.amounts_rounded), 0),
            coalesce(sum(a.rows_invalid), 0)
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

-- Import of the rows of an account

-- Imports the rows of an account already normalized by eb-sync (sections 5
-- and 6), all or nothing, one import at a time for each account. rows:
--   [{entry_reference, status, booking_date, value_date, transaction_date,
--     amount_cents (signed), currency, dedup_hash, payload,
--     original_amount_cents, original_currency, exchange_rate, description,
--     counterparty, counterparty_email, bank_code}]
-- 1. With entry_reference: a known reference is ignored, except a saved
--    PDNG row that arrives BOOK, which is updated (status, dates, amount,
--    hash, payload). A row already a movement that arrives CNCL stays as it
--    is and is counted in booked_then_cancelled.
-- 2. Without: the rows are grouped by dedup_hash; with n rows received and
--    m saved, the ordinals m + 1 ... n are inserted; n < m is counted in
--    groups_shrunk. An identical row is never dropped.
-- 3. The new rows (and the PDNG rows now BOOK) become movements only when
--    BOOK, from the start date of the owner of the account and with an
--    amount other than zero (section 6.1); the others are counted as
--    skipped for date or status. The trigger of the transactions creates
--    their line, to classify.
-- Returns the counts of the row of the account in sync_runs. Wrong shapes
-- and types are invalid_rows, without the value that failed.
create function public.ingest_bank_rows(account_id uuid, rows jsonb)
returns table (
  rows_received int,
  raw_inserted int,
  transactions_created int,
  skipped_before_start int,
  skipped_status int,
  groups_shrunk int,
  booked_then_cancelled int
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account public.accounts%rowtype;
  v_start_date date;
  v_row jsonb;
  v_id uuid;
  v_existing record;
  v_group record;
  v_saved int;
  v_new jsonb := '[]';
  v_item jsonb;
  v_raw public.bank_raw_transactions%rowtype;
  v_transaction_id uuid;
begin
  -- Shape and types, one check at a time: the order of the operands of an
  -- or is not fixed. Casts put the value in the message: invalid_rows.
  begin
    if jsonb_typeof(ingest_bank_rows.rows) is distinct from 'array' then
      raise exception 'invalid_rows';
    end if;
    for v_row in select e.value from jsonb_array_elements(ingest_bank_rows.rows) as e (value) loop
      if jsonb_typeof(v_row) is distinct from 'object' then
        raise exception 'invalid_rows';
      end if;
      if exists (
        select 1 from jsonb_object_keys(v_row) as k (key)
        where k.key not in (
          'entry_reference', 'status', 'booking_date', 'value_date', 'transaction_date',
          'amount_cents', 'currency', 'dedup_hash', 'payload', 'original_amount_cents',
          'original_currency', 'exchange_rate', 'description', 'counterparty',
          'counterparty_email', 'bank_code'
        )
      ) then
        raise exception 'invalid_rows';
      end if;
      if jsonb_typeof(v_row -> 'status') is distinct from 'string'
        or (v_row ->> 'status') not in ('BOOK', 'PDNG', 'RJCT', 'CNCL')
        or jsonb_typeof(v_row -> 'amount_cents') is distinct from 'number'
        or jsonb_typeof(v_row -> 'currency') is distinct from 'string'
        or (v_row ->> 'currency') !~ '^[A-Z]{3}$'
        or jsonb_typeof(v_row -> 'dedup_hash') is distinct from 'string'
        or (v_row ->> 'dedup_hash') !~ '^[0-9a-f]{64}$'
        or jsonb_typeof(v_row -> 'payload') is distinct from 'object'
        or coalesce(jsonb_typeof(v_row -> 'entry_reference'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'booking_date'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'value_date'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'transaction_date'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'original_amount_cents'), 'null') not in ('number', 'null')
        or coalesce(jsonb_typeof(v_row -> 'original_currency'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'exchange_rate'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'description'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'counterparty'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'counterparty_email'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_row -> 'bank_code'), 'null') not in ('string', 'null')
      then
        raise exception 'invalid_rows';
      end if;
      -- A reference is never blank; a movement has a date.
      if btrim(v_row ->> 'entry_reference') = ''
        or coalesce(v_row ->> 'booking_date', v_row ->> 'value_date', v_row ->> 'transaction_date') is null
        or (v_row ->> 'booking_date') !~ '^\d{4}-\d{2}-\d{2}$'
        or (v_row ->> 'value_date') !~ '^\d{4}-\d{2}-\d{2}$'
        or (v_row ->> 'transaction_date') !~ '^\d{4}-\d{2}-\d{2}$'
        or (v_row ->> 'original_currency') !~ '^[A-Z]{3}$'
        or (v_row ->> 'exchange_rate') !~ '^\d{1,15}(\.\d{1,20})?$'
      then
        raise exception 'invalid_rows';
      end if;
      -- Integer cents within bigint, real dates (a cast out of range is a
      -- data_exception).
      if (v_row ->> 'amount_cents')::numeric <> trunc((v_row ->> 'amount_cents')::numeric)
        or (v_row ->> 'original_amount_cents')::numeric
          <> trunc((v_row ->> 'original_amount_cents')::numeric)
      then
        raise exception 'invalid_rows';
      end if;
      perform ((v_row ->> 'amount_cents')::numeric)::bigint,
        ((v_row ->> 'original_amount_cents')::numeric)::bigint,
        (v_row ->> 'booking_date')::date,
        (v_row ->> 'value_date')::date,
        (v_row ->> 'transaction_date')::date,
        (v_row ->> 'exchange_rate')::numeric;
    end loop;
  exception
    when data_exception then
      raise exception 'invalid_rows';
  end;

  select a.* into v_account
  from public.accounts a
  where a.id = ingest_bank_rows.account_id
    and a.connection_id is not null;
  if not found then
    raise exception 'account_not_found';
  end if;

  -- One import at a time for each account: two syncs would both insert the
  -- same ordinals or the same references.
  perform pg_advisory_xact_lock(hashtextextended('bank_rows:' || v_account.id::text, 0));

  -- The owner of the account is an active member: the movements are theirs.
  select m.start_date into v_start_date
  from public.members m
  where m.id = v_account.owner_member_id
    and m.left_at is null;
  if not found then
    raise exception 'member_not_eligible';
  end if;

  rows_received := jsonb_array_length(ingest_bank_rows.rows);
  raw_inserted := 0;
  transactions_created := 0;
  skipped_before_start := 0;
  skipped_status := 0;
  groups_shrunk := 0;
  booked_then_cancelled := 0;

  begin
    -- 1. Rows with a reference, in the order received.
    for v_row in
      select e.value
      from jsonb_array_elements(ingest_bank_rows.rows) with ordinality as e (value, ord)
      where e.value ->> 'entry_reference' is not null
      order by e.ord
    loop
      v_id := null;
      insert into public.bank_raw_transactions (
        account_id, entry_reference, dedup_hash, dedup_ordinal, status, booking_date, value_date,
        transaction_date, amount_cents, currency, payload
      )
      values (
        v_account.id, v_row ->> 'entry_reference', v_row ->> 'dedup_hash', 1, v_row ->> 'status',
        (v_row ->> 'booking_date')::date, (v_row ->> 'value_date')::date,
        (v_row ->> 'transaction_date')::date, ((v_row ->> 'amount_cents')::numeric)::bigint,
        v_row ->> 'currency', v_row -> 'payload'
      )
      on conflict (account_id, entry_reference) where entry_reference is not null do nothing
      returning id into v_id;

      if v_id is not null then
        raw_inserted := raw_inserted + 1;
        v_new := v_new || jsonb_build_array(jsonb_build_object('id', v_id, 'row', v_row));
      else
        select r.id, r.status, r.transaction_id into v_existing
        from public.bank_raw_transactions r
        where r.account_id = v_account.id
          and r.entry_reference = v_row ->> 'entry_reference'
        for update;

        if v_existing.status = 'PDNG' and v_row ->> 'status' = 'BOOK' then
          update public.bank_raw_transactions r
          set status = 'BOOK',
              booking_date = (v_row ->> 'booking_date')::date,
              value_date = (v_row ->> 'value_date')::date,
              transaction_date = (v_row ->> 'transaction_date')::date,
              amount_cents = ((v_row ->> 'amount_cents')::numeric)::bigint,
              currency = v_row ->> 'currency',
              dedup_hash = v_row ->> 'dedup_hash',
              payload = v_row -> 'payload',
              fetched_at = now()
          where r.id = v_existing.id;
          v_new := v_new || jsonb_build_array(jsonb_build_object('id', v_existing.id, 'row', v_row));
        elsif v_row ->> 'status' = 'CNCL' and v_existing.transaction_id is not null then
          booked_then_cancelled := booked_then_cancelled + 1;
        end if;
      end if;
    end loop;

    -- 2. Rows without a reference, by group of identical rows: the groups
    -- are complete because the hash holds the dates and an account is
    -- imported only with all its pages.
    for v_group in
      select e.value ->> 'dedup_hash' as dedup_hash,
             jsonb_agg(e.value order by e.ord) as group_rows,
             count(*)::int as received
      from jsonb_array_elements(ingest_bank_rows.rows) with ordinality as e (value, ord)
      where e.value ->> 'entry_reference' is null
      group by e.value ->> 'dedup_hash'
      order by min(e.ord)
    loop
      select count(*)::int into v_saved
      from public.bank_raw_transactions r
      where r.account_id = v_account.id
        and r.entry_reference is null
        and r.dedup_hash = v_group.dedup_hash;

      if v_group.received > v_saved then
        for v_ordinal in v_saved + 1 .. v_group.received loop
          v_row := v_group.group_rows -> (v_ordinal - 1);
          insert into public.bank_raw_transactions (
            account_id, entry_reference, dedup_hash, dedup_ordinal, status, booking_date,
            value_date, transaction_date, amount_cents, currency, payload
          )
          values (
            v_account.id, null, v_row ->> 'dedup_hash', v_ordinal, v_row ->> 'status',
            (v_row ->> 'booking_date')::date, (v_row ->> 'value_date')::date,
            (v_row ->> 'transaction_date')::date, ((v_row ->> 'amount_cents')::numeric)::bigint,
            v_row ->> 'currency', v_row -> 'payload'
          )
          returning id into v_id;
          raw_inserted := raw_inserted + 1;
          v_new := v_new || jsonb_build_array(jsonb_build_object('id', v_id, 'row', v_row));
        end loop;
      elsif v_group.received < v_saved then
        groups_shrunk := groups_shrunk + 1;
      end if;
    end loop;

    -- 3. Movements of the new rows (section 6.1).
    for v_item in select e.value from jsonb_array_elements(v_new) as e (value) loop
      select r.* into v_raw
      from public.bank_raw_transactions r
      where r.id = (v_item ->> 'id')::uuid;
      v_row := v_item -> 'row';

      if v_raw.status <> 'BOOK' then
        skipped_status := skipped_status + 1;
      elsif v_raw.movement_date < v_start_date then
        skipped_before_start := skipped_before_start + 1;
      elsif v_raw.amount_cents = 0 then
        -- A movement is never zero: the row stays only here.
        skipped_status := skipped_status + 1;
      else
        insert into public.transactions (
          household_id, account_id, source, raw_id, paid_by_member_id, movement_date,
          booking_date, booking_status, amount_cents, currency, original_amount_cents,
          original_currency, exchange_rate, description, counterparty, counterparty_email,
          bank_code
        )
        values (
          v_account.household_id, v_account.id, 'bank', v_raw.id, v_account.owner_member_id,
          v_raw.movement_date, v_raw.booking_date, 'booked', v_raw.amount_cents, v_raw.currency,
          ((v_row ->> 'original_amount_cents')::numeric)::bigint, v_row ->> 'original_currency',
          (v_row ->> 'exchange_rate')::numeric, v_row ->> 'description', v_row ->> 'counterparty',
          v_row ->> 'counterparty_email', v_row ->> 'bank_code'
        )
        returning id into v_transaction_id;

        update public.bank_raw_transactions r
        set transaction_id = v_transaction_id
        where r.id = v_raw.id;
        transactions_created := transactions_created + 1;
      end if;
    end loop;
  exception
    when data_exception or check_violation or not_null_violation or unique_violation
      or foreign_key_violation
    then
      raise exception 'invalid_rows';
  end;

  return next;
end;
$$;

comment on function public.ingest_bank_rows(uuid, jsonb) is
  'Imports the normalized rows of an account and their movements in one transaction; returns the counts. Errors: invalid_rows, account_not_found, member_not_eligible.';

-- Request of a sync

-- Starts eb-sync for a connection with an HTTP request of pg_net, sent when
-- the transaction commits: the URL of the project (project_url) and the
-- secret of the jobs (x-sync-secret) are read from Vault and never
-- returned. Without the URL, or without the secret, nothing is sent.
create function public.request_bank_sync(connection_id uuid, trigger text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if request_bank_sync.trigger is null
    or request_bank_sync.trigger not in ('link', 'schedule', 'manual', 'admin')
  then
    raise exception 'invalid_trigger';
  end if;

  if not exists (
    select 1 from public.bank_connections c where c.id = request_bank_sync.connection_id
  ) then
    raise exception 'connection_not_found';
  end if;

  select btrim(s.decrypted_secret) into v_url
  from vault.decrypted_secrets s
  where s.name = 'project_url';
  if v_url is null or v_url !~ '^https?://[^/[:space:]]+/*$' then
    raise exception 'project_url_missing';
  end if;

  select s.decrypted_secret into v_secret
  from vault.decrypted_secrets s
  where s.name = 'sync_cron_secret';
  if coalesce(v_secret, '') = '' then
    raise exception 'sync_secret_missing';
  end if;

  perform net.http_post(
    url := regexp_replace(v_url, '/+$', '') || '/functions/v1/eb-sync',
    body := jsonb_build_object(
      'connection_id', request_bank_sync.connection_id,
      'trigger', request_bank_sync.trigger
    ),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sync-secret', v_secret)
  );
end;
$$;

comment on function public.request_bank_sync(uuid, text) is
  'Asks eb-sync to sync a connection (pg_net, secret from Vault). Errors: invalid_trigger, connection_not_found, project_url_missing, sync_secret_missing.';

-- Only the service role.

revoke all on function public.ingest_bank_rows(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.request_bank_sync(uuid, text) from public, anon, authenticated;

grant execute on function public.ingest_bank_rows(uuid, jsonb) to service_role;
grant execute on function public.request_bank_sync(uuid, text) to service_role;
