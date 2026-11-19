-- Completion of the bank links (docs/spec/sincronizzazione.md, 3, 6.4, 6.5
-- and 9): the member of a service call; the connection, the accounts, the
-- balances and the PayPal email of a link, in one transaction; the outcome
-- of a link that did not complete.
--
-- All of them run only for the service role (the Edge Functions): the app
-- and anon execute none. Their errors are only keys, without any value
-- received: a check that fails on a row would print the row in its DETAIL,
-- so those errors become invalid_link.

-- Member of a service call

-- The columns returned by eb_service_member: a type of its own, because a
-- function cannot return a column with the name of its parameter.
create type public.eb_member as (
  member_id uuid,
  user_id uuid,
  household_id uuid,
  start_date date
);

comment on type public.eb_member is
  'Active member returned by eb_service_member.';

-- The member of a call of the Edge Functions: active and with an account.
create function public.eb_service_member(member_id uuid)
returns public.eb_member
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member public.eb_member;
begin
  select m.id, m.user_id, m.household_id, m.start_date
  into v_member
  from public.members m
  where m.id = eb_service_member.member_id
    and m.left_at is null
    and m.user_id is not null;
  if not found then
    raise exception 'member_not_eligible';
  end if;
  return v_member;
end;
$$;

comment on function public.eb_service_member(uuid) is
  'Member, account, household and start date of an active member. Errors: member_not_eligible.';

-- Shape of a link

-- Checks the shape and the types of the link sent by eb-callback:
--   {session_id, valid_until,
--    accounts: [{uid, kind, cash_account_type, currency, identifier,
--                display_name, paypal_email,
--                balances: [{currency, balance_type, amount_cents, reference_date}]}]}
-- Anything else is invalid_link, without the value that failed.
create function public.check_bank_link(link jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_account jsonb;
  v_balance jsonb;
begin
  -- One check at a time: the order of the operands of an or is not fixed,
  -- and jsonb_object_keys fails on anything but an object.
  if jsonb_typeof(link) is distinct from 'object' then
    raise exception 'invalid_link';
  end if;
  if exists (
    select 1 from jsonb_object_keys(link) as k (key)
    where k.key not in ('session_id', 'valid_until', 'accounts')
  ) then
    raise exception 'invalid_link';
  end if;
  if jsonb_typeof(link -> 'session_id') is distinct from 'string'
    or btrim(link ->> 'session_id') = ''
    or jsonb_typeof(link -> 'valid_until') is distinct from 'string'
    or (link ->> 'valid_until') !~ '^\d{4}-\d{2}-\d{2}T'
    or jsonb_typeof(link -> 'accounts') is distinct from 'array'
  then
    raise exception 'invalid_link';
  end if;
  perform (link ->> 'valid_until')::timestamptz;

  -- An account once in a link.
  if (select count(*) from jsonb_array_elements(link -> 'accounts'))
    <> (select count(distinct e.value ->> 'uid') from jsonb_array_elements(link -> 'accounts') as e (value))
  then
    raise exception 'invalid_link';
  end if;

  for v_account in select e.value from jsonb_array_elements(link -> 'accounts') as e (value) loop
    if jsonb_typeof(v_account) is distinct from 'object' then
      raise exception 'invalid_link';
    end if;
    if exists (
      select 1 from jsonb_object_keys(v_account) as k (key)
      where k.key not in (
        'uid', 'kind', 'cash_account_type', 'currency', 'identifier', 'display_name',
        'paypal_email', 'balances'
      )
    ) then
      raise exception 'invalid_link';
    end if;
    if jsonb_typeof(v_account -> 'uid') is distinct from 'string'
      or btrim(v_account ->> 'uid') = ''
      or jsonb_typeof(v_account -> 'kind') is distinct from 'string'
      or (v_account ->> 'kind') not in ('bank', 'card', 'paypal')
      or coalesce(jsonb_typeof(v_account -> 'cash_account_type'), 'null') not in ('string', 'null')
      or jsonb_typeof(v_account -> 'currency') is distinct from 'string'
      or (v_account ->> 'currency') !~ '^[A-Z]{3}$'
      or coalesce(jsonb_typeof(v_account -> 'identifier'), 'null') not in ('string', 'null')
      or jsonb_typeof(v_account -> 'display_name') is distinct from 'string'
      or btrim(v_account ->> 'display_name') = ''
      or coalesce(jsonb_typeof(v_account -> 'paypal_email'), 'null') not in ('string', 'null')
      or jsonb_typeof(v_account -> 'balances') is distinct from 'array'
    then
      raise exception 'invalid_link';
    end if;
    -- The email of the account only for PayPal.
    if (v_account ->> 'paypal_email') is not null
      and ((v_account ->> 'kind') <> 'paypal' or btrim(v_account ->> 'paypal_email') = '')
    then
      raise exception 'invalid_link';
    end if;

    for v_balance in select e.value from jsonb_array_elements(v_account -> 'balances') as e (value) loop
      if jsonb_typeof(v_balance) is distinct from 'object' then
        raise exception 'invalid_link';
      end if;
      if exists (
        select 1 from jsonb_object_keys(v_balance) as k (key)
        where k.key not in ('currency', 'balance_type', 'amount_cents', 'reference_date')
      ) then
        raise exception 'invalid_link';
      end if;
      if jsonb_typeof(v_balance -> 'currency') is distinct from 'string'
        or (v_balance ->> 'currency') !~ '^[A-Z]{3}$'
        or jsonb_typeof(v_balance -> 'balance_type') is distinct from 'string'
        or btrim(v_balance ->> 'balance_type') = ''
        or jsonb_typeof(v_balance -> 'amount_cents') is distinct from 'number'
        or coalesce(jsonb_typeof(v_balance -> 'reference_date'), 'null') not in ('string', 'null')
      then
        raise exception 'invalid_link';
      end if;
      -- Integer cents, within bigint (a cast out of range is a data_exception).
      if (v_balance -> 'amount_cents')::numeric <> trunc((v_balance -> 'amount_cents')::numeric) then
        raise exception 'invalid_link';
      end if;
      perform ((v_balance -> 'amount_cents')::numeric)::bigint;
      if (v_balance ->> 'reference_date') is not null then
        if (v_balance ->> 'reference_date') !~ '^\d{4}-\d{2}-\d{2}$' then
          raise exception 'invalid_link';
        end if;
        perform (v_balance ->> 'reference_date')::date;
      end if;
    end loop;
  end loop;
exception
  -- Casts and jsonb functions put the value in the message.
  when data_exception then
    raise exception 'invalid_link';
end;
$$;

comment on function public.check_bank_link(jsonb) is
  'Checks the shape of a link for complete_bank_link. Errors: invalid_link.';

-- Completion of a link

-- Writes what eb-callback read from Enable Banking, all or nothing: the
-- connection (reused for the same member, bank and country), the accounts
-- (section 6.4), the balances (6.5), the PayPal email of the account, the
-- outcome ok on the request. The request must be claimed by
-- claim_link_request and without an outcome; once claimed, its expiry no
-- longer matters, because the callback works for a while after the claim.
create function public.complete_bank_link(request_id uuid, link jsonb)
returns table (connection_id uuid, account_count int)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_id uuid;
  v_request public.bank_link_requests%rowtype;
  v_member public.eb_member;
  v_connection_id uuid;
  v_account jsonb;
  v_balance jsonb;
  v_account_id uuid;
  v_identifier text;
  v_email text;
  v_email_owner uuid;
  v_count int := 0;
begin
  select r.member_id into v_member_id
  from public.bank_link_requests r
  where r.id = complete_bank_link.request_id;
  if not found then
    raise exception 'link_not_claimable';
  end if;

  -- One link at a time for each member: two callbacks of the same bank
  -- would both create the connection, or the same account twice.
  perform pg_advisory_xact_lock(hashtextextended('bank_link:' || v_member_id::text, 0));

  select r.* into v_request
  from public.bank_link_requests r
  where r.id = complete_bank_link.request_id
  for update;
  if v_request.used_at is null or v_request.result is not null then
    raise exception 'link_not_claimable';
  end if;

  -- The member may have left since the request: nothing is written.
  v_member := public.eb_service_member(v_member_id);

  perform public.check_bank_link(complete_bank_link.link);

  begin
    -- The connection: the one of the same member, bank and country, else a
    -- new one.
    select c.id into v_connection_id
    from public.bank_connections c
    where c.member_id = v_member.member_id
      and c.aspsp_name = v_request.aspsp_name
      and c.aspsp_country = v_request.aspsp_country
    order by c.created_at desc, c.id
    limit 1
    for update;

    if v_connection_id is null then
      insert into public.bank_connections (
        member_id, aspsp_name, aspsp_country, session_id, uses_global_app, status, valid_until
      )
      values (
        v_member.member_id, v_request.aspsp_name, v_request.aspsp_country,
        complete_bank_link.link ->> 'session_id', v_request.uses_global_app, 'active',
        (complete_bank_link.link ->> 'valid_until')::timestamptz
      )
      returning id into v_connection_id;
    else
      update public.bank_connections c
      set session_id = complete_bank_link.link ->> 'session_id',
          valid_until = (complete_bank_link.link ->> 'valid_until')::timestamptz,
          uses_global_app = v_request.uses_global_app,
          status = 'active',
          last_error = null
      where c.id = v_connection_id;
    end if;

    for v_account in
      select e.value from jsonb_array_elements(complete_bank_link.link -> 'accounts') as e (value)
    loop
      v_identifier := nullif(btrim(v_account ->> 'identifier'), '');
      v_account_id := null;

      -- A known account: same owner, same kind, same identifier; else the
      -- same account of Enable Banking in this connection; else a new one.
      if v_identifier is not null then
        select a.id into v_account_id
        from public.accounts a
        where a.owner_member_id = v_member.member_id
          and a.kind = v_account ->> 'kind'
          and a.identifier = v_identifier
        order by a.created_at, a.id
        limit 1
        for update;
      end if;

      if v_account_id is null then
        select a.id into v_account_id
        from public.accounts a
        where a.connection_id = v_connection_id
          and a.provider_account_id = v_account ->> 'uid'
        for update;
      end if;

      if v_account_id is null then
        insert into public.accounts (
          household_id, owner_member_id, kind, connection_id, provider_account_id,
          cash_account_type, currency, display_name, identifier
        )
        values (
          v_member.household_id, v_member.member_id, v_account ->> 'kind', v_connection_id,
          v_account ->> 'uid', v_account ->> 'cash_account_type', v_account ->> 'currency',
          btrim(v_account ->> 'display_name'), v_identifier
        )
        returning id into v_account_id;
      else
        -- The name, the preferences and the archive of the owner stay.
        update public.accounts a
        set kind = v_account ->> 'kind',
            connection_id = v_connection_id,
            provider_account_id = v_account ->> 'uid',
            cash_account_type = v_account ->> 'cash_account_type',
            currency = v_account ->> 'currency',
            identifier = coalesce(v_identifier, a.identifier)
        where a.id = v_account_id;
      end if;

      -- The last value for each currency and type; one statement for each
      -- balance, so a repeated pair keeps the last one.
      for v_balance in select e.value from jsonb_array_elements(v_account -> 'balances') as e (value) loop
        insert into public.account_balances (
          account_id, currency, balance_type, amount_cents, reference_date, fetched_at
        )
        values (
          v_account_id, v_balance ->> 'currency', v_balance ->> 'balance_type',
          ((v_balance -> 'amount_cents')::numeric)::bigint,
          (v_balance ->> 'reference_date')::date, now()
        )
        on conflict (account_id, currency, balance_type) do update
        set amount_cents = excluded.amount_cents,
            reference_date = excluded.reference_date,
            fetched_at = excluded.fetched_at;
      end loop;

      -- The email of a PayPal account, if nobody else has it.
      v_email := lower(nullif(btrim(v_account ->> 'paypal_email'), ''));
      if v_email is not null then
        insert into public.paypal_emails (user_id, email, source)
        values (v_member.user_id, v_email, 'linked_account')
        on conflict (email) do nothing;
        if not found then
          select pe.user_id into v_email_owner
          from public.paypal_emails pe
          where pe.email = v_email;
          if v_email_owner is distinct from v_member.user_id then
            insert into public.sync_runs (connection_id, trigger, status, error_code, finished_at)
            values (v_connection_id, 'link', 'ok', 'paypal_email_taken', now());
          end if;
        end if;
      end if;

      v_count := v_count + 1;
    end loop;

    update public.bank_link_requests r
    set result = 'ok'
    where r.id = v_request.id;
  exception
    when data_exception or check_violation or not_null_violation or unique_violation
      or foreign_key_violation
    then
      raise exception 'invalid_link';
  end;

  complete_bank_link.connection_id := v_connection_id;
  complete_bank_link.account_count := v_count;
  return next;
end;
$$;

comment on function public.complete_bank_link(uuid, jsonb) is
  'Completes a claimed link in one transaction: connection, accounts, balances, PayPal email, outcome ok. Errors: link_not_claimable, member_not_eligible, invalid_link.';

-- Outcome of a link that did not complete

-- The code of a cancelled, rejected or failed link on a claimed request
-- without an outcome; nothing else changes.
create function public.finish_link_request(request_id uuid, result text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if finish_link_request.result is null
    or finish_link_request.result not in ('link_cancelled', 'link_rejected', 'link_failed')
  then
    raise exception 'invalid_result';
  end if;

  update public.bank_link_requests r
  set result = finish_link_request.result
  where r.id = finish_link_request.request_id
    and r.used_at is not null
    and r.result is null;
  if not found then
    raise exception 'link_not_claimable';
  end if;
end;
$$;

comment on function public.finish_link_request(uuid, text) is
  'Writes the outcome of a link that did not complete on a claimed request. Errors: invalid_result, link_not_claimable.';

-- Only the service role.

revoke all on function public.eb_service_member(uuid) from public, anon, authenticated;
revoke all on function public.check_bank_link(jsonb) from public, anon, authenticated;
revoke all on function public.complete_bank_link(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.finish_link_request(uuid, text) from public, anon, authenticated;

grant execute on function public.eb_service_member(uuid) to service_role;
grant execute on function public.check_bank_link(jsonb) to service_role;
grant execute on function public.complete_bank_link(uuid, jsonb) to service_role;
grant execute on function public.finish_link_request(uuid, text) to service_role;
