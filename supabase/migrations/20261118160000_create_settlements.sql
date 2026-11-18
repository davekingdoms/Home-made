-- Settlements between two members (docs/spec/schema.md, 10).
--
-- The first side that arrives creates the settlement; the server links the
-- second one (same pair, amount and currency, date within 3 days). From the
-- app a member marks a payment as done ("Segna come pagato"): a manual
-- settlement, seen only by the two members.

-- Every member id written in the tables of this migration and of the next
-- ones: an active member of the same household, or member_not_eligible.
-- Internal.
create function public.check_active_member(p_member_id uuid, p_household_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_member_id is not null and not exists (
    select 1
    from public.members m
    where m.id = p_member_id
      and m.household_id = p_household_id
      and m.left_at is null
  ) then
    raise exception 'member_not_eligible';
  end if;
end;
$$;

revoke all on function public.check_active_member(uuid, uuid) from public, anon, authenticated;

create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  payer_member_id uuid not null references public.members (id),
  payee_member_id uuid not null references public.members (id),
  amount_cents bigint not null
    constraint settlements_amount_positive check (amount_cents > 0),
  currency char(3) not null
    constraint settlements_currency_format check (currency ~ '^[A-Z]{3}$'),
  settled_on date not null,
  -- manual: "Segna come pagato".
  origin text not null
    constraint settlements_origin check (origin in ('paypal', 'manual', 'bank_transfer')),
  -- Both sides optional.
  payer_transaction_id uuid unique references public.transactions (id),
  payee_transaction_id uuid unique references public.transactions (id),
  -- Null when the server creates it.
  created_by_member_id uuid references public.members (id),
  deleted_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint settlements_distinct_members check (payer_member_id <> payee_member_id)
);

comment on table public.settlements is
  'Payments between two members of a household, seen only by the two of them.';

create index settlements_household_id on public.settlements (household_id);
create index settlements_payer_member_id on public.settlements (payer_member_id);
create index settlements_payee_member_id on public.settlements (payee_member_id);
create index settlements_created_by_member_id on public.settlements (created_by_member_id);

create trigger settlements_touch_row
  before update on public.settlements
  for each row execute function public.touch_row();

alter table public.transaction_lines
  add constraint transaction_lines_settlement_id_fkey
  foreign key (settlement_id) references public.settlements (id);

create index transaction_lines_settlement_id on public.transaction_lines (settlement_id);

-- Payer, payee and creator are active members of the household; the date is
-- not before the start date of either; each side is a movement of its member.
create function public.check_settlement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
    or (new.household_id, new.payer_member_id, new.payee_member_id, new.created_by_member_id)
      is distinct from (old.household_id, old.payer_member_id, old.payee_member_id, old.created_by_member_id)
  then
    perform public.check_active_member(new.payer_member_id, new.household_id);
    perform public.check_active_member(new.payee_member_id, new.household_id);
    perform public.check_active_member(new.created_by_member_id, new.household_id);
  end if;

  if exists (
    select 1 from public.members m
    where m.id in (new.payer_member_id, new.payee_member_id)
      and m.start_date > new.settled_on
  ) then
    raise exception 'member_not_eligible';
  end if;

  if new.payer_transaction_id is not null and (
    select t.paid_by_member_id from public.transactions t where t.id = new.payer_transaction_id
  ) is distinct from new.payer_member_id then
    raise exception 'the side of the payer is a movement of the payer'
      using errcode = 'check_violation';
  end if;

  if new.payee_transaction_id is not null and (
    select t.paid_by_member_id from public.transactions t where t.id = new.payee_transaction_id
  ) is distinct from new.payee_member_id then
    raise exception 'the side of the payee is a movement of the payee'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function public.check_settlement() from public, anon, authenticated;

create trigger settlements_check
  before insert or update on public.settlements
  for each row execute function public.check_settlement();

-- RLS: everything only for the payer and the payee. From the app only manual
-- settlements; the sides are linked by the server.

alter table public.settlements enable row level security;

revoke all on table public.settlements from anon, authenticated;

grant select on table public.settlements to authenticated;
grant insert (
  id, household_id, payer_member_id, payee_member_id, amount_cents, currency,
  settled_on, origin, created_by_member_id
) on table public.settlements to authenticated;
grant update (amount_cents, settled_on, deleted_at) on table public.settlements to authenticated;

create policy settlements_select_pair on public.settlements
  for select to authenticated
  using ((select public.current_member_id()) in (payer_member_id, payee_member_id));

create policy settlements_insert_pair on public.settlements
  for insert to authenticated
  with check (
    household_id = (select public.current_household_id())
    and (select public.current_member_id()) in (payer_member_id, payee_member_id)
    and created_by_member_id = (select public.current_member_id())
    and origin = 'manual'
  );

create policy settlements_update_pair on public.settlements
  for update to authenticated
  using ((select public.current_member_id()) in (payer_member_id, payee_member_id))
  with check ((select public.current_member_id()) in (payer_member_id, payee_member_id));
