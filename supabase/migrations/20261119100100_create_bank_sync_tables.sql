-- Tables of the bank sync (docs/spec/sincronizzazione.md, 9): the links in
-- progress and the outcome of every sync.
--
-- Both are written only by the server (Edge Functions with the service
-- role, through the functions of the next migration). The app never sees
-- the link requests; it reads the outcome of the syncs of its own
-- connections, for the warnings of a later screen. Only codes and counts:
-- no amount, description or name.

-- A link in progress: its id is the state sent to Enable Banking, valid
-- once and for 30 minutes.
create table public.bank_link_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id),
  -- The bank as Enable Banking names it.
  aspsp_name text not null
    constraint bank_link_requests_aspsp_name
    check (btrim(aspsp_name) <> '' and char_length(aspsp_name) <= 200),
  aspsp_country text not null
    constraint bank_link_requests_aspsp_country check (aspsp_country ~ '^[A-Z]{2}$'),
  psu_type text not null
    constraint bank_link_requests_psu_type check (psu_type in ('personal', 'business')),
  uses_global_app boolean not null,
  expires_at timestamptz not null default now() + interval '30 minutes',
  used_at timestamptz,
  -- Code of the outcome, written by eb-callback.
  result text
    constraint bank_link_requests_result check (result ~ '^[a-z_]{1,40}$'),
  created_at timestamptz not null default now()
);

comment on table public.bank_link_requests is
  'Bank links in progress; the id is the state sent to Enable Banking. Server only.';

create index bank_link_requests_member_id on public.bank_link_requests (member_id);

-- Cleanup of the requests older than 7 days (scheduled job).
create index bank_link_requests_created_at on public.bank_link_requests (created_at);

-- The member of a request is an active member, also for the server.
create function public.check_link_request_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.members m
    where m.id = new.member_id
      and m.left_at is null
  ) then
    raise exception 'member_not_eligible';
  end if;
  return new;
end;
$$;

revoke all on function public.check_link_request_member() from public, anon, authenticated;

create trigger bank_link_requests_check_member
  before insert or update of member_id on public.bank_link_requests
  for each row execute function public.check_link_request_member();

-- Outcome of a sync: one row for the connection and, when the sync closes,
-- one row for each account with its counts, linked to the first by run_id.
create table public.sync_runs (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.bank_connections (id) on delete cascade,
  -- Null on the row of the connection.
  account_id uuid references public.accounts (id) on delete cascade,
  -- Null on the row of the connection; its id on the rows of the accounts.
  run_id uuid references public.sync_runs (id) on delete cascade,
  trigger text not null
    constraint sync_runs_trigger check (trigger in ('link', 'schedule', 'manual', 'admin')),
  status text not null
    constraint sync_runs_status
    check (status in ('running', 'ok', 'partial', 'error', 'skipped')),
  -- Only the codes of docs/spec/sincronizzazione.md, 4: never text of the bank.
  error_code text
    constraint sync_runs_error_code check (error_code in (
      'period_rejected', 'consent_expired', 'consent_revoked', 'rate_limited',
      'no_credentials', 'invalid_credentials', 'bank_unavailable', 'bank_error',
      'link_expired', 'link_cancelled', 'link_rejected', 'link_failed',
      'already_running', 'paypal_email_taken', 'internal'
    )),
  strategy text
    constraint sync_runs_strategy check (strategy in ('longest', 'default')),
  -- Asked.
  date_from date,
  -- Obtained.
  history_from date,
  history_incomplete boolean not null default false,
  rows_received int not null default 0,
  raw_inserted int not null default 0,
  transactions_created int not null default 0,
  skipped_before_start int not null default 0,
  skipped_status int not null default 0,
  groups_shrunk int not null default 0,
  booked_then_cancelled int not null default 0,
  purchase_already_classified int not null default 0,
  matched_transfers int not null default 0,
  matched_settlements int not null default 0,
  matched_installments int not null default 0,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint sync_runs_counts_not_negative check (
    least(
      rows_received, raw_inserted, transactions_created, skipped_before_start,
      skipped_status, groups_shrunk, booked_then_cancelled,
      purchase_already_classified, matched_transfers, matched_settlements,
      matched_installments
    ) >= 0
  ),
  -- The row of the connection has neither; the row of an account has both.
  constraint sync_runs_account_with_run
    check ((account_id is null) = (run_id is null)),
  constraint sync_runs_one_row_per_account unique (run_id, account_id)
);

comment on table public.sync_runs is
  'Outcome of every sync: codes and counts for the connection and each account. Written by the server.';

-- One sync at a time for each connection.
create unique index sync_runs_one_running
  on public.sync_runs (connection_id)
  where status = 'running' and account_id is null;

create index sync_runs_connection_started_at
  on public.sync_runs (connection_id, started_at desc);

-- Cleanup of the rows older than 180 days (scheduled job).
create index sync_runs_started_at on public.sync_runs (started_at);

create index sync_runs_account_id on public.sync_runs (account_id);

-- RLS

alter table public.bank_link_requests enable row level security;
alter table public.sync_runs enable row level security;

revoke all on table public.bank_link_requests from anon, authenticated;
revoke all on table public.sync_runs from anon, authenticated;

-- bank_link_requests: no grant, no policy.

-- The owner of the connection reads its syncs; no writes from the app.
grant select on table public.sync_runs to authenticated;

create policy sync_runs_select_own on public.sync_runs
  for select to authenticated
  using (
    exists (
      select 1
      from public.bank_connections c
      where c.id = connection_id
        and c.member_id = (select public.current_member_id())
    )
  );
