-- Links of the lines (docs/spec/schema.md, 5): a line links only a
-- settlement, a transfer or an installment plan of its household that
-- concerns it, from the app and from the server.
--   settlement_id: who paid the line is the payer or the payee;
--   transfer_id: the account of the transaction is one of the two accounts;
--   installment_plan_id: the plan is on the account of the transaction.

create function public.check_line_links()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction public.transactions%rowtype;
begin
  select t.* into v_transaction from public.transactions t where t.id = new.transaction_id;

  if new.settlement_id is not null
    and (tg_op = 'INSERT' or new.settlement_id is distinct from old.settlement_id)
    and not exists (
      select 1 from public.settlements s
      where s.id = new.settlement_id
        and s.household_id = v_transaction.household_id
        and v_transaction.paid_by_member_id in (s.payer_member_id, s.payee_member_id)
    )
  then
    raise exception 'line_link_not_valid';
  end if;

  if new.transfer_id is not null
    and (tg_op = 'INSERT' or new.transfer_id is distinct from old.transfer_id)
    and not exists (
      select 1 from public.transfers tr
      where tr.id = new.transfer_id
        and tr.household_id = v_transaction.household_id
        and v_transaction.account_id in (tr.from_account_id, tr.to_account_id)
    )
  then
    raise exception 'line_link_not_valid';
  end if;

  if new.installment_plan_id is not null
    and (tg_op = 'INSERT' or new.installment_plan_id is distinct from old.installment_plan_id)
    and not exists (
      select 1 from public.installment_plans p
      where p.id = new.installment_plan_id
        and p.household_id = v_transaction.household_id
        and p.account_id = v_transaction.account_id
    )
  then
    raise exception 'line_link_not_valid';
  end if;

  return new;
end;
$$;

revoke all on function public.check_line_links() from public, anon, authenticated;

create trigger transaction_lines_check_links
  before insert or update of settlement_id, transfer_id, installment_plan_id
  on public.transaction_lines
  for each row execute function public.check_line_links();
