-- PayPal settlements after a sync (docs/spec/sincronizzazione.md, 7, 7.1,
-- 7.2, 9 and 12): settlement_candidates and apply_settlements with case 5
-- from both sides and in both orders, a manual settlement that takes both
-- sides, three members, the PayPal ID that settles a tie, what never
-- becomes a settlement, a settlement undone by the user, the state shared
-- with the automatic transfers, member_balances() computed by hand, the
-- locks of the two members, wrong shapes and permissions.
-- The rules that choose the proposals are in TypeScript
-- (supabase/functions/_shared/match/settlements_test.ts): the proposals
-- applied here are the ones they make for the same movements.
-- Invented users: Anna (a1) and Bruno (b1) in "Casa di prova", Carla (c1)
-- who joins later, a former member (a9), Dario (d1) in another household.
-- Start date: 2031-03-01 (Carla: 2031-03-08).
begin;

create extension if not exists pgtap with schema extensions;

select plan(77);

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

-- Ids: accounts ...71 to ...75, movements ...000000000101 and following,
-- their raw rows ...000000100101 and following.
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

create function pg_temp.raw(n int)
returns uuid
language sql
immutable
as $$
  select ('00000000-0000-4000-8000-' || lpad((100000 + n)::text, 12, '0'))::uuid
$$;

-- A proposal as eb-sync sends it.
create function pg_temp.proposal(n int, counterpart uuid, settlement_id uuid)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'transaction_id', pg_temp.tx(n),
    'counterpart_member_id', counterpart,
    'settlement_id', settlement_id
  )
$$;

-- A bank movement as ingest_bank_rows creates it: the raw row with the
-- reference of the bank, then the transaction with the counterparty email.
create function pg_temp.movement(
  n int, account_code text, movement_date date, amount_cents bigint, email text,
  reference text, currency text default 'EUR'
)
returns void
language sql
as $$
  insert into public.bank_raw_transactions (
    id, account_id, entry_reference, dedup_hash, dedup_ordinal, status, transaction_date,
    amount_cents, currency, payload
  )
  values (
    pg_temp.raw(movement.n), pg_temp.acc(movement.account_code), movement.reference,
    encode(sha256(convert_to('riga-' || movement.n, 'UTF8')), 'hex'), 1, 'BOOK',
    movement.movement_date, movement.amount_cents, movement.currency, '{}'
  );
  insert into public.transactions (
    id, household_id, account_id, source, raw_id, paid_by_member_id, movement_date,
    booking_date, amount_cents, currency, counterparty_email
  )
  select pg_temp.tx(movement.n), a.household_id, a.id, 'bank', pg_temp.raw(movement.n),
         a.owner_member_id, movement.movement_date, movement.movement_date,
         movement.amount_cents, movement.currency, movement.email
  from public.accounts a
  where a.id = pg_temp.acc(movement.account_code);
  update public.bank_raw_transactions
  set transaction_id = pg_temp.tx(movement.n)
  where id = pg_temp.raw(movement.n);
$$;

-- The movement fields eb-sync reads for a member, by number.
create function pg_temp.candidate(member_id uuid, n int)
returns jsonb
language sql
as $$
  select m
  from jsonb_array_elements(
    public.settlement_candidates(candidate.member_id, '2031-03-01') -> 'movements'
  ) as e (m)
  where (m ->> 'transaction_id')::uuid = pg_temp.tx(candidate.n)
$$;

-- The settlement a movement is a side of.
create function pg_temp.settlement_of(n int)
returns uuid
language sql
security definer
as $$
  select s.id from public.settlements s
  where pg_temp.tx(settlement_of.n) in (s.payer_transaction_id, s.payee_transaction_id)
$$;

-- Kind and settlement of the line of a movement.
create function pg_temp.line_of(n int)
returns table (kind text, settlement_id uuid)
language sql
as $$
  select l.kind, l.settlement_id
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

-- The balances seen by Anna, by member.
create function pg_temp.balances()
returns table (member_id uuid, net_cents bigint)
language plpgsql
as $$
begin
  set local role authenticated;
  perform pg_temp.login('00000000-0000-4000-8000-00000000000a');
  return query select b.member_id, b.net_cents from public.member_balances() b order by 1;
  reset role;
end;
$$;

create function pg_temp.cash_of(member_id uuid)
returns uuid
language sql
security definer
as $$
  select a.id from public.accounts a where a.owner_member_id = cash_of.member_id and a.kind = 'cash'
$$;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000009', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla'),
  ('00000000-0000-4000-8000-00000000000d', 'Dario'),
  ('00000000-0000-4000-8000-000000000009', 'Ex membro di prova');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', '2031-03-01'),
  ('00000000-0000-4000-8000-0000000000f2', 'Altra casa di prova', '2031-03-01');
-- Two members first: Carla and the former member come later.
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', '2031-03-01'),
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', '2031-03-01'),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', '2031-03-01');

insert into public.paypal_emails (user_id, email, source) values
  ('00000000-0000-4000-8000-00000000000a', 'anna.paypal@example.com', 'linked_account'),
  ('00000000-0000-4000-8000-00000000000b', 'bruno.paypal@example.com', 'linked_account'),
  ('00000000-0000-4000-8000-00000000000c', 'carla.paypal@example.com', 'manual'),
  ('00000000-0000-4000-8000-00000000000d', 'dario.paypal@example.com', 'linked_account'),
  ('00000000-0000-4000-8000-000000000009', 'ex.membro@example.com', 'manual');

insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, session_id, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', 'sessione-di-prova-1', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000b1',
   'PayPal', 'IT', 'sessione-di-prova-2', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-0000000000d1',
   'PayPal', 'IT', 'sessione-di-prova-3', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000a1',
   'Credito Emiliano', 'IT', 'sessione-di-prova-4', false, 'active');

-- PayPal of Anna, Bruno and Dario; the current account of Anna; an old
-- PayPal account of Anna, archived.
insert into public.accounts (
  id, household_id, owner_member_id, kind, connection_id, provider_account_id,
  cash_account_type, currency, display_name, identifier, archived_at
) values
  (pg_temp.acc('71'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'paypal', '00000000-0000-4000-8000-0000000000e1',
   'paypal-uid-1', 'OTHR', 'XXX', 'anna.paypal@example.com', 'anna.paypal@example.com', null),
  (pg_temp.acc('72'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000b1', 'paypal', '00000000-0000-4000-8000-0000000000e2',
   'paypal-uid-2', 'OTHR', 'XXX', 'bruno.paypal@example.com', 'bruno.paypal@example.com', null),
  (pg_temp.acc('73'), '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-0000000000d1', 'paypal', '00000000-0000-4000-8000-0000000000e3',
   'paypal-uid-3', 'OTHR', 'XXX', 'dario.paypal@example.com', 'dario.paypal@example.com', null),
  (pg_temp.acc('74'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e4',
   'conto-uid-4', 'CACC', 'EUR', 'Credito Emiliano …1234', 'IT00A0000000000000000001234', null),
  (pg_temp.acc('75'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'paypal', '00000000-0000-4000-8000-0000000000e1',
   'paypal-uid-5', 'OTHR', 'XXX', 'vecchio PayPal', 'vecchio.paypal@example.com',
   '2031-03-02 10:00+00');

-- A dinner paid by Bruno in cash, split in two with Anna.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id,
  movement_date, amount_cents, currency
) values (
  pg_temp.tx(101), '00000000-0000-4000-8000-0000000000f1',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
  '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1',
  '2031-03-05', -4000, 'EUR'
);
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
update public.transaction_lines set kind = 'expense' where transaction_id = pg_temp.tx(101);
select public.set_line_shares(
  (select l.id from public.transaction_lines l where l.transaction_id = pg_temp.tx(101)),
  jsonb_build_array(
    jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000a1', 'weight', 1),
    jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000b1', 'weight', 1)
  )
);
reset role;

-- Case 5 (paypal/transactions-anna-sync-1.json PP…05 and
-- paypal/transactions-bruno.json PP…101): Anna pays Bruno, the day after
-- Bruno receives it. The email of Bruno as the bank writes it.
select pg_temp.movement(201, '71', '2031-03-06', -2000, 'Bruno.Paypal@Example.com', 'PP0000000000000005');
select pg_temp.movement(301, '72', '2031-03-07', 2000, 'anna.paypal@example.com', 'PP0000000000000101');
-- What never becomes a candidate: the archived account, the current account.
select pg_temp.movement(221, '75', '2031-03-06', -2000, 'bruno.paypal@example.com', 'PP-vecchio-1');
select pg_temp.movement(401, '74', '2031-03-11', 1200, null, null);
select pg_temp.check_deferred();

-- Balances with two members, before the settlements: Bruno paid 40 for
-- both, Anna owes him 20.
select results_eq(
  'select * from pg_temp.balances()',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, -2000::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 2000::bigint)$$,
  'two members, before: Anna owes Bruno half of the dinner'
);

-- Candidates

set local role service_role;
select is(
  pg_temp.candidate('00000000-0000-4000-8000-0000000000a1', 201),
  jsonb_build_object(
    'transaction_id', pg_temp.tx(201),
    'account_id', pg_temp.acc('71'),
    'amount_cents', -2000,
    'currency', 'EUR',
    'movement_date', '2031-03-06',
    'entry_reference', 'PP0000000000000005',
    'counterpart_member_id', '00000000-0000-4000-8000-0000000000b1',
    'free', true,
    'cancelled', false
  ),
  'case 5: the payment of Anna with the PayPal ID and Bruno as counterpart, never the email'
);
select results_eq(
  $$select (m ->> 'transaction_id')::uuid
    from jsonb_array_elements(
      public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
    ) as e (m)$$,
  $$values (pg_temp.tx(201))$$,
  'only the PayPal accounts of Anna with a connection: not the archived one, the current account, Bruno'
);
select is(
  public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'settlements',
  '[]'::jsonb,
  'no settlement yet'
);
select is(
  jsonb_array_length(
    public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-07') -> 'movements'
  ),
  0,
  'the movements from the date only'
);
select throws_ok(
  $$select public.settlement_candidates('00000000-0000-4000-8000-0000000000ff', '2031-03-01')$$,
  'P0001', 'member_not_eligible',
  'an unknown member has no candidates'
);
select throws_ok(
  $$select public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', null)$$,
  'P0001', 'invalid_since',
  'the candidates need a date'
);

-- Case 5, Anna first: her side creates the settlement.
select ok(
  not pg_temp.member_locked('00000000-0000-4000-8000-0000000000a1')
    and not pg_temp.member_locked('00000000-0000-4000-8000-0000000000b1'),
  'no lock before the settlements'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(201, '00000000-0000-4000-8000-0000000000b1', null)
  )),
  1,
  'case 5: the side of Anna creates the settlement'
);
select ok(
  pg_temp.member_locked('00000000-0000-4000-8000-0000000000a1')
    and pg_temp.member_locked('00000000-0000-4000-8000-0000000000b1'),
  'the call of Anna holds her lock and the one of Bruno until the end of the transaction'
);
select ok(
  not pg_temp.member_locked('00000000-0000-4000-8000-0000000000d1'),
  'Dario is not locked'
);
-- Bruno's sync started at the same time and also proposed a new settlement:
-- under the locks it sees the one of Anna.
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(301, '00000000-0000-4000-8000-0000000000a1', null)
  )),
  0,
  'the second call proposing a new settlement: none, the one of Anna would take the movement'
);

reset role;
select results_eq(
  $$select s.household_id, s.payer_member_id, s.payee_member_id, s.amount_cents, s.currency::text,
           s.settled_on, s.origin, s.payer_transaction_id, s.payee_transaction_id,
           s.created_by_member_id, s.deleted_at
    from public.settlements s$$,
  $$values ('00000000-0000-4000-8000-0000000000f1'::uuid, '00000000-0000-4000-8000-0000000000a1'::uuid,
            '00000000-0000-4000-8000-0000000000b1'::uuid, 2000::bigint, 'EUR', '2031-03-06'::date, 'paypal',
            pg_temp.tx(201), null::uuid, null::uuid, null::timestamptz)$$,
  'one paypal settlement from Anna to Bruno, on the date of the payment, by the server, with the side of Anna'
);

set local role service_role;
select is(
  public.settlement_candidates('00000000-0000-4000-8000-0000000000b1', '2031-03-01') -> 'settlements',
  jsonb_build_array(jsonb_build_object(
    'id', pg_temp.settlement_of(201),
    'payer_member_id', '00000000-0000-4000-8000-0000000000a1',
    'payee_member_id', '00000000-0000-4000-8000-0000000000b1',
    'amount_cents', 2000,
    'currency', 'EUR',
    'settled_on', '2031-03-06',
    'payer_transaction_id', pg_temp.tx(201),
    'payee_transaction_id', null,
    'payer_entry_reference', 'PP0000000000000005',
    'payee_entry_reference', null
  )),
  'Bruno sees the settlement with the PayPal ID of the side of Anna'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(301, '00000000-0000-4000-8000-0000000000a1', pg_temp.settlement_of(201))
  )),
  1,
  'case 5: the side of Bruno, the day after, links to the same settlement'
);
reset role;
select results_eq(
  $$select count(*)::int, min(s.payer_transaction_id::text)::uuid, min(s.payee_transaction_id::text)::uuid,
           min(s.amount_cents), min(s.settled_on), min(s.origin)
    from public.settlements s$$,
  $$values (1, pg_temp.tx(201), pg_temp.tx(301), 2000::bigint, '2031-03-06'::date, 'paypal')$$,
  'case 5: one settlement with both sides, amount and date unchanged'
);
select results_eq(
  $$select n, l.kind, l.settlement_id = pg_temp.settlement_of(201)
    from unnest(array[201, 301]) as n, pg_temp.line_of(n) l$$,
  $$values (201, 'settlement', true), (301, 'settlement', true)$$,
  'the lines of both sides take kind settlement and the settlement'
);
select lives_ok('select pg_temp.check_deferred()', 'the lines still add up and their shares too');

select results_eq(
  'select * from pg_temp.balances()',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 0::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 0::bigint)$$,
  'two members, after: the PayPal payment settles the dinner'
);

-- Idempotence: the same proposals again.
set local role service_role;
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(201, '00000000-0000-4000-8000-0000000000b1', null)
  )) + public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(301, '00000000-0000-4000-8000-0000000000a1', pg_temp.settlement_of(201))
  )),
  0,
  'applied again from both sides: nothing'
);
select is(
  (pg_temp.candidate('00000000-0000-4000-8000-0000000000a1', 201) ->> 'free')::boolean,
  false,
  'a side of a settlement is no longer free'
);
reset role;
select is((select count(*)::int from public.settlements), 1, 'still one settlement');

-- Three members: Carla joins on 2031-03-08, a former member is in the
-- household too.
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', '2031-03-08');
insert into public.members (id, household_id, user_id, start_date, left_at) values
  ('00000000-0000-4000-8000-0000000000a9', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-000000000009', '2031-03-01', now());

-- Carla pays a shopping of 30 for the three of them.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id,
  movement_date, amount_cents, currency
) values (
  pg_temp.tx(102), '00000000-0000-4000-8000-0000000000f1',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000c1'), 'manual',
  '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000c1',
  '2031-03-09', -3000, 'EUR'
);
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
update public.transaction_lines set kind = 'expense' where transaction_id = pg_temp.tx(102);
select public.set_line_shares(
  (select l.id from public.transaction_lines l where l.transaction_id = pg_temp.tx(102)),
  jsonb_build_array(
    jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000a1', 'weight', 1),
    jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000b1', 'weight', 1),
    jsonb_build_object('member_id', '00000000-0000-4000-8000-0000000000c1', 'weight', 1)
  )
);
reset role;

-- Anna pays Bruno and Carla the same day, the same amount; Bruno pays
-- Carla his share.
select pg_temp.movement(206, '71', '2031-03-10', -1000, 'bruno.paypal@example.com', 'PP0000000000000206');
select pg_temp.movement(207, '71', '2031-03-10', -1000, 'carla.paypal@example.com', 'PP0000000000000207');
select pg_temp.movement(305, '72', '2031-03-10', -1000, 'carla.paypal@example.com', 'PP0000000000000305');
-- Never a settlement: an email of no member, of the former member, of a
-- member of another household, in USD, before the start date of Carla, the
-- email of Anna herself.
select pg_temp.movement(208, '71', '2031-03-12', -900, 'negozio@example.com', 'PP0000000000000208');
select pg_temp.movement(209, '71', '2031-03-12', -900, 'ex.membro@example.com', 'PP0000000000000209');
select pg_temp.movement(210, '71', '2031-03-12', -900, 'dario.paypal@example.com', 'PP0000000000000210');
select pg_temp.movement(211, '71', '2031-03-12', -900, 'bruno.paypal@example.com', 'PP0000000000000211', 'USD');
select pg_temp.movement(212, '71', '2031-03-05', -900, 'carla.paypal@example.com', 'PP0000000000000212');
select pg_temp.movement(213, '71', '2031-03-12', -900, 'anna.paypal@example.com', 'PP0000000000000213');
select pg_temp.check_deferred();

select results_eq(
  'select * from pg_temp.balances()',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, -1000::bigint),
           ('00000000-0000-4000-8000-0000000000a9'::uuid, 0::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -1000::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 2000::bigint)$$,
  'three members, before: Anna and Bruno owe Carla 10 each'
);

set local role service_role;
select results_eq(
  $$select (m ->> 'transaction_id')::uuid, (m ->> 'counterpart_member_id')::uuid, m ->> 'currency'
    from jsonb_array_elements(
      public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
    ) as e (m)
    where (m ->> 'free')::boolean
    order by 1$$,
  $$values (pg_temp.tx(206), '00000000-0000-4000-8000-0000000000b1'::uuid, 'EUR'),
           (pg_temp.tx(207), '00000000-0000-4000-8000-0000000000c1'::uuid, 'EUR'),
           (pg_temp.tx(208), null::uuid, 'EUR'),
           (pg_temp.tx(209), null::uuid, 'EUR'),
           (pg_temp.tx(210), null::uuid, 'EUR'),
           (pg_temp.tx(211), '00000000-0000-4000-8000-0000000000b1'::uuid, 'USD'),
           (pg_temp.tx(212), '00000000-0000-4000-8000-0000000000c1'::uuid, 'EUR'),
           (pg_temp.tx(213), null::uuid, 'EUR')$$,
  'the counterpart: Bruno and Carla; no one for a stranger, the former member, Dario, Anna herself'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(206, '00000000-0000-4000-8000-0000000000b1', null),
    pg_temp.proposal(207, '00000000-0000-4000-8000-0000000000c1', null)
  )),
  2,
  'three members: Anna pays Bruno and Carla the same day and amount, two settlements'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(305, '00000000-0000-4000-8000-0000000000c1', null)
  )),
  1,
  'Bruno pays Carla: a third settlement'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(208, '00000000-0000-4000-8000-0000000000b1', null),
    pg_temp.proposal(209, '00000000-0000-4000-8000-0000000000a9', null),
    pg_temp.proposal(210, '00000000-0000-4000-8000-0000000000d1', null),
    pg_temp.proposal(211, '00000000-0000-4000-8000-0000000000b1', null),
    pg_temp.proposal(212, '00000000-0000-4000-8000-0000000000c1', null),
    pg_temp.proposal(213, '00000000-0000-4000-8000-0000000000a1', null),
    pg_temp.proposal(221, '00000000-0000-4000-8000-0000000000b1', null),
    pg_temp.proposal(301, '00000000-0000-4000-8000-0000000000a1', null)
  )),
  0,
  'skipped: a stranger, the former member, Dario, USD, before the start of Carla, Anna herself, an archived account, a movement of Bruno'
);
reset role;
select results_eq(
  $$select s.payer_member_id, s.payee_member_id, s.amount_cents, s.settled_on,
           s.payer_transaction_id, s.payee_transaction_id
    from public.settlements s
    where s.settled_on = '2031-03-10'
    order by s.payer_member_id, s.payee_member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, '00000000-0000-4000-8000-0000000000b1'::uuid,
            1000::bigint, '2031-03-10'::date, pg_temp.tx(206), null::uuid),
           ('00000000-0000-4000-8000-0000000000a1'::uuid, '00000000-0000-4000-8000-0000000000c1'::uuid,
            1000::bigint, '2031-03-10'::date, pg_temp.tx(207), null::uuid),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, '00000000-0000-4000-8000-0000000000c1'::uuid,
            1000::bigint, '2031-03-10'::date, pg_temp.tx(305), null::uuid)$$,
  'three distinct settlements, each with its pair'
);
select results_eq(
  $$select n, l.kind from unnest(array[208, 209, 210, 211, 212, 213, 221]) as n, pg_temp.line_of(n) l$$,
  $$values (208, null::text), (209, null::text), (210, null::text), (211, null::text),
           (212, null::text), (213, null::text), (221, null::text)$$,
  'the skipped movements stay to classify'
);
select lives_ok('select pg_temp.check_deferred()', 'the lines still add up');
select results_eq(
  'select * from pg_temp.balances()',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1000::bigint),
           ('00000000-0000-4000-8000-0000000000a9'::uuid, 0::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -1000::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 0::bigint)$$,
  'three members, after: Carla is paid, and Anna paid Bruno 10 more'
);
select is(
  (select sum(b.net_cents)::bigint from pg_temp.balances() b),
  0::bigint,
  'the sum of the balances is zero'
);

-- Case 5 in the other order: Bruno receives first and creates the
-- settlement on his date, Anna's side the day before links to it.
select pg_temp.movement(302, '72', '2031-03-12', 1200, 'anna.paypal@example.com', 'PP0000000000000302');
select pg_temp.movement(202, '71', '2031-03-11', -1200, 'bruno.paypal@example.com', 'PP0000000000000202');
select pg_temp.check_deferred();
set local role service_role;
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(302, '00000000-0000-4000-8000-0000000000a1', null)
  )),
  1,
  'the other order: the side of Bruno creates the settlement'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(202, '00000000-0000-4000-8000-0000000000b1', pg_temp.settlement_of(302))
  )),
  1,
  'the other order: the side of Anna links to it'
);
reset role;
select results_eq(
  $$select s.payer_member_id, s.payee_member_id, s.amount_cents, s.settled_on, s.origin,
           s.payer_transaction_id, s.payee_transaction_id
    from public.settlements s where s.id = pg_temp.settlement_of(302)$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, '00000000-0000-4000-8000-0000000000b1'::uuid,
            1200::bigint, '2031-03-12'::date, 'paypal', pg_temp.tx(202), pg_temp.tx(302))$$,
  'the other order: one settlement from Anna to Bruno on the date of Bruno, with both sides'
);

-- "Segna come pagato": Anna marks a payment to Bruno, then both sides
-- arrive.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
insert into public.settlements (
  id, household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on, origin,
  created_by_member_id
) values (
  '00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1',
  1500, 'EUR', '2031-03-14', 'manual', '00000000-0000-4000-8000-0000000000a1'
);
reset role;
select pg_temp.movement(203, '71', '2031-03-15', -1500, 'bruno.paypal@example.com', 'PP0000000000000203');
select pg_temp.movement(303, '72', '2031-03-16', 1500, 'anna.paypal@example.com', 'PP0000000000000303');
select pg_temp.check_deferred();
set local role service_role;
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(203, '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-000000000501')
  )) + public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(303, '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000501')
  )),
  2,
  'a manual settlement takes both sides'
);
reset role;
select results_eq(
  $$select s.amount_cents, s.settled_on, s.origin, s.created_by_member_id,
           s.payer_transaction_id, s.payee_transaction_id
    from public.settlements s where s.id = '00000000-0000-4000-8000-000000000501'$$,
  $$values (1500::bigint, '2031-03-14'::date, 'manual', '00000000-0000-4000-8000-0000000000a1'::uuid,
            pg_temp.tx(203), pg_temp.tx(303))$$,
  'the manual settlement keeps amount, date, origin and author'
);

-- A tie and the PayPal ID that settles it: Bruno received 7 and created
-- the settlement; Anna sent 7 twice, the second with the same PayPal ID.
-- The rules propose the link of the second and a new settlement for the
-- first (its only candidate is taken): the creation, sent first, waits for
-- the link.
select pg_temp.movement(304, '72', '2031-03-18', 700, 'anna.paypal@example.com', 'PP0000000000000131');
select pg_temp.movement(204, '71', '2031-03-18', -700, 'bruno.paypal@example.com', 'PP0000000000000204');
select pg_temp.movement(205, '71', '2031-03-19', -700, 'bruno.paypal@example.com', 'PP0000000000000131');
select pg_temp.check_deferred();
set local role service_role;
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(304, '00000000-0000-4000-8000-0000000000a1', null)
  )),
  1,
  'the side of Bruno creates the settlement of 7'
);
select results_eq(
  $$select (s ->> 'payee_entry_reference'),
           (pg_temp.candidate('00000000-0000-4000-8000-0000000000a1', 204) ->> 'entry_reference'),
           (pg_temp.candidate('00000000-0000-4000-8000-0000000000a1', 205) ->> 'entry_reference')
    from jsonb_array_elements(
      public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'settlements'
    ) as e (s)
    where (s ->> 'id')::uuid = pg_temp.settlement_of(304)$$,
  $$values ('PP0000000000000131', 'PP0000000000000204', 'PP0000000000000131')$$,
  'the candidates carry the PayPal IDs: the second payment has the one of Bruno'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(205, '00000000-0000-4000-8000-0000000000b1', null),
    pg_temp.proposal(204, '00000000-0000-4000-8000-0000000000b1', null)
  )),
  0,
  'on a par: no new settlement while a settlement would take the movements'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(204, '00000000-0000-4000-8000-0000000000b1', null),
    pg_temp.proposal(205, '00000000-0000-4000-8000-0000000000b1', pg_temp.settlement_of(304))
  )),
  2,
  'the same PayPal ID: the link first, then the new settlement for the other payment'
);
reset role;
select results_eq(
  $$select s.payer_transaction_id, s.payee_transaction_id, s.settled_on
    from public.settlements s
    where s.amount_cents = 700
    order by s.payer_transaction_id$$,
  $$values (pg_temp.tx(204), null::uuid, '2031-03-18'::date),
           (pg_temp.tx(205), pg_temp.tx(304), '2031-03-18'::date)$$,
  'two settlements of 7: one with both sides, one with the other payment'
);

-- Checks done again: what no longer holds is skipped.
select pg_temp.movement(214, '71', '2031-03-20', -500, 'bruno.paypal@example.com', 'PP0000000000000214');
select pg_temp.movement(215, '71', '2031-03-20', 500, 'bruno.paypal@example.com', 'PP0000000000000215');
select pg_temp.movement(217, '71', '2031-03-20', -700, 'bruno.paypal@example.com', 'PP0000000000000217');
select pg_temp.movement(306, '72', '2031-03-14', 1000, 'anna.paypal@example.com', 'PP0000000000000306');
select pg_temp.check_deferred();
set local role service_role;
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(214, '00000000-0000-4000-8000-0000000000c1', null),
    pg_temp.proposal(214, '00000000-0000-4000-8000-0000000000b1', pg_temp.settlement_of(206)),
    pg_temp.proposal(214, '00000000-0000-4000-8000-0000000000b1', pg_temp.settlement_of(207)),
    pg_temp.proposal(217, '00000000-0000-4000-8000-0000000000b1', pg_temp.settlement_of(204)),
    pg_temp.proposal(215, '00000000-0000-4000-8000-0000000000b1', pg_temp.settlement_of(206)),
    pg_temp.proposal(214, '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000005ff')
  )),
  0,
  'skipped: another counterpart, amount that differs, another pair, side already linked, wrong direction, unknown settlement'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(306, '00000000-0000-4000-8000-0000000000a1', pg_temp.settlement_of(206))
  )),
  0,
  'skipped: the side of Bruno 4 days after the settlement'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000d1', jsonb_build_array(
    pg_temp.proposal(214, '00000000-0000-4000-8000-0000000000b1', null)
  )),
  0,
  'Dario does not settle the movements of Anna'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(214, '00000000-0000-4000-8000-0000000000b1', null),
    pg_temp.proposal(214, '00000000-0000-4000-8000-0000000000b1', null)
  )),
  1,
  'the same movement twice in one call: only once'
);
reset role;

-- The lines and the transactions of every side.
select is_empty(
  $$select 1
    from public.settlements s
    join public.transaction_lines l
      on l.transaction_id in (s.payer_transaction_id, s.payee_transaction_id) and l.deleted_at is null
    where l.kind is distinct from 'settlement' or l.settlement_id is distinct from s.id
      or l.category_id is not null$$,
  'every side has its line of kind settlement with its settlement, still without category'
);
select is_empty(
  $$select 1
    from public.settlements s
    join public.transactions t on t.id in (s.payer_transaction_id, s.payee_transaction_id)
    where t.version <> 1$$,
  'the transactions are not changed: version 1'
);
select is_empty(
  $$select 1
    from public.settlements s
    join public.transaction_lines l on l.transaction_id in (s.payer_transaction_id, s.payee_transaction_id)
    join public.line_shares sh on sh.line_id = l.id
    where sh.member_id <> l.paid_by_member_id or sh.amount_cents <> l.amount_cents$$,
  'the shares stay as they were: all of who paid'
);

-- The state shared with the automatic transfers (7.1).
set local role service_role;
select results_eq(
  $$select (m ->> 'transaction_id')::uuid, (m ->> 'free')::boolean, (m ->> 'in_transfer')::boolean,
           (m ->> 'cancelled')::boolean
    from jsonb_array_elements(
      public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
    ) as e (m)
    where m ->> 'transaction_id' in (pg_temp.tx(202)::text, pg_temp.tx(208)::text)
    order by 1$$,
  $$values (pg_temp.tx(202), false, false, false), (pg_temp.tx(208), true, false, false)$$,
  'for the transfers, a side of a settlement is not free'
);
-- A charge of the bank funds a payment already in a settlement (7.1).
reset role;
select pg_temp.movement(402, '74', '2031-03-12', -1000, null, null);
update public.transactions set counterparty = 'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.' where id = pg_temp.tx(402);
select pg_temp.check_deferred();
set local role service_role;
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(jsonb_build_object(
    'from_account_id', pg_temp.acc('74'), 'to_account_id', pg_temp.acc('71'),
    'out_transaction_id', pg_temp.tx(402), 'in_transaction_id', null,
    'funded_transaction_id', pg_temp.tx(206)
  ))),
  1,
  'a payment in a settlement can still be funded by a charge of the bank'
);
-- A payment already funded can become a settlement: the funding does not
-- classify it.
reset role;
select pg_temp.movement(216, '71', '2031-03-21', -800, 'bruno.paypal@example.com', 'PP0000000000000216');
select pg_temp.movement(403, '74', '2031-03-21', -800, null, null);
update public.transactions set counterparty = 'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.' where id = pg_temp.tx(403);
select pg_temp.check_deferred();
set local role service_role;
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(jsonb_build_object(
    'from_account_id', pg_temp.acc('74'), 'to_account_id', pg_temp.acc('71'),
    'out_transaction_id', pg_temp.tx(403), 'in_transaction_id', null,
    'funded_transaction_id', pg_temp.tx(216)
  ))),
  1,
  'a charge of the bank funds a payment to Bruno'
);
select is(
  (pg_temp.candidate('00000000-0000-4000-8000-0000000000a1', 216) ->> 'free')::boolean,
  true,
  'a funded payment is still free for the settlements'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(216, '00000000-0000-4000-8000-0000000000b1', null)
  )),
  1,
  'a funded payment becomes a settlement'
);

-- A settlement undone by the user: its movements are never matched again,
-- neither as a settlement nor as a transfer.
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.settlements set deleted_at = now() where id = pg_temp.settlement_of(302);
reset role;
update public.transaction_lines
set kind = null, settlement_id = null
where transaction_id in (pg_temp.tx(202), pg_temp.tx(302));
select pg_temp.check_deferred();

set local role service_role;
select results_eq(
  $$select (pg_temp.candidate('00000000-0000-4000-8000-0000000000a1', 202) ->> 'free')::boolean,
           (pg_temp.candidate('00000000-0000-4000-8000-0000000000a1', 202) ->> 'cancelled')::boolean$$,
  $$values (true, true)$$,
  'a side of a deleted settlement: one line without kind again, but cancelled'
);
select is_empty(
  $$select 1
    from jsonb_array_elements(
      public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'settlements'
    ) as e (s)
    where (s ->> 'id')::uuid = pg_temp.settlement_of(302)$$,
  'the deleted settlement is no longer a candidate'
);
select is(
  public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
    pg_temp.proposal(202, '00000000-0000-4000-8000-0000000000b1', null)
  )) + public.apply_settlements('00000000-0000-4000-8000-0000000000b1', jsonb_build_array(
    pg_temp.proposal(302, '00000000-0000-4000-8000-0000000000a1', null)
  )),
  0,
  'the settlement undone is not made again from either side'
);
select results_eq(
  $$select (m ->> 'free')::boolean, (m ->> 'in_transfer')::boolean, (m ->> 'cancelled')::boolean
    from jsonb_array_elements(
      public.transfer_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01') -> 'movements'
    ) as e (m)
    where (m ->> 'transaction_id')::uuid = pg_temp.tx(202)$$,
  $$values (true, false, true)$$,
  'for the transfers too, the side of a deleted settlement is cancelled'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(jsonb_build_object(
    'from_account_id', pg_temp.acc('71'), 'to_account_id', pg_temp.acc('74'),
    'out_transaction_id', pg_temp.tx(202), 'in_transaction_id', pg_temp.tx(401),
    'funded_transaction_id', null
  ))),
  0,
  'nor does it become a transfer'
);
reset role;
select results_eq(
  $$select n, l.kind from unnest(array[202, 302]) as n, pg_temp.line_of(n) l$$,
  $$values (202, null::text), (302, null::text)$$,
  'the two movements stay to classify'
);

-- Wrong shapes and members
set local role service_role;
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1', '{}')$$,
  'P0001', 'invalid_settlements', 'settlements are an array'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1', null)$$,
  'P0001', 'invalid_settlements', 'settlements are not null'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1', '[1]')$$,
  'P0001', 'invalid_settlements', 'each settlement is an object'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(pg_temp.proposal(208, '00000000-0000-4000-8000-0000000000b1', null) - 'transaction_id'))$$,
  'P0001', 'invalid_settlements', 'a proposal has its movement'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(pg_temp.proposal(208, null, null)))$$,
  'P0001', 'invalid_settlements', 'a proposal has its counterpart'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(pg_temp.proposal(208, '00000000-0000-4000-8000-0000000000b1', null) || '{"email": "x"}'))$$,
  'P0001', 'invalid_settlements', 'no other key'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(jsonb_set(pg_temp.proposal(208, '00000000-0000-4000-8000-0000000000b1', null),
                                  '{counterpart_member_id}', '"membro-bruno"')))$$,
  'P0001', 'invalid_settlements', 'the ids are uuids'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1',
      jsonb_build_array(jsonb_set(pg_temp.proposal(208, '00000000-0000-4000-8000-0000000000b1', null),
                                  '{settlement_id}', '7')))$$,
  'P0001', 'invalid_settlements', 'a settlement is a string or null'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(
      pg_temp.proposal(208, '00000000-0000-4000-8000-0000000000b1', null),
      pg_temp.proposal(208, '00000000-0000-4000-8000-0000000000b1', null) || '{"extra": 1}'
    ))$$,
  'P0001', 'invalid_settlements',
  'a valid proposal next to a wrong one: nothing is written'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a9', '[]')$$,
  'P0001', 'member_not_eligible', 'a former member has no settlements'
);
select throws_ok(
  $$select public.settlement_candidates('00000000-0000-4000-8000-0000000000a9', '2031-03-01')$$,
  'P0001', 'member_not_eligible', 'a former member has no candidates'
);

-- Permissions
reset role;
select is_empty(
  $$select p.oid::regprocedure
    from pg_proc p
    where p.oid in (
        'public.transfer_movement_state(uuid)'::regprocedure,
        'public.settlement_movement_state(uuid)'::regprocedure,
        'public.paypal_counterpart_member(uuid, text)'::regprocedure,
        'public.settlement_candidates(uuid, date)'::regprocedure,
        'public.apply_settlements(uuid, jsonb)'::regprocedure
      )
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))$$,
  'the app and anon execute none of the new functions'
);
select ok(
  has_function_privilege('service_role', 'public.settlement_candidates(uuid, date)', 'execute')
    and has_function_privilege('service_role', 'public.apply_settlements(uuid, jsonb)', 'execute'),
  'the service role reads the candidates and writes the settlements'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$select public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01')$$,
  '42501', null,
  'the app does not read the candidates'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1', '[]')$$,
  '42501', null,
  'the app does not write PayPal settlements'
);
set local role anon;
select throws_ok(
  $$select public.settlement_candidates('00000000-0000-4000-8000-0000000000a1', '2031-03-01')$$,
  '42501', null,
  'anon does not read the candidates'
);
select throws_ok(
  $$select public.apply_settlements('00000000-0000-4000-8000-0000000000a1', '[]')$$,
  '42501', null,
  'anon does not write PayPal settlements'
);

select * from finish();
rollback;
