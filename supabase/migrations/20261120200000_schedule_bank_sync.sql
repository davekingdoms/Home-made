-- Scheduled jobs of the bank sync (docs/spec/sincronizzazione.md, 10): three
-- syncs a day for every active connection, the expired consents, the
-- cleanup. pg_cron runs each job as postgres, at fixed times in UTC, with a
-- single select of a function of this migration.
--
-- The functions run as their owner; besides the jobs only the service role
-- executes them: the app and anon execute none. Their errors and warnings
-- are only keys, never a value.

-- Asks eb-sync, with request_bank_sync, to sync every active connection of
-- an active member with no sync started in the last 2 hours: after a link
-- or a sync by hand the scheduled one is skipped, so three syncs and a link
-- stay within the about 4 accesses a day of the banks. A skipped row does
-- not count. The rest (missing credentials, a consent expired at the bank)
-- is up to eb-sync and its codes in sync_runs.
--
-- Each request runs in its own block: the error of a connection becomes a
-- warning with only its code, and the next connections are asked anyway.
-- The function never ends with an error: it would roll back the requests
-- already queued by pg_net, which leave only at the commit. Returns the
-- number of requests queued.
create function public.schedule_bank_syncs()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_connection_id uuid;
  v_requested int := 0;
begin
  for v_connection_id in
    select c.id
    from public.bank_connections c
    join public.members m on m.id = c.member_id
    where c.status = 'active'
      and m.left_at is null
      and not exists (
        select 1
        from public.sync_runs sr
        where sr.connection_id = c.id
          and sr.account_id is null
          and sr.status <> 'skipped'
          and sr.started_at > now() - interval '2 hours'
      )
    order by c.id
  loop
    begin
      perform public.request_bank_sync(v_connection_id, 'schedule');
      v_requested := v_requested + 1;
    exception
      when others then
        -- Only a key: never the raw message, which could carry a value.
        raise warning '%',
          case when sqlerrm ~ '^[a-z_]{1,40}$' then sqlerrm else 'internal' end;
    end;
  end loop;

  return v_requested;
end;
$$;

comment on function public.schedule_bank_syncs() is
  'Scheduled syncs: requests eb-sync for the active connections without a sync in the last 2 hours; returns how many. Never raises.';

-- Marks the active connections whose consent is past valid_until as expired
-- (consent_expired); returns how many. No other column changes.
create function public.expire_bank_consents()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expired int;
begin
  update public.bank_connections c
  set status = 'expired',
      last_error = 'consent_expired'
  where c.status = 'active'
    and c.valid_until < now();
  get diagnostics v_expired = row_count;

  return v_expired;
end;
$$;

comment on function public.expire_bank_consents() is
  'Active connections past valid_until become expired (consent_expired); returns how many.';

-- Weekly cleanup:
--   - the link requests created more than 7 days ago;
--   - the syncs started more than 180 days ago (row of the connection with
--     the rows of its accounts), except the sync that holds the last ok row
--     of an account: the window of its next syncs starts there (eb-sync,
--     docs/spec/sincronizzazione.md 4), and without it an account in error
--     for six months would start again from the start date;
--   - the runs of the jobs older than 30 days.
-- Returns the counts in a JSON object.
create function public.cleanup_bank_sync()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link_requests int;
  v_runs uuid[];
  v_connection_rows int;
  v_account_rows int;
  v_job_runs int;
begin
  delete from public.bank_link_requests r
  where r.created_at < now() - interval '7 days';
  get diagnostics v_link_requests = row_count;

  select coalesce(array_agg(sr.id), '{}')
  into v_runs
  from public.sync_runs sr
  where sr.account_id is null
    and sr.started_at < now() - interval '180 days'
    and not exists (
      select 1
      from public.sync_runs a
      where a.run_id = sr.id
        and a.status = 'ok'
        and not exists (
          select 1
          from public.sync_runs b
          where b.account_id = a.account_id
            and b.status = 'ok'
            and b.started_at > a.started_at
        )
    );

  -- The rows of the accounts would go with their sync anyway (run_id on
  -- delete cascade): deleted in the same statement to count them.
  with deleted as (
    delete from public.sync_runs sr
    where sr.id = any (v_runs)
      or sr.run_id = any (v_runs)
    returning sr.account_id
  )
  select
    count(*) filter (where d.account_id is null)::int,
    count(*) filter (where d.account_id is not null)::int
  into v_connection_rows, v_account_rows
  from deleted d;

  -- A run that never started has only its end, one still going only its
  -- start.
  delete from cron.job_run_details d
  where coalesce(d.end_time, d.start_time) < now() - interval '30 days';
  get diagnostics v_job_runs = row_count;

  return jsonb_build_object(
    'link_requests', v_link_requests,
    'connection_runs', v_connection_rows,
    'account_runs', v_account_rows,
    'job_runs', v_job_runs
  );
end;
$$;

comment on function public.cleanup_bank_sync() is
  'Weekly cleanup: link requests (7 days), syncs (180 days, keeping the last ok of each account), job runs (30 days); returns the counts.';

-- Only the service role, besides the jobs.

revoke all on function public.schedule_bank_syncs() from public, anon, authenticated;
revoke all on function public.expire_bank_consents() from public, anon, authenticated;
revoke all on function public.cleanup_bank_sync() from public, anon, authenticated;

grant execute on function public.schedule_bank_syncs() to service_role;
grant execute on function public.expire_bank_consents() to service_role;
grant execute on function public.cleanup_bank_sync() to service_role;

-- The jobs, by name: cron.schedule updates a job with the same name instead
-- of adding one. Times in UTC (one hour later in Italy in summer).
select cron.schedule('bank-consents', '0 6 * * *', 'select public.expire_bank_consents()');
select cron.schedule('bank-sync', '10 6,12,19 * * *', 'select public.schedule_bank_syncs()');
select cron.schedule('bank-cleanup', '30 3 * * 0', 'select public.cleanup_bank_sync()');
