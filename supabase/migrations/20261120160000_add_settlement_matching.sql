-- PayPal settlements after a sync (docs/spec/sincronizzazione.md, 7, 7.2
-- and 9): the candidates of a member for the rules of eb-sync
-- (supabase/functions/_shared/match/settlements.ts) and the atomic writing
-- of the settlements those rules propose.
--
-- As for the automatic transfers, the rules decide in TypeScript and the
-- database reads the candidates and writes, checking everything again. The
-- emails are compared only here: the candidates carry the member an email
-- belongs to, never the email. The two sides of a settlement arrive from
-- the syncs of two different members, which run together: the writing
-- holds the lock of the owner and of every other member of the proposals.
-- Both functions run only for the service role (eb-sync): the app and anon
-- execute neither. Their errors are only keys, without any value received.

-- The state of a movement for the automatic transfers, now also with the
-- settlements (section 7.1): a side of a settlement not deleted is not
-- free, a side of a deleted settlement (undone by the user) is cancelled,
-- like a movement of a deleted transfer. Same signature: transfer_candidates
-- and apply_transfers read it as before.
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
    coalesce(tf.cancelled, false) or coalesce(st.cancelled, false)
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
  where t.id = transfer_movement_state.transaction_id
$$;

comment on function public.transfer_movement_state(uuid) is
  'Free, in a transfer, in a deleted transfer or settlement: the state of a movement for the automatic matches.';

-- The state of a movement for the PayPal settlements (section 7):
--   free: one line not deleted, without kind and without links, no
--     installment plan on the movement, not the outgoing or incoming
--     movement of a transfer and not a side of a settlement, both not
--     deleted. Unlike the transfers, a payment funded by a transfer is free:
--     the funding does not classify it (7.1);
--   cancelled: as for the transfers, in a deleted transfer or settlement.
-- Internal.
create function public.settlement_movement_state(transaction_id uuid)
returns table (free boolean, cancelled boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    ln.lines = 1 and ln.unlinked and t.installment_plan_id is null
      and not exists (
        select 1 from public.transfers tr
        where tr.deleted_at is null
          and t.id in (tr.out_transaction_id, tr.in_transaction_id)
      )
      and not exists (
        select 1 from public.settlements s
        where s.deleted_at is null
          and t.id in (s.payer_transaction_id, s.payee_transaction_id)
      ),
    ts.cancelled
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
  cross join lateral public.transfer_movement_state(t.id) ts
  where t.id = settlement_movement_state.transaction_id
$$;

comment on function public.settlement_movement_state(uuid) is
  'Free and cancelled: the state of a movement for the PayPal settlements.';

-- The member a PayPal email belongs to, for a member: an active member of
-- the same household, other than the member, with that email in
-- paypal_emails (compared in lower case); otherwise null. Internal: the
-- email never leaves the database.
create function public.paypal_counterpart_member(member_id uuid, email text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.members o
  join public.paypal_emails pe on pe.email = lower(btrim(paypal_counterpart_member.email))
  join public.members m on m.user_id = pe.user_id
  where o.id = paypal_counterpart_member.member_id
    and m.household_id = o.household_id
    and m.left_at is null
    and m.id <> o.id
$$;

comment on function public.paypal_counterpart_member(uuid, text) is
  'The active member of the same household a PayPal email belongs to, or null.';

-- The candidates of a member for the PayPal settlements (7.2): the bank
-- movements of the PayPal accounts of the member with a connection, not
-- archived, with movement_date from `since`, each with the reference of
-- the bank, the member of the same household its counterparty email
-- belongs to (never the email) and its state; and the settlements not
-- deleted of the member, as payer or payee, with settled_on from 3 days
-- before `since`, with the references of the sides already linked.
-- Returns
--   {movements: [{transaction_id, account_id, amount_cents, currency,
--                 movement_date, entry_reference, counterpart_member_id,
--                 free, cancelled}],
--    settlements: [{id, payer_member_id, payee_member_id, amount_cents,
--                   currency, settled_on, payer_transaction_id,
--                   payee_transaction_id, payer_entry_reference,
--                   payee_entry_reference}]}
-- in a fixed order. Errors: member_not_eligible, invalid_since.
create function public.settlement_candidates(member_id uuid, since date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.members m
    where m.id = settlement_candidates.member_id
      and m.left_at is null
  ) then
    raise exception 'member_not_eligible';
  end if;
  if settlement_candidates.since is null then
    raise exception 'invalid_since';
  end if;

  return jsonb_build_object(
    'movements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'transaction_id', t.id,
          'account_id', t.account_id,
          'amount_cents', t.amount_cents,
          'currency', t.currency,
          'movement_date', t.movement_date,
          'entry_reference', r.entry_reference,
          'counterpart_member_id',
            public.paypal_counterpart_member(settlement_candidates.member_id, t.counterparty_email),
          'free', s.free,
          'cancelled', s.cancelled
        )
        order by t.movement_date, t.id
      )
      from public.transactions t
      join public.accounts a on a.id = t.account_id
      left join public.bank_raw_transactions r on r.id = t.raw_id
      cross join lateral public.settlement_movement_state(t.id) s
      where a.owner_member_id = settlement_candidates.member_id
        and a.kind = 'paypal'
        and a.connection_id is not null
        and a.archived_at is null
        and t.source = 'bank'
        and t.movement_date >= settlement_candidates.since
    ), '[]'::jsonb),
    'settlements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'payer_member_id', s.payer_member_id,
          'payee_member_id', s.payee_member_id,
          'amount_cents', s.amount_cents,
          'currency', s.currency,
          'settled_on', s.settled_on,
          'payer_transaction_id', s.payer_transaction_id,
          'payee_transaction_id', s.payee_transaction_id,
          'payer_entry_reference', rp.entry_reference,
          'payee_entry_reference', re.entry_reference
        )
        order by s.settled_on, s.id
      )
      from public.settlements s
      left join public.transactions tp on tp.id = s.payer_transaction_id
      left join public.bank_raw_transactions rp on rp.id = tp.raw_id
      left join public.transactions te on te.id = s.payee_transaction_id
      left join public.bank_raw_transactions re on re.id = te.raw_id
      where s.deleted_at is null
        and settlement_candidates.member_id in (s.payer_member_id, s.payee_member_id)
        and s.settled_on >= settlement_candidates.since - 3
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.settlement_candidates(uuid, date) is
  'PayPal movements of a member from a date, with the member of their counterparty, and the settlements of the member, for the PayPal settlements. Errors: member_not_eligible, invalid_since.';

-- Writes the PayPal settlements proposed by eb-sync for a member, in one
-- transaction. settlements:
--   [{transaction_id, counterpart_member_id, settlement_id}]
-- with settlement_id null to create a settlement. The lock of the member and
-- of every counterpart, in the order of their ids, is taken before reading:
-- the two sides of a settlement come from the syncs of two members, which
-- run together. The links go before the creations. Every condition is
-- checked again, and a proposal that no longer holds is skipped and not
-- counted:
--   - the movement is a bank movement of a PayPal account of the member,
--     with a connection and not archived, in EUR, free and in no deleted
--     transfer or settlement;
--   - its counterparty email belongs to the counterpart, an active member of
--     the same household other than the member: an outflow is paid to the
--     counterpart, an inflow is received from the counterpart;
--   - a link: the settlement is not deleted, same payer and payee, same
--     amount and currency, settled_on at most 3 days from the movement, the
--     side of the member still empty. Amount, date and origin do not change;
--   - a creation: no settlement would take the movement (the same check as
--     a link, for any settlement); the new one is paypal, settled on the
--     date of the movement, created by the server;
--   - payer and payee are active members of the household with a start date
--     not after settled_on.
-- The line of the movement takes kind settlement and the settlement;
-- category, shares and the transaction itself (its version) do not change.
-- Returns the number of movements linked (sides). Errors:
-- invalid_settlements (without the value that failed), member_not_eligible.
create function public.apply_settlements(member_id uuid, settlements jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_member public.members%rowtype;
  v_lock_id uuid;
  v_transaction_id uuid;
  v_counterpart_id uuid;
  v_settlement_id uuid;
  v_transaction public.transactions%rowtype;
  v_settlement public.settlements%rowtype;
  v_state record;
  v_payer_id uuid;
  v_payee_id uuid;
  v_amount bigint;
  v_paid boolean;
  v_settled_on date;
  v_linked int := 0;
begin
  -- Shape and types, one check at a time. Casts put the value in the
  -- message: invalid_settlements.
  begin
    if jsonb_typeof(apply_settlements.settlements) is distinct from 'array' then
      raise exception 'invalid_settlements';
    end if;
    for v_item in select e.value from jsonb_array_elements(apply_settlements.settlements) as e (value) loop
      if jsonb_typeof(v_item) is distinct from 'object' then
        raise exception 'invalid_settlements';
      end if;
      if exists (
        select 1 from jsonb_object_keys(v_item) as k (key)
        where k.key not in ('transaction_id', 'counterpart_member_id', 'settlement_id')
      ) then
        raise exception 'invalid_settlements';
      end if;
      if jsonb_typeof(v_item -> 'transaction_id') is distinct from 'string'
        or jsonb_typeof(v_item -> 'counterpart_member_id') is distinct from 'string'
        or coalesce(jsonb_typeof(v_item -> 'settlement_id'), 'null') not in ('string', 'null')
      then
        raise exception 'invalid_settlements';
      end if;
      perform (v_item ->> 'transaction_id')::uuid,
        (v_item ->> 'counterpart_member_id')::uuid,
        (v_item ->> 'settlement_id')::uuid;
    end loop;
  exception
    when data_exception then
      raise exception 'invalid_settlements';
  end;

  select m.* into v_member
  from public.members m
  where m.id = apply_settlements.member_id
    and m.left_at is null;
  if not found then
    raise exception 'member_not_eligible';
  end if;

  -- The member and every counterpart, in the order of their ids: the sync
  -- of the counterpart takes the same locks in the same order. The matches
  -- of section 7 share these locks.
  for v_lock_id in
    select x.id
    from (
      select v_member.id as id
      union
      select (e.value ->> 'counterpart_member_id')::uuid
      from jsonb_array_elements(apply_settlements.settlements) as e (value)
    ) x
    order by x.id
  loop
    perform pg_advisory_xact_lock(hashtextextended('matches:' || v_lock_id::text, 0));
  end loop;

  for v_item in
    select e.value
    from jsonb_array_elements(apply_settlements.settlements) with ordinality as e (value, ord)
    order by (e.value ->> 'settlement_id') is null, e.ord
  loop
    v_transaction_id := (v_item ->> 'transaction_id')::uuid;
    v_counterpart_id := (v_item ->> 'counterpart_member_id')::uuid;
    v_settlement_id := (v_item ->> 'settlement_id')::uuid;

    -- The lines are locked before they are read: the app waits until the
    -- end, and what it changed before is seen here.
    perform 1
    from public.transaction_lines l
    where l.transaction_id = v_transaction_id
    order by l.id
    for update;

    -- A movement of a PayPal account of the member, in EUR.
    select t.* into v_transaction
    from public.transactions t
    join public.accounts a on a.id = t.account_id
    where t.id = v_transaction_id
      and t.source = 'bank'
      and t.currency = 'EUR'
      and t.amount_cents <> 0
      and a.owner_member_id = v_member.id
      and a.kind = 'paypal'
      and a.connection_id is not null
      and a.archived_at is null;
    continue when not found;
    select * into v_state from public.settlement_movement_state(v_transaction_id);
    continue when not v_state.free or v_state.cancelled;

    -- The email of the counterparty is still of the counterpart.
    continue when public.paypal_counterpart_member(v_member.id, v_transaction.counterparty_email)
      is distinct from v_counterpart_id;

    v_paid := v_transaction.amount_cents < 0;
    v_payer_id := case when v_paid then v_member.id else v_counterpart_id end;
    v_payee_id := case when v_paid then v_counterpart_id else v_member.id end;
    v_amount := abs(v_transaction.amount_cents);

    if v_settlement_id is not null then
      select s.* into v_settlement
      from public.settlements s
      where s.id = v_settlement_id
      for update;
      continue when not found
        or v_settlement.deleted_at is not null
        or v_settlement.household_id <> v_member.household_id
        or v_settlement.payer_member_id <> v_payer_id
        or v_settlement.payee_member_id <> v_payee_id
        or v_settlement.amount_cents <> v_amount
        or v_settlement.currency <> v_transaction.currency
        or abs(v_settlement.settled_on - v_transaction.movement_date) > 3
        or (case when v_paid then v_settlement.payer_transaction_id
                 else v_settlement.payee_transaction_id end) is not null;
      v_settled_on := v_settlement.settled_on;
    else
      -- A new settlement only when no settlement would take the movement.
      continue when exists (
        select 1
        from public.settlements s
        where s.deleted_at is null
          and s.household_id = v_member.household_id
          and s.payer_member_id = v_payer_id
          and s.payee_member_id = v_payee_id
          and s.amount_cents = v_amount
          and s.currency = v_transaction.currency
          and abs(s.settled_on - v_transaction.movement_date) <= 3
          and (case when v_paid then s.payer_transaction_id else s.payee_transaction_id end) is null
      );
      v_settled_on := v_transaction.movement_date;
    end if;

    -- Payer and payee: active members of the household, started by then.
    continue when (
      select count(*)
      from public.members m
      where m.id in (v_payer_id, v_payee_id)
        and m.household_id = v_member.household_id
        and m.left_at is null
        and m.start_date <= v_settled_on
    ) <> 2;

    if v_settlement_id is not null then
      if v_paid then
        update public.settlements s set payer_transaction_id = v_transaction.id where s.id = v_settlement_id;
      else
        update public.settlements s set payee_transaction_id = v_transaction.id where s.id = v_settlement_id;
      end if;
    else
      insert into public.settlements (
        household_id, payer_member_id, payee_member_id, amount_cents, currency, settled_on,
        origin, payer_transaction_id, payee_transaction_id, created_by_member_id
      )
      values (
        v_member.household_id, v_payer_id, v_payee_id, v_amount, v_transaction.currency, v_settled_on,
        'paypal',
        case when v_paid then v_transaction.id end,
        case when v_paid then null else v_transaction.id end,
        null
      )
      returning id into v_settlement_id;
    end if;

    update public.transaction_lines l
    set kind = 'settlement',
        settlement_id = v_settlement_id
    where l.transaction_id = v_transaction.id
      and l.deleted_at is null;

    v_linked := v_linked + 1;
  end loop;

  return v_linked;
end;
$$;

comment on function public.apply_settlements(uuid, jsonb) is
  'Writes the PayPal settlements proposed for a member, checking everything again under the locks of the members; returns how many movements were linked. Errors: invalid_settlements, member_not_eligible.';

-- Only the service role.

revoke all on function public.transfer_movement_state(uuid) from public, anon, authenticated;
revoke all on function public.settlement_movement_state(uuid) from public, anon, authenticated;
revoke all on function public.paypal_counterpart_member(uuid, text) from public, anon, authenticated;
revoke all on function public.settlement_candidates(uuid, date) from public, anon, authenticated;
revoke all on function public.apply_settlements(uuid, jsonb) from public, anon, authenticated;

grant execute on function public.settlement_candidates(uuid, date) to service_role;
grant execute on function public.apply_settlements(uuid, jsonb) to service_role;
