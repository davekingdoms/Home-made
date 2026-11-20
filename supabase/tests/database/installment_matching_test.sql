-- PayPal installment plans after a sync (docs/spec/sincronizzazione.md, 6.1,
-- 7, 7.3, 9 and 12): installment_candidates and apply_installments with
-- case 4 over two syncs imported by ingest_bank_rows, the variant (the
-- purchase a movement first, deleted when the plan is born; left and
-- counted once when classified or funded), the category and the weights of
-- a plan on its installments (or not, when they do not apply), two plans
-- with the same installment, a complete plan, the last installment with a
-- few cents more, purchases on a par, a plan undone by the user, the state
-- shared with the transfers and the settlements, the lock of the owner,
-- finish_sync_run with the purchases left, wrong shapes and permissions.
-- The rules that choose the proposals are in TypeScript
-- (supabase/functions/_shared/match/installments_test.ts): the proposals
-- applied here are the ones they make for the same rows.
-- Invented users: Anna (a1) and Bruno (b1) in "Casa di prova", Dario (d1) in
-- another household. Start date: 2031-03-01.
begin;

create extension if not exists pgtap with schema extensions;

select plan(86);

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

create function pg_temp.acc(code text)
returns uuid
language sql
immutable
as $$
  select ('00000000-0000-4000-8000-0000000000' || code)::uuid
$$;

-- A PayPal row as eb-sync normalizes it for ingest_bank_rows: PAYMENT/PAYMENT
-- a purchase, PAYMENT/LOAN an installment (creditor PayPal).
create function pg_temp.paypal_row(
  reference text, day date, cents bigint, sub_code text, creditor text default 'PayPal',
  status text default 'BOOK'
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'entry_reference', paypal_row.reference,
    'status', paypal_row.status,
    'transaction_date', paypal_row.day,
    'amount_cents', paypal_row.cents,
    'currency', 'EUR',
    'dedup_hash', encode(sha256(convert_to(paypal_row.reference || paypal_row.status, 'UTF8')), 'hex'),
    'payload', jsonb_build_object(
      'entry_reference', paypal_row.reference,
      'status', paypal_row.status,
      'bank_transaction_code', jsonb_build_object(
        'description', null, 'code', 'PAYMENT', 'sub_code', paypal_row.sub_code
      ),
      'creditor', jsonb_build_object(
        'name', paypal_row.creditor,
        'contact_details', jsonb_build_object('email_address', 'negozio@example.com')
      ),
      'remittance_information', case
        when paypal_row.sub_code = 'PAYMENT' then jsonb_build_array('Ordine ' || paypal_row.creditor)
        else '[]'::jsonb
      end
    ),
    'counterparty', paypal_row.creditor,
    'counterparty_email', 'negozio@example.com',
    'bank_code', 'PAYMENT/' || paypal_row.sub_code
  )
$$;

-- A direct debit of the bank towards PayPal.
create function pg_temp.bank_row(reference text, day date, cents bigint)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'entry_reference', bank_row.reference,
    'status', 'BOOK',
    'value_date', bank_row.day,
    'amount_cents', bank_row.cents,
    'currency', 'EUR',
    'dedup_hash', encode(sha256(convert_to(bank_row.reference, 'UTF8')), 'hex'),
    'payload', '{}'::jsonb,
    'description', 'SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001',
    'counterparty', 'PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.'
  )
$$;

-- The movements created by an import.
create function pg_temp.ingest(account_code text, variadic rows jsonb[])
returns int
language sql
as $$
  select i.transactions_created
  from public.ingest_bank_rows(pg_temp.acc(ingest.account_code), to_jsonb(ingest.rows)) i
$$;

create function pg_temp.raw_of(reference text)
returns uuid
language sql
security definer
as $$
  select r.id from public.bank_raw_transactions r where r.entry_reference = raw_of.reference
$$;

create function pg_temp.tx_of(reference text)
returns uuid
language sql
security definer
as $$
  select r.transaction_id from public.bank_raw_transactions r where r.entry_reference = tx_of.reference
$$;

create function pg_temp.plan_of(purchase text)
returns uuid
language sql
security definer
as $$
  select p.id from public.installment_plans p where p.purchase_raw_id = pg_temp.raw_of(plan_of.purchase)
$$;

create function pg_temp.links(references_ text[])
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(pg_temp.tx_of(x.reference) order by x.ord), '[]'::jsonb)
  from unnest(links.references_) with ordinality as x (reference, ord)
$$;

-- A proposal as eb-sync sends it: a new plan, or a plan to update (by the
-- reference of its purchase).
create function pg_temp.creation(
  purchase text, first text, merchant text, before int, paid int, last date,
  variadic links text[] default '{}'
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'plan_id', null,
    'purchase_raw_id', pg_temp.raw_of(creation.purchase),
    'first_raw_id', pg_temp.raw_of(creation.first),
    'merchant', creation.merchant,
    'installments_before_start', creation.before,
    'installments_paid', creation.paid,
    'last_installment_date', creation.last,
    'transaction_ids', pg_temp.links(creation.links)
  )
$$;

create function pg_temp.plan_update(
  purchase text, before int, paid int, last date, variadic links text[] default '{}'
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'plan_id', pg_temp.plan_of(plan_update.purchase),
    'purchase_raw_id', null,
    'first_raw_id', null,
    'merchant', null,
    'installments_before_start', plan_update.before,
    'installments_paid', plan_update.paid,
    'last_installment_date', plan_update.last,
    'transaction_ids', pg_temp.links(plan_update.links)
  )
$$;

create function pg_temp.apply(member_id uuid, variadic proposals jsonb[])
returns jsonb
language sql
as $$
  select public.apply_installments(apply.member_id, to_jsonb(apply.proposals))
$$;

create function pg_temp.counts(created int, linked int, classified int)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'plans_created', counts.created,
    'matched_installments', counts.linked,
    'purchase_already_classified', counts.classified
  )
$$;

-- The row of the candidates of Anna for a reference.
create function pg_temp.candidate(reference text)
returns jsonb
language sql
as $$
  select r
  from jsonb_array_elements(
    public.installment_candidates('00000000-0000-4000-8000-0000000000a1', '2031-02-03') -> 'rows'
  ) as e (r)
  where (r ->> 'raw_id')::uuid = pg_temp.raw_of(candidate.reference)
$$;

-- Plan, kind and category of the line of a movement.
create function pg_temp.line_of(reference text)
returns table (installment_plan_id uuid, kind text, category_id uuid)
language sql
security definer
as $$
  select l.installment_plan_id, l.kind, l.category_id
  from public.transaction_lines l
  where l.transaction_id = pg_temp.tx_of(line_of.reference)
    and l.deleted_at is null
$$;

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

insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, session_id, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'PayPal', 'IT', 'sessione-di-prova-1', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000b1',
   'PayPal', 'IT', 'sessione-di-prova-2', false, 'active'),
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000a1',
   'Credito Emiliano', 'IT', 'sessione-di-prova-4', false, 'active');

-- PayPal of Anna and Bruno, the current account of Anna.
insert into public.accounts (
  id, household_id, owner_member_id, kind, connection_id, provider_account_id,
  cash_account_type, currency, display_name, identifier
) values
  (pg_temp.acc('71'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'paypal', '00000000-0000-4000-8000-0000000000e1',
   'paypal-uid-1', 'OTHR', 'XXX', 'anna.paypal@example.com', 'anna.paypal@example.com'),
  (pg_temp.acc('72'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000b1', 'paypal', '00000000-0000-4000-8000-0000000000e2',
   'paypal-uid-2', 'OTHR', 'XXX', 'bruno.paypal@example.com', 'bruno.paypal@example.com'),
  (pg_temp.acc('74'), '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e4',
   'conto-uid-4', 'CACC', 'EUR', 'Credito Emiliano …1234', 'IT00A0000000000000000001234');

-- A personal category of Anna, for a plan whose weights cannot use it.
insert into public.categories (id, household_id, parent_id, name, kind, scope, owner_member_id)
select '00000000-0000-4000-8000-0000000000c9', c.household_id, c.id, 'Personale di prova',
       'expense', 'personal', '00000000-0000-4000-8000-0000000000a1'
from public.categories c
where c.household_id = '00000000-0000-4000-8000-0000000000f1'
  and c.kind = 'expense' and c.parent_id is null
order by c.name
limit 1;

create function pg_temp.shared_category()
returns uuid
language sql
security definer
as $$
  select c.id
  from public.categories c
  where c.household_id = '00000000-0000-4000-8000-0000000000f1'
    and c.kind = 'expense' and c.scope = 'shared' and c.parent_id is not null
    and c.system_key is null and c.archived_at is null
  order by c.name
  limit 1
$$;

-- Case 4, first sync (paypal/transactions-anna-sync-1.json): the purchase
-- PP…01 and its first installment PP…02 before the start date, the second
-- installment PP…03 after; the purchase of the variant PP…10 without its
-- installments yet.

set local role service_role;
select is(
  pg_temp.ingest('71',
    pg_temp.paypal_row('PP0000000000000001', '2031-02-10', -9000, 'PAYMENT', 'Negozio Esempio'),
    pg_temp.paypal_row('PP0000000000000002', '2031-02-10', -3000, 'LOAN'),
    pg_temp.paypal_row('PP0000000000000010', '2031-03-05', -6000, 'PAYMENT', 'Elettronica Esempio'),
    pg_temp.paypal_row('PP0000000000000003', '2031-03-12', -3000, 'LOAN')),
  2,
  'case 4, first sync: the second installment and the purchase of the variant become movements'
);

select set_eq(
  $$select (r ->> 'raw_id')::uuid
    from jsonb_array_elements(
      public.installment_candidates('00000000-0000-4000-8000-0000000000a1', '2031-02-03') -> 'rows'
    ) as e (r)$$,
  $$values (pg_temp.raw_of('PP0000000000000001')), (pg_temp.raw_of('PP0000000000000002')),
           (pg_temp.raw_of('PP0000000000000003'))$$,
  'the candidates: all the raw rows of the installments and of the purchases with one the same day'
);
select is(
  pg_temp.candidate('PP0000000000000001'),
  jsonb_build_object(
    'raw_id', pg_temp.raw_of('PP0000000000000001'),
    'account_id', pg_temp.acc('71'),
    'status', 'BOOK',
    'movement_date', '2031-02-10',
    'amount_cents', -9000,
    'currency', 'EUR',
    'code', 'PAYMENT',
    'sub_code', 'PAYMENT',
    'creditor_name', 'Negozio Esempio',
    'remittance', jsonb_build_array('Ordine Negozio Esempio'),
    'transaction_id', null,
    'installment_plan_id', null,
    'free', false,
    'cancelled', false
  ),
  'case 4: the purchase before the start date, with its creditor, without a movement'
);
select is(
  pg_temp.candidate('PP0000000000000003'),
  jsonb_build_object(
    'raw_id', pg_temp.raw_of('PP0000000000000003'),
    'account_id', pg_temp.acc('71'),
    'status', 'BOOK',
    'movement_date', '2031-03-12',
    'amount_cents', -3000,
    'currency', 'EUR',
    'code', 'PAYMENT',
    'sub_code', 'LOAN',
    'creditor_name', null,
    'remittance', null,
    'transaction_id', pg_temp.tx_of('PP0000000000000003'),
    'installment_plan_id', null,
    'free', true,
    'cancelled', false
  ),
  'case 4: the second installment, a free movement'
);
select is(
  public.installment_candidates('00000000-0000-4000-8000-0000000000a1', '2031-02-03') - 'rows',
  '{"start_date": "2031-03-01", "plans": []}'::jsonb,
  'the start date of Anna, no plan yet'
);
select ok(
  strpos(public.installment_candidates('00000000-0000-4000-8000-0000000000a1', '2031-02-03')::text, '@') = 0,
  'never an email in the candidates'
);

select ok(
  not pg_temp.member_locked('00000000-0000-4000-8000-0000000000a1'),
  'no lock on Anna before the plans'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.creation('PP0000000000000001', 'PP0000000000000002', 'Negozio Esempio', 1, 2,
      '2031-03-12', 'PP0000000000000003')),
  pg_temp.counts(1, 1, 0),
  'case 4: the plan is created and the second installment linked'
);
select ok(
  pg_temp.member_locked('00000000-0000-4000-8000-0000000000a1'),
  'the plans of Anna hold her lock until the end of the transaction'
);
select ok(
  not pg_temp.member_locked('00000000-0000-4000-8000-0000000000b1'),
  'the lock is of the owner only'
);

reset role;
select lives_ok('select pg_temp.check_deferred()', 'the lines still add up and their shares too');
select results_eq(
  $$select account_id, merchant, total_cents, installments_count::int, purchase_date, purchase_raw_id,
           installments_before_start::int, next_due_date, status, category_id, version
    from public.installment_plans$$,
  $$values (pg_temp.acc('71'), 'Negozio Esempio'::text, 9000::bigint, 3, '2031-02-10'::date,
            pg_temp.raw_of('PP0000000000000001'), 1, '2031-04-11'::date, 'active'::text, null::uuid, 1)$$,
  'case 4: the plan of the purchase, one installment before the start date, the next one 30 days later'
);
select results_eq(
  $$select t.installment_plan_id, t.version from public.transactions t
    where t.id = pg_temp.tx_of('PP0000000000000003')$$,
  $$values (pg_temp.plan_of('PP0000000000000001'), 2)$$,
  'the installment takes the plan, and its version goes up'
);
select results_eq(
  $$select * from pg_temp.line_of('PP0000000000000003')$$,
  $$values (pg_temp.plan_of('PP0000000000000001'), null::text, null::uuid)$$,
  'a plan without category and weights: the installment stays to classify'
);
select results_eq(
  $$select r.transaction_id, (select count(*)::int from public.transactions t where t.raw_id = r.id)
    from public.bank_raw_transactions r where r.entry_reference = 'PP0000000000000001'$$,
  $$values (null::uuid, 0)$$,
  'case 4: the purchase is never a movement'
);

set local role service_role;
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.creation('PP0000000000000001', 'PP0000000000000002', 'Negozio Esempio', 1, 2,
      '2031-03-12', 'PP0000000000000003'),
    pg_temp.plan_update('PP0000000000000001', 1, 2, '2031-03-12', 'PP0000000000000003')),
  pg_temp.counts(0, 0, 0),
  'run again: no plan and no link more'
);
reset role;
select results_eq(
  $$select p.version, t.version
    from public.installment_plans p, public.transactions t
    where t.id = pg_temp.tx_of('PP0000000000000003')$$,
  $$values (1, 2)$$,
  'run again: plan and installment do not change'
);
select results_eq(
  $$select tm.free, tm.in_transfer, tm.cancelled, sm.free, sm.cancelled
    from public.transfer_movement_state(pg_temp.tx_of('PP0000000000000003')) tm,
         public.settlement_movement_state(pg_temp.tx_of('PP0000000000000003')) sm$$,
  $$values (false, false, false, false, false)$$,
  'an installment is free neither for the transfers nor for the settlements, and is not cancelled'
);

-- Case 4, second sync (paypal/transactions-anna-sync-2.json): the third
-- installment PP…04; the variant, with the installments PP…11 and PP…12 of
-- the purchase PP…10, already a movement.

set local role service_role;
select is(
  pg_temp.ingest('71',
    pg_temp.paypal_row('PP0000000000000001', '2031-02-10', -9000, 'PAYMENT', 'Negozio Esempio'),
    pg_temp.paypal_row('PP0000000000000002', '2031-02-10', -3000, 'LOAN'),
    pg_temp.paypal_row('PP0000000000000010', '2031-03-05', -6000, 'PAYMENT', 'Elettronica Esempio'),
    pg_temp.paypal_row('PP0000000000000011', '2031-03-05', -2000, 'LOAN'),
    pg_temp.paypal_row('PP0000000000000003', '2031-03-12', -3000, 'LOAN'),
    pg_temp.paypal_row('PP0000000000000012', '2031-04-04', -2000, 'LOAN'),
    pg_temp.paypal_row('PP0000000000000004', '2031-04-11', -3000, 'LOAN')),
  3,
  'case 4, second sync: three new installments become movements'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11', 'PP0000000000000004'),
    pg_temp.creation('PP0000000000000010', 'PP0000000000000011', 'Elettronica Esempio', 0, 2,
      '2031-04-04', 'PP0000000000000011', 'PP0000000000000012')),
  pg_temp.counts(1, 3, 0),
  'case 4 and the variant: the third installment, the plan of the variant with its two installments'
);
reset role;
select lives_ok('select pg_temp.check_deferred()', 'the purchase deleted leaves no line to add up');
select results_eq(
  $$select merchant, total_cents, installments_count::int, installments_before_start::int,
           next_due_date, status
    from public.installment_plans order by purchase_date$$,
  $$values ('Negozio Esempio'::text, 9000::bigint, 3, 1, null::date, 'completed'::text),
           ('Elettronica Esempio'::text, 6000::bigint, 3, 0, '2031-05-04'::date, 'active'::text)$$,
  'case 4 completed at the third installment, without a next one; the variant active'
);
select results_eq(
  $$select r.entry_reference, l.installment_plan_id
    from public.bank_raw_transactions r
    cross join lateral pg_temp.line_of(r.entry_reference) l
    where r.entry_reference in ('PP0000000000000004', 'PP0000000000000011', 'PP0000000000000012')
    order by r.entry_reference$$,
  $$values ('PP0000000000000004'::text, pg_temp.plan_of('PP0000000000000001')),
           ('PP0000000000000011'::text, pg_temp.plan_of('PP0000000000000010')),
           ('PP0000000000000012'::text, pg_temp.plan_of('PP0000000000000010'))$$,
  'each installment on its plan'
);
select results_eq(
  $$select r.transaction_id, (select count(*)::int from public.transactions t where t.raw_id = r.id)
    from public.bank_raw_transactions r where r.entry_reference = 'PP0000000000000010'$$,
  $$values (null::uuid, 0)$$,
  'the variant: the movement of the purchase, untouched, is deleted and the raw row unlinked'
);

set local role service_role;
select is(
  pg_temp.ingest('71',
    pg_temp.paypal_row('PP0000000000000010', '2031-03-05', -6000, 'PAYMENT', 'Elettronica Esempio'),
    pg_temp.paypal_row('PP0000000000000010', '2031-03-05', -6000, 'PAYMENT', 'Elettronica Esempio', 'PDNG')),
  0,
  'the purchase imported again, BOOK or PDNG, does not become a movement again'
);
reset role;
select results_eq(
  $$select r.status, r.transaction_id from public.bank_raw_transactions r
    where r.entry_reference = 'PP0000000000000010'$$,
  $$values ('BOOK'::text, null::uuid)$$,
  'its raw row stays as it was'
);
set local role service_role;
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11', 'PP0000000000000004'),
    pg_temp.creation('PP0000000000000010', 'PP0000000000000011', 'Elettronica Esempio', 0, 2,
      '2031-04-04', 'PP0000000000000011', 'PP0000000000000012')),
  pg_temp.counts(0, 0, 0),
  'the second sync run again: nothing more'
);

-- The variant with a purchase already classified (PP…20) and one funded by
-- a charge of the bank (PP…30): their installments arrive later.
select is(
  pg_temp.ingest('71',
    pg_temp.paypal_row('PP0000000000000020', '2031-03-15', -4500, 'PAYMENT', 'Libreria Prova'),
    pg_temp.paypal_row('PP0000000000000030', '2031-03-16', -2400, 'PAYMENT', 'Cartoleria Prova'))
  + pg_temp.ingest('74',
    pg_temp.bank_row('CREDEM-20310317-0000201-001', '2031-03-17', -2400),
    pg_temp.bank_row('CREDEM-20310405-0000202-001', '2031-04-05', -2000),
    pg_temp.bank_row('CREDEM-20310420-0000203-001', '2031-04-20', -3333)),
  5,
  'two purchases and three charges of the bank become movements'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(jsonb_build_object(
    'from_account_id', pg_temp.acc('74'), 'to_account_id', pg_temp.acc('71'),
    'out_transaction_id', pg_temp.tx_of('CREDEM-20310317-0000201-001'),
    'in_transaction_id', null,
    'funded_transaction_id', pg_temp.tx_of('PP0000000000000030')))),
  1,
  'the charge funds the second purchase'
);
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.transaction_lines set kind = 'expense'
where transaction_id = pg_temp.tx_of('PP0000000000000020');
reset role;

set local role service_role;
select is(
  pg_temp.ingest('71',
    pg_temp.paypal_row('PP0000000000000021', '2031-03-15', -1500, 'LOAN'),
    pg_temp.paypal_row('PP0000000000000031', '2031-03-16', -1200, 'LOAN')),
  2,
  'their first installments arrive in the next sync'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.creation('PP0000000000000020', 'PP0000000000000021', 'Libreria Prova', 0, 1,
      '2031-03-15', 'PP0000000000000021'),
    pg_temp.creation('PP0000000000000030', 'PP0000000000000031', 'Cartoleria Prova', 0, 1,
      '2031-03-16', 'PP0000000000000031')),
  pg_temp.counts(2, 2, 2),
  'the plans are created, the classified and the funded purchases are left and counted'
);
reset role;
select results_eq(
  $$select r.entry_reference, r.transaction_id = t.id, l.kind, t.version
    from public.bank_raw_transactions r
    join public.transactions t on t.raw_id = r.id
    join public.transaction_lines l on l.transaction_id = t.id
    where r.entry_reference in ('PP0000000000000020', 'PP0000000000000030')
    order by 1$$,
  $$values ('PP0000000000000020'::text, true, 'expense'::text, 1),
           ('PP0000000000000030'::text, true, null::text, 1)$$,
  'the two purchases stay as they are'
);
set local role service_role;
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.creation('PP0000000000000020', 'PP0000000000000021', 'Libreria Prova', 0, 1,
      '2031-03-15', 'PP0000000000000021'),
    pg_temp.creation('PP0000000000000030', 'PP0000000000000031', 'Cartoleria Prova', 0, 1,
      '2031-03-16', 'PP0000000000000031')),
  pg_temp.counts(0, 0, 0),
  'a purchase left is counted once, when its plan is created'
);
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(jsonb_build_object(
    'from_account_id', pg_temp.acc('74'), 'to_account_id', pg_temp.acc('71'),
    'out_transaction_id', pg_temp.tx_of('CREDEM-20310405-0000202-001'),
    'in_transaction_id', null,
    'funded_transaction_id', pg_temp.tx_of('PP0000000000000012')))),
  1,
  'an installment of a plan stays fundable by a charge of the bank'
);

-- A plan with category and weights: the next installment of the variant
-- takes kind expense, the category and the shares.
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.installment_plans set category_id = pg_temp.shared_category()
where id = pg_temp.plan_of('PP0000000000000010');
insert into public.installment_plan_shares (plan_id, member_id, weight) values
  (pg_temp.plan_of('PP0000000000000010'), '00000000-0000-4000-8000-0000000000a1', 1),
  (pg_temp.plan_of('PP0000000000000010'), '00000000-0000-4000-8000-0000000000b1', 1);
reset role;

set local role service_role;
select is(
  pg_temp.ingest('71', pg_temp.paypal_row('PP0000000000000013', '2031-05-04', -2000, 'LOAN')),
  1,
  'the last installment of the variant becomes a movement'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.plan_update('PP0000000000000010', 0, 3, '2031-05-04', 'PP0000000000000013')),
  pg_temp.counts(0, 1, 0),
  'and is linked'
);
reset role;
select lives_ok('select pg_temp.check_deferred()', 'the shares of the installment add up');
select results_eq(
  $$select l.installment_plan_id, l.kind, l.category_id from pg_temp.line_of('PP0000000000000013') l$$,
  $$values (pg_temp.plan_of('PP0000000000000010'), 'expense'::text, pg_temp.shared_category())$$,
  'with category and weights: the installment is an expense of the category of the plan'
);
select results_eq(
  $$select s.member_id, s.weight, s.amount_cents
    from public.line_shares s
    join public.transaction_lines l on l.id = s.line_id
    where l.transaction_id = pg_temp.tx_of('PP0000000000000013')
    order by s.member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::numeric, -1000::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 1::numeric, -1000::bigint)$$,
  'and the shares of the weights of the plan'
);
select results_eq(
  $$select status, next_due_date from public.installment_plans
    where id = pg_temp.plan_of('PP0000000000000010')$$,
  $$values ('completed'::text, null::date)$$,
  'the variant completed'
);

-- A plan whose category and weights do not apply: a personal category of
-- Anna with a weight of Bruno. The last installment a few cents more.
set local role service_role;
select is(
  pg_temp.ingest('71',
    pg_temp.paypal_row('PP0000000000000040', '2031-03-20', -10000, 'PAYMENT', 'Negozio Prova'),
    pg_temp.paypal_row('PP0000000000000041', '2031-03-20', -3333, 'LOAN')),
  2,
  'a purchase of 100 in three installments of 33.33'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.creation('PP0000000000000040', 'PP0000000000000041', 'Negozio Prova', 0, 1,
      '2031-03-20', 'PP0000000000000041')),
  pg_temp.counts(1, 1, 0),
  'its plan, with the first installment'
);
reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.installment_plans set category_id = '00000000-0000-4000-8000-0000000000c9'
where id = pg_temp.plan_of('PP0000000000000040');
insert into public.installment_plan_shares (plan_id, member_id, weight) values
  (pg_temp.plan_of('PP0000000000000040'), '00000000-0000-4000-8000-0000000000a1', 1),
  (pg_temp.plan_of('PP0000000000000040'), '00000000-0000-4000-8000-0000000000b1', 1);
reset role;
set local role service_role;
select is(
  pg_temp.ingest('71',
    pg_temp.paypal_row('PP0000000000000042', '2031-04-19', -3333, 'LOAN'),
    pg_temp.paypal_row('PP0000000000000043', '2031-05-19', -3335, 'LOAN')),
  2,
  'the second installment and the last one, 2 cents more'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.plan_update('PP0000000000000040', 0, 3, '2031-05-19',
      'PP0000000000000042', 'PP0000000000000043')),
  pg_temp.counts(0, 2, 0),
  'both linked, the last one too'
);
reset role;
select lives_ok('select pg_temp.check_deferred()', 'no line breaks a check');
select results_eq(
  $$select r.entry_reference, l.installment_plan_id, l.kind, l.category_id,
           (select array_agg(s.member_id) from public.line_shares s
            join public.transaction_lines x on x.id = s.line_id
            where x.transaction_id = r.transaction_id)
    from public.bank_raw_transactions r
    cross join lateral pg_temp.line_of(r.entry_reference) l
    where r.entry_reference in ('PP0000000000000042', 'PP0000000000000043')
    order by 1$$,
  $$values
    ('PP0000000000000042'::text, pg_temp.plan_of('PP0000000000000040'), null::text, null::uuid,
     array['00000000-0000-4000-8000-0000000000a1'::uuid]),
    ('PP0000000000000043'::text, pg_temp.plan_of('PP0000000000000040'), null::text, null::uuid,
     array['00000000-0000-4000-8000-0000000000a1'::uuid])$$,
  'category and weights that do not apply: the installments are linked and stay to classify'
);
set local role service_role;
select is(
  pg_temp.ingest('71', pg_temp.paypal_row('PP0000000000000044', '2031-06-18', -3333, 'LOAN')),
  1,
  'one more installment of 33.33'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.plan_update('PP0000000000000040', 0, 3, '2031-05-19', 'PP0000000000000044')),
  pg_temp.counts(0, 0, 0),
  'a complete plan takes no installment more'
);
reset role;
select results_eq(
  $$select * from pg_temp.line_of('PP0000000000000044')$$,
  $$values (null::uuid, null::text, null::uuid)$$,
  'that installment stays free'
);

-- Two plans of Bruno with the same installment: the next one goes to the
-- oldest; one 18 days after the first installment goes to none.
set local role service_role;
select is(
  pg_temp.ingest('72',
    pg_temp.paypal_row('PB0000000000000001', '2031-03-02', -9000, 'PAYMENT', 'Negozio Prova'),
    pg_temp.paypal_row('PB0000000000000002', '2031-03-02', -3000, 'LOAN'),
    pg_temp.paypal_row('PB0000000000000003', '2031-03-05', -9000, 'PAYMENT', 'Negozio Esempio'),
    pg_temp.paypal_row('PB0000000000000004', '2031-03-05', -3000, 'LOAN'),
    pg_temp.paypal_row('PB0000000000000005', '2031-03-20', -3000, 'LOAN'),
    pg_temp.paypal_row('PB0000000000000006', '2031-04-01', -3000, 'LOAN')),
  6,
  'Bruno: two purchases of 90 in three installments of 30, two more installments'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000b1',
    pg_temp.creation('PB0000000000000001', 'PB0000000000000002', 'Negozio Prova', 0, 2,
      '2031-04-01', 'PB0000000000000002', 'PB0000000000000006'),
    pg_temp.creation('PB0000000000000003', 'PB0000000000000004', 'Negozio Esempio', 0, 1,
      '2031-03-05', 'PB0000000000000004')),
  pg_temp.counts(2, 3, 0),
  'the installment of 1 April goes to the oldest plan'
);
reset role;
select results_eq(
  $$select r.entry_reference, l.installment_plan_id
    from public.bank_raw_transactions r
    cross join lateral pg_temp.line_of(r.entry_reference) l
    where r.entry_reference in ('PB0000000000000005', 'PB0000000000000006')
    order by 1$$,
  $$values ('PB0000000000000005'::text, null::uuid),
           ('PB0000000000000006'::text, pg_temp.plan_of('PB0000000000000001'))$$,
  'less than 20 days from the previous installment: no plan'
);

-- On a par: a purchase with two first installments, two purchases for one.
set local role service_role;
select is(
  pg_temp.ingest('72',
    pg_temp.paypal_row('PB0000000000000007', '2031-03-25', -9000, 'PAYMENT', 'Negozio Prova'),
    pg_temp.paypal_row('PB0000000000000008', '2031-03-25', -3000, 'LOAN'),
    pg_temp.paypal_row('PB0000000000000009', '2031-03-25', -3000, 'LOAN'),
    pg_temp.paypal_row('PB0000000000000010', '2031-03-26', -6000, 'PAYMENT', 'Negozio Prova'),
    pg_temp.paypal_row('PB0000000000000011', '2031-03-26', -6000, 'PAYMENT', 'Negozio Esempio'),
    pg_temp.paypal_row('PB0000000000000012', '2031-03-26', -3000, 'LOAN')),
  6,
  'Bruno: purchases and installments on a par'
);
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000b1',
    pg_temp.creation('PB0000000000000007', 'PB0000000000000008', 'Negozio Prova', 0, 1,
      '2031-03-25', 'PB0000000000000008'),
    pg_temp.creation('PB0000000000000010', 'PB0000000000000012', 'Negozio Prova', 0, 1,
      '2031-03-26', 'PB0000000000000012')),
  pg_temp.counts(0, 0, 0),
  'on a par: no plan, even when proposed'
);
reset role;
select results_eq(
  $$select count(*)::int from public.transactions t
    join public.bank_raw_transactions r on r.id = t.raw_id
    where r.entry_reference in ('PB0000000000000007', 'PB0000000000000010', 'PB0000000000000011')
      and t.installment_plan_id is null$$,
  $$values (3)$$,
  'the purchases on a par stay movements, to classify'
);

-- A plan undone by the user: never made again, its purchase and its
-- installments never touched again, nor matched by the transfers and the
-- settlements.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
update public.installment_plans set deleted_at = now()
where id = pg_temp.plan_of('PP0000000000000040');
reset role;

set local role service_role;
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
    pg_temp.creation('PP0000000000000040', 'PP0000000000000041', 'Negozio Prova', 0, 3,
      '2031-05-19', 'PP0000000000000044'),
    pg_temp.plan_update('PP0000000000000040', 0, 3, '2031-05-19', 'PP0000000000000044')),
  pg_temp.counts(0, 0, 0),
  'a deleted plan is not made again nor updated'
);
select is(
  (select p -> 'deleted'
   from jsonb_array_elements(
     public.installment_candidates('00000000-0000-4000-8000-0000000000a1', '2031-02-03') -> 'plans'
   ) as e (p)
   where (p ->> 'id')::uuid = pg_temp.plan_of('PP0000000000000040')),
  'true'::jsonb,
  'the candidates still carry the deleted plan, marked'
);
select results_eq(
  $$select (pg_temp.candidate('PP0000000000000042') ->> 'cancelled')::boolean,
           (pg_temp.candidate('PP0000000000000041') ->> 'cancelled')::boolean,
           (pg_temp.candidate('PP0000000000000003') ->> 'cancelled')::boolean$$,
  $$values (true, true, false)$$,
  'the installments of the deleted plan are cancelled, the others not'
);
reset role;
select results_eq(
  $$select tm.free, tm.in_transfer, tm.cancelled, sm.free, sm.cancelled
    from public.transfer_movement_state(pg_temp.tx_of('PP0000000000000042')) tm,
         public.settlement_movement_state(pg_temp.tx_of('PP0000000000000042')) sm$$,
  $$values (false, false, true, false, true)$$,
  'cancelled for the transfers and the settlements too'
);
set local role service_role;
select is(
  public.apply_transfers('00000000-0000-4000-8000-0000000000a1', jsonb_build_array(jsonb_build_object(
    'from_account_id', pg_temp.acc('74'), 'to_account_id', pg_temp.acc('71'),
    'out_transaction_id', pg_temp.tx_of('CREDEM-20310420-0000203-001'),
    'in_transaction_id', null,
    'funded_transaction_id', pg_temp.tx_of('PP0000000000000042')))),
  0,
  'an installment of a deleted plan is never funded by an automatic transfer'
);
reset role;
select throws_ok(
  $$insert into public.installment_plans (
      household_id, account_id, merchant, total_cents, installments_count, purchase_date, purchase_raw_id
    ) values (
      '00000000-0000-4000-8000-0000000000f1', pg_temp.acc('71'), 'Negozio Prova', 10000, 3,
      '2031-03-20', pg_temp.raw_of('PP0000000000000040')
    )$$,
  '23505', null,
  'one plan for each purchase, also when the plan is deleted'
);

-- Another household: Dario never makes a plan of Anna.
set local role service_role;
select is(
  pg_temp.apply('00000000-0000-4000-8000-0000000000d1',
    pg_temp.creation('PP0000000000000020', 'PP0000000000000021', 'Libreria Prova', 0, 1,
      '2031-03-15', 'PP0000000000000021'),
    pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11', 'PP0000000000000044')),
  pg_temp.counts(0, 0, 0),
  'Dario neither creates nor updates a plan of Anna'
);
select is(
  public.installment_candidates('00000000-0000-4000-8000-0000000000d1', '2031-02-03'),
  '{"start_date": "2031-03-01", "rows": [], "plans": []}'::jsonb,
  'Dario has no candidate'
);

-- The purchases left on the row of the connection.
reset role;
create temp table runs as
select 'anna' as name, run_id as id
from public.begin_sync_run('00000000-0000-4000-8000-0000000000e1', 'admin');
insert into runs
select 'bruno', run_id from public.begin_sync_run('00000000-0000-4000-8000-0000000000e2', 'admin');
grant select on runs to service_role;
set local role service_role;
select lives_ok(
  $$select public.finish_sync_run((select id from runs where name = 'anna'), 'ok', null,
      jsonb_build_object(
        'strategy', 'default', 'purchase_already_classified', 2, 'matched_installments', 3,
        'matched_settlements', 0, 'matched_transfers', 1,
        'accounts', jsonb_build_array(jsonb_build_object(
          'account_id', pg_temp.acc('71'), 'status', 'ok', 'rows_received', 7,
          'purchase_already_classified', 0)))
    )$$,
  'a sync closes with the purchases left at the top of the result'
);
reset role;
select results_eq(
  $$select account_id, purchase_already_classified, matched_installments
    from public.sync_runs
    where id = (select id from runs where name = 'anna') or run_id = (select id from runs where name = 'anna')
    order by account_id nulls first$$,
  $$values (null::uuid, 2, 3), (pg_temp.acc('71'), 0, 0)$$,
  'on the row of the connection only, the rows of the accounts at 0'
);
set local role service_role;
select throws_ok(
  $$select public.finish_sync_run((select id from runs where name = 'bruno'), 'ok', null,
      '{"purchase_already_classified": "due"}')$$,
  'P0001', 'invalid_result',
  'the purchases left are a number'
);

-- Wrong shapes and members
select throws_ok(
  $$select public.apply_installments('00000000-0000-4000-8000-0000000000a1', '{}')$$,
  'P0001', 'invalid_installments', 'the plans are an array'
);
select throws_ok(
  $$select public.apply_installments('00000000-0000-4000-8000-0000000000a1', null)$$,
  'P0001', 'invalid_installments', 'the plans are not null'
);
select throws_ok(
  $$select public.apply_installments('00000000-0000-4000-8000-0000000000a1', '[1]')$$,
  'P0001', 'invalid_installments', 'each plan is an object'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11') || '{"total_cents": 9000}')$$,
  'P0001', 'invalid_installments', 'no other key'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      pg_temp.creation('PP0000000000000001', 'PP0000000000000002', ' ', 1, 3, '2031-04-11'))$$,
  'P0001', 'invalid_installments', 'a new plan has a merchant'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      pg_temp.creation('PP0000000000000001', 'PP0000000000000002', 'Negozio', 1, 3, '2031-04-11')
        - 'first_raw_id')$$,
  'P0001', 'invalid_installments', 'a new plan has its first installment'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      jsonb_set(pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11'), '{merchant}', '"Negozio"'))$$,
  'P0001', 'invalid_installments', 'an update has no merchant'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      jsonb_set(pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11'), '{transaction_ids}', '["rata-4"]'))$$,
  'P0001', 'invalid_installments', 'the installments are uuids'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      jsonb_set(pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11'), '{transaction_ids}', '{}'))$$,
  'P0001', 'invalid_installments', 'the installments are an array'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      jsonb_set(pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11'), '{installments_paid}', '2.5'))$$,
  'P0001', 'invalid_installments', 'the installments paid are an integer'
);
select throws_ok(
  $$select pg_temp.apply('00000000-0000-4000-8000-0000000000a1',
      jsonb_set(pg_temp.plan_update('PP0000000000000001', 1, 3, '2031-04-11'), '{last_installment_date}', '"11 aprile"'))$$,
  'P0001', 'invalid_installments', 'the last installment is a date'
);
select throws_ok(
  $$select public.apply_installments('00000000-0000-4000-8000-0000000000ff', '[]')$$,
  'P0001', 'member_not_eligible', 'an unknown member has no plans'
);
select throws_ok(
  $$select public.installment_candidates('00000000-0000-4000-8000-0000000000ff', '2031-02-03')$$,
  'P0001', 'member_not_eligible', 'an unknown member has no candidates'
);
select throws_ok(
  $$select public.installment_candidates('00000000-0000-4000-8000-0000000000a1', null)$$,
  'P0001', 'invalid_since', 'the candidates need a date'
);

-- Permissions
reset role;
select is_empty(
  $$select p.oid::regprocedure
    from pg_proc p
    where p.oid in (
        'public.installment_row_role(jsonb)'::regprocedure,
        'public.installment_count(bigint, bigint)'::regprocedure,
        'public.installment_rows(uuid)'::regprocedure,
        'public.installment_candidates(uuid, date)'::regprocedure,
        'public.installment_plan_classifies(uuid, uuid)'::regprocedure,
        'public.purchase_movement_untouched(uuid)'::regprocedure,
        'public.apply_installments(uuid, jsonb)'::regprocedure,
        'public.check_lines_sum(uuid)'::regprocedure,
        'public.transfer_movement_state(uuid)'::regprocedure,
        'public.finish_sync_run(uuid, text, text, jsonb)'::regprocedure
      )
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))$$,
  'the app and anon execute none of the new or changed functions'
);
select ok(
  has_function_privilege('service_role', 'public.installment_candidates(uuid, date)', 'execute')
    and has_function_privilege('service_role', 'public.apply_installments(uuid, jsonb)', 'execute'),
  'the service role reads the candidates and writes the plans'
);

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$select public.installment_candidates('00000000-0000-4000-8000-0000000000a1', '2031-02-03')$$,
  '42501', null,
  'the app does not read the candidates'
);
select throws_ok(
  $$select public.apply_installments('00000000-0000-4000-8000-0000000000a1', '[]')$$,
  '42501', null,
  'the app does not write plans'
);
set local role anon;
select throws_ok(
  $$select public.installment_candidates('00000000-0000-4000-8000-0000000000a1', '2031-02-03')$$,
  '42501', null,
  'anon does not read the candidates'
);
select throws_ok(
  $$select public.apply_installments('00000000-0000-4000-8000-0000000000a1', '[]')$$,
  '42501', null,
  'anon does not write plans'
);
reset role;

select * from finish();
rollback;
