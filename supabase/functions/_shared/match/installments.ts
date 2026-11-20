/**
 * PayPal installment plans after a sync (sincronizzazione.md, 7 and 7.3),
 * as pure functions: from the raw rows and the plans of a member, as
 * `installment_candidates` returns them, to the proposals for
 * `apply_installments`, which checks everything again under the lock of
 * the member and writes them. No database, no log, no email.
 *
 * Only BOOK outflows in EUR of the PayPal accounts count, from all the raw
 * rows (a plan lasts months, the raw rows start 90 days before the start
 * date):
 *
 * - a purchase is a `PAYMENT/PAYMENT` of `P` with, the same day on the same
 *   account, a `PAYMENT/LOAN` (the first installment) of `L` such that
 *   `n = round(P / L)` is between 2 and 12 and `|P − n·L| ≤ n` cents. A
 *   purchase with more possible first installments, or a first installment
 *   for more purchases, gives no plan; a purchase with a plan, also
 *   deleted, never gives another one; a purchase in a deleted transfer,
 *   settlement or plan neither;
 * - the plan: the counterparty of the purchase as merchant (the name,
 *   normalized as for the movements; without it the description, then
 *   "PayPal"; never the email), `P`, `n`, the date of the purchase;
 * - the installments: in order of date, the `PAYMENT/LOAN` of the account
 *   of `L` (±1 cent; the last one, the n-th, up to `n` cents), from the date
 *   of the purchase, at least 20 days after the previous installment of the
 *   plan, go to the oldest plan with that amount and fewer than `n`
 *   installments. An installment already linked to a plan stays with it.
 *   The deleted plans keep taking their installments, which are never
 *   touched: they do not go to another plan;
 * - `installments_before_start` counts the installments before the start
 *   date of the member, out of the budget; the plan is completed at the
 *   n-th installment, otherwise its next one is due 30 days after the last.
 *
 * The installments that became movements are linked when they are free
 * (one line, without kind, not linked), not cancelled, not linked yet and
 * in the window of 45 days. A plan already there is proposed again only
 * when something changes: run again, the rules propose nothing.
 */

import { counterparty } from "../normalize/counterparty.ts";
import { normalizeDescription } from "../normalize/description.ts";

/** Plans only in euro. */
export const INSTALLMENT_CURRENCY = "EUR";
/** At least 2 and at most 12 installments. */
export const MIN_INSTALLMENTS = 2;
export const MAX_INSTALLMENTS = 12;
/** At least 20 days between two installments of a plan. */
export const INSTALLMENT_GAP_DAYS = 20;
/** The next installment, 30 days after the last one. */
export const NEXT_DUE_DAYS = 30;
/** The merchant of a purchase without a name and a description. */
export const DEFAULT_MERCHANT = "PayPal";

/** A raw row of a PayPal account of the member, with its movement. */
export interface InstallmentRow {
  raw_id: string;
  account_id: string;
  status: string;
  /** `YYYY-MM-DD`. */
  movement_date: string;
  /** Signed: an outflow is negative. */
  amount_cents: number;
  currency: string;
  /** `bank_transaction_code.code`, in upper case. */
  code: string | null;
  /** `bank_transaction_code.sub_code`, in upper case. */
  sub_code: string | null;
  /** The name of the creditor, purchases only. */
  creditor_name: string | null;
  /** `remittance_information`, purchases only. */
  remittance: unknown;
  /** The movement the row became, if any. */
  transaction_id: string | null;
  /** The plan of that movement. */
  installment_plan_id: string | null;
  /** One line, without kind, not linked, not in a transfer or settlement. */
  free: boolean;
  /** In a deleted transfer, settlement or plan. */
  cancelled: boolean;
}

/** A plan of a PayPal account of the member, also deleted. */
export interface CandidatePlan {
  id: string;
  account_id: string;
  purchase_raw_id: string | null;
  /** `YYYY-MM-DD`. */
  purchase_date: string;
  /** Positive. */
  total_cents: number;
  installments_count: number;
  installments_before_start: number;
  next_due_date: string | null;
  status: "active" | "completed";
  deleted: boolean;
}

export interface InstallmentCandidates {
  /** The start date of the member, `YYYY-MM-DD`. */
  start_date: string;
  rows: InstallmentRow[];
  plans: CandidatePlan[];
}

/** A proposal in the shape of `apply_installments`. */
export interface InstallmentProposal {
  /** The plan to update; null creates one. */
  plan_id: string | null;
  /** A creation: the purchase, its first installment, the merchant. */
  purchase_raw_id: string | null;
  first_raw_id: string | null;
  merchant: string | null;
  installments_before_start: number;
  /** The installments of the plan in the raw rows. */
  installments_paid: number;
  /** `YYYY-MM-DD`. */
  last_installment_date: string;
  /** The installments to link. */
  transaction_ids: string[];
}

/** A plan while the installments are given out. */
interface Plan {
  existing: CandidatePlan | null;
  /** A new plan: its purchase. */
  purchase: InstallmentRow | null;
  /** The first installment; null when it is not known for sure. */
  first: InstallmentRow | null;
  account: string;
  date: string;
  total: number;
  count: number;
  deleted: boolean;
  installments: InstallmentRow[];
}

/**
 * The number of installments of a purchase of `purchase` cents with a first
 * installment of `installment` cents (both positive), or null.
 */
export function installmentCount(
  purchase: number,
  installment: number,
): number | null {
  if (purchase <= 0 || installment <= 0) return null;
  // round(P / L), half up, in integers.
  const n = Math.floor((2 * purchase + installment) / (2 * installment));
  if (n < MIN_INSTALLMENTS || n > MAX_INSTALLMENTS) return null;
  return Math.abs(purchase - n * installment) <= n ? n : null;
}

/** The merchant of a purchase: the name, the description, or PayPal. */
export function merchantOf(purchase: InstallmentRow): string {
  return counterparty(
    {
      indicator: "DBIT",
      creditor: { name: purchase.creditor_name },
      description: null,
      code: purchase.code,
    },
    "paypal",
  ) ?? normalizeDescription(purchase.remittance) ?? DEFAULT_MERCHANT;
}

/**
 * The plans of the candidates. `since` is the first day of the window: the
 * installments before it are counted, never linked.
 */
export function matchInstallments(
  candidates: InstallmentCandidates,
  since: string,
): InstallmentProposal[] {
  const rows = candidates.rows
    .filter((row) =>
      row.status === "BOOK" && row.currency === INSTALLMENT_CURRENCY &&
      row.amount_cents < 0 && row.code === "PAYMENT"
    )
    .sort(byDate);
  const purchases = rows.filter((row) => row.sub_code === "PAYMENT");
  const loans = rows.filter((row) => row.sub_code === "LOAN");

  // The plans already there, with their first installment when sure.
  const plans: Plan[] = [...candidates.plans].sort(byPurchase).map((
    existing,
  ) => ({
    existing,
    purchase: null,
    first: null,
    account: existing.account_id,
    date: existing.purchase_date,
    total: existing.total_cents,
    count: existing.installments_count,
    deleted: existing.deleted,
    installments: [],
  }));
  const firsts = new Set<InstallmentRow>();
  for (const plan of plans) {
    const possible = loans.filter((loan) =>
      !firsts.has(loan) && loan.account_id === plan.account &&
      loan.movement_date === plan.date &&
      installmentCount(plan.total, -loan.amount_cents) === plan.count &&
      (loan.installment_plan_id === null ||
        loan.installment_plan_id === plan.existing!.id)
    );
    const linked = possible.filter((loan) =>
      loan.installment_plan_id === plan.existing!.id
    );
    const first = linked.length === 1
      ? linked[0]!
      : possible.length === 1
      ? possible[0]!
      : null;
    if (first !== null) {
      plan.first = first;
      firsts.add(first);
    }
  }

  // New plans: a purchase and its first installment, each with the other
  // only; never for a purchase with a plan, also deleted, or cancelled.
  const planned = new Set(
    candidates.plans.flatMap((plan) =>
      plan.purchase_raw_id === null ? [] : [plan.purchase_raw_id]
    ),
  );
  const pairs = uniquePairs(
    purchases,
    loans,
    (purchase, loan) =>
      loan.account_id === purchase.account_id &&
      loan.movement_date === purchase.movement_date &&
      installmentCount(-purchase.amount_cents, -loan.amount_cents) !== null,
  );
  for (const purchase of purchases) {
    const first = pairs.get(purchase);
    if (
      first === undefined || planned.has(purchase.raw_id) ||
      purchase.cancelled || firsts.has(first) ||
      first.installment_plan_id !== null
    ) {
      continue;
    }
    firsts.add(first);
    plans.push({
      existing: null,
      purchase,
      first,
      account: purchase.account_id,
      date: purchase.movement_date,
      total: -purchase.amount_cents,
      count: installmentCount(-purchase.amount_cents, -first.amount_cents)!,
      deleted: false,
      installments: [],
    });
  }
  plans.sort(byAge);
  for (const plan of plans) {
    if (plan.first !== null) plan.installments.push(plan.first);
  }

  // The other installments, in order of date, to the oldest plan.
  const byId = new Map(
    plans.flatMap((plan) =>
      plan.existing === null ? [] : [[plan.existing.id, plan] as const]
    ),
  );
  for (const loan of loans) {
    if (firsts.has(loan)) continue;
    if (loan.installment_plan_id !== null) {
      byId.get(loan.installment_plan_id)?.installments.push(loan);
      continue;
    }
    const plan = plans.find((plan) => takes(plan, loan));
    plan?.installments.push(loan);
  }

  return plans.flatMap((plan): InstallmentProposal[] => {
    if (plan.deleted || plan.first === null) return [];
    const installments = plan.installments;
    const paid = installments.length;
    const before = installments.filter((loan) =>
      loan.movement_date < candidates.start_date
    ).length;
    const last = installments.map((loan) => loan.movement_date).sort().at(-1)!;
    const links = installments
      .filter((loan) =>
        loan.transaction_id !== null && loan.free && !loan.cancelled &&
        loan.installment_plan_id === null && loan.movement_date >= since
      )
      .map((loan) => loan.transaction_id!);
    const proposal = {
      installments_before_start: before,
      installments_paid: paid,
      last_installment_date: last,
      transaction_ids: links,
    };
    if (plan.existing === null) {
      return [{
        plan_id: null,
        purchase_raw_id: plan.purchase!.raw_id,
        first_raw_id: plan.first.raw_id,
        merchant: merchantOf(plan.purchase!),
        ...proposal,
      }];
    }
    const existing = plan.existing;
    const status = paid >= plan.count ? "completed" : "active";
    const nextDue = status === "active" ? addDays(last, NEXT_DUE_DAYS) : null;
    const changed = links.length > 0 ||
      existing.installments_before_start !== before ||
      existing.status !== status || existing.next_due_date !== nextDue;
    if (!changed) return [];
    return [{
      plan_id: existing.id,
      purchase_raw_id: null,
      first_raw_id: null,
      merchant: null,
      ...proposal,
    }];
  });
}

/**
 * The plan takes the installment: same account, from the purchase, room
 * left, at least 20 days after its last installment, the amount of `L`
 * (±1 cent, the last one up to `n` cents).
 */
function takes(plan: Plan, loan: InstallmentRow): boolean {
  const last = plan.installments.at(-1);
  if (
    plan.first === null || last === undefined ||
    plan.account !== loan.account_id || loan.movement_date < plan.date ||
    plan.installments.length >= plan.count ||
    daysBetween(last.movement_date, loan.movement_date) < INSTALLMENT_GAP_DAYS
  ) {
    return false;
  }
  const tolerance = plan.installments.length === plan.count - 1
    ? plan.count
    : 1;
  return Math.abs(loan.amount_cents - plan.first.amount_cents) <= tolerance;
}

/**
 * The pairs where each side has only the other: a left with more possible
 * rights, or a right with more possible lefts, stays without a pair.
 */
function uniquePairs<L, R>(
  lefts: readonly L[],
  rights: readonly R[],
  matches: (left: L, right: R) => boolean,
): Map<L, R> {
  const byLeft = new Map<L, R[]>();
  const byRight = new Map<R, L[]>();
  for (const left of lefts) {
    for (const right of rights) {
      if (!matches(left, right)) continue;
      byLeft.set(left, [...byLeft.get(left) ?? [], right]);
      byRight.set(right, [...byRight.get(right) ?? [], left]);
    }
  }
  const pairs = new Map<L, R>();
  for (const [left, found] of byLeft) {
    const right = found[0]!;
    if (found.length === 1 && byRight.get(right)?.length === 1) {
      pairs.set(left, right);
    }
  }
  return pairs;
}

const DAY_MS = 86_400_000;

/** Days from the first day to the second, negative when before. */
function daysBetween(from: string, to: string): number {
  return (Date.parse(to) - Date.parse(from)) / DAY_MS;
}

function addDays(day: string, days: number): string {
  return new Date(Date.parse(day) + days * DAY_MS).toISOString().slice(0, 10);
}

/** By date, then by raw row: the same rows always give the same result. */
function byDate(a: InstallmentRow, b: InstallmentRow): number {
  return compare(a.movement_date, b.movement_date) ||
    compare(a.raw_id, b.raw_id);
}

function byPurchase(a: CandidatePlan, b: CandidatePlan): number {
  return compare(a.purchase_date, b.purchase_date) || compare(a.id, b.id);
}

/** The oldest plan first: by purchase date, the plans already there first. */
function byAge(a: Plan, b: Plan): number {
  return compare(a.date, b.date) ||
    Number(a.existing === null) - Number(b.existing === null) ||
    compare(keyOf(a), keyOf(b));
}

function keyOf(plan: Plan): string {
  return plan.existing?.id ?? plan.purchase!.raw_id;
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
