/**
 * Automatic transfers after a sync (sincronizzazione.md, 7 and 7.1), as
 * pure functions: from the accounts and movements of a member, as
 * `transfer_candidates` returns them, to the transfers for
 * `apply_transfers`, which checks again that the movements are still free
 * and writes them. No database, no log.
 *
 * Only free movements (one line, without kind, not linked) in no deleted
 * transfer, with `movement_date` in the window, are matched. The rules go
 * in this order, and a movement used by a rule does not enter the next
 * ones (the signals in the description and in the counterparty are surer
 * than the amount alone):
 *
 * - monthly charge of the credit card: an outflow with the description of
 *   the charge (section 8) on an account whose connection has one card:
 *   from the account to the card, with the inflow of the card of the same
 *   amount at most 5 days away, before or after, as the incoming side. With
 *   more cards in the connection the charge stays to classify;
 * - bank or card → PayPal: an outflow of a bank or card account whose
 *   counterparty is PayPal, when the member has one PayPal account: to
 *   PayPal, without incoming side, funding the PayPal outflow of the same
 *   amount from 7 days before to the day of the charge, not already funded.
 *   Without a PayPal account, or with more, the outflow stays to classify;
 * - between two accounts of the member: same amount and currency, opposite
 *   signs, different accounts, at most 3 days away; with a PayPal account,
 *   the counterparty of the other side holds PayPal (two PayPal accounts:
 *   never). PayPal → bank is this rule: never an income.
 *
 * Candidates on a par: between two accounts, an outflow with more possible
 * inflows (or an inflow with more possible outflows) is not matched; for
 * the card and PayPal the transfer is made without the side that is not
 * unique (the inflow of the card, the funded payment).
 */

import type { LinkedAccountKind } from "../normalize/account.ts";
import { bankFormat, isCardMonthlyCharge } from "../normalize/counterparty.ts";

/** Movements matched: the last 45 days (section 7). */
export const WINDOW_DAYS = 45;
/** Between two accounts: at most 3 days between the two sides. */
export const BETWEEN_ACCOUNTS_DAYS = 3;
/** Card charge: the inflow of the card at most 5 days from the charge. */
export const CARD_CHARGE_DAYS = 5;
/** To PayPal: the payment funded from 7 days before the charge. */
export const FUNDING_DAYS = 7;

/** An account of the member with a connection, not archived. */
export interface CandidateAccount {
  id: string;
  kind: LinkedAccountKind;
  connection_id: string;
  /** Name of the bank, for the format of section 8. */
  aspsp_name: string;
  cash_account_type: string | null;
}

/** A bank movement of one of those accounts, with its state. */
export interface CandidateMovement {
  transaction_id: string;
  account_id: string;
  /** Signed: an outflow is negative. */
  amount_cents: number;
  currency: string;
  /** `YYYY-MM-DD`. */
  movement_date: string;
  counterparty: string | null;
  description: string | null;
  /** One line, without kind, not linked, in no transfer. */
  free: boolean;
  /** Out, in or funded movement of a transfer not deleted. */
  in_transfer: boolean;
  /** Out, in or funded movement of a deleted transfer. */
  cancelled: boolean;
}

export interface Candidates {
  accounts: CandidateAccount[];
  movements: CandidateMovement[];
}

/** A transfer in the shape of `apply_transfers`. */
export interface TransferProposal {
  from_account_id: string;
  to_account_id: string;
  out_transaction_id: string;
  in_transaction_id: string | null;
  funded_transaction_id: string | null;
}

/**
 * The transfers of the candidates, case by case. `since` is the first day
 * of the window: the movements before it are never matched, but a payment
 * of those days may be funded.
 */
export function matchTransfers(
  candidates: Candidates,
  since: string,
): TransferProposal[] {
  const accounts = new Map(candidates.accounts.map((a) => [a.id, a]));
  const accountOf = (movement: CandidateMovement) =>
    accounts.get(movement.account_id)!;
  const movements = candidates.movements
    .filter((movement) => accounts.has(movement.account_id))
    .sort(byDate);
  const open = movements.filter((movement) =>
    movement.free && !movement.cancelled && movement.movement_date >= since
  );
  const used = new Set<string>();
  const unused = (movement: CandidateMovement) =>
    !used.has(movement.transaction_id);
  const use = (movement: CandidateMovement | undefined) => {
    if (movement !== undefined) used.add(movement.transaction_id);
  };
  const proposals: TransferProposal[] = [];

  // Monthly charge of the credit card.
  const charges: { charge: CandidateMovement; card: CandidateAccount }[] = [];
  for (const movement of open) {
    const account = accountOf(movement);
    if (
      movement.amount_cents >= 0 ||
      !isCardMonthlyCharge(movement.description, formatOf(account))
    ) {
      continue;
    }
    const cards = candidates.accounts.filter((card) =>
      card.kind === "card" && card.connection_id === account.connection_id
    );
    if (cards.length === 0) continue;
    use(movement);
    if (cards.length === 1) charges.push({ charge: movement, card: cards[0]! });
  }
  const cardInflows = open.filter((movement) =>
    unused(movement) && movement.amount_cents > 0 &&
    accountOf(movement).kind === "card"
  );
  const cardInflowOf = uniquePairs(
    charges,
    cardInflows,
    ({ charge, card }, inflow) =>
      inflow.account_id === card.id && opposite(charge, inflow) &&
      Math.abs(daysBetween(charge, inflow)) <= CARD_CHARGE_DAYS,
  );
  for (const entry of charges) {
    const inflow = cardInflowOf.get(entry);
    use(inflow);
    proposals.push(
      proposal(entry.charge, entry.card.id, inflow ?? null, null),
    );
  }

  // Bank or card → PayPal.
  const toPaypal = open.filter((movement) =>
    unused(movement) && movement.amount_cents < 0 &&
    accountOf(movement).kind !== "paypal" &&
    isPaypalCounterparty(movement.counterparty)
  );
  toPaypal.forEach(use);
  const paypals = candidates.accounts.filter((a) => a.kind === "paypal");
  if (paypals.length === 1) {
    const paypal = paypals[0]!;
    const payments = movements.filter((movement) =>
      unused(movement) && movement.account_id === paypal.id &&
      movement.amount_cents < 0 && !movement.in_transfer && !movement.cancelled
    );
    const fundedOf = uniquePairs(toPaypal, payments, (charge, payment) => {
      const days = daysBetween(payment, charge);
      return sameAmount(charge, payment) && days >= 0 && days <= FUNDING_DAYS;
    });
    for (const charge of toPaypal) {
      const funded = fundedOf.get(charge);
      use(funded);
      proposals.push(proposal(charge, paypal.id, null, funded ?? null));
    }
  }

  // Between two accounts of the member (also PayPal → bank).
  const outflows = open.filter((m) => unused(m) && m.amount_cents < 0);
  const inflows = open.filter((m) => unused(m) && m.amount_cents > 0);
  const inflowOf = uniquePairs(
    outflows,
    inflows,
    (outflow, inflow) =>
      outflow.account_id !== inflow.account_id && opposite(outflow, inflow) &&
      Math.abs(daysBetween(outflow, inflow)) <= BETWEEN_ACCOUNTS_DAYS &&
      paypalSides(accountOf(outflow), outflow, accountOf(inflow), inflow),
  );
  for (const outflow of outflows) {
    const inflow = inflowOf.get(outflow);
    if (inflow !== undefined) {
      proposals.push(proposal(outflow, inflow.account_id, inflow, null));
    }
  }

  return proposals;
}

/** The first day of the window of a sync made on `today` (`YYYY-MM-DD`). */
export function windowStart(today: string): string {
  return addDays(today, -WINDOW_DAYS);
}

/** The first day read: the window and the payments a charge may fund. */
export function candidatesSince(today: string): string {
  return addDays(windowStart(today), -FUNDING_DAYS);
}

/** The counterparty is PayPal (direct debit or card payment to PayPal). */
export function isPaypalCounterparty(counterparty: string | null): boolean {
  return counterparty !== null && /paypal/i.test(counterparty);
}

function formatOf(account: CandidateAccount) {
  return bankFormat({
    aspspName: account.aspsp_name,
    cashAccountType: account.cash_account_type,
    accountKind: account.kind,
  });
}

/**
 * With a PayPal account on one side, the other side is a bank or a card
 * with PayPal as counterparty.
 */
function paypalSides(
  outAccount: CandidateAccount,
  outflow: CandidateMovement,
  inAccount: CandidateAccount,
  inflow: CandidateMovement,
): boolean {
  const outPaypal = outAccount.kind === "paypal";
  const inPaypal = inAccount.kind === "paypal";
  if (outPaypal && inPaypal) return false;
  if (outPaypal) return isPaypalCounterparty(inflow.counterparty);
  if (inPaypal) return isPaypalCounterparty(outflow.counterparty);
  return true;
}

function proposal(
  outflow: CandidateMovement,
  toAccountId: string,
  inflow: CandidateMovement | null,
  funded: CandidateMovement | null,
): TransferProposal {
  return {
    from_account_id: outflow.account_id,
    to_account_id: toAccountId,
    out_transaction_id: outflow.transaction_id,
    in_transaction_id: inflow?.transaction_id ?? null,
    funded_transaction_id: funded?.transaction_id ?? null,
  };
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

/** Same currency, amounts with opposite signs. */
function opposite(a: CandidateMovement, b: CandidateMovement): boolean {
  return a.currency === b.currency && a.amount_cents === -b.amount_cents;
}

/** Same currency and signed amount. */
function sameAmount(a: CandidateMovement, b: CandidateMovement): boolean {
  return a.currency === b.currency && a.amount_cents === b.amount_cents;
}

const DAY_MS = 86_400_000;

/** Days from the first movement to the second, negative when before. */
function daysBetween(from: CandidateMovement, to: CandidateMovement): number {
  return (Date.parse(to.movement_date) - Date.parse(from.movement_date)) /
    DAY_MS;
}

function addDays(day: string, days: number): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) {
    throw new RangeError("dates must be YYYY-MM-DD");
  }
  return new Date(Date.parse(day) + days * DAY_MS).toISOString().slice(0, 10);
}

/** By date, then by id: the same candidates always give the same result. */
function byDate(a: CandidateMovement, b: CandidateMovement): number {
  if (a.movement_date !== b.movement_date) {
    return a.movement_date < b.movement_date ? -1 : 1;
  }
  return a.transaction_id < b.transaction_id
    ? -1
    : a.transaction_id > b.transaction_id
    ? 1
    : 0;
}
