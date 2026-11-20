-- PayPal installment plans after a sync (docs/spec/sincronizzazione.md, 7,
-- 7.3 and 9): the candidates of a member for the rules of eb-sync
-- (supabase/functions/_shared/match/installments.ts) and the atomic writing
-- of the plans and of the installments those rules propose; the state of
-- the movements shared with the transfers and the settlements, now with the
-- plans; the new count of the run.
--
-- As for the transfers and the settlements, the rules decide in TypeScript
-- and the database reads the candidates and writes, checking everything
-- again under the lock of the owner. Both functions run only for the
-- service role (eb-sync): the app and anon execute neither. Their errors
-- are only keys, without any value received.

-- One plan for each purchase, also for the deleted plans: a plan undone by
-- the user is never made again.
create unique index installment_plans_purchase_raw_id
  on public.installment_plans (purchase_raw_id);

-- A transaction that no longer exists has no line to add up: the server
-- deletes the movement of a purchase in installments (7.3), and the
-- deferred check of its deleted lines finds no transaction. Same signature.
create or replace function public.check_lines_sum(transaction_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.transactions t where t.id = check_lines_sum.transaction_id
  ) then
    return;
  end if;

  if (
    select t.amount_cents from public.transactions t where t.id = check_lines_sum.transaction_id
  ) is distinct from (
    select coalesce(sum(l.amount_cents), 0)
    from public.transaction_lines l
    where l.transaction_id = check_lines_sum.transaction_id
      and l.deleted_at is null
  ) then
    raise exception 'lines_sum_mismatch' using errcode = 'check_violation';
  end if;
end;
$$;

revoke all on function public.check_lines_sum(uuid) from public, anon, authenticated;

-- The state of a movement for the automatic matches, now also with the
-- installment plans (sections 7.1 and 7.2): a movement with a plan is not
-- free (as before), a movement of a deleted plan (undone by the user) is
-- cancelled, like a movement of a deleted transfer or settlement. Same
-- signature: transfer_candidates, apply_transfers and
-- settlement_movement_state read it as before. An installment of a plan
-- not deleted is neither in a transfer nor cancelled: a charge of the bank
-- may still fund it.
create or replace function public.transfer_movement_state(transaction_id uuid)
returns table (free boolean, in_transfer boolean, cancelled boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    ln.lines = 1 and ln.unlinked and t.installment_plan_id is null
      and not coalesce(tf.in_transfer, false)
      and not coalesce(st.in_settlement, false),
    coalesce(tf.in_transfer, false),
    coalesce(tf.cancelled, false) or coalesce(st.cancelled, false) or pl.cancelled
  from public.transactions t
  cross join lateral (
    select count(*) as lines,
           coalesce(bool_and(
             l.kind is null
             and l.transfer_id is null
             and l.settlement_id is null
             and l.installment_plan_id is null
           ), false) as unlinked
    from public.transaction_lines l
    where l.transaction_id = t.id
      and l.deleted_at is null
  ) ln
  cross join lateral (
    select bool_or(tr.deleted_at is null) as in_transfer,
           bool_or(tr.deleted_at is not null) as cancelled
    from public.transfers tr
    where t.id in (tr.out_transaction_id, tr.in_transaction_id, tr.funded_transaction_id)
  ) tf
  cross join lateral (
    select bool_or(s.deleted_at is null) as in_settlement,
           bool_or(s.deleted_at is not null) as cancelled
    from public.settlements s
    where t.id in (s.payer_transaction_id, s.payee_transaction_id)
  ) st
  cross join lateral (
    select exists (
      select 1
      from public.installment_plans p
      where p.deleted_at is not null
        and (
          p.id = t.installment_plan_id
          or exists (
            select 1 from public.transaction_lines l
            where l.transaction_id = t.id
              and l.installment_plan_id = p.id
          )
        )
    ) as cancelled
  ) pl
  where t.id = transfer_movement_state.transaction_id
$$;

comment on function public.transfer_movement_state(uuid) is
  'Free, in a transfer, in a deleted transfer, settlement or plan: the state of a movement for the automatic matches.';

revoke all on function public.transfer_movement_state(uuid) from public, anon, authenticated;

-- The role of a PayPal row in a plan, from bank_transaction_code of the
-- payload: PAYMENT/PAYMENT a purchase, PAYMENT/LOAN an installment
-- (section 8); anything else null. Internal.
create function public.installment_row_role(payload jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when upper(btrim(installment_row_role.payload -> 'bank_transaction_code' ->> 'code')) = 'PAYMENT'
    then case upper(btrim(installment_row_role.payload -> 'bank_transaction_code' ->> 'sub_code'))
      when 'PAYMENT' then 'purchase'
      when 'LOAN' then 'installment'
    end
  end
$$;

comment on function public.installment_row_role(jsonb) is
  'purchase (PAYMENT/PAYMENT), installment (PAYMENT/LOAN) or null: the role of a PayPal row in a plan.';

-- The number of installments of a purchase of `purchase_cents` with a first
-- installment of `installment_cents` (both positive): n = round(P / L)
-- between 2 and 12 with |P - n L| at most n cents (7.3); otherwise null.
-- Internal.
create function public.installment_count(purchase_cents bigint, installment_cents bigint)
returns int
language sql
immutable
set search_path = ''
as $$
  select n
  from (
    select round(installment_count.purchase_cents::numeric / installment_count.installment_cents)::int as n
    where installment_count.purchase_cents > 0
      and installment_count.installment_cents > 0
  ) x
  where n between 2 and 12
    and abs(installment_count.purchase_cents - n * installment_count.installment_cents) <= n
$$;

comment on function public.installment_count(bigint, bigint) is
  'The number of installments of a purchase from its first installment, or null.';

-- The raw rows a plan is made of, for a member: the BOOK outflows in EUR of
-- the PayPal accounts of the member with a connection, not archived, that
-- are an installment (PAYMENT/LOAN) or a purchase (PAYMENT/PAYMENT) with an
-- installment on the same day and account. All the raw rows, not only the
-- window: a plan lasts months, and the raw rows of PayPal start 90 days
-- before the start date. Internal.
create function public.installment_rows(member_id uuid)
returns table (row_id uuid, account_id uuid, role text)
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select r.id, r.account_id, r.movement_date, public.installment_row_role(r.payload) as role
    from public.bank_raw_transactions r
    join public.accounts a on a.id = r.account_id
    where a.owner_member_id = installment_rows.member_id
      and a.kind = 'paypal'
      and a.connection_id is not null
      and a.archived_at is null
      and r.status = 'BOOK'
      and r.currency = 'EUR'
      and r.amount_cents < 0
  )
  select r.id, r.account_id, r.role
  from r
  where r.role = 'installment'
    or (
      r.role = 'purchase'
      and exists (
        select 1 from r l
        where l.role = 'installment'
          and l.account_id = r.account_id
          and l.movement_date = r.movement_date
      )
    )
$$;

comment on function public.installment_rows(uuid) is
  'The PayPal raw rows of a member that can make a plan: installments and purchases with one on the same day.';

-- The candidates of a member for the installment plans (7.3): the start
-- date of the member; the raw rows of installment_rows, each with its role,
-- code and sub-code, the name of the creditor and the remittance
-- information of a purchase (never the email), and the movement it became
-- with its plan and its state (free for the plans as for the settlements:
-- one line not deleted, without kind and links, not the outgoing or
-- incoming movement of a transfer and not a side of a settlement, both not
-- deleted; cancelled in a deleted transfer, settlement or plan); the plans
-- of the PayPal accounts of the member with a connection, not archived,
-- also the deleted ones (marked), whose purchase and installments are never
-- touched again.
-- Returns
--   {start_date,
--    rows: [{raw_id, account_id, status, movement_date, amount_cents,
--            currency, code, sub_code, creditor_name, remittance,
--            transaction_id, installment_plan_id, free, cancelled}],
--    plans: [{id, account_id, purchase_raw_id, purchase_date, total_cents,
--             installments_count, installments_before_start, next_due_date,
--             status, deleted}]}
-- in a fixed order. `since` is checked like the other matches: the rows
-- are all read, eb-sync links only the installments from `since`. Errors:
-- member_not_eligible, invalid_since.
create function public.installment_candidates(member_id uuid, since date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start_date date;
begin
  select m.start_date into v_start_date
  from public.members m
  where m.id = installment_candidates.member_id
    and m.left_at is null;
  if not found then
    raise exception 'member_not_eligible';
  end if;
  if installment_candidates.since is null then
    raise exception 'invalid_since';
  end if;

  return jsonb_build_object(
    'start_date', v_start_date,
    'rows', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'raw_id', r.id,
          'account_id', r.account_id,
          'status', r.status,
          'movement_date', r.movement_date,
          'amount_cents', r.amount_cents,
          'currency', r.currency,
          'code', upper(btrim(r.payload -> 'bank_transaction_code' ->> 'code')),
          'sub_code', upper(btrim(r.payload -> 'bank_transaction_code' ->> 'sub_code')),
          'creditor_name', case when x.role = 'purchase' then r.payload -> 'creditor' ->> 'name' end,
          'remittance', case when x.role = 'purchase' then r.payload -> 'remittance_information' end,
          'transaction_id', t.id,
          'installment_plan_id', t.installment_plan_id,
          'free', coalesce(s.free, false),
          'cancelled', coalesce(s.cancelled, false)
        )
        order by r.movement_date, r.id
      )
      from public.installment_rows(installment_candidates.member_id) x
      join public.bank_raw_transactions r on r.id = x.row_id
      left join public.transactions t on t.id = r.transaction_id
      left join lateral public.settlement_movement_state(t.id) s on true
    ), '[]'::jsonb),
    'plans', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'account_id', p.account_id,
          'purchase_raw_id', p.purchase_raw_id,
          'purchase_date', p.purchase_date,
          'total_cents', p.total_cents,
          'installments_count', p.installments_count,
          'installments_before_start', p.installments_before_start,
          'next_due_date', p.next_due_date,
          'status', p.status,
          'deleted', p.deleted_at is not null
        )
        order by p.purchase_date, p.id
      )
      from public.installment_plans p
      join public.accounts a on a.id = p.account_id
      where a.owner_member_id = installment_candidates.member_id
        and a.kind = 'paypal'
        and a.connection_id is not null
        and a.archived_at is null
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.installment_candidates(uuid, date) is
  'PayPal raw rows that make installment plans, with their movements, and the plans of a member. Errors: member_not_eligible, invalid_since.';

-- The category and the weights of a plan go on the line of an installment
-- only when the line takes them without breaking a check (sections 5 and 6
-- of the schema): an expense category of the household; weights of active
-- members of the household, started by the date of the line; with a weight
-- of a member other than the payer, a shared category other than
-- Differenza di cassa and no personal tag on the line; a personal category
-- only of the payer. Otherwise the installment stays to classify. Internal.
create function public.installment_plan_classifies(plan_id uuid, line_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select exists (select 1 from public.installment_plan_shares w where w.plan_id = p.id)
      and c.household_id = l.household_id
      and c.kind = 'expense'
      and (c.scope = 'shared' or c.owner_member_id = l.paid_by_member_id)
      and not exists (
        select 1
        from public.installment_plan_shares w
        join public.members m on m.id = w.member_id
        where w.plan_id = p.id
          and (m.household_id <> l.household_id
            or m.left_at is not null
            or m.start_date > l.movement_date)
      )
      and (
        not exists (
          select 1 from public.installment_plan_shares w
          where w.plan_id = p.id and w.member_id <> l.paid_by_member_id
        )
        or (
          c.scope = 'shared'
          and c.system_key is null
          and not exists (
            select 1
            from public.line_tags lt
            join public.tags tg on tg.id = lt.tag_id
            where lt.line_id = l.id and tg.scope = 'personal'
          )
        )
      )
    from public.installment_plans p
    join public.categories c on c.id = p.category_id
    join public.transaction_lines l on l.id = installment_plan_classifies.line_id
    where p.id = installment_plan_classifies.plan_id
  ), false)
$$;

comment on function public.installment_plan_classifies(uuid, uuid) is
  'True when the category and the weights of a plan can go on the line of an installment.';

-- The movement of a purchase is still as it was created (7.3): version 1,
-- one line (with version 1, not deleted) without kind, category, tags or
-- links and with the share of 100% of the payer, no plan, in no transfer
-- (also as the funded payment) and no settlement, deleted or not, and no
-- piggy bank or advance. Internal.
create function public.purchase_movement_untouched(transaction_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select t.version = 1
      and t.installment_plan_id is null
      and (select count(*) from public.transaction_lines l where l.transaction_id = t.id) = 1
      and exists (
        select 1
        from public.transaction_lines l
        where l.transaction_id = t.id
          and l.deleted_at is null
          and l.version = 1
          and l.kind is null
          and l.category_id is null
          and l.transfer_id is null
          and l.settlement_id is null
          and l.installment_plan_id is null
          and (select count(*) from public.line_shares s where s.line_id = l.id) = 1
          and exists (
            select 1 from public.line_shares s
            where s.line_id = l.id
              and s.member_id = t.paid_by_member_id
              and s.weight = 1
          )
          and not exists (select 1 from public.line_tags lt where lt.line_id = l.id)
          and not exists (select 1 from public.advances ad where ad.line_id = l.id)
          and not exists (select 1 from public.advance_repayments ar where ar.line_id = l.id)
      )
      and not exists (
        select 1 from public.transfers tr
        where t.id in (tr.out_transaction_id, tr.in_transaction_id, tr.funded_transaction_id)
      )
      and not exists (
        select 1 from public.settlements s
        where t.id in (s.payer_transaction_id, s.payee_transaction_id)
      )
      and not exists (
        select 1 from public.piggy_bank_entries e where e.transaction_id = t.id
      )
    from public.transactions t
    where t.id = purchase_movement_untouched.transaction_id
  ), false)
$$;

comment on function public.purchase_movement_untouched(uuid) is
  'True when the movement of a purchase is still as it was created, and can be deleted.';

-- Writes the installment plans proposed by eb-sync for a member, in one
-- transaction. installments:
--   [{plan_id, purchase_raw_id, first_raw_id, merchant,
--     installments_before_start, installments_paid, last_installment_date,
--     transaction_ids}]
-- plan_id null creates the plan of a purchase (purchase_raw_id, its first
-- installment first_raw_id and merchant required); otherwise the plan is
-- updated (the three null). installments_paid and installments_before_start
-- are the installments of the plan in the raw rows, all and before the
-- start date; last_installment_date is the date of the last one;
-- transaction_ids are the installments to link.
-- The lock of the owner, shared by the matches of section 7, is taken
-- before reading; the raw row of a purchase, the movement of the purchase,
-- the plans to update and the lines to link are locked with for update.
-- Every condition is checked again, and what no longer holds is skipped
-- and not counted:
--   - a creation: a purchase and its first installment on a PayPal account
--     of the member with a connection, not archived, BOOK outflows in EUR,
--     PAYMENT/PAYMENT and PAYMENT/LOAN on the same day, n between 2 and 12
--     with |P - n L| at most n; no other installment for the purchase and no
--     other purchase for the installment (on a par: nothing); no plan for
--     the purchase yet, also deleted; the purchase not in a deleted
--     transfer, settlement or plan. The movement of the purchase is deleted
--     when still as it was created, otherwise left and counted in
--     purchase_already_classified, once, when the plan is created;
--   - an update: a plan not deleted of a PayPal account of the member, with
--     a connection, not archived;
--   - 0 <= installments_before_start <= installments_paid <= n, the last
--     installment not before the purchase;
--   - a link: a bank movement of the account of the plan, BOOK, PAYMENT/LOAN,
--     an outflow in EUR from the date of the purchase, with an amount near
--     the installments of the plan, free and not cancelled, with room in
--     the plan. The transaction and its line take the plan (the version of
--     the transaction goes up: the app sees the change); with the category
--     and the weights of the plan, when they apply, the line takes kind
--     expense, the category and the shares.
-- Status completed when all the installments are paid (next_due_date
-- null), otherwise active with next_due_date the last installment + 30
-- days. Returns {plans_created, matched_installments (movements linked),
-- purchase_already_classified}. Errors: invalid_installments (without the
-- value that failed), member_not_eligible.
create function public.apply_installments(member_id uuid, installments jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_id jsonb;
  v_member public.members%rowtype;
  v_plan public.installment_plans%rowtype;
  v_purchase public.bank_raw_transactions%rowtype;
  v_first public.bank_raw_transactions%rowtype;
  v_household_id uuid;
  v_plan_id uuid;
  v_count int;
  v_before int;
  v_paid int;
  v_last date;
  v_status text;
  v_transaction_id uuid;
  v_line public.transaction_lines%rowtype;
  v_state record;
  v_created int := 0;
  v_linked int := 0;
  v_classified int := 0;
begin
  -- Shape and types, one check at a time. Casts put the value in the
  -- message: invalid_installments.
  begin
    if jsonb_typeof(apply_installments.installments) is distinct from 'array' then
      raise exception 'invalid_installments';
    end if;
    for v_item in select e.value from jsonb_array_elements(apply_installments.installments) as e (value) loop
      if jsonb_typeof(v_item) is distinct from 'object' then
        raise exception 'invalid_installments';
      end if;
      if exists (
        select 1 from jsonb_object_keys(v_item) as k (key)
        where k.key not in (
          'plan_id', 'purchase_raw_id', 'first_raw_id', 'merchant', 'installments_before_start',
          'installments_paid', 'last_installment_date', 'transaction_ids'
        )
      ) then
        raise exception 'invalid_installments';
      end if;
      if coalesce(jsonb_typeof(v_item -> 'plan_id'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_item -> 'purchase_raw_id'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_item -> 'first_raw_id'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_item -> 'merchant'), 'null') not in ('string', 'null')
        or jsonb_typeof(v_item -> 'installments_before_start') is distinct from 'number'
        or jsonb_typeof(v_item -> 'installments_paid') is distinct from 'number'
        or jsonb_typeof(v_item -> 'last_installment_date') is distinct from 'string'
        or jsonb_typeof(v_item -> 'transaction_ids') is distinct from 'array'
      then
        raise exception 'invalid_installments';
      end if;
      -- A creation has its purchase, first installment and merchant; an
      -- update none of them.
      if (v_item ->> 'plan_id') is null and (
          (v_item ->> 'purchase_raw_id') is null
          or (v_item ->> 'first_raw_id') is null
          or coalesce(btrim(v_item ->> 'merchant'), '') = ''
        )
      then
        raise exception 'invalid_installments';
      end if;
      if (v_item ->> 'plan_id') is not null and (
          (v_item ->> 'purchase_raw_id') is not null
          or (v_item ->> 'first_raw_id') is not null
          or (v_item ->> 'merchant') is not null
        )
      then
        raise exception 'invalid_installments';
      end if;
      if (v_item ->> 'last_installment_date') !~ '^\d{4}-\d{2}-\d{2}$'
        or (v_item ->> 'installments_before_start')::numeric
          <> trunc((v_item ->> 'installments_before_start')::numeric)
        or (v_item ->> 'installments_paid')::numeric <> trunc((v_item ->> 'installments_paid')::numeric)
      then
        raise exception 'invalid_installments';
      end if;
      for v_id in select e.value from jsonb_array_elements(v_item -> 'transaction_ids') as e (value) loop
        if jsonb_typeof(v_id) is distinct from 'string' then
          raise exception 'invalid_installments';
        end if;
        perform (v_id #>> '{}')::uuid;
      end loop;
      perform (v_item ->> 'plan_id')::uuid,
        (v_item ->> 'purchase_raw_id')::uuid,
        (v_item ->> 'first_raw_id')::uuid,
        ((v_item ->> 'installments_before_start')::numeric)::smallint,
        ((v_item ->> 'installments_paid')::numeric)::smallint,
        (v_item ->> 'last_installment_date')::date;
    end loop;
  exception
    when data_exception then
      raise exception 'invalid_installments';
  end;

  select m.* into v_member
  from public.members m
  where m.id = apply_installments.member_id
    and m.left_at is null;
  if not found then
    raise exception 'member_not_eligible';
  end if;

  -- One member at a time: a plan is of one account, so the lock of the
  -- owner is enough. The matches of section 7 share this lock.
  perform pg_advisory_xact_lock(hashtextextended('matches:' || v_member.id::text, 0));

  for v_item in
    select e.value
    from jsonb_array_elements(apply_installments.installments) with ordinality as e (value, ord)
    order by e.ord
  loop
    v_before := (v_item ->> 'installments_before_start')::int;
    v_paid := (v_item ->> 'installments_paid')::int;
    v_last := (v_item ->> 'last_installment_date')::date;

    if (v_item ->> 'plan_id') is null then
      -- The purchase, on a PayPal account of the member.
      select r.* into v_purchase
      from public.bank_raw_transactions r
      join public.accounts a on a.id = r.account_id
      where r.id = (v_item ->> 'purchase_raw_id')::uuid
        and a.owner_member_id = v_member.id
        and a.kind = 'paypal'
        and a.connection_id is not null
        and a.archived_at is null
        and r.status = 'BOOK'
        and r.currency = 'EUR'
        and r.amount_cents < 0
        and public.installment_row_role(r.payload) = 'purchase'
      for update of r;
      continue when not found;
      -- One plan for each purchase, also deleted.
      continue when exists (
        select 1 from public.installment_plans p where p.purchase_raw_id = v_purchase.id
      );

      -- Its first installment, the same day on the same account.
      select r.* into v_first
      from public.bank_raw_transactions r
      where r.id = (v_item ->> 'first_raw_id')::uuid
        and r.account_id = v_purchase.account_id
        and r.movement_date = v_purchase.movement_date
        and r.status = 'BOOK'
        and r.currency = 'EUR'
        and r.amount_cents < 0
        and public.installment_row_role(r.payload) = 'installment';
      continue when not found;
      v_count := public.installment_count(-v_purchase.amount_cents, -v_first.amount_cents);
      continue when v_count is null;

      -- On a par: another installment for the purchase, or another purchase
      -- for the installment.
      continue when (
        select count(*)
        from public.bank_raw_transactions r
        where r.account_id = v_purchase.account_id
          and r.movement_date = v_purchase.movement_date
          and r.status = 'BOOK'
          and r.currency = 'EUR'
          and r.amount_cents < 0
          and public.installment_row_role(r.payload) = 'installment'
          and public.installment_count(-v_purchase.amount_cents, -r.amount_cents) is not null
      ) <> 1;
      continue when (
        select count(*)
        from public.bank_raw_transactions r
        where r.account_id = v_purchase.account_id
          and r.movement_date = v_purchase.movement_date
          and r.status = 'BOOK'
          and r.currency = 'EUR'
          and r.amount_cents < 0
          and public.installment_row_role(r.payload) = 'purchase'
          and public.installment_count(-r.amount_cents, -v_first.amount_cents) is not null
      ) <> 1;

      -- A purchase in a deleted transfer, settlement or plan is never
      -- matched again.
      continue when v_purchase.transaction_id is not null and (
        select s.cancelled from public.transfer_movement_state(v_purchase.transaction_id) s
      );

      continue when v_before < 0 or v_before > v_paid or v_paid < 1 or v_paid > v_count
        or v_last < v_purchase.movement_date;

      select a.household_id into v_household_id
      from public.accounts a
      where a.id = v_purchase.account_id;

      v_status := case when v_paid >= v_count then 'completed' else 'active' end;
      insert into public.installment_plans (
        household_id, account_id, merchant, total_cents, installments_count, purchase_date,
        purchase_raw_id, installments_before_start, next_due_date, status
      )
      values (
        v_household_id, v_purchase.account_id, btrim(v_item ->> 'merchant'),
        -v_purchase.amount_cents, v_count, v_purchase.movement_date, v_purchase.id, v_before,
        case when v_status = 'active' then v_last + 30 end, v_status
      )
      returning * into v_plan;
      v_created := v_created + 1;

      -- The purchase is never a movement: deleted when still as it was
      -- created, otherwise left and counted once.
      if v_purchase.transaction_id is not null then
        v_transaction_id := v_purchase.transaction_id;
        perform 1 from public.transactions t where t.id = v_transaction_id for update;
        perform 1
        from public.transaction_lines l
        where l.transaction_id = v_transaction_id
        order by l.id
        for update;

        if public.purchase_movement_untouched(v_transaction_id) then
          delete from public.line_shares s
          using public.transaction_lines l
          where s.line_id = l.id
            and l.transaction_id = v_transaction_id;
          update public.bank_raw_transactions r
          set transaction_id = null
          where r.id = v_purchase.id;
          delete from public.transaction_lines l where l.transaction_id = v_transaction_id;
          delete from public.transactions t where t.id = v_transaction_id;
        else
          v_classified := v_classified + 1;
        end if;
      end if;
    else
      -- A plan not deleted, of a PayPal account of the member.
      select p.* into v_plan
      from public.installment_plans p
      join public.accounts a on a.id = p.account_id
      where p.id = (v_item ->> 'plan_id')::uuid
        and a.owner_member_id = v_member.id
        and a.kind = 'paypal'
        and a.connection_id is not null
        and a.archived_at is null
      for update of p;
      continue when not found or v_plan.deleted_at is not null;
      continue when v_before < 0 or v_before > v_paid or v_paid < 1
        or v_paid > v_plan.installments_count or v_last < v_plan.purchase_date;

      v_status := case when v_paid >= v_plan.installments_count then 'completed' else 'active' end;
      -- Only a real change: the plan keeps its version otherwise.
      update public.installment_plans p
      set installments_before_start = v_before,
          status = v_status,
          next_due_date = case when v_status = 'active' then v_last + 30 end
      where p.id = v_plan.id
        and (p.installments_before_start, p.status, p.next_due_date)
          is distinct from (v_before, v_status, case when v_status = 'active' then v_last + 30 end)
      returning * into v_plan;
      if not found then
        select p.* into v_plan from public.installment_plans p where p.id = (v_item ->> 'plan_id')::uuid;
      end if;
    end if;

    -- The installments that became movements.
    for v_transaction_id in
      select (e.value #>> '{}')::uuid
      from jsonb_array_elements(v_item -> 'transaction_ids') with ordinality as e (value, ord)
      order by e.ord
    loop
      -- The lines are locked before they are read: the app waits until the
      -- end, and what it changed before is seen here.
      perform 1
      from public.transaction_lines l
      where l.transaction_id = v_transaction_id
      order by l.id
      for update;

      continue when not exists (
        select 1
        from public.transactions t
        join public.bank_raw_transactions r on r.id = t.raw_id
        where t.id = v_transaction_id
          and t.source = 'bank'
          and t.account_id = v_plan.account_id
          and t.currency = 'EUR'
          and t.amount_cents < 0
          and t.movement_date >= v_plan.purchase_date
          and r.status = 'BOOK'
          and public.installment_row_role(r.payload) = 'installment'
          -- Near L: n x (L +- 1) for every installment, n cents of rounding.
          and abs(-t.amount_cents * v_plan.installments_count - v_plan.total_cents)
            <= v_plan.installments_count * (v_plan.installments_count + 1)
      );
      select * into v_state from public.settlement_movement_state(v_transaction_id);
      continue when not v_state.free or v_state.cancelled;
      -- Room in the plan.
      continue when v_plan.installments_before_start + (
        select count(*) from public.transactions t where t.installment_plan_id = v_plan.id
      ) >= v_plan.installments_count;

      update public.transactions t
      set installment_plan_id = v_plan.id
      where t.id = v_transaction_id;

      update public.transaction_lines l
      set installment_plan_id = v_plan.id
      where l.transaction_id = v_transaction_id
        and l.deleted_at is null
      returning * into v_line;

      if public.installment_plan_classifies(v_plan.id, v_line.id) then
        update public.transaction_lines l
        set kind = 'expense',
            category_id = v_plan.category_id,
            deductible_730 = (
              select c.deductible_730_default from public.categories c where c.id = v_plan.category_id
            )
        where l.id = v_line.id;

        delete from public.line_shares s where s.line_id = v_line.id;
        insert into public.line_shares (line_id, member_id, household_id, weight, amount_cents)
        select v_line.id, c.member_id, v_line.household_id, w.weight, c.amount_cents
        from public.installment_plan_shares w
        join public.split_cents(
          v_line.amount_cents,
          (select jsonb_agg(jsonb_build_object('member_id', x.member_id, 'weight', x.weight))
           from public.installment_plan_shares x where x.plan_id = v_plan.id),
          v_line.paid_by_member_id
        ) c on c.member_id = w.member_id
        where w.plan_id = v_plan.id;
      end if;

      v_linked := v_linked + 1;
    end loop;
  end loop;

  return jsonb_build_object(
    'plans_created', v_created,
    'matched_installments', v_linked,
    'purchase_already_classified', v_classified
  );
end;
$$;

comment on function public.apply_installments(uuid, jsonb) is
  'Writes the installment plans proposed for a member, checking everything again under the lock of the member; returns the plans created, the installments linked and the purchases left. Errors: invalid_installments, member_not_eligible.';

-- Closes a running sync, as before, with purchase_already_classified at the
-- top of the result: the purchases left by the plans of the run (7.3), on
-- the row of the connection only, added to the counts of the accounts
-- (which stay 0 for this count). Same signature.
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
        'strategy', 'matched_transfers', 'matched_settlements', 'matched_installments',
        'purchase_already_classified', 'accounts'
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
            coalesce(sum(a.purchase_already_classified), 0)
              + coalesce((v_result ->> 'purchase_already_classified')::int, 0),
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
  'Closes a running sync with its outcome, the counts of the accounts and the purchases left by the plans. Errors: run_not_running, invalid_result, account_not_in_connection.';

-- Only the service role.

revoke all on function public.installment_row_role(jsonb) from public, anon, authenticated;
revoke all on function public.installment_count(bigint, bigint) from public, anon, authenticated;
revoke all on function public.installment_rows(uuid) from public, anon, authenticated;
revoke all on function public.installment_candidates(uuid, date) from public, anon, authenticated;
revoke all on function public.installment_plan_classifies(uuid, uuid) from public, anon, authenticated;
revoke all on function public.purchase_movement_untouched(uuid) from public, anon, authenticated;
revoke all on function public.apply_installments(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.finish_sync_run(uuid, text, text, jsonb) from public, anon, authenticated;

grant execute on function public.installment_candidates(uuid, date) to service_role;
grant execute on function public.apply_installments(uuid, jsonb) to service_role;
grant execute on function public.finish_sync_run(uuid, text, text, jsonb) to service_role;
