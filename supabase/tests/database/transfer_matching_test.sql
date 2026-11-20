-- Automatic transfers after a sync (docs/spec/sincronizzazione.md, 7, 7.1, 9
-- and 12): transfer_candidates and apply_transfers with the movements of the
-- synthetic data (cases 6, 7, 8, 9, 18 and 19), applied twice, with the
-- checks done again, the lock on the member, wrong shapes and permissions.
-- The rules that choose the transfers are in TypeScript
-- (supabase/functions/_shared/match/transfers_test.ts): the transfers
-- applied here are the ones they propose for the same movements.
-- Invented users: Anna (a1) and Bruno (b1) in "Casa di prova", Dario (d1)
-- in another household, a former member (a9). Start date: 2031-03-01.
begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

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

create function pg_temp.check_deferred()
returns void
language plpgsql
as $$
begin
  set constraints all immediate;
  set constraints all deferred;
end;
$$;

-- Ids: accounts ...c1 to ...c6, movements ...000000000101 and following.
create function pg_temp.acc(code text)
returns uuid
language sql
immutable
as $$
  select ('00000000-0000-4000-8000-0000000000' || code)::uuid
$$;

create function pg_temp.tx(n int)
returns uuid
language sql
immutable
as $$
  select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;

-- A proposal as eb-sync sends it: accounts by code, movements by number.
create function pg_temp.proposal(from_code text, to_code text, out_n int, in_n int, funded_n int)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'from_account_id', pg_temp.acc(from_code),
    'to_account_id', pg_temp.acc(to_code),
    'out_transaction_id', pg_temp.tx(out_n),
    'in_transaction_id', pg_temp.tx(in_n),
    'funded_transaction_id', pg_temp.tx(funded_n)
  )
$$;

-- The movement fields eb-sync reads, by number.
create function pg_temp.candidate(n int)
returns jsonb
language sql
as $$
  select m
  from jsonb_array_elements(
    public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
  ) as e (m)
  where (m ->> 'transaction_id')::uuid = pg_temp.tx(candidate.n)
$$;

-- Kind and transfer of the line of a movement.
create function pg_temp.line_of(n int)
returns table (kind text, transfer_id uuid)
language sql
as $$
  select l.kind, l.transfer_id
  from public.transaction_lines l
  where l.transaction_id = pg_temp.tx(line_of.n)
    and l.deleted_at is null
$$;

-- The advisory lock of a member is held by this session.
create function pg_temp.member_locked(member_id uuid)
returns boolean
language sql
as $$
  with k as (select hashtextextended('matches:' || member_locked.member_id::text, 0) as key)
  select exists (
    select 1
    from pg_locks l, k
    where l.locktype = 'advisory'
      and l.pid = pg_backend_pid()
      and l.objsubid = 1
      and l.classid::bigint = ((k.key >> 32) & 4294967295)
      and l.objid::bigint = (k.key & 4294967295)
  )
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
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000a9', '00000000-0000-4000-8000-0000000000f1',
   null, '2031-03-01', now());

insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, session_id, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Credito Emiliano', 'IT', 'sessione-di-prova-1', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000a1',
   'HYPE', 'IT', 'sessione-di-prova-2', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', 'sessione-di-prova-3', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000b1',
   'Credito Emiliano', 'IT', 'sessione-di-prova-4', false, 'active');

-- Anna: the card and the current account of the same bank, an old card
-- archived, a prepaid account, PayPal. Bruno: a current account, no PayPal.
insert into public.accounts (
  id, household_id, owner_member_id, kind, connection_id, provider_account_id,
  cash_account_type, currency, display_name, identifier, archived_at
) values
  (pg_temp.acc('c1'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1',
   'carta-uid-1', 'CARD', 'EUR', 'Carta …0001', '000000******0001', null),
  (pg_temp.acc('c2'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1',
   'conto-uid-1', 'CACC', 'EUR', 'Credito Emiliano …1234', 'IT00A0000000000000000001234', null),
  (pg_temp.acc('c3'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e2',
   'conto-uid-2', 'CACC', 'EUR', 'HYPE …5678', 'IT00A0000000000000000005678', null),
  (pg_temp.acc('c4'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'paypal', '00000000-0000-4000-8000-0000000000e3',
   'paypal-uid-1', 'OTHR', 'XXX', 'anna.paypal@example.com', 'anna.paypal@example.com', null),
  (pg_temp.acc('c5'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000b1', 'bank', '00000000-0000-4000-8000-0000000000e4',
   'conto-uid-5', 'CACC', 'EUR', 'Credito Emiliano …0005', 'IT00A0000000000000000000005', null),
  (pg_temp.acc('c6'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'card', '00000000-0000-4000-8000-0000000000e1',
   'carta-uid-6', 'CARD', 'EUR', 'Carta …0006', '000000******0006', '2031-03-02 10:00+00');

-- The movements of the synthetic data (credem-cacc pages 1 and 2,
-- credem-card day 1, hype sync 1, paypal sync 1 of Anna), as
-- ingest_bank_rows creates them; Bruno has the charge of case 7.
create function pg_temp.movement(
  n int, account_code text, movement_date date, amount_cents bigint,
  description text, counterparty text
)
returns void
language sql
as $$
  insert into public.transactions (
    id, household_id, account_id, source, paid_by_member_id, movement_date,
    booking_date, amount_cents, currency, description, counterparty
  )
  select pg_temp.tx(movement.n), a.household_id, a.id, 'bank', a.owner_member_id,
         movement.movement_date, movement.movement_date, movement.amount_cents, 'EUR',
         movement.description, movement.counterparty
  from public.accounts a
  where a.id = pg_temp.acc(movement.account_code)
$$;

select pg_temp.movement(104, 'c2', '2031-03-03', -350,
  'BANCOMAT 03/03/31,ORE 12:34,TESS.00000000 BAR ESEMPIO', 'BAR ESEMPIO');
select pg_temp.movement(105, 'c2', '2031-03-05', 185000,
  'EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO', 'DITTA ESEMPIO SRL');
select pg_temp.movement(106, 'c2', '2031-03-09', 2500,
  'BONIFICO A VOSTRO FAVORE', 'PAYPAL EUROPE S.A R.L. ET CIE S.C.A.');
select pg_temp.movement(107, 'c2', '2031-03-10', -6430,
  'SEPA DD CORE DA ESEMPIO ENERGIA SPA MANDATO XX000000', 'ESEMPIO ENERGIA SPA');
select pg_temp.movement(102, 'c2', '2031-03-03', -8000,
  'PAGAMENTO CBILL ESEMPIO SERVIZI', 'ESEMPIO SERVIZI');
select pg_temp.movement(108, 'c2', '2031-03-12', -1500,
  'SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001',
  'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.');
select pg_temp.movement(109, 'c2', '2031-03-14', -999,
  'SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001',
  'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.');
select pg_temp.movement(110, 'c2', '2031-03-15', -5000,
  'BON. ISTANTANEO A DEBITO ANNA ESEMPIO IT00A0000000000000000005678 RICARICA', 'ANNA ESEMPIO');
select pg_temp.movement(111, 'c2', '2031-03-16', -12050, 'ADDEBITO MESE CARTA EGO', null);
select pg_temp.movement(112, 'c2', '2031-03-20', -3000,
  'BON. ISTANTANEO A DEBITO ANNA ESEMPIO IT00A0000000000000000005678 RICARICA', 'ANNA ESEMPIO');
select pg_temp.movement(121, 'c1', '2031-03-05', -1250,
  'FERRAMENTA PROVA CITTAPROVA IT', 'FERRAMENTA PROVA');
select pg_temp.movement(122, 'c1', '2031-03-18', 12050, 'PAGAMENTO SALDO CARTA', null);
select pg_temp.movement(131, 'c3', '2031-03-15', 5000, 'RICARICA DA BONIFICO', 'ANNA ESEMPIO');
select pg_temp.movement(132, 'c3', '2031-03-20', 3000, 'RICARICA DA BONIFICO', 'ANNA ESEMPIO');
select pg_temp.movement(133, 'c3', '2031-03-21', 3000, 'RICARICA DA BONIFICO', 'ANNA ESEMPIO');
select pg_temp.movement(141, 'c4', '2031-03-08', -2500, 'Trasferimento sul conto bancario', null);
select pg_temp.movement(142, 'c4', '2031-03-10', -1500, null, 'Libreria Esempio');
select pg_temp.movement(143, 'c4', '2031-03-13', -920, null, 'App Esempio');
select pg_temp.movement(151, 'c5', '2031-03-12', -1500,
  'SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001',
  'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.');
-- A movement of the archived card.
select pg_temp.movement(161, 'c6', '2031-03-15', 5000, 'RICARICA', null);
-- A manual movement in the cash of Anna.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id,
  movement_date, amount_cents, currency
)
select pg_temp.tx(171), a.household_id, a.id, 'manual', a.owner_member_id, a.owner_member_id,
       '2031-03-15', 5000, 'EUR'
from public.accounts a
where a.owner_member_id = '00000000-0000-4000-8000-0000000000a1' and a.kind = 'cash';

-- Anna has already classified the bill (107) and split the payment of the
-- bill in two lines (102).
update public.transaction_lines set kind = 'expense' where transaction_id = pg_temp.tx(107);
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select public.split_line(
  (select l.id from public.transaction_lines l where l.transaction_id = pg_temp.tx(102)),
  jsonb_build_array(jsonb_build_object('id', '00000000-0000-4000-8000-000000000902', 'amount_cents', -2000))
);
reset role;
select pg_temp.check_deferred();

-- Candidates

set local role service_role;
select results_eq(
  $$select a.id, a.kind, a.connection_id, a.aspsp_name, a.cash_account_type
    from jsonb_to_recordset(
      public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'accounts'
    ) as a (id uuid, kind text, connection_id uuid, aspsp_name text, cash_account_type text)$$,
  $$values
    (pg_temp.acc('c1'), 'card', '00000000-0000-4000-8000-0000000000e1'::uuid, 'Credito Emiliano', 'CARD'),
    (pg_temp.acc('c2'), 'bank', '00000000-0000-4000-8000-0000000000e1'::uuid, 'Credito Emiliano', 'CACC'),
    (pg_temp.acc('c3'), 'bank', '00000000-0000-4000-8000-0000000000e2'::uuid, 'HYPE', 'CACC'),
    (pg_temp.acc('c4'), 'paypal', '00000000-0000-4000-8000-0000000000e3'::uuid, 'PayPal', 'OTHR')$$,
  'the accounts of Anna with a connection, without the archived card and the cash'
);
select results_eq(
  $$select (m ->> 'transaction_id')::uuid
    from jsonb_array_elements(
      public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-05') -> 'movements'
    ) as e (m)$$,
  $$values (pg_temp.tx(105)), (pg_temp.tx(121)), (pg_temp.tx(141)), (pg_temp.tx(106)),
           (pg_temp.tx(107)), (pg_temp.tx(142)), (pg_temp.tx(108)), (pg_temp.tx(143)),
           (pg_temp.tx(109)), (pg_temp.tx(110)), (pg_temp.tx(131)), (pg_temp.tx(111)),
           (pg_temp.tx(122)), (pg_temp.tx(112)), (pg_temp.tx(132)), (pg_temp.tx(133))$$,
  'the bank movements of Anna from the date, by date: not the archived card, the cash, Bruno'
);
select is(
  pg_temp.candidate(108),
  jsonb_build_object(
    'transaction_id', pg_temp.tx(108),
    'account_id', pg_temp.acc('c2'),
    'amount_cents', -1500,
    'currency', 'EUR',
    'movement_date', '2031-03-12',
    'counterparty', 'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.',
    'description', 'SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001',
    'free', true,
    'in_transfer', false,
    'cancelled', false
  ),
  'a movement with its account, signed amount, currency, date, counterparty, description and state'
);
select results_eq(
  $$select (m ->> 'transaction_id')::uuid, (m ->> 'free')::boolean
    from jsonb_array_elements(
      public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
    ) as e (m)
    where m ->> 'transaction_id' in (pg_temp.tx(102)::text, pg_temp.tx(107)::text)
    order by 1$$,
  $$values (pg_temp.tx(102), false), (pg_temp.tx(107), false)$$,
  'a movement in two lines and a classified one are not free'
);
select is(
  (select count(*)::int
   from jsonb_array_elements(
     public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
   ) as e (m)
   where (m ->> 'free')::boolean and not (m ->> 'in_transfer')::boolean and not (m ->> 'cancelled')::boolean),
  16,
  'the other movements are free, in no transfer'
);
select is(
  public.transfer_candidates('00000000-0000-4000-8000-0000000000d1', '2031-03-01'),
  '{"accounts": [], "movements": []}'::jsonb,
  'a member without accounts has no candidates'
);
select throws_ok(
  $$select public.transfer_candidates('00000000-0000-4000-8000-0000000000a9', '2031-03-01')$$,
  'P0001', 'member_not_eligible',
  'a former member has no candidates'
);
select throws_ok(
  $$select public.transfer_candidates('00000000-0000-4000-8000-0000000000ff', '2031-03-01')$$,
  'P0001', 'member_not_eligible',
  'an unknown member has no candidates'
);
select throws_ok(
  $$select public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', null)$$,
  'P0001', 'invalid_since',
  'the candidates need a date'
);

-- Cases 9, 7, 6 and 8: the transfers proposed for these movements, in the
-- order of the rules (card, PayPal, between two accounts). Case 19 (112
-- with 132 and 133) has no proposal.
create temp table proposals (n int primary key, transfer jsonb not null);
grant select on proposals to service_role;
insert into proposals values
  (1, pg_temp.proposal('c2', 'c1', 111, 122, null)),
  (2, pg_temp.proposal('c2', 'c4', 108, null, 142)),
  (3, pg_temp.proposal('c2', 'c4', 109, null, null)),
  (4, pg_temp.proposal('c4', 'c2', 141, 106, null)),
  (5, pg_temp.proposal('c2', 'c3', 110, 131, null));

select ok(
  not pg_temp.member_locked('00000000-0000-4000-8000-0000000000a1'),
  'no lock on Anna before the transfers'
);
select is(
  public.apply_transfers(
    '00000000-0000-4000-8000-0000000000a1',
    (select jsonb_agg(p.transfer order by p.n) from proposals p)
  ),
  5,
  'cases 6 to 9: five transfers created'
);
select ok(
  pg_temp.member_locked('00000000-0000-4000-8000-0000000000a1'),
  'the transfers of Anna hold her lock until the end of the transaction'
);
select ok(
  not pg_temp.member_locked('00000000-0000-4000-8000-0000000000b1'),
  'the lock is of the member: Bruno is not locked'
);

reset role;
select lives_ok('select pg_temp.check_deferred()', 'the lines still add up and their shares too');
select results_eq(
  $$select t.from_account_id, t.to_account_id, t.out_transaction_id, t.in_transaction_id,
           t.funded_transaction_id, t.origin, t.deleted_at
    from public.transfers t
    order by t.out_transaction_id$$,
  $$values
    (pg_temp.acc('c2'), pg_temp.acc('c4'), pg_temp.tx(108), null::uuid, pg_temp.tx(142), 'auto', null::timestamptz),
    (pg_temp.acc('c2'), pg_temp.acc('c4'), pg_temp.tx(109), null, null, 'auto', null),
    (pg_temp.acc('c2'), pg_temp.acc('c3'), pg_temp.tx(110), pg_temp.tx(131), null, 'auto', null),
    (pg_temp.acc('c2'), pg_temp.acc('c1'), pg_temp.tx(111), pg_temp.tx(122), null, 'auto', null),
    (pg_temp.acc('c4'), pg_temp.acc('c2'), pg_temp.tx(141), pg_temp.tx(106), null, 'auto', null)$$,
  'case 9 account to card; case 7 to PayPal with and without the funded payment; case 8 both sides; case 6 PayPal to bank'
);
select is_empty(
  $$select 1 from public.transfers t where t.household_id <> '00000000-0000-4000-8000-0000000000f1'$$,
  'the transfers are in the household of Anna'
);
select results_eq(
  $$select l.transaction_id, l.kind, l.transfer_id = tr.id, l.category_id
    from public.transaction_lines l
    join public.transfers tr on l.transaction_id in (tr.out_transaction_id, tr.in_transaction_id)
    order by l.transaction_id$$,
  $$values
    (pg_temp.tx(106), 'transfer', true, null::uuid),
    (pg_temp.tx(108), 'transfer', true, null),
    (pg_temp.tx(109), 'transfer', true, null),
    (pg_temp.tx(110), 'transfer', true, null),
    (pg_temp.tx(111), 'transfer', true, null),
    (pg_temp.tx(122), 'transfer', true, null),
    (pg_temp.tx(131), 'transfer', true, null),
    (pg_temp.tx(141), 'transfer', true, null)$$,
  'the lines of both sides take kind transfer and their transfer, still without category'
);
select results_eq(
  $$select * from pg_temp.line_of(142)$$,
  $$values (null::text, null::uuid)$$,
  'case 7: the funded payment keeps its line as it is'
);
select is_empty(
  $$select 1
    from public.line_shares s
    join public.transaction_lines l on l.id = s.line_id
    where l.kind = 'transfer'
      and (s.member_id <> '00000000-0000-4000-8000-0000000000a1' or s.amount_cents <> l.amount_cents)$$,
  'the shares stay as they were: all of Anna'
);
select is_empty(
  $$select 1 from public.transactions t
    where t.id in (pg_temp.tx(106), pg_temp.tx(108), pg_temp.tx(109), pg_temp.tx(110),
                   pg_temp.tx(111), pg_temp.tx(122), pg_temp.tx(131), pg_temp.tx(141))
      and t.version <> 1$$,
  'the transactions are not changed: version 1'
);
select results_eq(
  $$select n, l.kind from unnest(array[112, 132, 133]) as n, pg_temp.line_of(n) l$$,
  $$values (112, null::text), (132, null::text), (133, null::text)$$,
  'case 19: the three movements without a proposal stay to classify'
);

set local role service_role;
select results_eq(
  $$select (m ->> 'transaction_id')::uuid, (m ->> 'free')::boolean, (m ->> 'in_transfer')::boolean
    from jsonb_array_elements(
      public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
    ) as e (m)
    where m ->> 'transaction_id' in (pg_temp.tx(111)::text, pg_temp.tx(142)::text, pg_temp.tx(112)::text)
    order by 1$$,
  $$values (pg_temp.tx(111), false, true), (pg_temp.tx(112), true, false), (pg_temp.tx(142), false, true)$$,
  'a matched movement and a funded payment are in a transfer, no longer free'
);

-- Idempotence: the same proposals again, as a second job of the same
-- member would send them after waiting for the lock.
select is(
  public.apply_transfers(
    '00000000-0000-4000-8000-0000000000a1',
    (select jsonb_agg(p.transfer order by p.n) from proposals p)
  ),
  0,
  'applied again (a second call of the same member): no transfer'
);
reset role;
select is((select count(*)::int from public.transfers), 5, 'still five transfers');

-- The checks done again: a transfer that no longer holds is skipped. Two
-- movements arrive with a later sync.
select pg_temp.movement(113, 'c2', '2031-03-13', -1500,
  'SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001',
  'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.');
select pg_temp.movement(114, 'c2', '2031-03-16', -5000,
  'BON. ISTANTANEO A DEBITO ANNA ESEMPIO IT00A0000000000000000005678 RICARICA', 'ANNA ESEMPIO');
select pg_temp.check_deferred();

set local role service_role;
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal('c5', 'c4', 151, null, null)
  )),
  0,
  'case 7: Bruno has no PayPal account, and the one of Anna is not his'
);
select ok(
  pg_temp.member_locked('00000000-0000-4000-8000-0000000000b1'),
  'the call of Bruno holds his own lock'
);
select results_eq(
  $$select * from pg_temp.line_of(151)$$,
  $$values (null::text, null::uuid)$$,
  'case 7: the charge of Bruno stays to classify'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000d1', jsonb_build_array(
    pg_temp.proposal('c2', 'c3', 112, 132, null)
  )),
  0,
  'Dario does not move the accounts of Anna'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal('c2', 'c2', 112, null, null),
    pg_temp.proposal('c2', 'c6', 112, 161, null),
    pg_temp.proposal('c3', 'c2', 132, 112, null),
    pg_temp.proposal('c2', 'c3', 104, 132, null),
    pg_temp.proposal('c2', 'c4', 107, null, null),
    pg_temp.proposal('c2', 'c4', 102, null, null),
    pg_temp.proposal('c2', 'c4', 110, null, null),
    pg_temp.proposal('c2', 'c4', 113, null, 142),
    pg_temp.proposal('c2', 'c3', 113, null, 133),
    pg_temp.proposal('c2', 'c4', 113, null, 143)
  )),
  0,
  'skipped: same account, archived account, signs swapped, amounts that differ, classified, in two lines, already in a transfer, payment already funded, funded on an account other than PayPal, payment of another amount'
);
reset role;
select is((select count(*)::int from public.transfers), 5, 'nothing was written');

set local role service_role;
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
      pg_temp.proposal('c2', 'c4', 113, null, null),
      pg_temp.proposal('c2', 'c4', 113, null, null) || '{"extra": 1}'
    ))$$,
  'P0001', 'invalid_transfers',
  'a valid transfer next to a wrong one: nothing is written'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal('c2', 'c4', 113, null, null),
    pg_temp.proposal('c2', 'c4', 113, null, null)
  )),
  1,
  'the same movement twice in one call: only the first transfer'
);

-- Case 18: Anna undoes the transfer of case 8; it is never made again.
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transfers set deleted_at = now() where out_transaction_id = pg_temp.tx(110);
update public.transaction_lines
set kind = null, transfer_id = null
where transaction_id in (pg_temp.tx(110), pg_temp.tx(131));
reset role;
select pg_temp.check_deferred();

set local role service_role;
select results_eq(
  $$select (m ->> 'transaction_id')::uuid, (m ->> 'free')::boolean, (m ->> 'in_transfer')::boolean,
           (m ->> 'cancelled')::boolean
    from jsonb_array_elements(
      public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
    ) as e (m)
    where m ->> 'transaction_id' in (pg_temp.tx(110)::text, pg_temp.tx(131)::text)
    order by 1$$,
  $$values (pg_temp.tx(110), true, false, true), (pg_temp.tx(131), true, false, true)$$,
  'case 18: the two movements are free again, in a deleted transfer'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal('c2', 'c3', 110, 131, null)
  )),
  0,
  'case 18: the transfer undone is not made again'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal('c2', 'c3', 114, 131, null)
  )),
  0,
  'case 18: nor with another outflow of the same amount'
);
reset role;
select results_eq(
  $$select n, l.kind from unnest(array[110, 131]) as n, pg_temp.line_of(n) l$$,
  $$values (110, null::text), (131, null::text)$$,
  'case 18: the two movements stay to classify'
);

-- Wrong shapes and members
set local role service_role;
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1', '{}')$$,
  'P0001', 'invalid_transfers', 'transfers are an array'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1', null)$$,
  'P0001', 'invalid_transfers', 'transfers are not null'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1', '[1]')$$,
  'P0001', 'invalid_transfers', 'each transfer is an object'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(pg_temp.proposal('c2', 'c4', 113, null, null) - 'from_account_id'))$$,
  'P0001', 'invalid_transfers', 'a transfer has its first account'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(jsonb_set(pg_temp.proposal('c2', 'c4', 113, null, null), '{to_account_id}', '"conto-4"')))$$,
  'P0001', 'invalid_transfers', 'the ids are uuids'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(jsonb_set(pg_temp.proposal('c2', 'c4', 113, null, null), '{out_transaction_id}', '7')))$$,
  'P0001', 'invalid_transfers', 'a movement is a string'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(pg_temp.proposal('c2', 'c4', null, null, null)))$$,
  'P0001', 'invalid_transfers', 'a transfer has at least one movement'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(pg_temp.proposal('c4', 'c2', null, 106, 143)))$$,
  'P0001', 'invalid_transfers', 'a funded payment needs the outgoing movement'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a9', '[]')$$,
  'P0001', 'member_not_eligible', 'a former member has no transfers'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000ff', '[]')$$,
  'P0001', 'member_not_eligible', 'an unknown member has no transfers'
);

-- Permissions
reset role;
select is_empty(
  $$select p.oid::regprocedure
    from pg_proc p
    where p.oid in (
        'public.transfer_movement_state(uuid)'::regprocedure,
        'public.transfer_candidates(uuid, date)'::regprocedure,
        'public.apply_transfers(uuid, jsonb)'::regprocedure
      )
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))$$,
  'the app and anon execute none of the new functions'
);
select ok(
  has_function_privilege('service_role', 'public.transfer_candidates(uuid, date)', 'execute')
    and has_function_privilege('service_role', 'public.apply_transfers(uuid, jsonb)', 'execute'),
  'the service role reads the candidates and writes the transfers'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$select public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01')$$,
  '42501', null,
  'the app does not read the candidates'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1', '[]')$$,
  '42501', null,
  'the app does not write automatic transfers'
);
set local role anon;
select throws_ok(
  $$select public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01')$$,
  '42501', null,
  'anon does not read the candidates'
);
select throws_ok(
  $$select public.apply_transfers('00000000-0000-4000-8000-0000000000a1', '[]')$$,
  '42501', null,
  'anon does not write automatic transfers'
);

select * from finish();
rollback;
