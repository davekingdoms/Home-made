-- PayPal emails of an account (docs/spec/schema.md, 10): one person for each
-- email, to recognise the settlements paid with PayPal. Only the owner reads
-- and writes them; the recognition reads them on the server.

create table public.paypal_emails (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Saved in lower case.
  email text not null unique
    constraint paypal_emails_email_not_empty check (char_length(email) > 0),
  source text not null
    constraint paypal_emails_source check (source in ('linked_account', 'manual')),
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.paypal_emails is
  'PayPal emails of an account, unique: one person for each email.';

create index paypal_emails_user_id on public.paypal_emails (user_id);

create trigger paypal_emails_touch_row
  before update on public.paypal_emails
  for each row execute function public.touch_row();

create function public.normalize_paypal_email()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.email := lower(btrim(new.email));
  return new;
end;
$$;

revoke all on function public.normalize_paypal_email() from public, anon, authenticated;

create trigger paypal_emails_normalize
  before insert or update of email on public.paypal_emails
  for each row execute function public.normalize_paypal_email();

-- RLS: everything, only the owner.
alter table public.paypal_emails enable row level security;

revoke all on table public.paypal_emails from anon, authenticated;
grant select, insert, update, delete on table public.paypal_emails to authenticated;

create policy paypal_emails_all_own on public.paypal_emails
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
