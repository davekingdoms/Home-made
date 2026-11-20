-- Import of the bank rows and requests of the syncs
-- (docs/spec/sincronizzazione.md, 4, 5, 6, 9 and 12): ingest_bank_rows with
-- the rows of the synthetic data normalized as eb-sync sends them (cases 1,
-- 2, 3, 10 and 16, each imported again to check that nothing is added),
-- request_bank_sync, the new counts of sync_runs, permissions. Invented
-- users: Anna (a1) and Bruno (b1) in "Casa di prova", Dario (d1) in another
-- household. Rows from supabase/functions/_shared/testdata/eb/, normalized
-- with normalizeTransaction; payloads without their null fields. Start
-- date of the members: 2031-03-01.
begin;

create extension if not exists pgtap with schema extensions;

select plan(85);

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

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000d', 'Dario');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', '2031-03-01'),
  ('00000000-0000-4000-8000-0000000000f2', 'Altra casa di prova', '2031-03-01');
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', '2031-03-01'),
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', '2031-03-01'),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', '2031-03-01');

insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, session_id, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', 'sessione-di-prova-1', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000a1',
   'Banca Prepagata di Prova', 'IT', 'sessione-di-prova-2', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', 'sessione-di-prova-3', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000b1',
   'Banca di Prova', 'IT', 'sessione-di-prova-4', false, 'active');

-- Anna: a card and a current account of the same bank, a prepaid account,
-- PayPal. Bruno: a current account, then he leaves the household.
insert into public.accounts (
  id, household_id, owner_member_id, kind, connection_id, provider_account_id,
  cash_account_type, currency, display_name, identifier
) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1',
   'carta-uid-1', 'CARD', 'EUR', 'Carta …0001', '000000******0001'),
  ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1',
   'conto-uid-1', 'CACC', 'EUR', 'Banca di Prova …0001', 'IT00A0000000000000000000001'),
  ('00000000-0000-4000-8000-0000000000c3', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e2',
   'conto-uid-2', 'CACC', 'EUR', 'Banca Prepagata di Prova …0002', 'IT00A0000000000000000000002'),
  ('00000000-0000-4000-8000-0000000000c4', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'paypal', '00000000-0000-4000-8000-0000000000e3',
   'paypal-uid-1', 'OTHR', 'XXX', 'anna.paypal@example.com', 'anna.paypal@example.com'),
  ('00000000-0000-4000-8000-0000000000c5', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000b1', 'bank', '00000000-0000-4000-8000-0000000000e4',
   'conto-uid-5', 'CACC', 'EUR', 'Banca di Prova …0005', 'IT00A0000000000000000000005');

update public.members set left_at = now() where id = '00000000-0000-4000-8000-0000000000b1';

-- The normalized rows of each page, as eb-sync sends them.
create temp table pages (name text primary key, rows jsonb not null);
grant select on pages to service_role;

insert into pages (name, rows) values
  -- credem-card/transactions-day-1.json
  ('card_day_1', $$[
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-05","amount_cents":-1250,"currency":"EUR","dedup_hash":"f1ee08af3530d2cdae64fc84200bea365809c0e0729321b4e4f42ecde9cfa424","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"FERRAMENTA PROVA CITTAPROVA IT","counterparty":"FERRAMENTA PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"12.50"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-05","remittance_information":["FERRAMENTA PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-05","amount_cents":-440,"currency":"EUR","dedup_hash":"338c5b2f0b78dd1a5726de6793b9707980c7a52bf43405eb2465cc3431438152","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"EDICOLA PROVA CITTAPROVA IT","counterparty":"EDICOLA PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"4.4"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-05","remittance_information":["EDICOLA PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-06","amount_cents":-100,"currency":"EUR","dedup_hash":"6c194027c98f76659e1c47588bb39d9ad606f2cd8cc9bc56c0a64ed5bec232d7","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"PARCHEGGIO PROVA CITTAPROVA IT","counterparty":"PARCHEGGIO PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-06","remittance_information":["PARCHEGGIO PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-06","amount_cents":-713,"currency":"EUR","dedup_hash":"8fa9adb57b2cef4d878221f3ed86f08ae74d54de0f84251c6410e57de8740583","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"LIBRERIA ESEMPIO CITTAPROVA IT","counterparty":"LIBRERIA ESEMPIO","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"7.125"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-06","remittance_information":["LIBRERIA ESEMPIO CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-07","amount_cents":-120,"currency":"EUR","dedup_hash":"41a6e172d6bac4ce7559aecbceaf04310b3f5cf1812412efd0c9f5c677df645c","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"CAFFE PROVA CITTAPROVA IT","counterparty":"CAFFE PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"1.20"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-07","remittance_information":["CAFFE PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-07","amount_cents":-120,"currency":"EUR","dedup_hash":"41a6e172d6bac4ce7559aecbceaf04310b3f5cf1812412efd0c9f5c677df645c","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"CAFFE PROVA CITTAPROVA IT","counterparty":"CAFFE PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"1.20"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-07","remittance_information":["CAFFE PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-18","amount_cents":12050,"currency":"EUR","dedup_hash":"5d899a682d6f10a8e5d9d0d3d78c9314ce578ed305927b9bc0279fca9bca775e","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"PAGAMENTO SALDO CARTA","counterparty":null,"counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"120.5"},"credit_debit_indicator":"CRDT","status":"BOOK","transaction_date":"2031-03-18","remittance_information":["PAGAMENTO SALDO CARTA"]}}
  ]$$),
  -- credem-card/transactions-day-2.json
  ('card_day_2', $$[
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-05","amount_cents":-1250,"currency":"EUR","dedup_hash":"f1ee08af3530d2cdae64fc84200bea365809c0e0729321b4e4f42ecde9cfa424","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"FERRAMENTA PROVA CITTAPROVA IT","counterparty":"FERRAMENTA PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"12.50"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-05","remittance_information":["FERRAMENTA PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-05","amount_cents":-440,"currency":"EUR","dedup_hash":"338c5b2f0b78dd1a5726de6793b9707980c7a52bf43405eb2465cc3431438152","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"EDICOLA PROVA CITTAPROVA IT","counterparty":"EDICOLA PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"4.4"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-05","remittance_information":["EDICOLA PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-06","amount_cents":-100,"currency":"EUR","dedup_hash":"6c194027c98f76659e1c47588bb39d9ad606f2cd8cc9bc56c0a64ed5bec232d7","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"PARCHEGGIO PROVA CITTAPROVA IT","counterparty":"PARCHEGGIO PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-06","remittance_information":["PARCHEGGIO PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-06","amount_cents":-713,"currency":"EUR","dedup_hash":"8fa9adb57b2cef4d878221f3ed86f08ae74d54de0f84251c6410e57de8740583","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"LIBRERIA ESEMPIO CITTAPROVA IT","counterparty":"LIBRERIA ESEMPIO","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"7.125"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-06","remittance_information":["LIBRERIA ESEMPIO CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-07","amount_cents":-120,"currency":"EUR","dedup_hash":"41a6e172d6bac4ce7559aecbceaf04310b3f5cf1812412efd0c9f5c677df645c","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"CAFFE PROVA CITTAPROVA IT","counterparty":"CAFFE PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"1.20"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-07","remittance_information":["CAFFE PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-07","amount_cents":-120,"currency":"EUR","dedup_hash":"41a6e172d6bac4ce7559aecbceaf04310b3f5cf1812412efd0c9f5c677df645c","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"CAFFE PROVA CITTAPROVA IT","counterparty":"CAFFE PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"1.20"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-07","remittance_information":["CAFFE PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-07","amount_cents":-120,"currency":"EUR","dedup_hash":"41a6e172d6bac4ce7559aecbceaf04310b3f5cf1812412efd0c9f5c677df645c","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"CAFFE PROVA CITTAPROVA IT","counterparty":"CAFFE PROVA","counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"1.20"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-07","remittance_information":["CAFFE PROVA CITTAPROVA IT"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-18","amount_cents":12050,"currency":"EUR","dedup_hash":"5d899a682d6f10a8e5d9d0d3d78c9314ce578ed305927b9bc0279fca9bca775e","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"PAGAMENTO SALDO CARTA","counterparty":null,"counterparty_email":null,"bank_code":null,"payload":{"transaction_amount":{"currency":"EUR","amount":"120.5"},"credit_debit_indicator":"CRDT","status":"BOOK","transaction_date":"2031-03-18","remittance_information":["PAGAMENTO SALDO CARTA"]}}
  ]$$),
  -- credem-cacc/transactions-page-1.json
  ('cacc_page_1', $$[
    {"entry_reference":"0000000000-20310302-0000101-001","status":"BOOK","booking_date":"2031-03-02","value_date":"2031-02-27","transaction_date":null,"amount_cents":-2390,"currency":"EUR","dedup_hash":"cb0f2792b96e4c573ff6e6df68b4b98baf5f31d0627063004952802366d166bb","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"BANCOMAT 27/02/31,ORE 19:45,TESS.00000000 PIZZERIA ESEMPIO","counterparty":"PIZZERIA ESEMPIO","counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"0000000000-20310302-0000101-001","transaction_amount":{"currency":"EUR","amount":"23.90"},"debtor":{},"debtor_account":{"iban":"IT00A0000000000000000001234"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-02","value_date":"2031-02-27","remittance_information":["BANCOMAT 27/02/31,ORE 19:45,TESS.00000000 PIZZERIA ESEMPIO"]}},
    {"entry_reference":"0000000000-20310303-0000102-001","status":"BOOK","booking_date":"2031-03-03","value_date":"2031-03-03","transaction_date":null,"amount_cents":-8000,"currency":"EUR","dedup_hash":"7aa11138ab550fbbea39158e634a1d42be9b9acb5b1c52518d12138d5bdf989a","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"PAGAMENTO CBILL ESEMPIO SERVIZI","counterparty":"ESEMPIO SERVIZI","counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"0000000000-20310303-0000102-001","transaction_amount":{"currency":"EUR","amount":"80.00"},"debtor":{},"debtor_account":{"iban":"IT00A0000000000000000001234"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-03","value_date":"2031-03-03","remittance_information":["PAGAMENTO CBILL ESEMPIO SERVIZI"]}},
    {"entry_reference":"0000000000-20310303-0000102-002","status":"BOOK","booking_date":"2031-03-03","value_date":"2031-03-03","transaction_date":null,"amount_cents":-150,"currency":"EUR","dedup_hash":"ca4243d312fad831cf522f95934f7b39809b76d75783d8a49b2b96c6c13fbc80","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"COMM. PAG. CBILL","counterparty":null,"counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"0000000000-20310303-0000102-002","transaction_amount":{"currency":"EUR","amount":"1.5"},"debtor":{},"debtor_account":{"iban":"IT00A0000000000000000001234"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-03","value_date":"2031-03-03","remittance_information":["COMM. PAG. CBILL"]}},
    {"entry_reference":"0000000000-20310304-0000104-001","status":"BOOK","booking_date":"2031-03-04","value_date":"2031-03-03","transaction_date":null,"amount_cents":-350,"currency":"EUR","dedup_hash":"6054e3dae3fca3d9ae471e0bac7f1616a33eef2a5fc6a9829728808d347431a6","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"BANCOMAT 03/03/31,ORE 12:34,TESS.00000000 BAR ESEMPIO","counterparty":"BAR ESEMPIO","counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"0000000000-20310304-0000104-001","transaction_amount":{"currency":"EUR","amount":"3.5"},"debtor":{},"debtor_account":{"iban":"IT00A0000000000000000001234"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-04","value_date":"2031-03-03","remittance_information":["BANCOMAT 03/03/31,ORE 12:34,TESS.00000000 BAR ESEMPIO"]}},
    {"entry_reference":"0000000000-20310305-0000105-001","status":"BOOK","booking_date":"2031-03-05","value_date":"2031-03-05","transaction_date":null,"amount_cents":185000,"currency":"EUR","dedup_hash":"b0edf0ac259afb0d09a5137bbc8d9bde9c2bb2fe8526155a315c1f07292304b8","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO","counterparty":"DITTA ESEMPIO SRL","counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"0000000000-20310305-0000105-001","transaction_amount":{"currency":"EUR","amount":"1850.00"},"creditor_account":{"iban":"IT00A0000000000000000001234"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-05","value_date":"2031-03-05","remittance_information":["EMOLUMENTI DITTA ESEMPIO SRL","STIPENDIO MARZO"]}},
    {"entry_reference":"0000000000-20310309-0000106-001","status":"BOOK","booking_date":"2031-03-09","value_date":"2031-03-09","transaction_date":null,"amount_cents":2500,"currency":"EUR","dedup_hash":"2ab96cef2606b421297e0d2e7605a686aa1e75cd0859ecc3585992d1f2293598","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"BONIFICO A VOSTRO FAVORE","counterparty":"PAYPAL EUROPE S.A R.L. ET CIE S.C.A.","counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"0000000000-20310309-0000106-001","transaction_amount":{"currency":"EUR","amount":"25.00"},"creditor_account":{"iban":"IT00A0000000000000000001234"},"debtor":{"name":"PAYPAL EUROPE S.A R.L. ET CIE S.C.A."},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-09","value_date":"2031-03-09","remittance_information":["BONIFICO A VOSTRO FAVORE"]}},
    {"entry_reference":"0000000000-20310310-0000107-001","status":"BOOK","booking_date":"2031-03-10","value_date":"2031-03-10","transaction_date":null,"amount_cents":-6430,"currency":"EUR","dedup_hash":"23304767f1f0bb63c391c790e60a36556ccbc3bf6707a72638e2be695c3d4a11","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"SEPA DD CORE DA ESEMPIO ENERGIA SPA MANDATO XX000000","counterparty":"ESEMPIO ENERGIA SPA","counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"0000000000-20310310-0000107-001","transaction_amount":{"currency":"EUR","amount":"64.30"},"debtor":{},"debtor_account":{"iban":"IT00A0000000000000000001234"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-10","value_date":"2031-03-10","remittance_information":["SEPA DD CORE DA ESEMPIO ENERGIA SPA MANDATO XX000000"]}}
  ]$$),
  -- paypal/transactions-anna-sync-1.json
  ('paypal_sync_1', $$[
    {"entry_reference":"PP0000000000000001","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-02-10","amount_cents":-9000,"currency":"EUR","dedup_hash":"bb9d375be0baf536347b27daa4c52c9fd5044145d10bccc0e5fb1bf230ea3642","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"Ordine Negozio Esempio","counterparty":"Negozio Esempio","counterparty_email":"negozio@example.com","bank_code":"PAYMENT/PAYMENT","payload":{"entry_reference":"PP0000000000000001","transaction_amount":{"currency":"EUR","amount":"90.00"},"creditor":{"name":"Negozio Esempio","contact_details":{"email_address":"negozio@example.com"}},"bank_transaction_code":{"code":"PAYMENT","sub_code":"PAYMENT"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-02-10","remittance_information":["Ordine Negozio Esempio"]}},
    {"entry_reference":"PP0000000000000002","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-02-10","amount_cents":-3000,"currency":"EUR","dedup_hash":"f29d5f7afd3ba05d873787ad5f5b7e237cc7781e2760c0c9505b7783838f143d","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":null,"counterparty":"PayPal","counterparty_email":null,"bank_code":"PAYMENT/LOAN","payload":{"entry_reference":"PP0000000000000002","transaction_amount":{"currency":"EUR","amount":"30.00"},"creditor":{"name":"PayPal"},"bank_transaction_code":{"code":"PAYMENT","sub_code":"LOAN"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-02-10","remittance_information":[]}},
    {"entry_reference":"PP0000000000000010","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-05","amount_cents":-6000,"currency":"EUR","dedup_hash":"e0449129ee461fd4dce15c949781ad5087f0f37f2cf2708d8a0e011d4d8d0973","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":null,"counterparty":"Elettronica Esempio","counterparty_email":"elettronica@example.com","bank_code":"PAYMENT/PAYMENT","payload":{"entry_reference":"PP0000000000000010","transaction_amount":{"currency":"EUR","amount":"60.00"},"creditor":{"name":"Elettronica Esempio","contact_details":{"email_address":"elettronica@example.com"}},"bank_transaction_code":{"code":"PAYMENT","sub_code":"PAYMENT"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-05","remittance_information":[]}},
    {"entry_reference":"PP0000000000000005","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-06","amount_cents":-2000,"currency":"EUR","dedup_hash":"0a7611ee309c1fff0b07ca3437b72b8355d5eba7d8f6e4848a93b8a2c9fe4a39","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"Cena di prova","counterparty":"Bruno Esempio","counterparty_email":"bruno.paypal@example.com","bank_code":"PAYMENT/PAYMENT","payload":{"entry_reference":"PP0000000000000005","transaction_amount":{"currency":"EUR","amount":"20.00"},"creditor":{"name":"Bruno Esempio","contact_details":{"email_address":"Bruno.Paypal@Example.com"}},"bank_transaction_code":{"code":"PAYMENT","sub_code":"PAYMENT"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-06","remittance_information":["Cena di prova"]}},
    {"entry_reference":"PP0000000000000006","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-08","amount_cents":-2500,"currency":"EUR","dedup_hash":"2e8adee859d4f9c608494e304f636555bb3162bb89c7a2ab352f932a2359e98a","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"Trasferimento sul conto bancario","counterparty":null,"counterparty_email":null,"bank_code":null,"payload":{"entry_reference":"PP0000000000000006","transaction_amount":{"currency":"EUR","amount":"25.00"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-08","remittance_information":["Trasferimento sul conto bancario"]}},
    {"entry_reference":"PP0000000000000007","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-10","amount_cents":-1500,"currency":"EUR","dedup_hash":"aa0df3efd23dad0b0b7cf55fcd3826e82f61ee856b9364a4400e905f53c86dbf","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":null,"counterparty":"Libreria Esempio","counterparty_email":"libreria@example.com","bank_code":"PAYMENT/PAYMENT","payload":{"entry_reference":"PP0000000000000007","transaction_amount":{"currency":"EUR","amount":"15.00"},"creditor":{"name":"Libreria Esempio","contact_details":{"email_address":"libreria@example.com"}},"bank_transaction_code":{"code":"PAYMENT","sub_code":"PAYMENT"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-10","remittance_information":[]}},
    {"entry_reference":"PP0000000000000008","status":"RJCT","booking_date":null,"value_date":null,"transaction_date":"2031-03-11","amount_cents":-1200,"currency":"EUR","dedup_hash":"65b0fa597bc9e99b6861aa28d24fdfaf7ff85c3d3baa281c83349c9d82cdda72","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":null,"counterparty":"Negozio Prova","counterparty_email":"negozio.prova@example.com","bank_code":"PAYMENT/PAYMENT","payload":{"entry_reference":"PP0000000000000008","transaction_amount":{"currency":"EUR","amount":"12.00"},"creditor":{"name":"Negozio Prova","contact_details":{"email_address":"negozio.prova@example.com"}},"bank_transaction_code":{"code":"PAYMENT","sub_code":"PAYMENT"},"credit_debit_indicator":"DBIT","status":"RJCT","transaction_date":"2031-03-11","remittance_information":[]}},
    {"entry_reference":"PP0000000000000003","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-12","amount_cents":-3000,"currency":"EUR","dedup_hash":"4f8724fb61d5aaa904f023f3ca61bba0e253cc6e7eb88159e6a81b64abec7ba6","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":null,"counterparty":"PayPal","counterparty_email":null,"bank_code":"PAYMENT/LOAN","payload":{"entry_reference":"PP0000000000000003","transaction_amount":{"currency":"EUR","amount":"30.00"},"creditor":{"name":"PayPal"},"bank_transaction_code":{"code":"PAYMENT","sub_code":"LOAN"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-12","remittance_information":[]}},
    {"entry_reference":"PP0000000000000009","status":"BOOK","booking_date":null,"value_date":null,"transaction_date":"2031-03-13","amount_cents":-920,"currency":"EUR","dedup_hash":"6cb0ca30bf20e81d6e9e0ecf0c19ec02ded33a2bb8cdc023f223bce9d6148d47","original_amount_cents":-1000,"original_currency":"USD","exchange_rate":"1.0870","description":null,"counterparty":"App Esempio","counterparty_email":"app@example.com","bank_code":"PAYMENT/PAYMENT","payload":{"entry_reference":"PP0000000000000009","transaction_amount":{"currency":"EUR","amount":"9.20"},"creditor":{"name":"App Esempio","contact_details":{"email_address":"app@example.com"}},"bank_transaction_code":{"code":"PAYMENT","sub_code":"PAYMENT"},"credit_debit_indicator":"DBIT","status":"BOOK","transaction_date":"2031-03-13","remittance_information":[],"exchange_rate":{"unit_currency":"USD","exchange_rate":"1.0870","instructed_amount":{"currency":"USD","amount":"10.00"}}}}
  ]$$),
  -- hype/transactions-sync-1.json
  ('hype_sync_1', $$[
    {"entry_reference":null,"status":"BOOK","booking_date":"2031-03-06","value_date":"2031-03-06","transaction_date":null,"amount_cents":-250,"currency":"EUR","dedup_hash":"ba8a6347aec9f94bde3a49a0309d380fb2f3f220d4b25178080aa5b460e657bc","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"CAFFE ESEMPIO CITTAPROVA ZZ","counterparty":"CAFFE ESEMPIO","counterparty_email":null,"bank_code":"pos","payload":{"transaction_amount":{"currency":"EUR","amount":"2.5"},"bank_transaction_code":{"code":"pos"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-06","value_date":"2031-03-06","remittance_information":["CAFFE ESEMPIO CITTAPROVA ZZ"]}},
    {"entry_reference":"HY00000000000001","status":"BOOK","booking_date":"2031-03-15","value_date":"2031-03-15","transaction_date":null,"amount_cents":5000,"currency":"EUR","dedup_hash":"af3fe7c369c545236b08b03ecc4babef195c3a6e7839ca8e16a9805ca6ed76a6","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"ANNA ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000001","transaction_amount":{"currency":"EUR","amount":"50.00"},"debtor":{"name":"ANNA ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-15","value_date":"2031-03-15","remittance_information":["RICARICA DA BONIFICO"]}},
    {"entry_reference":"HY00000000000002","status":"BOOK","booking_date":"2031-03-20","value_date":"2031-03-20","transaction_date":null,"amount_cents":3000,"currency":"EUR","dedup_hash":"1ba627ef0d26c5cf0e317d2038c1a92f57a3cdabf5505db8e5080403448a52a1","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"ANNA ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000002","transaction_amount":{"currency":"EUR","amount":"30.00"},"debtor":{"name":"ANNA ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-20","value_date":"2031-03-20","remittance_information":["RICARICA DA BONIFICO"]}},
    {"entry_reference":null,"status":"CNCL","booking_date":null,"value_date":"2031-03-21","transaction_date":null,"amount_cents":-1500,"currency":"EUR","dedup_hash":"36a31c22972b0b5e885aeb896b236f0e081be335fa8ebc10a6a3f64501cc473e","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"NEGOZIO PROVA CITTAPROVA ZZ","counterparty":"NEGOZIO PROVA","counterparty_email":null,"bank_code":"pos","payload":{"transaction_amount":{"currency":"EUR","amount":"15.00"},"bank_transaction_code":{"code":"pos"},"credit_debit_indicator":"DBIT","status":"CNCL","value_date":"2031-03-21","remittance_information":["NEGOZIO PROVA CITTAPROVA ZZ"]}},
    {"entry_reference":"HY00000000000003","status":"BOOK","booking_date":"2031-03-21","value_date":"2031-03-21","transaction_date":null,"amount_cents":3000,"currency":"EUR","dedup_hash":"ee246212a9c5adfc32fc9948814ce75175fb41cb8a95fa812b5229ee3c32d803","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"ANNA ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000003","transaction_amount":{"currency":"EUR","amount":"30.00"},"debtor":{"name":"ANNA ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-21","value_date":"2031-03-21","remittance_information":["RICARICA DA BONIFICO"]}},
    {"entry_reference":null,"status":"PDNG","booking_date":null,"value_date":"2031-03-22","transaction_date":null,"amount_cents":-380,"currency":"EUR","dedup_hash":"e6ec8a2641acb9778c2f35d5181a376336f76a5e32de64b254bf040f5790c1a0","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"PANETTERIA PROVA CITTAPROVA ZZ","counterparty":"PANETTERIA PROVA","counterparty_email":null,"bank_code":"pos","payload":{"transaction_amount":{"currency":"EUR","amount":"3.80"},"bank_transaction_code":{"code":"pos"},"credit_debit_indicator":"DBIT","status":"PDNG","value_date":"2031-03-22","remittance_information":["PANETTERIA PROVA CITTAPROVA ZZ"]}},
    {"entry_reference":"HY00000000000004","status":"PDNG","booking_date":null,"value_date":"2031-03-22","transaction_date":null,"amount_cents":2000,"currency":"EUR","dedup_hash":"8d56254c551f4e56f115784bbc4972011de64f5dd9e05903ca87e4bb8c844900","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"BRUNO ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000004","transaction_amount":{"currency":"EUR","amount":"20.00"},"debtor":{"name":"BRUNO ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"PDNG","value_date":"2031-03-22","remittance_information":["RICARICA DA BONIFICO"]}}
  ]$$),
  -- hype/transactions-sync-2.json
  ('hype_sync_2', $$[
    {"entry_reference":null,"status":"BOOK","booking_date":"2031-03-06","value_date":"2031-03-06","transaction_date":null,"amount_cents":-250,"currency":"EUR","dedup_hash":"ba8a6347aec9f94bde3a49a0309d380fb2f3f220d4b25178080aa5b460e657bc","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"CAFFE ESEMPIO CITTAPROVA ZZ","counterparty":"CAFFE ESEMPIO","counterparty_email":null,"bank_code":"pos","payload":{"transaction_amount":{"currency":"EUR","amount":"2.5"},"bank_transaction_code":{"code":"pos"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-06","value_date":"2031-03-06","remittance_information":["CAFFE ESEMPIO CITTAPROVA ZZ"]}},
    {"entry_reference":"HY00000000000001","status":"BOOK","booking_date":"2031-03-15","value_date":"2031-03-15","transaction_date":null,"amount_cents":5000,"currency":"EUR","dedup_hash":"af3fe7c369c545236b08b03ecc4babef195c3a6e7839ca8e16a9805ca6ed76a6","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"ANNA ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000001","transaction_amount":{"currency":"EUR","amount":"50.00"},"debtor":{"name":"ANNA ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-15","value_date":"2031-03-15","remittance_information":["RICARICA DA BONIFICO"]}},
    {"entry_reference":"HY00000000000002","status":"BOOK","booking_date":"2031-03-20","value_date":"2031-03-20","transaction_date":null,"amount_cents":3000,"currency":"EUR","dedup_hash":"1ba627ef0d26c5cf0e317d2038c1a92f57a3cdabf5505db8e5080403448a52a1","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"ANNA ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000002","transaction_amount":{"currency":"EUR","amount":"30.00"},"debtor":{"name":"ANNA ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-20","value_date":"2031-03-20","remittance_information":["RICARICA DA BONIFICO"]}},
    {"entry_reference":null,"status":"CNCL","booking_date":null,"value_date":"2031-03-21","transaction_date":null,"amount_cents":-1500,"currency":"EUR","dedup_hash":"36a31c22972b0b5e885aeb896b236f0e081be335fa8ebc10a6a3f64501cc473e","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"NEGOZIO PROVA CITTAPROVA ZZ","counterparty":"NEGOZIO PROVA","counterparty_email":null,"bank_code":"pos","payload":{"transaction_amount":{"currency":"EUR","amount":"15.00"},"bank_transaction_code":{"code":"pos"},"credit_debit_indicator":"DBIT","status":"CNCL","value_date":"2031-03-21","remittance_information":["NEGOZIO PROVA CITTAPROVA ZZ"]}},
    {"entry_reference":"HY00000000000003","status":"BOOK","booking_date":"2031-03-21","value_date":"2031-03-21","transaction_date":null,"amount_cents":3000,"currency":"EUR","dedup_hash":"ee246212a9c5adfc32fc9948814ce75175fb41cb8a95fa812b5229ee3c32d803","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"ANNA ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000003","transaction_amount":{"currency":"EUR","amount":"30.00"},"debtor":{"name":"ANNA ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-21","value_date":"2031-03-21","remittance_information":["RICARICA DA BONIFICO"]}},
    {"entry_reference":null,"status":"BOOK","booking_date":"2031-03-23","value_date":"2031-03-22","transaction_date":null,"amount_cents":-380,"currency":"EUR","dedup_hash":"b81fdba96999b4f67a78cbb4a8008ef583388c8d84b97ced44ef2731e2bcc318","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"PANETTERIA PROVA CITTAPROVA ZZ","counterparty":"PANETTERIA PROVA","counterparty_email":null,"bank_code":"pos","payload":{"transaction_amount":{"currency":"EUR","amount":"3.80"},"bank_transaction_code":{"code":"pos"},"credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2031-03-23","value_date":"2031-03-22","remittance_information":["PANETTERIA PROVA CITTAPROVA ZZ"]}},
    {"entry_reference":"HY00000000000004","status":"BOOK","booking_date":"2031-03-23","value_date":"2031-03-22","transaction_date":null,"amount_cents":2000,"currency":"EUR","dedup_hash":"000ec45c3589ccbe68f1eae9057b174dfc2c6eb8546ed7d8b589c871f715cbe7","original_amount_cents":null,"original_currency":null,"exchange_rate":null,"description":"RICARICA DA BONIFICO","counterparty":"BRUNO ESEMPIO","counterparty_email":null,"bank_code":"boi","payload":{"entry_reference":"HY00000000000004","transaction_amount":{"currency":"EUR","amount":"20.00"},"debtor":{"name":"BRUNO ESEMPIO"},"bank_transaction_code":{"code":"boi"},"credit_debit_indicator":"CRDT","status":"BOOK","booking_date":"2031-03-23","value_date":"2031-03-22","remittance_information":["RICARICA DA BONIFICO"]}}
  ]$$);

-- The rows of a page; one row of a page by reference.
create function pg_temp.page(name text)
returns jsonb
language sql
stable
as $$
  select p.rows from pages p where p.name = page.name
$$;

create function pg_temp.page_row(name text, reference text)
returns jsonb
language sql
stable
as $$
  select e.value
  from pages p, jsonb_array_elements(p.rows) as e (value)
  where p.name = page_row.name
    and e.value ->> 'entry_reference' = page_row.reference
$$;

-- Wrong shapes: each one from the first row of the card.
create temp table bad (name text primary key, rows jsonb not null);
grant select on bad to service_role;

insert into bad (name, rows)
select v.name, v.rows
from (select p.rows -> 0 as base from pages p where p.name = 'card_day_1') b,
  lateral (values
    ('not_array', jsonb_build_object('rows', jsonb_build_array(b.base))),
    ('not_object', '[1]'::jsonb),
    ('extra_key', jsonb_build_array(b.base || '{"extra": 1}')),
    ('no_status', jsonb_build_array(b.base - 'status')),
    ('status_hold', jsonb_build_array(jsonb_set(b.base, '{status}', '"HOLD"'))),
    ('cents_decimal', jsonb_build_array(jsonb_set(b.base, '{amount_cents}', '12.5'))),
    ('cents_text', jsonb_build_array(jsonb_set(b.base, '{amount_cents}', '"-1250"'))),
    ('cents_huge', jsonb_build_array(jsonb_set(b.base, '{amount_cents}', '1e30'))),
    ('currency_lower', jsonb_build_array(jsonb_set(b.base, '{currency}', '"eur"'))),
    ('hash_short', jsonb_build_array(jsonb_set(b.base, '{dedup_hash}', '"abc"'))),
    ('payload_array', jsonb_build_array(jsonb_set(b.base, '{payload}', '[]'))),
    ('reference_blank', jsonb_build_array(jsonb_set(b.base, '{entry_reference}', '" "'))),
    ('no_date', jsonb_build_array(jsonb_set(b.base, '{transaction_date}', 'null'))),
    ('day_wrong', jsonb_build_array(jsonb_set(b.base, '{transaction_date}', '"2031-02-30"'))),
    ('date_time', jsonb_build_array(jsonb_set(b.base, '{transaction_date}', '"2031-03-05T10:00:00"'))),
    ('rate_comma', jsonb_build_array(jsonb_set(b.base, '{exchange_rate}', '"1,0870"'))),
    ('description_number', jsonb_build_array(jsonb_set(b.base, '{description}', '5'))),
    -- A new valid row next to a wrong one: nothing is written.
    ('half_wrong', jsonb_build_array(
      jsonb_set(b.base, '{dedup_hash}', to_jsonb(repeat('0', 64))),
      jsonb_set(b.base, '{currency}', '"eur"')
    ))
  ) as v (name, rows);

-- Case 1: identical rows without reference
set local role service_role;
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', pg_temp.page('card_day_1'))$$,
  $$values (7, 7, 7, 0, 0, 0, 0)$$,
  'case 1: the card rows are all saved, the two identical ones too, and become movements'
);
select results_eq(
  $$select r.dedup_ordinal, r.transaction_id is not null
    from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c1'
      and r.payload -> 'remittance_information' ->> 0 = 'CAFFE PROVA CITTAPROVA IT'
    order by r.dedup_ordinal$$,
  $$values (1, true), (2, true)$$,
  'case 1: the two identical rows get the ordinals 1 and 2, each with its movement'
);
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', pg_temp.page('card_day_1'))$$,
  $$values (7, 0, 0, 0, 0, 0, 0)$$,
  'case 1: downloaded again, no row is added'
);
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', pg_temp.page('card_day_2'))$$,
  $$values (8, 1, 1, 0, 0, 0, 0)$$,
  'case 1: a third identical row the day after, in the overlapping window: only that one is added'
);
select results_eq(
  $$select r.dedup_ordinal, r.transaction_id is not null
    from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c1'
      and r.payload -> 'remittance_information' ->> 0 = 'CAFFE PROVA CITTAPROVA IT'
    order by r.dedup_ordinal$$,
  $$values (1, true), (2, true), (3, true)$$,
  'case 1: the third one takes the ordinal 3 and its own movement'
);
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', pg_temp.page('card_day_1'))$$,
  $$values (7, 0, 0, 0, 0, 1, 0)$$,
  'case 1: an answer with fewer identical rows than saved adds nothing and counts in groups_shrunk'
);
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', pg_temp.page('card_day_2'))$$,
  $$values (8, 0, 0, 0, 0, 0, 0)$$,
  'case 1: the second day downloaded again adds nothing'
);
select results_eq(
  $$select count(*)::int, count(r.transaction_id)::int,
           (select count(*)::int from public.transactions t
            where t.account_id = '00000000-0000-4000-8000-0000000000c1')
    from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c1'$$,
  $$values (8, 8, 8)$$,
  'case 1: eight rows, eight movements: no duplicate, no row lost'
);

-- Cases 2 and 3: references, value date before the start date
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c2', pg_temp.page('cacc_page_1'))$$,
  $$values (7, 7, 6, 1, 0, 0, 0)$$,
  'cases 2 and 3: seven rows saved, six movements, one before the start date'
);
select results_eq(
  $$select r.entry_reference, t.amount_cents, t.description
    from public.bank_raw_transactions r
    join public.transactions t on t.raw_id = r.id
    where r.entry_reference like '%-0000102-%'
    order by r.entry_reference$$,
  $$values ('0000000000-20310303-0000102-001'::text, -8000::bigint, 'PAGAMENTO CBILL ESEMPIO SERVIZI'::text),
           ('0000000000-20310303-0000102-002'::text, -150::bigint, 'COMM. PAG. CBILL'::text)$$,
  'case 2: bill and fee, with references -001 and -002, are two rows and two movements'
);
select results_eq(
  $$select r.status, r.value_date, r.booking_date, r.movement_date, r.transaction_id
    from public.bank_raw_transactions r
    where r.entry_reference = '0000000000-20310302-0000101-001'$$,
  $$values ('BOOK'::text, '2031-02-27'::date, '2031-03-02'::date, '2031-02-27'::date, null::uuid)$$,
  'case 3: an expense with value date before the start date and booking date after stays only raw'
);
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c2', pg_temp.page('cacc_page_1'))$$,
  $$values (7, 0, 0, 0, 0, 0, 0)$$,
  'cases 2 and 3: downloaded again, no row is added'
);

-- PayPal from 90 days before the start date; case 10 (RJCT)
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c4', pg_temp.page('paypal_sync_1'))$$,
  $$values (9, 9, 6, 2, 1, 0, 0)$$,
  'PayPal: nine rows saved, six movements, two before the start date, one RJCT'
);
select results_eq(
  $$select r.entry_reference, r.status, r.transaction_id is null
    from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c4'
      and r.entry_reference in ('PP0000000000000001', 'PP0000000000000002', 'PP0000000000000008')
    order by r.entry_reference$$,
  $$values ('PP0000000000000001'::text, 'BOOK'::text, true),
           ('PP0000000000000002'::text, 'BOOK'::text, true),
           ('PP0000000000000008'::text, 'RJCT'::text, true)$$,
  'case 10 and the start date: the rows before it and the RJCT row stay only raw'
);
select results_eq(
  $$select t.original_amount_cents, t.original_currency::text, t.exchange_rate, t.counterparty,
           t.counterparty_email, t.bank_code
    from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id
    where r.entry_reference = 'PP0000000000000009'$$,
  $$values (-1000::bigint, 'USD'::text, 1.0870::numeric, 'App Esempio'::text, 'app@example.com'::text,
            'PAYMENT/PAYMENT'::text)$$,
  'a payment in another currency keeps the original amount, currency and rate'
);
select results_eq(
  $$select t.amount_cents, t.counterparty, t.counterparty_email
    from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id
    where r.entry_reference = 'PP0000000000000005'$$,
  $$values (-2000::bigint, 'Bruno Esempio'::text, 'bruno.paypal@example.com'::text)$$,
  'a PayPal payment keeps the email of the counterparty'
);

-- Fields of the movements (6.2)
select results_eq(
  $$select count(*)::int
    from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id
    join (
      select e.value as row
      from pages p, jsonb_array_elements(p.rows) as e (value)
      where p.name in ('cacc_page_1', 'paypal_sync_1')
    ) f on f.row ->> 'entry_reference' = r.entry_reference$$,
  $$values (12)$$,
  'the movements of the current account and of PayPal match their normalized rows'
);
select is_empty(
  $$select r.entry_reference
    from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id
    join (
      select e.value as row
      from pages p, jsonb_array_elements(p.rows) as e (value)
      where p.name in ('cacc_page_1', 'paypal_sync_1')
    ) f on f.row ->> 'entry_reference' = r.entry_reference
    where (t.amount_cents, t.currency::text, t.description, t.counterparty, t.counterparty_email,
           t.bank_code, t.original_amount_cents, t.original_currency::text, t.exchange_rate,
           t.movement_date, t.booking_date)
      is distinct from (
        (f.row ->> 'amount_cents')::bigint, f.row ->> 'currency', f.row ->> 'description',
        f.row ->> 'counterparty', f.row ->> 'counterparty_email', f.row ->> 'bank_code',
        (f.row ->> 'original_amount_cents')::bigint, f.row ->> 'original_currency',
        (f.row ->> 'exchange_rate')::numeric,
        coalesce((f.row ->> 'value_date')::date, (f.row ->> 'transaction_date')::date,
                 (f.row ->> 'booking_date')::date),
        (f.row ->> 'booking_date')::date
      )$$,
  'every movement has amount, currency, dates, description, counterparty, email and code of its row'
);
select results_eq(
  $$select bool_and(t.source = 'bank'), bool_and(t.household_id = '00000000-0000-4000-8000-0000000000f1'),
           bool_and(t.paid_by_member_id = '00000000-0000-4000-8000-0000000000a1'),
           bool_and(t.entered_by_member_id is null), bool_and(t.booking_status = 'booked'),
           bool_and(r.transaction_id = t.id and r.account_id = t.account_id)
    from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id$$,
  $$values (true, true, true, true, true, true)$$,
  'the movements come from the bank, paid by the owner of the account, linked to their raw row'
);
select results_eq(
  $$select t.amount_cents, t.counterparty
    from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id
    where r.entry_reference = '0000000000-20310305-0000105-001'$$,
  $$values (185000::bigint, 'DITTA ESEMPIO SRL'::text)$$,
  'the salary is an income with its counterparty'
);
select is_empty(
  $$select t.id
    from public.transactions t
    left join public.transaction_lines l on l.transaction_id = t.id
    left join public.line_shares s on s.line_id = l.id
    where l.id is null
       or l.kind is not null
       or l.amount_cents <> t.amount_cents
       or s.member_id is distinct from t.paid_by_member_id
       or s.amount_cents <> t.amount_cents$$,
  'every movement has its line without kind, with a share of 100% of the owner: to classify'
);
select is(
  (select count(*)::int from public.transaction_lines),
  (select count(*)::int from public.transactions),
  'one line for each movement'
);

-- Case 10 (CNCL) and case 16 (PDNG that comes back BOOK)
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c3', pg_temp.page('hype_sync_1'))$$,
  $$values (7, 7, 4, 0, 3, 0, 0)$$,
  'case 16, first sync: seven rows saved, four movements, CNCL and the two PDNG only raw'
);
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c3', pg_temp.page('hype_sync_2'))$$,
  $$values (7, 1, 2, 0, 0, 0, 0)$$,
  'case 16, second sync: the row without reference is a new row, the one with reference is updated: two movements'
);
select results_eq(
  $$select count(*)::int, min(r.status), min(r.booking_date), count(r.transaction_id)::int
    from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c3'
      and r.entry_reference = 'HY00000000000004'$$,
  $$values (1, 'BOOK'::text, '2031-03-23'::date, 1)$$,
  'case 16 with reference: the PDNG row is updated to BOOK, with its booking date and a movement'
);
select results_eq(
  $$select t.amount_cents, t.booking_date, t.movement_date
    from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id
    where r.entry_reference = 'HY00000000000004'$$,
  $$values (2000::bigint, '2031-03-23'::date, '2031-03-22'::date)$$,
  'case 16 with reference: one movement with the booked data'
);
select results_eq(
  $$select r.status, r.transaction_id is not null
    from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c3'
      and r.payload -> 'remittance_information' ->> 0 = 'PANETTERIA PROVA CITTAPROVA ZZ'
    order by r.status$$,
  $$values ('BOOK'::text, true), ('PDNG'::text, false)$$,
  'case 16 without reference: the booked row is a new row with the movement, the PDNG one stays raw'
);
select is(
  (select count(*)::int from public.transactions t
   where t.account_id = '00000000-0000-4000-8000-0000000000c3'
     and t.description = 'PANETTERIA PROVA CITTAPROVA ZZ'),
  1,
  'case 16 without reference: one movement'
);
select results_eq(
  $$select r.status, r.transaction_id is null
    from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c3'
      and r.payload -> 'remittance_information' ->> 0 = 'NEGOZIO PROVA CITTAPROVA ZZ'$$,
  $$values ('CNCL'::text, true)$$,
  'case 10: the CNCL row stays only raw'
);
select results_eq(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c3', pg_temp.page('hype_sync_2'))$$,
  $$values (7, 0, 0, 0, 0, 0, 0)$$,
  'case 16: the second sync downloaded again adds nothing'
);
select results_eq(
  $$select * from public.ingest_bank_rows(
      '00000000-0000-4000-8000-0000000000c3',
      jsonb_build_array(jsonb_set(pg_temp.page_row('hype_sync_1', 'HY00000000000001'), '{status}', '"CNCL"'))
    )$$,
  $$values (1, 0, 0, 0, 0, 0, 1)$$,
  'a row already a movement that comes back CNCL is counted in booked_then_cancelled'
);
select results_eq(
  $$select r.status, (select count(*)::int from public.transactions t where t.raw_id = r.id)
    from public.bank_raw_transactions r
    where r.entry_reference = 'HY00000000000001'$$,
  $$values ('BOOK'::text, 1)$$,
  'and stays as it was, with its movement'
);
select results_eq(
  $$select * from public.ingest_bank_rows(
      '00000000-0000-4000-8000-0000000000c3',
      jsonb_build_array(jsonb_set(
        jsonb_set(pg_temp.page_row('hype_sync_1', 'HY00000000000001'), '{entry_reference}', '"HY00000000000099"'),
        '{amount_cents}', '0'
      ))
    )$$,
  $$values (1, 1, 0, 0, 1, 0, 0)$$,
  'a booked row of zero is saved and counted in skipped_status'
);
select results_eq(
  $$select r.status, r.amount_cents, r.transaction_id is null
    from public.bank_raw_transactions r
    where r.entry_reference = 'HY00000000000099'$$,
  $$values ('BOOK'::text, 0::bigint, true)$$,
  'a row of zero stays only raw'
);
select is_empty(
  $$select 1 from public.transactions t where t.movement_date < '2031-03-01'$$,
  'no movement before the start date'
);

-- Wrong shapes: invalid_rows, without the value in the message.
select throws_ok(
  format(
    'select * from public.ingest_bank_rows(%L, (select b.rows from bad b where b.name = %L))',
    '00000000-0000-4000-8000-0000000000c1', b.name
  ),
  'P0001', 'invalid_rows',
  'wrong shape refused: ' || b.name
)
from bad b
order by b.name;
select throws_ok(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', null)$$,
  'P0001', 'invalid_rows',
  'missing rows are refused'
);
select results_eq(
  $$select count(*)::int from public.bank_raw_transactions r
    where r.account_id = '00000000-0000-4000-8000-0000000000c1'$$,
  $$values (8)$$,
  'a refused import writes nothing'
);

-- Accounts
select throws_ok(
  $$select * from public.ingest_bank_rows(
      (select a.id from public.accounts a
       where a.owner_member_id = '00000000-0000-4000-8000-0000000000a1' and a.kind = 'cash'),
      pg_temp.page('card_day_1'))$$,
  'P0001', 'account_not_found',
  'an account without a connection takes no bank rows'
);
select throws_ok(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000ff', pg_temp.page('card_day_1'))$$,
  'P0001', 'account_not_found',
  'an unknown account is refused'
);
select throws_ok(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c5', pg_temp.page('hype_sync_1'))$$,
  'P0001', 'member_not_eligible',
  'the account of a member who left takes no rows'
);
select is_empty(
  $$select 1 from public.bank_raw_transactions r where r.account_id = '00000000-0000-4000-8000-0000000000c5'$$,
  'nothing is saved on it'
);

-- New counts of sync_runs
create temp table runs (name text primary key, id uuid not null);
insert into runs
  select 'run1', run_id from public.begin_sync_run('00000000-0000-4000-8000-0000000000e1', 'admin');
select lives_ok(
  $$select public.finish_sync_run(
      (select id from runs where name = 'run1'), 'ok', null,
      '{"strategy": "longest", "accounts": [
         {"account_id": "00000000-0000-4000-8000-0000000000c1", "status": "ok", "rows_received": 8,
          "amounts_rounded": 1, "rows_invalid": 2},
         {"account_id": "00000000-0000-4000-8000-0000000000c2", "status": "ok", "rows_received": 7,
          "amounts_rounded": 3}
       ]}'
    )$$,
  'a sync closes with the rounded amounts and the invalid rows of its accounts'
);
select results_eq(
  $$select account_id, rows_received, amounts_rounded, rows_invalid
    from public.sync_runs where run_id = (select id from runs where name = 'run1')
    order by account_id$$,
  $$values ('00000000-0000-4000-8000-0000000000c1'::uuid, 8, 1, 2),
           ('00000000-0000-4000-8000-0000000000c2'::uuid, 7, 3, 0)$$,
  'each account keeps its rounded amounts and invalid rows'
);
select results_eq(
  $$select rows_received, amounts_rounded, rows_invalid
    from public.sync_runs where id = (select id from runs where name = 'run1')$$,
  $$values (15, 4, 2)$$,
  'the row of the connection has their sums'
);
insert into runs
  select 'run2', run_id from public.begin_sync_run('00000000-0000-4000-8000-0000000000e2', 'admin');
select throws_ok(
  $$select public.finish_sync_run((select id from runs where name = 'run2'), 'ok', null,
      '{"accounts": [{"account_id": "00000000-0000-4000-8000-0000000000c3", "status": "ok", "rows_invalid": -1}]}')$$,
  'P0001', 'invalid_result',
  'a negative count of invalid rows is refused'
);
reset role;
select throws_ok(
  $$insert into public.sync_runs (connection_id, trigger, status, amounts_rounded)
    values ('00000000-0000-4000-8000-0000000000e1', 'admin', 'ok', -1)$$,
  '23514', null,
  'the rounded amounts are never negative'
);

-- Request of a sync: nothing without the URL of the project, then one POST
-- to eb-sync with the secret of the jobs.
create temp table queue_start as
  select coalesce(max(q.id), 0) as id from net.http_request_queue q;
delete from vault.secrets where name = 'project_url';

set local role service_role;
select throws_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000e1', 'link')$$,
  'P0001', 'project_url_missing',
  'without the URL of the project in Vault nothing is requested'
);
select throws_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000e1', 'cron')$$,
  'P0001', 'invalid_trigger',
  'an unknown trigger is refused'
);
select throws_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000e1', null)$$,
  'P0001', 'invalid_trigger',
  'a missing trigger is refused'
);
select throws_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000ff', 'link')$$,
  'P0001', 'connection_not_found',
  'an unknown connection is refused'
);

reset role;
select is_empty(
  $$select 1 from net.http_request_queue q where q.id > (select id from queue_start)$$,
  'no request is queued'
);
select vault.create_secret('ftp://progetto-di-prova.example.com', 'project_url');
set local role service_role;
select throws_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000e1', 'link')$$,
  'P0001', 'project_url_missing',
  'a URL of the project that is not http(s) is refused'
);

reset role;
select vault.update_secret(
  (select s.id from vault.secrets s where s.name = 'project_url'),
  'https://progetto-di-prova.example.com/'
);
set local role service_role;
select lives_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000e1', 'link')$$,
  'a sync is requested'
);

reset role;
select results_eq(
  $$select q.method::text, q.url, convert_from(q.body, 'utf8')::jsonb, q.headers ->> 'Content-Type',
           (select array_agg(k order by k) from jsonb_object_keys(q.headers) as k)
    from net.http_request_queue q
    where q.id > (select id from queue_start)$$,
  $$values ('POST'::text, 'https://progetto-di-prova.example.com/functions/v1/eb-sync'::text,
            '{"connection_id": "00000000-0000-4000-8000-0000000000e1", "trigger": "link"}'::jsonb,
            'application/json'::text, array['Content-Type', 'x-sync-secret'])$$,
  'one POST to eb-sync with the connection and the trigger'
);
select ok(
  public.sync_secret_matches((
    select q.headers ->> 'x-sync-secret' from net.http_request_queue q
    where q.id > (select id from queue_start)
  )),
  'the request carries the secret of the jobs'
);
delete from vault.secrets where name = 'sync_cron_secret';
set local role service_role;
select throws_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000e1', 'link')$$,
  'P0001', 'sync_secret_missing',
  'without the secret of the jobs nothing is requested'
);
reset role;
select is(
  (select count(*)::int from net.http_request_queue q where q.id > (select id from queue_start)),
  1,
  'only the accepted request is queued'
);

-- Permissions
select is_empty(
  $$select p.oid::regprocedure
    from pg_proc p
    where p.oid in (
        'public.ingest_bank_rows(uuid, jsonb)'::regprocedure,
        'public.request_bank_sync(uuid, text)'::regprocedure
      )
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))$$,
  'the app and anon execute neither the import nor the request'
);
select ok(
  has_function_privilege('service_role', 'public.ingest_bank_rows(uuid, jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.request_bank_sync(uuid, text)', 'execute'),
  'the service role executes both'
);
select is_empty(
  $$select r
    from unnest(array['anon', 'authenticated']) r
    where has_table_privilege(r, 'public.bank_raw_transactions', 'select, insert, update, delete, truncate')
       or has_any_column_privilege(r, 'public.bank_raw_transactions', 'select, insert, update')$$,
  'the app and anon have no privilege on the raw rows'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  'select id from public.bank_raw_transactions',
  '42501', null,
  'the app does not read the raw rows'
);
select throws_ok(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', '[]')$$,
  '42501', null,
  'the app does not import rows'
);
select throws_ok(
  $$select public.request_bank_sync('00000000-0000-4000-8000-0000000000e1', 'manual')$$,
  '42501', null,
  'the app does not request syncs through the function'
);
select is(
  (select count(*)::int from public.transactions),
  26,
  'Anna sees the movements imported on her accounts'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is_empty('select 1 from public.transactions', 'Dario does not see them');

set local role anon;
select throws_ok(
  'select id from public.bank_raw_transactions',
  '42501', null,
  'anon does not read the raw rows'
);
select throws_ok(
  $$select * from public.ingest_bank_rows('00000000-0000-4000-8000-0000000000c1', '[]')$$,
  '42501', null,
  'anon does not import rows'
);

select * from finish();
rollback;
