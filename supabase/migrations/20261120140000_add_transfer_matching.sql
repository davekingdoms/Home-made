-- Automatic transfers after a sync (docs/spec/sincronizzazione.md, 7, 7.1
-- and 9): the candidates of a member for the rules of eb-sync
-- (supabase/functions/_shared/match/transfers.ts) and the atomic writing of
-- the transfers those rules propose.
--
-- The rules decide in TypeScript; the database reads the candidates and
-- writes the transfers, checking again, under a lock on the member, that
-- the movements are still free. Both functions run only for the service
-- role (eb-sync): the app and anon execute neither. Their errors are only
-- keys, without any value received.

-- The state of a movement for the automatic matches (section 7):
--   free: one line not deleted, without kind and without links (transfer,
--     settlement, installment plan), no installment plan on the movement,
--     and the movement is in no transfer that is not deleted;
--   in_transfer: out, in or funded movement of a transfer not deleted;
--   cancelled: out, in or funded movement of a deleted transfer (undone by
--     the user): never matched automatically again.
create function public.transfer_movement_state(transaction_id uuid)
returns table (free boolean, in_transfer boolean, cancelled boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    ln.lines = 1 and ln.unlinked and t.installment_plan_id is null
      and not coalesce(tf.in_transfer, false),
    coalesce(tf.in_transfer, false),
    coalesce(tf.cancelled, false)
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
  where t.id = transfer_movement_state.transaction_id
$$;

comment on function public.transfer_movement_state(uuid) is
  'Free, in a transfer, in a deleted transfer: the state of a movement for the automatic matches.';

-- The candidates of a member for the automatic transfers (7.1): the
-- accounts with a connection, not archived, and their bank movements with
-- movement_date from `since`, each with its state. eb-sync reads them from
-- 7 days before the window of 45 days: those days only hold the PayPal
-- payments a charge may fund.
-- Returns
--   {accounts: [{id, kind, connection_id, aspsp_name, cash_account_type}],
--    movements: [{transaction_id, account_id, amount_cents, currency,
--                 movement_date, counterparty, description, free,
--                 in_transfer, cancelled}]}
-- in a fixed order. Errors: member_not_eligible, invalid_since.
create function public.transfer_candidates(member_id uuid, since date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.members m
    where m.id = transfer_candidates.member_id
      and m.left_at is null
  ) then
    raise exception 'member_not_eligible';
  end if;
  if transfer_candidates.since is null then
    raise exception 'invalid_since';
  end if;

  return jsonb_build_object(
    'accounts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'kind', a.kind,
          'connection_id', a.connection_id,
          'aspsp_name', c.aspsp_name,
          'cash_account_type', a.cash_account_type
        )
        order by a.id
      )
      from public.accounts a
      join public.bank_connections c on c.id = a.connection_id
      where a.owner_member_id = transfer_candidates.member_id
        and a.archived_at is null
    ), '[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'transaction_id', t.id,
          'account_id', t.account_id,
          'amount_cents', t.amount_cents,
          'currency', t.currency,
          'movement_date', t.movement_date,
          'counterparty', t.counterparty,
          'description', t.description,
          'free', s.free,
          'in_transfer', s.in_transfer,
          'cancelled', s.cancelled
        )
        order by t.movement_date, t.id
      )
      from public.transactions t
      join public.accounts a on a.id = t.account_id
      cross join lateral public.transfer_movement_state(t.id) s
      where a.owner_member_id = transfer_candidates.member_id
        and a.connection_id is not null
        and a.archived_at is null
        and t.source = 'bank'
        and t.movement_date >= transfer_candidates.since
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.transfer_candidates(uuid, date) is
  'Accounts and bank movements of a member from a date, with their state, for the automatic transfers. Errors: member_not_eligible, invalid_since.';

-- Writes the automatic transfers proposed by eb-sync for a member, in one
-- transaction, one member at a time: the syncs of two connections of the
-- same member run together. transfers:
--   [{from_account_id, to_account_id, out_transaction_id, in_transaction_id,
--     funded_transaction_id}]
-- with the two accounts and at least one movement; funded only with the
-- outgoing movement. Every condition is checked again, and a transfer that
-- no longer holds is skipped and not counted:
--   - the two accounts are different accounts of the member, with a
--     connection and not archived;
--   - the outgoing movement is a bank movement of the first account, an
--     outflow, free and in no deleted transfer; the incoming one the same
--     on the second account, an inflow, with the same amount and currency;
--   - the funded payment is an outflow of the second account, a PayPal
--     account, with the same amount and currency as the outgoing movement,
--     in no transfer (not already funded) and in no deleted transfer.
-- The lines of the movements take kind transfer and the transfer; category,
-- shares and the transactions themselves (their version) do not change.
-- Returns the number of transfers created. Errors: invalid_transfers
-- (without the value that failed), member_not_eligible.
create function public.apply_transfers(member_id uuid, transfers jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_member_id uuid;
  v_from public.accounts%rowtype;
  v_to public.accounts%rowtype;
  v_out_id uuid;
  v_in_id uuid;
  v_funded_id uuid;
  v_out public.transactions%rowtype;
  v_in public.transactions%rowtype;
  v_funded public.transactions%rowtype;
  v_state record;
  v_transfer_id uuid;
  v_created int := 0;
begin
  -- Shape and types, one check at a time. Casts put the value in the
  -- message: invalid_transfers.
  begin
    if jsonb_typeof(apply_transfers.transfers) is distinct from 'array' then
      raise exception 'invalid_transfers';
    end if;
    for v_item in select e.value from jsonb_array_elements(apply_transfers.transfers) as e (value) loop
      if jsonb_typeof(v_item) is distinct from 'object' then
        raise exception 'invalid_transfers';
      end if;
      if exists (
        select 1 from jsonb_object_keys(v_item) as k (key)
        where k.key not in (
          'from_account_id', 'to_account_id', 'out_transaction_id', 'in_transaction_id',
          'funded_transaction_id'
        )
      ) then
        raise exception 'invalid_transfers';
      end if;
      if jsonb_typeof(v_item -> 'from_account_id') is distinct from 'string'
        or jsonb_typeof(v_item -> 'to_account_id') is distinct from 'string'
        or coalesce(jsonb_typeof(v_item -> 'out_transaction_id'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_item -> 'in_transaction_id'), 'null') not in ('string', 'null')
        or coalesce(jsonb_typeof(v_item -> 'funded_transaction_id'), 'null') not in ('string', 'null')
      then
        raise exception 'invalid_transfers';
      end if;
      if (v_item ->> 'out_transaction_id') is null and (v_item ->> 'in_transaction_id') is null then
        raise exception 'invalid_transfers';
      end if;
      if (v_item ->> 'funded_transaction_id') is not null and (v_item ->> 'out_transaction_id') is null then
        raise exception 'invalid_transfers';
      end if;
      perform (v_item ->> 'from_account_id')::uuid,
        (v_item ->> 'to_account_id')::uuid,
        (v_item ->> 'out_transaction_id')::uuid,
        (v_item ->> 'in_transaction_id')::uuid,
        (v_item ->> 'funded_transaction_id')::uuid;
    end loop;
  exception
    when data_exception then
      raise exception 'invalid_transfers';
  end;

  select m.id into v_member_id
  from public.members m
  where m.id = apply_transfers.member_id
    and m.left_at is null;
  if not found then
    raise exception 'member_not_eligible';
  end if;

  -- One member at a time: two connections of the same member sync
  -- together. The matches of section 7 share this lock.
  perform pg_advisory_xact_lock(hashtextextended('matches:' || v_member_id::text, 0));

  for v_item in
    select e.value
    from jsonb_array_elements(apply_transfers.transfers) with ordinality as e (value, ord)
    order by e.ord
  loop
    v_out_id := (v_item ->> 'out_transaction_id')::uuid;
    v_in_id := (v_item ->> 'in_transaction_id')::uuid;
    v_funded_id := (v_item ->> 'funded_transaction_id')::uuid;

    -- Two different accounts of the member, with a connection.
    select a.* into v_from
    from public.accounts a
    where a.id = (v_item ->> 'from_account_id')::uuid
      and a.owner_member_id = v_member_id
      and a.connection_id is not null
      and a.archived_at is null;
    continue when not found;
    select a.* into v_to
    from public.accounts a
    where a.id = (v_item ->> 'to_account_id')::uuid
      and a.owner_member_id = v_member_id
      and a.connection_id is not null
      and a.archived_at is null;
    continue when not found or v_to.id = v_from.id;

    -- The lines are locked before they are read: the app waits until the
    -- end, and what it changed before is seen here.
    perform 1
    from public.transaction_lines l
    where l.transaction_id in (v_out_id, v_in_id)
    order by l.id
    for update;

    if v_out_id is not null then
      select t.* into v_out
      from public.transactions t
      where t.id = v_out_id
        and t.account_id = v_from.id
        and t.source = 'bank'
        and t.amount_cents < 0;
      continue when not found;
      select * into v_state from public.transfer_movement_state(v_out_id);
      continue when not v_state.free or v_state.cancelled;
    end if;

    if v_in_id is not null then
      select t.* into v_in
      from public.transactions t
      where t.id = v_in_id
        and t.account_id = v_to.id
        and t.source = 'bank'
        and t.amount_cents > 0;
      continue when not found;
      continue when v_out_id is not null
        and (v_in.amount_cents <> -v_out.amount_cents or v_in.currency <> v_out.currency);
      select * into v_state from public.transfer_movement_state(v_in_id);
      continue when not v_state.free or v_state.cancelled;
    end if;

    if v_funded_id is not null then
      continue when v_to.kind <> 'paypal';
      select t.* into v_funded
      from public.transactions t
      where t.id = v_funded_id
        and t.account_id = v_to.id
        and t.source = 'bank'
        and t.amount_cents = v_out.amount_cents
        and t.currency = v_out.currency;
      continue when not found;
      select * into v_state from public.transfer_movement_state(v_funded_id);
      continue when v_state.in_transfer or v_state.cancelled;
    end if;

    insert into public.transfers (
      household_id, from_account_id, to_account_id, out_transaction_id, in_transaction_id,
      funded_transaction_id, origin
    )
    values (
      v_from.household_id, v_from.id, v_to.id, v_out_id, v_in_id, v_funded_id, 'auto'
    )
    returning id into v_transfer_id;

    update public.transaction_lines l
    set kind = 'transfer',
        transfer_id = v_transfer_id
    where l.transaction_id in (v_out_id, v_in_id)
      and l.deleted_at is null;

    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$$;

comment on function public.apply_transfers(uuid, jsonb) is
  'Writes the automatic transfers proposed for a member, checking again that their movements are free; returns how many were created. Errors: invalid_transfers, member_not_eligible.';

-- Only the service role.

revoke all on function public.transfer_movement_state(uuid) from public, anon, authenticated;
revoke all on function public.transfer_candidates(uuid, date) from public, anon, authenticated;
revoke all on function public.apply_transfers(uuid, jsonb) from public, anon, authenticated;

grant execute on function public.transfer_candidates(uuid, date) to service_role;
grant execute on function public.apply_transfers(uuid, jsonb) to service_role;
