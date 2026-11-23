-- Numbers of the hub (docs/spec/schema.md, 10): how many items there are to
-- classify, the own spending of each month and the total of the own
-- accounts. One definition for the hub, the badge of Movimenti and the
-- Riepilogo.
--
-- unclassified_count() and my_accounts_total() are security invoker: they
-- read with the policies of the caller, so no row becomes visible that the
-- caller could not already read. my_spending_by_month() is security definer:
-- with the policies, can_see_line() would run on every share the member ever
-- had; it reads only the shares of the caller, the other shares of the same
-- lines (which the caller sees) and, of the transaction, only whether it is
-- deleted and its currency, as member_balances() does. All three act only on
-- the active member of the caller (current_member_id()) and take no member
-- id; without a household they give 0, or months at zero. Errors only as
-- keys.

-- The lines still to classify of a member, for unclassified_count(): only a
-- few of all the lines, so the count reads just those.
create index transaction_lines_unclassified
  on public.transaction_lines (paid_by_member_id)
  where kind is null and deleted_at is null;

-- "Da classificare": the transactions of the caller, not deleted, with at
-- least one line not deleted and without kind that does not belong to a
-- plan not deleted and without category; plus the plans of the accounts of
-- the caller, not deleted and without category, whatever their status
-- (also completed, and also born before the start date): such a plan counts
-- 1 in place of its installments. A line of a deleted plan counts with its
-- transaction. The plan of a line is in transaction_lines.installment_plan_id,
-- which apply_installments writes with the one of the transaction. The payer
-- is read from the copy on the line, always the one of the transaction (the
-- triggers keep it): only the lines to classify are read, and then their
-- transactions by id. The exact number: the app shows "99+".
create function public.unclassified_count()
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select (
    (
      select count(distinct l.transaction_id)
      from public.transaction_lines l
      join public.transactions t on t.id = l.transaction_id
      where l.paid_by_member_id = (select public.current_member_id())
        and l.kind is null
        and l.deleted_at is null
        and t.deleted_at is null
        and not exists (
          select 1
          from public.installment_plans p
          where p.id = l.installment_plan_id
            and p.deleted_at is null
            and p.category_id is null
        )
    )
    + (
      select count(*)
      from public.installment_plans p
      join public.accounts a on a.id = p.account_id
      where a.owner_member_id = (select public.current_member_id())
        and p.deleted_at is null
        and p.category_id is null
    )
  )::integer
$$;

comment on function public.unclassified_count() is
  'Items to classify of the caller: own transactions with a line without kind (outside a plan without category) plus own plans without category.';

-- "Le tue spese": one row for each of the last `months` months, the month
-- of `today` included, from the oldest, also at zero; `month` is the first
-- day. `today` is the local date of the phone (the server date is UTC).
-- The own shares of the lines of kind expense, not deleted, in the budget,
-- with the date in the month and from the own start date, of transactions
-- not deleted and in EUR (as member_balances(): the other currencies are
-- postponed). Spending is positive (-sum of the shares): a positive expense
-- line (a refund) lowers it. Personal: lines with only the share of the
-- caller, who paid them (Mia); shared: every other line with a share of the
-- caller (with other members, or paid by another member for the caller
-- alone). Security definer: only lines the caller sees, having a share in
-- them, and their shares; of the transaction only deleted_at and currency.
create function public.my_spending_by_month(today date, months integer default 6)
returns table (month date, shared_cents bigint, personal_cents bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member public.members%rowtype;
  v_first date;
  v_end date;
begin
  if my_spending_by_month.months is null or my_spending_by_month.months not between 1 and 12 then
    raise exception 'invalid_months';
  end if;
  if my_spending_by_month.today is null then
    raise exception 'invalid_date';
  end if;

  -- No row without a household: every month at zero.
  select m.* into v_member from public.members m where m.id = public.current_member_id();
  v_end := (date_trunc('month', my_spending_by_month.today) + interval '1 month')::date;
  v_first := (v_end - interval '1 month' * my_spending_by_month.months)::date;

  return query
  with months_list as (
    select (v_first + interval '1 month' * i)::date as first_day
    from generate_series(0, my_spending_by_month.months - 1) as i
  ),
  own_shares as (
    select date_trunc('month', l.movement_date)::date as first_day,
           -s.amount_cents as cents,
           l.paid_by_member_id = v_member.id and not exists (
             select 1
             from public.line_shares o
             where o.line_id = l.id
               and o.member_id <> v_member.id
           ) as personal
    from public.line_shares s
    join public.transaction_lines l on l.id = s.line_id
    join public.transactions t on t.id = l.transaction_id
    where s.member_id = v_member.id
      and l.kind = 'expense'
      and l.deleted_at is null
      and not l.excluded_from_budget
      and l.movement_date >= v_first
      and l.movement_date < v_end
      and l.movement_date >= v_member.start_date
      and t.deleted_at is null
      and t.currency = 'EUR'
  )
  select ml.first_day,
         coalesce(sum(os.cents) filter (where not os.personal), 0)::bigint,
         coalesce(sum(os.cents) filter (where os.personal), 0)::bigint
  from months_list ml
  left join own_shares os on os.first_day = ml.first_day
  group by ml.first_day
  order by ml.first_day;
end;
$$;

comment on function public.my_spending_by_month(date, integer) is
  'Own spending of the caller in the last months (1-12) up to the month of today: shared and personal, positive. Errors: invalid_months, invalid_date.';

-- Provisional until the accounts screen: the total in EUR cents of the
-- accounts of the caller, not archived and not excluded from the total.
-- Accounts of the banks: the EUR balance of the preferred type; without it
-- (null, or no EUR balance of that type), the first one of ITAV, CLAV,
-- XPCD, ITBD, CLBD, then any other type in alphabetical order; no EUR
-- balance: 0. A negative card stays negative; PayPal only in EUR. Cash and
-- manual accounts in EUR: the opening balance plus the transactions in EUR
-- not deleted; in another currency: 0.
create function public.my_accounts_total()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(
    case
      when a.kind in ('bank', 'card', 'paypal') then coalesce((
        select b.amount_cents
        from public.account_balances b
        where b.account_id = a.id
          and b.currency = 'EUR'
        order by b.balance_type is not distinct from a.preferred_balance_type desc,
                 array_position(array['ITAV', 'CLAV', 'XPCD', 'ITBD', 'CLBD'], b.balance_type) nulls last,
                 b.balance_type
        limit 1
      ), 0)
      when a.currency = 'EUR' then coalesce(a.opening_balance_cents, 0) + coalesce((
        select sum(t.amount_cents)
        from public.transactions t
        where t.account_id = a.id
          and t.deleted_at is null
          and t.currency = 'EUR'
      ), 0)
      else 0
    end
  ), 0)::bigint
  from public.accounts a
  where a.owner_member_id = (select public.current_member_id())
    and a.archived_at is null
    and not a.excluded_from_total
$$;

comment on function public.my_accounts_total() is
  'Provisional total in EUR cents of the accounts of the caller, not archived and not excluded from the total.';

revoke all on function public.unclassified_count() from public, anon;
revoke all on function public.my_spending_by_month(date, integer) from public, anon;
revoke all on function public.my_accounts_total() from public, anon;
grant execute on function public.unclassified_count() to authenticated;
grant execute on function public.my_spending_by_month(date, integer) to authenticated;
grant execute on function public.my_accounts_total() to authenticated;
