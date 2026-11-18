-- Purchases in installments (docs/spec/schema.md, 9).
--
-- The purchase is not a movement and is out of the budget: the installments
-- count, from the start date of the owner of the account. Plans are created
-- by the server; the owner of the account sets their category and weights,
-- which every installment copies with set_line_shares.

create table public.installment_plans (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  account_id uuid not null references public.accounts (id),
  merchant text not null,
  total_cents bigint not null
    constraint installment_plans_total_positive check (total_cents > 0),
  installments_count smallint not null
    constraint installment_plans_count_positive check (installments_count > 0),
  -- Also before the start date.
  purchase_date date not null,
  purchase_raw_id uuid references public.bank_raw_transactions (id),
  -- Charged before the start date (out of the budget), to show "2/3 pagate".
  installments_before_start smallint not null default 0
    constraint installment_plans_before_start_range
    check (installments_before_start between 0 and installments_count),
  next_due_date date,
  -- Inherited by every installment.
  category_id uuid references public.categories (id),
  status text not null default 'active'
    constraint installment_plans_status check (status in ('active', 'completed')),
  deleted_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.installment_plans is
  'Purchases in installments; the installments are the movements that count.';

create index installment_plans_account_id on public.installment_plans (account_id);

create trigger installment_plans_touch_row
  before update on public.installment_plans
  for each row execute function public.touch_row();

create table public.installment_plan_shares (
  plan_id uuid not null references public.installment_plans (id),
  member_id uuid not null references public.members (id),
  weight numeric(12, 4) not null
    constraint installment_plan_shares_weight_positive check (weight > 0),
  primary key (plan_id, member_id)
);

comment on table public.installment_plan_shares is
  'Weights of a plan, copied on every installment.';

create index installment_plan_shares_member_id on public.installment_plan_shares (member_id);

-- A weight only for an active member of the household of the plan, from
-- the app and from the server.
create function public.check_installment_plan_share()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.installment_plans p
    join public.members m on m.household_id = p.household_id
    where p.id = new.plan_id
      and m.id = new.member_id
      and m.left_at is null
  ) then
    raise exception 'member_not_eligible';
  end if;
  return new;
end;
$$;

revoke all on function public.check_installment_plan_share() from public, anon, authenticated;

create trigger installment_plan_shares_check_member
  before insert or update on public.installment_plan_shares
  for each row execute function public.check_installment_plan_share();

-- The owner of the account and the members with a weight. Security definer:
-- plans and weights read each other without their policies.
create function public.can_see_installment_plan(plan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.installment_plans p
    where p.id = can_see_installment_plan.plan_id
      and (
        public.is_account_owner(p.account_id)
        or exists (
          select 1
          from public.installment_plan_shares s
          where s.plan_id = p.id
            and s.member_id = (select public.current_member_id())
        )
      )
  )
$$;

comment on function public.can_see_installment_plan(uuid) is
  'True for the owner of the account of the plan and for the members with a weight on it.';

revoke all on function public.can_see_installment_plan(uuid) from public, anon;
grant execute on function public.can_see_installment_plan(uuid) to authenticated;

-- RLS

alter table public.installment_plans enable row level security;
alter table public.installment_plan_shares enable row level security;

revoke all on table public.installment_plans from anon, authenticated;
revoke all on table public.installment_plan_shares from anon, authenticated;

grant select on table public.installment_plans to authenticated;
grant update (category_id, deleted_at) on table public.installment_plans to authenticated;

create policy installment_plans_select_visible on public.installment_plans
  for select to authenticated
  using (public.can_see_installment_plan(id));

create policy installment_plans_update_owner on public.installment_plans
  for update to authenticated
  using (public.is_account_owner(account_id))
  with check (public.is_account_owner(account_id));

grant select, insert, update, delete on table public.installment_plan_shares to authenticated;

create policy installment_plan_shares_select_visible on public.installment_plan_shares
  for select to authenticated
  using (public.can_see_installment_plan(plan_id));

create policy installment_plan_shares_write_owner on public.installment_plan_shares
  for all to authenticated
  using (
    exists (
      select 1 from public.installment_plans p
      where p.id = plan_id and public.is_account_owner(p.account_id)
    )
  )
  with check (
    exists (
      select 1 from public.installment_plans p
      where p.id = plan_id and public.is_account_owner(p.account_id)
    )
    and exists (
      select 1 from public.members m
      where m.id = member_id and m.left_at is null
    )
  );
