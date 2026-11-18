-- Functions on lines, shares and categories (docs/spec/schema.md, 6 and 8).
--
-- They change several rows in one call: the sums are checked at the end of
-- the call by the deferred triggers.

-- Replaces the shares of a line and computes the cents.
-- shares = [{member_id, weight}]. For who sees the transaction and who is
-- involved in the line.
create function public.set_line_shares(line_id uuid, shares jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line public.transaction_lines%rowtype;
begin
  select l.* into v_line
  from public.transaction_lines l
  where l.id = set_line_shares.line_id
  for update;

  if v_line.id is null or not public.can_edit_line(v_line.id) then
    raise exception 'the line cannot be changed' using errcode = 'insufficient_privilege';
  end if;

  if set_line_shares.shares is null
    or jsonb_typeof(set_line_shares.shares) <> 'array'
    or jsonb_array_length(set_line_shares.shares) = 0
  then
    raise exception 'no_members';
  end if;

  -- Left the household, or starting after the date of the line.
  if exists (
    select 1
    from jsonb_array_elements(set_line_shares.shares) as e
    left join public.members m on m.id = (e ->> 'member_id')::uuid
    where m.id is null
      or m.household_id <> v_line.household_id
      or m.left_at is not null
      or m.start_date > v_line.movement_date
  ) then
    raise exception 'member_not_eligible';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(set_line_shares.shares) as e
    where coalesce((e ->> 'weight')::numeric, 0) <= 0
  ) then
    raise exception 'a weight is greater than zero' using errcode = 'check_violation';
  end if;

  delete from public.line_shares s where s.line_id = v_line.id;

  insert into public.line_shares (line_id, member_id, household_id, weight, amount_cents)
  select v_line.id, c.member_id, v_line.household_id, (e ->> 'weight')::numeric, c.amount_cents
  from jsonb_array_elements(set_line_shares.shares) as e
  join public.split_cents(v_line.amount_cents, set_line_shares.shares, v_line.paid_by_member_id) c
    on c.member_id = (e ->> 'member_id')::uuid;
end;
$$;

comment on function public.set_line_shares(uuid, jsonb) is
  'Replaces the shares of a line [{member_id, weight}] and computes the cents. Errors: no_members, member_not_eligible.';

-- Splits a line. parts = [{id, amount_cents}], ids generated on the device:
-- every part becomes a new line that inherits kind, category, flags and
-- weights; the line keeps the rest of its amount. A second call with the
-- same ids does nothing. Only for who sees the transaction.
create function public.split_line(line_id uuid, parts jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line public.transaction_lines%rowtype;
  v_count int;
  v_existing int;
  v_parts_sum bigint;
  v_position smallint;
  v_weights jsonb;
begin
  select l.* into v_line
  from public.transaction_lines l
  where l.id = split_line.line_id
  for update;

  if v_line.id is null or not public.can_see_transaction(v_line.transaction_id) then
    raise exception 'the line cannot be split' using errcode = 'insufficient_privilege';
  end if;

  if split_line.parts is null
    or jsonb_typeof(split_line.parts) <> 'array'
    or jsonb_array_length(split_line.parts) = 0
  then
    raise exception 'invalid_parts';
  end if;

  v_count := jsonb_array_length(split_line.parts);

  select count(*) into v_existing
  from public.transaction_lines l
  where l.id in (select (e ->> 'id')::uuid from jsonb_array_elements(split_line.parts) as e);

  if v_existing = v_count and not exists (
    select 1
    from jsonb_array_elements(split_line.parts) as e
    join public.transaction_lines l on l.id = (e ->> 'id')::uuid
    where l.transaction_id <> v_line.transaction_id
  ) then
    return;
  end if;

  if v_existing > 0
    or v_line.deleted_at is not null
    or (select count(distinct e ->> 'id') from jsonb_array_elements(split_line.parts) as e) <> v_count
    or exists (
      select 1
      from jsonb_array_elements(split_line.parts) as e
      where (e ->> 'id') is null
        or (e ->> 'amount_cents') is null
        or sign((e ->> 'amount_cents')::bigint) <> sign(v_line.amount_cents)
    )
  then
    raise exception 'invalid_parts';
  end if;

  select sum((e ->> 'amount_cents')::bigint) into v_parts_sum
  from jsonb_array_elements(split_line.parts) as e;

  -- The line keeps a part of its amount.
  if abs(v_parts_sum) >= abs(v_line.amount_cents) then
    raise exception 'invalid_parts';
  end if;

  select jsonb_agg(jsonb_build_object('member_id', s.member_id, 'weight', s.weight))
  into v_weights
  from public.line_shares s
  where s.line_id = v_line.id;

  select max(l.position) into v_position
  from public.transaction_lines l
  where l.transaction_id = v_line.transaction_id;

  update public.transaction_lines l
  set amount_cents = l.amount_cents - v_parts_sum
  where l.id = v_line.id;

  insert into public.transaction_lines (
    id, transaction_id, household_id, position, amount_cents, kind, category_id,
    excluded_from_budget, deductible_730, movement_date, counterparty, paid_by_member_id
  )
  select
    (p.e ->> 'id')::uuid,
    v_line.transaction_id,
    v_line.household_id,
    (v_position + p.ord)::smallint,
    (p.e ->> 'amount_cents')::bigint,
    v_line.kind,
    v_line.category_id,
    v_line.excluded_from_budget,
    v_line.deductible_730,
    v_line.movement_date,
    v_line.counterparty,
    v_line.paid_by_member_id
  from jsonb_array_elements(split_line.parts) with ordinality as p (e, ord);

  insert into public.line_shares (line_id, member_id, household_id, weight, amount_cents)
  select (p.e ->> 'id')::uuid, c.member_id, v_line.household_id, (w ->> 'weight')::numeric, c.amount_cents
  from jsonb_array_elements(split_line.parts) as p (e)
  cross join lateral public.split_cents(
    (p.e ->> 'amount_cents')::bigint, v_weights, v_line.paid_by_member_id
  ) c
  join jsonb_array_elements(v_weights) as w on (w ->> 'member_id')::uuid = c.member_id;
end;
$$;

comment on function public.split_line(uuid, jsonb) is
  'Splits a line into new lines [{id, amount_cents}] that inherit kind, category, flags and weights. Errors: invalid_parts.';

-- Merges a category into another: every line (also the ones the caller does
-- not see) and every installment plan moves, and the merged category is
-- archived. The flags of the lines stay as they are.
create function public.merge_categories(from_id uuid, into_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_id uuid := public.current_member_id();
  v_household_id uuid := public.current_household_id();
  v_from public.categories%rowtype;
  v_into public.categories%rowtype;
begin
  if v_member_id is null then
    raise exception 'not_member';
  end if;

  -- Only categories the caller sees.
  select c.* into v_from
  from public.categories c
  where c.id = merge_categories.from_id
    and c.household_id = v_household_id
    and (c.scope = 'shared' or c.owner_member_id = v_member_id)
  for update;

  select c.* into v_into
  from public.categories c
  where c.id = merge_categories.into_id
    and c.household_id = v_household_id
    and (c.scope = 'shared' or c.owner_member_id = v_member_id);

  -- System categories are never merged; a macro with subcategories neither.
  if v_from.id is null
    or v_into.id is null
    or v_from.id = v_into.id
    or v_from.kind <> v_into.kind
    or v_from.system_key is not null
    or v_into.system_key is not null
    or v_from.archived_at is not null
    or v_into.archived_at is not null
    or exists (
      select 1 from public.categories c
      where c.parent_id = v_from.id and c.archived_at is null
    )
  then
    raise exception 'category_not_mergeable';
  end if;

  update public.transaction_lines l
  set category_id = v_into.id
  where l.category_id = v_from.id;

  update public.installment_plans p
  set category_id = v_into.id
  where p.category_id = v_from.id;

  update public.categories c
  set archived_at = now(),
      merged_into_id = v_into.id
  where c.id = v_from.id;
end;
$$;

comment on function public.merge_categories(uuid, uuid) is
  'Moves every line of a category to another and archives the first. Errors: not_member, category_not_mergeable.';

revoke all on function public.set_line_shares(uuid, jsonb) from public, anon;
revoke all on function public.split_line(uuid, jsonb) from public, anon;
revoke all on function public.merge_categories(uuid, uuid) from public, anon;
grant execute on function public.set_line_shares(uuid, jsonb) to authenticated;
grant execute on function public.split_line(uuid, jsonb) to authenticated;
grant execute on function public.merge_categories(uuid, uuid) to authenticated;
