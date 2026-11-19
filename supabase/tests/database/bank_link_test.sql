-- Completion of the bank links (docs/spec/sincronizzazione.md, 3, 6.4, 6.5
-- and 9): the member of a service call, complete_bank_link,
-- finish_link_request, permissions. Invented users: Anna (a1), Bruno (b1)
-- and Carla (c1) in "Casa di prova", with a former member (e9) and a member
-- without an account (e8). Invented banks, sessions, IBANs, cards and
-- emails; dates of 2031.
begin;

create extension if not exists pgtap with schema extensions;

select plan(75);

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

-- Links sent to complete_bank_link, by name.
create temp table links (name text primary key, link jsonb not null);
grant select on links to service_role, authenticated;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60),
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 30),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 60),
  ('00000000-0000-4000-8000-0000000000e8', '00000000-0000-4000-8000-0000000000f1',
   null, current_date - 60);
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000e9', '00000000-0000-4000-8000-0000000000f1',
   null, current_date - 60, now());

-- PayPal emails already saved: one of Anna, one of Bruno.
insert into public.paypal_emails (user_id, email, source) values
  ('00000000-0000-4000-8000-00000000000a', 'anna.altra@example.com', 'manual'),
  ('00000000-0000-4000-8000-00000000000b', 'bruno.paypal@example.com', 'manual');

-- Link requests: claimed (used_at set) unless said otherwise.
insert into public.bank_link_requests (
  id, member_id, aspsp_name, aspsp_country, psu_type, uses_global_app, expires_at, used_at, result
) values
  -- First link of Banca di Prova.
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  -- Second link of the same bank, with the global application, claimed
  -- before its expiry and completed after it.
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', true, now() - interval '1 minute', now() - interval '29 minutes', null),
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000a1',
   'Altra Banca di Prova', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  ('00000000-0000-4000-8000-000000000104', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  ('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  -- Not claimed.
  ('00000000-0000-4000-8000-000000000107', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', false, now() + interval '20 minutes', null, null),
  -- Already with an outcome.
  ('00000000-0000-4000-8000-000000000108', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', false, now() + interval '20 minutes', now(), 'ok'),
  ('00000000-0000-4000-8000-000000000109', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', false, now() + interval '20 minutes', now(), 'link_cancelled'),
  -- Carla, who leaves the household after the claim.
  ('00000000-0000-4000-8000-00000000010a', '00000000-0000-4000-8000-0000000000c1',
   'Banca di Prova', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  -- Wrong shapes and a link that fails halfway.
  ('00000000-0000-4000-8000-00000000010b', '00000000-0000-4000-8000-0000000000a1',
   'Banca Nuova di Prova', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  ('00000000-0000-4000-8000-00000000010c', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'personal', false, now() + interval '20 minutes', now(), null),
  -- For finish_link_request.
  ('00000000-0000-4000-8000-00000000010d', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'business', false, now() + interval '20 minutes', now(), null);

update public.members set left_at = now() where id = '00000000-0000-4000-8000-0000000000c1';

insert into links (name, link) values
  ('first', $${
    "session_id": "sessione-di-prova-1",
    "valid_until": "2031-08-28T10:00:00.000000+00:00",
    "accounts": [
      {"uid": "conto-uid-1", "kind": "bank", "cash_account_type": "CACC", "currency": "EUR",
       "identifier": "IT60X0542811101000000123456", "display_name": "Banca di Prova …3456",
       "paypal_email": null,
       "balances": [
         {"currency": "EUR", "balance_type": "CLBD", "amount_cents": 123456, "reference_date": "2031-03-04"},
         {"currency": "EUR", "balance_type": "ITAV", "amount_cents": 120000, "reference_date": null}
       ]},
      {"uid": "carta-uid-1", "kind": "card", "cash_account_type": "CARD", "currency": "EUR",
       "identifier": "000000******0000", "display_name": "Carta …0000",
       "balances": [
         {"currency": "EUR", "balance_type": "CLBD", "amount_cents": -5000, "reference_date": "2031-03-04"}
       ]}
    ]
  }$$),
  -- The bank account with a new uid, the card without its identifier, a
  -- new account.
  ('second', $${
    "session_id": "sessione-di-prova-2",
    "valid_until": "2031-09-30T10:00:00+00:00",
    "accounts": [
      {"uid": "conto-uid-2", "kind": "bank", "cash_account_type": "CACC", "currency": "EUR",
       "identifier": "IT60X0542811101000000123456", "display_name": "Banca di Prova …3456",
       "balances": [
         {"currency": "EUR", "balance_type": "CLBD", "amount_cents": 99900, "reference_date": "2031-03-05"}
       ]},
      {"uid": "carta-uid-1", "kind": "card", "cash_account_type": "CARD", "currency": "EUR",
       "identifier": null, "display_name": "Carta", "balances": []},
      {"uid": "conto-uid-3", "kind": "bank", "cash_account_type": "CACC", "currency": "EUR",
       "identifier": "IT00A0000000000000000000002", "display_name": "Banca di Prova …0002",
       "balances": []}
    ]
  }$$),
  ('other_bank', $${
    "session_id": "sessione-di-prova-3",
    "valid_until": "2031-08-28T10:00:00+00:00",
    "accounts": [
      {"uid": "conto-uid-9", "kind": "bank", "cash_account_type": "CACC", "currency": "EUR",
       "identifier": "IT00A0000000000000000000009", "display_name": "Altra Banca di Prova …0009",
       "balances": []}
    ]
  }$$),
  ('paypal', $${
    "session_id": "sessione-di-prova-pp1",
    "valid_until": "2031-08-28T10:00:00+00:00",
    "accounts": [
      {"uid": "paypal-uid-1", "kind": "paypal", "cash_account_type": "OTHR", "currency": "XXX",
       "identifier": "anna.paypal@example.com", "display_name": "anna.paypal@example.com",
       "paypal_email": "Anna.PayPal@Example.com",
       "balances": [
         {"currency": "EUR", "balance_type": "XPCD", "amount_cents": 2500, "reference_date": null},
         {"currency": "USD", "balance_type": "XPCD", "amount_cents": 1000, "reference_date": null}
       ]}
    ]
  }$$),
  ('paypal_mine', $${
    "session_id": "sessione-di-prova-pp2",
    "valid_until": "2031-08-28T10:00:00+00:00",
    "accounts": [
      {"uid": "paypal-uid-2", "kind": "paypal", "cash_account_type": "OTHR", "currency": "XXX",
       "identifier": "anna.altra@example.com", "display_name": "anna.altra@example.com",
       "paypal_email": "anna.altra@example.com", "balances": []}
    ]
  }$$),
  ('paypal_taken', $${
    "session_id": "sessione-di-prova-pp3",
    "valid_until": "2031-08-28T10:00:00+00:00",
    "accounts": [
      {"uid": "paypal-uid-3", "kind": "paypal", "cash_account_type": "OTHR", "currency": "XXX",
       "identifier": "bruno.paypal@example.com", "display_name": "bruno.paypal@example.com",
       "paypal_email": "bruno.paypal@example.com", "balances": []}
    ]
  }$$),
  -- A valid account and a wrong one.
  ('half_wrong', $${
    "session_id": "sessione-di-prova-4",
    "valid_until": "2031-08-28T10:00:00+00:00",
    "accounts": [
      {"uid": "conto-uid-5", "kind": "bank", "currency": "EUR",
       "identifier": "IT00A0000000000000000000005", "display_name": "Banca Nuova di Prova …0005",
       "balances": [
         {"currency": "EUR", "balance_type": "CLBD", "amount_cents": 100, "reference_date": "2031-03-04"}
       ]},
      {"uid": "conto-uid-6", "kind": "bank", "currency": "eur",
       "display_name": "Banca Nuova di Prova", "balances": []}
    ]
  }$$),
  -- A new account, then one that takes the uid of another account of the
  -- connection: the second write fails.
  ('conflict', $${
    "session_id": "sessione-di-prova-5",
    "valid_until": "2031-08-28T10:00:00+00:00",
    "accounts": [
      {"uid": "conto-uid-4", "kind": "bank", "currency": "EUR",
       "identifier": "IT00A0000000000000000000004", "display_name": "Banca di Prova …0004",
       "balances": []},
      {"uid": "conto-uid-3", "kind": "bank", "currency": "EUR",
       "identifier": "IT60X0542811101000000123456", "display_name": "Banca di Prova …3456",
       "balances": []}
    ]
  }$$);

-- Wrong shapes: each one from a valid link.
insert into links (name, link)
select v.name, v.link
from (select link from links where name = 'half_wrong') base,
  lateral (values
    ('not_object', '[]'::jsonb),
    ('extra_key', base.link || '{"extra": 1}'),
    ('no_session', base.link - 'session_id'),
    ('valid_until_word', jsonb_set(base.link, '{valid_until}', '"domani"')),
    ('valid_until_day', jsonb_set(base.link, '{valid_until}', '"2031-02-30T10:00:00+00:00"')),
    ('accounts_object', jsonb_set(base.link, '{accounts}', '{}')),
    ('kind', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,kind}', '"loan"')),
    ('account_key', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,iban}', '"IT00"')),
    ('no_name', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,display_name}', '" "')),
    ('no_balances', base.link #- '{accounts,1}' #- '{accounts,0,balances}'),
    ('email_of_bank', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,paypal_email}', '"anna@example.com"')),
    ('same_uid', jsonb_set(base.link, '{accounts,1}', base.link #> '{accounts,0}')),
    ('cents_decimal', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,balances,0,amount_cents}', '12.5')),
    ('cents_text', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,balances,0,amount_cents}', '"100"')),
    ('cents_huge', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,balances,0,amount_cents}', '1e30')),
    ('reference_day', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,balances,0,reference_date}', '"2031-02-30"')),
    ('balance_currency', jsonb_set(base.link #- '{accounts,1}', '{accounts,0,balances,0,currency}', '"EURO"'))
  ) as v (name, link);

-- The member of a service call
set local role service_role;
select results_eq(
  $$select * from public.eb_service_member('00000000-0000-4000-8000-0000000000a1')$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, '00000000-0000-4000-8000-00000000000a'::uuid,
            '00000000-0000-4000-8000-0000000000f1'::uuid, current_date - 60)$$,
  'eb_service_member gives member, account, household and start date'
);
select throws_ok(
  $$select public.eb_service_member('00000000-0000-4000-8000-0000000000e9')$$,
  'P0001', 'member_not_eligible',
  'a former member is not eligible'
);
select throws_ok(
  $$select public.eb_service_member('00000000-0000-4000-8000-0000000000c1')$$,
  'P0001', 'member_not_eligible',
  'a member who left with the account is not eligible'
);
select throws_ok(
  $$select public.eb_service_member('00000000-0000-4000-8000-0000000000e8')$$,
  'P0001', 'member_not_eligible',
  'a member without an account is not eligible'
);
select throws_ok(
  $$select public.eb_service_member('00000000-0000-4000-8000-0000000000ff')$$,
  'P0001', 'member_not_eligible',
  'an unknown member is not eligible'
);

-- Requests that cannot be completed
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-000000000107', (select link from links where name = 'first'))$$,
  'P0001', 'link_not_claimable',
  'a request not claimed is not completed'
);
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-000000000108', (select link from links where name = 'first'))$$,
  'P0001', 'link_not_claimable',
  'a request already completed is not completed again'
);
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-000000000109', (select link from links where name = 'first'))$$,
  'P0001', 'link_not_claimable',
  'a cancelled request is not completed'
);
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-0000000000ff', (select link from links where name = 'first'))$$,
  'P0001', 'link_not_claimable',
  'an unknown request is not completed'
);
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-00000000010a', (select link from links where name = 'first'))$$,
  'P0001', 'member_not_eligible',
  'the request of a member who left is not completed'
);

reset role;
select is_empty(
  $$select 1 from public.bank_connections
    where member_id in ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000c1')$$,
  'the refused requests write no connection'
);

-- First link: a new connection with a bank account and a card.
set local role service_role;
select results_eq(
  $$select account_count from public.complete_bank_link('00000000-0000-4000-8000-000000000101', (select link from links where name = 'first'))$$,
  $$values (2)$$,
  'the first link returns its two accounts'
);

reset role;
select results_eq(
  $$select status, session_id, valid_until, uses_global_app, last_error
    from public.bank_connections
    where member_id = '00000000-0000-4000-8000-0000000000a1' and aspsp_name = 'Banca di Prova'$$,
  $$values ('active'::text, 'sessione-di-prova-1'::text, '2031-08-28 10:00:00+00'::timestamptz, false, null::text)$$,
  'the first link creates an active connection with session, validity and application of the request'
);
select results_eq(
  $$select a.household_id, a.owner_member_id, a.kind, a.provider_account_id, a.cash_account_type,
           a.currency::text, a.identifier, a.display_name
    from public.accounts a
    join public.bank_connections c on c.id = a.connection_id
    where c.aspsp_name = 'Banca di Prova'
    order by a.kind$$,
  $$values
    ('00000000-0000-4000-8000-0000000000f1'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid, 'bank'::text,
     'conto-uid-1'::text, 'CACC'::text, 'EUR'::text, 'IT60X0542811101000000123456'::text, 'Banca di Prova …3456'::text),
    ('00000000-0000-4000-8000-0000000000f1'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid, 'card'::text,
     'carta-uid-1'::text, 'CARD'::text, 'EUR'::text, '000000******0000'::text, 'Carta …0000'::text)$$,
  'the accounts belong to the member and the household, with uid, type, currency, identifier and name'
);
select results_eq(
  $$select a.kind, b.currency::text, b.balance_type, b.amount_cents, b.reference_date, b.fetched_at = now()
    from public.account_balances b
    join public.accounts a on a.id = b.account_id
    order by a.kind, b.balance_type$$,
  $$values
    ('bank'::text, 'EUR'::text, 'CLBD'::text, 123456::bigint, '2031-03-04'::date, true),
    ('bank'::text, 'EUR'::text, 'ITAV'::text, 120000::bigint, null::date, true),
    ('card'::text, 'EUR'::text, 'CLBD'::text, -5000::bigint, '2031-03-04'::date, true)$$,
  'the balances are saved with their sign, a card with its debt negative'
);
select is(
  (select result from public.bank_link_requests where id = '00000000-0000-4000-8000-000000000101'),
  'ok',
  'the request takes the outcome ok'
);

set local role service_role;
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-000000000101', (select link from links where name = 'first'))$$,
  'P0001', 'link_not_claimable',
  'a completed request is not completed twice'
);

-- Second link of the same bank, after the consent expired and a rename.
reset role;
create temp table first_ids as
  select c.id as connection_id,
    (select a.id from public.accounts a where a.connection_id = c.id and a.kind = 'bank') as bank_id,
    (select a.id from public.accounts a where a.connection_id = c.id and a.kind = 'card') as card_id
  from public.bank_connections c
  where c.aspsp_name = 'Banca di Prova';
grant select on first_ids to service_role;
update public.bank_connections
  set status = 'expired', last_error = 'consent_expired'
  where id = (select connection_id from first_ids);
update public.accounts set display_name = 'Conto di casa' where id = (select bank_id from first_ids);

set local role service_role;
select results_eq(
  $$select connection_id, account_count
    from public.complete_bank_link('00000000-0000-4000-8000-000000000102', (select link from links where name = 'second'))$$,
  $$select connection_id, 3 from first_ids$$,
  'a request claimed in time is completed after its expiry, on the same connection'
);

reset role;
select results_eq(
  $$select count(*)::int, min(status), min(session_id), min(valid_until), bool_and(uses_global_app),
           count(last_error)::int
    from public.bank_connections
    where member_id = '00000000-0000-4000-8000-0000000000a1' and aspsp_name = 'Banca di Prova'$$,
  $$values (1, 'active'::text, 'sessione-di-prova-2'::text, '2031-09-30 10:00:00+00'::timestamptz, true, 0)$$,
  'the same bank reuses the connection: active again, new session and validity, no error'
);
select results_eq(
  $$select a.id, a.provider_account_id, a.display_name
    from public.accounts a where a.id = (select bank_id from first_ids)$$,
  $$select bank_id, 'conto-uid-2'::text, 'Conto di casa'::text from first_ids$$,
  'the known account (same identifier, new uid) is updated and keeps its name'
);
select results_eq(
  $$select a.id, a.identifier from public.accounts a where a.id = (select card_id from first_ids)$$,
  $$select card_id, '000000******0000'::text from first_ids$$,
  'the card without identifier is found by its uid and keeps its identifier'
);
select results_eq(
  $$select a.kind, a.identifier, a.display_name
    from public.accounts a
    where a.connection_id = (select connection_id from first_ids)
      and a.id not in ((select bank_id from first_ids), (select card_id from first_ids))$$,
  $$values ('bank'::text, 'IT00A0000000000000000000002'::text, 'Banca di Prova …0002'::text)$$,
  'a new account of the bank is created'
);
select is(
  (select count(*)::int from public.accounts where owner_member_id = '00000000-0000-4000-8000-0000000000a1' and kind <> 'cash'),
  3,
  'no account is duplicated'
);
select results_eq(
  $$select b.balance_type, b.amount_cents, b.reference_date
    from public.account_balances b
    where b.account_id = (select bank_id from first_ids)
    order by b.balance_type$$,
  $$values ('CLBD'::text, 99900::bigint, '2031-03-05'::date), ('ITAV'::text, 120000::bigint, null::date)$$,
  'a balance read again replaces the previous one; the others stay'
);

-- Another bank: a connection of its own.
set local role service_role;
select results_eq(
  $$select account_count from public.complete_bank_link('00000000-0000-4000-8000-000000000103', (select link from links where name = 'other_bank'))$$,
  $$values (1)$$,
  'the link of another bank completes'
);

reset role;
select is(
  (select count(*)::int from public.bank_connections where member_id = '00000000-0000-4000-8000-0000000000a1'),
  2,
  'another bank gets a connection of its own'
);
select results_eq(
  $$select c.aspsp_name, a.provider_account_id
    from public.accounts a join public.bank_connections c on c.id = a.connection_id
    where a.provider_account_id = 'conto-uid-9'$$,
  $$values ('Altra Banca di Prova'::text, 'conto-uid-9'::text)$$,
  'its account is a bank account of the new connection'
);

-- PayPal: the email of the account, free, already of Anna, of Bruno.
set local role service_role;
select results_eq(
  $$select account_count from public.complete_bank_link('00000000-0000-4000-8000-000000000104', (select link from links where name = 'paypal'))$$,
  $$values (1)$$,
  'the PayPal link completes'
);

reset role;
select results_eq(
  $$select user_id, source from public.paypal_emails where email = 'anna.paypal@example.com'$$,
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid, 'linked_account'::text)$$,
  'a free email of the account is saved in lower case for Anna, from the linked account'
);
select results_eq(
  $$select a.kind, a.currency::text, a.cash_account_type, a.display_name
    from public.accounts a where a.provider_account_id = 'paypal-uid-1'$$,
  $$values ('paypal'::text, 'XXX'::text, 'OTHR'::text, 'anna.paypal@example.com'::text)$$,
  'the PayPal account is in several currencies'
);
select results_eq(
  $$select b.currency::text, b.balance_type, b.amount_cents
    from public.account_balances b
    join public.accounts a on a.id = b.account_id
    where a.provider_account_id = 'paypal-uid-1'
    order by b.currency$$,
  $$values ('EUR'::text, 'XPCD'::text, 2500::bigint), ('USD'::text, 'XPCD'::text, 1000::bigint)$$,
  'one balance for each currency'
);

set local role service_role;
select results_eq(
  $$select account_count from public.complete_bank_link('00000000-0000-4000-8000-000000000105', (select link from links where name = 'paypal_mine'))$$,
  $$values (1)$$,
  'a PayPal link with an email already of Anna completes'
);
reset role;
select results_eq(
  $$select user_id, source from public.paypal_emails where email = 'anna.altra@example.com'$$,
  $$values ('00000000-0000-4000-8000-00000000000a'::uuid, 'manual'::text)$$,
  'an email already of Anna stays as it was'
);

set local role service_role;
select results_eq(
  $$select account_count from public.complete_bank_link('00000000-0000-4000-8000-000000000106', (select link from links where name = 'paypal_taken'))$$,
  $$values (1)$$,
  'a PayPal link with the email of Bruno completes'
);
reset role;
select results_eq(
  $$select user_id, source from public.paypal_emails where email = 'bruno.paypal@example.com'$$,
  $$values ('00000000-0000-4000-8000-00000000000b'::uuid, 'manual'::text)$$,
  'the email of Bruno stays his, and Anna gets no row'
);
select results_eq(
  $$select c.aspsp_name, r.account_id, r.trigger, r.status, r.error_code, r.finished_at = now()
    from public.sync_runs r join public.bank_connections c on c.id = r.connection_id$$,
  $$values ('PayPal'::text, null::uuid, 'link'::text, 'ok'::text, 'paypal_email_taken'::text, true)$$,
  'only the taken email leaves a row in sync_runs, on the PayPal connection'
);
select is(
  (select count(*)::int from public.bank_connections where aspsp_name = 'PayPal'),
  1,
  'the three PayPal links share one connection'
);

-- Wrong shapes: invalid_link, without the value in the message.
set local role service_role;
select throws_ok(
  format(
    'select * from public.complete_bank_link(%L, (select link from links where name = %L))',
    '00000000-0000-4000-8000-00000000010b', l.name
  ),
  'P0001', 'invalid_link',
  'wrong shape refused: ' || l.name
)
from links l
where l.name in (
  'not_object', 'extra_key', 'no_session', 'valid_until_word', 'valid_until_day', 'accounts_object',
  'kind', 'account_key', 'no_name', 'no_balances', 'email_of_bank', 'same_uid', 'cents_decimal',
  'cents_text', 'cents_huge', 'reference_day', 'balance_currency', 'half_wrong'
)
order by l.name;
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-00000000010b', null)$$,
  'P0001', 'invalid_link',
  'a missing link is refused'
);

reset role;
select is_empty(
  $$select 1 from public.bank_connections where aspsp_name = 'Banca Nuova di Prova'
    union all
    select 1 from public.accounts where provider_account_id in ('conto-uid-5', 'conto-uid-6')$$,
  'a link with a wrong account leaves neither connection nor accounts'
);
select is(
  (select result from public.bank_link_requests where id = '00000000-0000-4000-8000-00000000010b'),
  null,
  'a refused link leaves the request without an outcome'
);

-- A write that fails halfway leaves everything as it was.
set local role service_role;
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-00000000010c', (select link from links where name = 'conflict'))$$,
  'P0001', 'invalid_link',
  'a link whose accounts clash in the database is refused with the key only'
);

reset role;
select results_eq(
  $$select c.session_id, c.status,
           (select a.provider_account_id from public.accounts a where a.id = (select bank_id from first_ids))
    from public.bank_connections c where c.id = (select connection_id from first_ids)$$,
  $$values ('sessione-di-prova-2'::text, 'active'::text, 'conto-uid-2'::text)$$,
  'the existing connection and its accounts stay as they were'
);
select is_empty(
  $$select 1 from public.accounts where provider_account_id = 'conto-uid-4'$$,
  'the account written before the failure is gone'
);

-- Outcome of a link that did not complete
set local role service_role;
select lives_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-00000000010d', 'link_failed')$$,
  'finish_link_request writes the outcome of a claimed request'
);

reset role;
select results_eq(
  $$select result, used_at = now(), psu_type from public.bank_link_requests
    where id = '00000000-0000-4000-8000-00000000010d'$$,
  $$values ('link_failed'::text, true, 'business'::text)$$,
  'only the outcome changes'
);
select is(
  (select count(*)::int from public.bank_connections where member_id = '00000000-0000-4000-8000-0000000000a1'),
  3,
  'finish_link_request writes no connection'
);

set local role service_role;
select throws_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-00000000010d', 'link_cancelled')$$,
  'P0001', 'link_not_claimable',
  'a request with an outcome keeps it'
);
select throws_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-000000000107', 'link_cancelled')$$,
  'P0001', 'link_not_claimable',
  'a request not claimed takes no outcome'
);
select throws_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-0000000000ff', 'link_rejected')$$,
  'P0001', 'link_not_claimable',
  'an unknown request takes no outcome'
);
select throws_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-00000000010c', 'ok')$$,
  'P0001', 'invalid_result',
  'finish_link_request does not write ok'
);
select throws_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-00000000010c', null)$$,
  'P0001', 'invalid_result',
  'finish_link_request needs a code'
);
select lives_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-00000000010c', 'link_rejected')$$,
  'a request refused by complete_bank_link can still take its outcome'
);

-- Permissions
reset role;
select is_empty(
  $$select p.oid::regprocedure
    from pg_proc p
    where p.oid in (
        'public.eb_service_member(uuid)'::regprocedure,
        'public.check_bank_link(jsonb)'::regprocedure,
        'public.complete_bank_link(uuid, jsonb)'::regprocedure,
        'public.finish_link_request(uuid, text)'::regprocedure
      )
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))$$,
  'the app and anon execute none of the link functions'
);
select set_eq(
  $$select p.proname::text
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('eb_service_member', 'check_bank_link', 'complete_bank_link', 'finish_link_request')
      and has_function_privilege('service_role', p.oid, 'execute')$$,
  array['eb_service_member', 'check_bank_link', 'complete_bank_link', 'finish_link_request'],
  'the service role executes all of them'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$select * from public.complete_bank_link('00000000-0000-4000-8000-000000000107', (select link from links where name = 'first'))$$,
  '42501', null,
  'the app does not complete a link'
);
select throws_ok(
  $$select public.eb_service_member('00000000-0000-4000-8000-0000000000a1')$$,
  '42501', null,
  'the app does not read the member of a service call'
);

set local role anon;
select throws_ok(
  $$select public.finish_link_request('00000000-0000-4000-8000-000000000107', 'link_failed')$$,
  '42501', null,
  'anon does not write an outcome'
);

select * from finish();
rollback;
