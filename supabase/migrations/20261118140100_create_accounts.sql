-- Accounts and data of the banks (docs/spec/schema.md, 4).
--
-- The app reads its own connections, accounts and balances, renames and
-- archives its accounts and creates manual ones. Connections, bank accounts,
-- balances and the raw data are written by the server (Edge Functions with
-- the service role); credentials and raw data are never read by the app.

-- Enable Banking application of a person. The private key (PEM) stays in
-- Supabase Vault: the Edge Function saves it with vault.create_secret and
-- reads it from vault.decrypted_secrets. Without a row the person uses the
-- global application.
create table public.eb_credentials (
  user_id uuid primary key references auth.users (id) on delete cascade,
  app_id text not null,
  private_key_secret_id uuid not null,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.eb_credentials is
  'Enable Banking application of a person; the private key is a secret in Vault. Server only.';
comment on column public.eb_credentials.private_key_secret_id is
  'Id of the secret in vault.secrets that holds the private key (PEM).';

create trigger eb_credentials_touch_row
  before update on public.eb_credentials
  for each row execute function public.touch_row();

-- One PSD2 consent for each bank.
create table public.bank_connections (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id),
  -- The bank as Enable Banking names it.
  aspsp_name text not null,
  aspsp_country text not null,
  session_id text unique,
  uses_global_app boolean not null,
  status text not null default 'pending'
    constraint bank_connections_status
    check (status in ('pending', 'active', 'expired', 'revoked', 'error')),
  valid_until timestamptz,
  last_sync_at timestamptz,
  last_success_at timestamptz,
  -- Only a code (period_rejected, consent_expired...), never text of the bank.
  last_error text,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.bank_connections is
  'PSD2 consents of a member, one for each bank.';

create index bank_connections_member_id on public.bank_connections (member_id);

create trigger bank_connections_touch_row
  before update on public.bank_connections
  for each row execute function public.touch_row();

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  -- Read only by is_account_owner.
  owner_member_id uuid not null references public.members (id),
  kind text not null
    constraint accounts_kind
    check (kind in ('bank', 'card', 'paypal', 'cash', 'manual')),
  connection_id uuid references public.bank_connections (id),
  -- Id of the account at Enable Banking.
  provider_account_id text,
  cash_account_type text,
  -- XXX for an account in several currencies (PayPal).
  currency char(3) not null
    constraint accounts_currency_format check (currency ~ '^[A-Z]{3}$'),
  display_name text not null,
  -- IBAN, masked card or email of the account.
  identifier text,
  -- Null: the default rule (the available balance).
  preferred_balance_type text,
  excluded_from_total boolean not null default false,
  -- Cash and manual accounts: balance at the start date of the member,
  -- out of the budget.
  opening_balance_cents bigint,
  archived_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_connection_by_kind
    check ((connection_id is not null) = (kind in ('bank', 'card', 'paypal'))),
  constraint accounts_opening_balance_by_kind
    check (opening_balance_cents is null or kind in ('cash', 'manual')),
  constraint accounts_provider_account_unique
    unique (connection_id, provider_account_id)
);

comment on table public.accounts is
  'Accounts of the members: bank, card, PayPal, cash, manual.';

-- One cash account for each member.
create unique index accounts_one_cash_per_member
  on public.accounts (owner_member_id)
  where kind = 'cash';

create index accounts_household_id on public.accounts (household_id);

create trigger accounts_touch_row
  before update on public.accounts
  for each row execute function public.touch_row();

-- Every new member gets a cash account.
create function public.create_cash_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.accounts (household_id, owner_member_id, kind, currency, display_name)
  values (new.household_id, new.id, 'cash', 'EUR', 'Contanti');
  return null;
end;
$$;

revoke all on function public.create_cash_account() from public, anon, authenticated;

create trigger members_create_cash_account
  after insert on public.members
  for each row execute function public.create_cash_account();

-- Balances read from the banks: the last value for each currency and type.
-- The balance of a bank account is never computed from the movements.
create table public.account_balances (
  account_id uuid not null references public.accounts (id),
  currency char(3) not null
    constraint account_balances_currency_format check (currency ~ '^[A-Z]{3}$'),
  -- CLBD, XPCD, ITAV, ITBD, OTHR...
  balance_type text not null,
  -- With sign: a credit card has its debt negative.
  amount_cents bigint not null,
  reference_date date,
  fetched_at timestamptz not null default now(),
  primary key (account_id, currency, balance_type)
);

comment on table public.account_balances is
  'Last balance read from the bank, for each account, currency and type.';

-- Raw data of the banks, one row for each row of the answer.
create table public.bank_raw_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id),
  entry_reference text,
  -- Hash of booking, value and transaction date, amount, sign, description.
  dedup_hash text not null,
  -- Position of the row among the identical rows (1, 2, 3...).
  dedup_ordinal int not null
    constraint bank_raw_transactions_dedup_ordinal check (dedup_ordinal >= 1),
  status text not null
    constraint bank_raw_transactions_status
    check (status in ('BOOK', 'PDNG', 'RJCT', 'CNCL')),
  booking_date date,
  value_date date,
  transaction_date date,
  -- Value date, else transaction date, else booking date.
  movement_date date not null
    generated always as (coalesce(value_date, transaction_date, booking_date)) stored,
  -- With sign, from credit_debit_indicator.
  amount_cents bigint not null,
  currency char(3) not null
    constraint bank_raw_transactions_currency_format check (currency ~ '^[A-Z]{3}$'),
  payload jsonb not null,
  -- Movement created from this row (foreign key with the transactions).
  transaction_id uuid,
  fetched_at timestamptz not null default now()
);

comment on table public.bank_raw_transactions is
  'Rows of the bank answers. Server only; an identical row is never dropped.';

-- Deduplication: by entry reference when the bank gives one, otherwise by
-- hash and position among the identical rows.
create unique index bank_raw_transactions_entry_reference
  on public.bank_raw_transactions (account_id, entry_reference)
  where entry_reference is not null;

create unique index bank_raw_transactions_dedup
  on public.bank_raw_transactions (account_id, dedup_hash, dedup_ordinal)
  where entry_reference is null;

-- The only place that decides who owns an account: a future joint account
-- changes only this function.
create function public.is_account_owner(account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.accounts a
    where a.id = is_account_owner.account_id
      and a.owner_member_id = (select public.current_member_id())
  )
$$;

comment on function public.is_account_owner(uuid) is
  'True if the account belongs to the active member of the signed-in user.';

revoke all on function public.is_account_owner(uuid) from public, anon;
grant execute on function public.is_account_owner(uuid) to authenticated;

-- RLS

alter table public.eb_credentials enable row level security;
alter table public.bank_connections enable row level security;
alter table public.accounts enable row level security;
alter table public.account_balances enable row level security;
alter table public.bank_raw_transactions enable row level security;

revoke all on table public.eb_credentials from anon, authenticated;
revoke all on table public.bank_connections from anon, authenticated;
revoke all on table public.accounts from anon, authenticated;
revoke all on table public.account_balances from anon, authenticated;
revoke all on table public.bank_raw_transactions from anon, authenticated;

-- eb_credentials and bank_raw_transactions: no grant, no policy.

grant select on table public.bank_connections to authenticated;

create policy bank_connections_select_own on public.bank_connections
  for select to authenticated
  using (member_id = (select public.current_member_id()));

-- The owner reads and changes a few columns of their accounts and creates
-- only manual ones; the accounts of the banks come from the server.
grant select on table public.accounts to authenticated;
grant insert (
  id, household_id, owner_member_id, kind, currency, display_name, identifier,
  preferred_balance_type, excluded_from_total, opening_balance_cents
) on table public.accounts to authenticated;
grant update (
  display_name, preferred_balance_type, excluded_from_total,
  opening_balance_cents, archived_at
) on table public.accounts to authenticated;

create policy accounts_select_own on public.accounts
  for select to authenticated
  using (public.is_account_owner(id));

create policy accounts_insert_manual on public.accounts
  for insert to authenticated
  with check (
    kind = 'manual'
    and owner_member_id = (select public.current_member_id())
    and household_id = (select public.current_household_id())
  );

create policy accounts_update_own on public.accounts
  for update to authenticated
  using (public.is_account_owner(id))
  with check (public.is_account_owner(id));

grant select on table public.account_balances to authenticated;

create policy account_balances_select_own on public.account_balances
  for select to authenticated
  using (public.is_account_owner(account_id));
