/**
 * PayPal settlements after a sync (sincronizzazione.md, 7 and 7.2), as pure
 * functions: from the PayPal movements and the settlements of a member, as
 * `settlement_candidates` returns them, to the proposals for
 * `apply_settlements`, which checks everything again under the locks of
 * the members and writes them. No database, no log, no email: the
 * candidates carry the member the counterparty email belongs to.
 *
 * Only free movements (one line, without kind, not linked) in no deleted
 * transfer or settlement, with `movement_date` in the window, in EUR, whose
 * counterparty is another active member of the household, are matched:
 *
 * - an outflow is the side of the payer (the member pays the counterpart),
 *   an inflow the side of the payee (the counterpart pays the member);
 * - a settlement takes the movement when it has the same payer and payee,
 *   the same amount and currency, `settled_on` at most 3 days from the
 *   movement and the side of the member still empty, whatever its origin;
 * - when the reference of the bank (the PayPal transaction ID) of the
 *   movement is the one of the side already linked of such a settlement,
 *   that pair goes first and settles a tie;
 * - candidates on a par (a movement with more settlements, or a settlement
 *   for more movements) give nothing, and no new settlement either: it
 *   would be a duplicate of the one already there;
 * - a movement without any settlement creates one. Two movements of the
 *   member that each create a settlement are not on a par.
 *
 * The links come before the creations: a creation is checked again in SQL
 * against the settlements still open.
 */

/** Settlements only in euro (7.2). */
export const SETTLEMENT_CURRENCY = "EUR";
/** At most 3 days between the movement and the settlement. */
export const SETTLEMENT_DAYS = 3;

/** A bank movement of a PayPal account of the member, with its state. */
export interface SettlementMovement {
  transaction_id: string;
  account_id: string;
  /** Signed: an outflow is negative. */
  amount_cents: number;
  currency: string;
  /** `YYYY-MM-DD`. */
  movement_date: string;
  /** The reference of the bank: the PayPal transaction ID. */
  entry_reference: string | null;
  /** The active member of the household the counterparty email is of. */
  counterpart_member_id: string | null;
  /** One line, without kind, not linked, not in a transfer or settlement. */
  free: boolean;
  /** In a deleted transfer or settlement. */
  cancelled: boolean;
}

/** A settlement not deleted of the member, as payer or payee. */
export interface CandidateSettlement {
  id: string;
  payer_member_id: string;
  payee_member_id: string;
  /** Positive. */
  amount_cents: number;
  currency: string;
  /** `YYYY-MM-DD`. */
  settled_on: string;
  payer_transaction_id: string | null;
  payee_transaction_id: string | null;
  payer_entry_reference: string | null;
  payee_entry_reference: string | null;
}

export interface SettlementCandidates {
  movements: SettlementMovement[];
  settlements: CandidateSettlement[];
}

/** A proposal in the shape of `apply_settlements`. */
export interface SettlementProposal {
  transaction_id: string;
  counterpart_member_id: string;
  /** The settlement to link; null creates one. */
  settlement_id: string | null;
}

/** A movement seen as one side of a settlement. */
interface Side {
  movement: SettlementMovement;
  counterpart: string;
  payer: string;
  payee: string;
  amount: number;
  /** The member pays: the side of the payer. */
  paid: boolean;
}

/**
 * The settlements of the candidates of `memberId`. `since` is the first day
 * of the window: the movements before it are never matched.
 */
export function matchSettlements(
  memberId: string,
  candidates: SettlementCandidates,
  since: string,
): SettlementProposal[] {
  const sides: Side[] = candidates.movements
    .filter((movement) =>
      movement.free && !movement.cancelled && movement.movement_date >= since &&
      movement.currency === SETTLEMENT_CURRENCY &&
      movement.amount_cents !== 0 &&
      movement.counterpart_member_id !== null &&
      movement.counterpart_member_id !== memberId
    )
    .sort(byDate)
    .map((movement) => {
      const counterpart = movement.counterpart_member_id!;
      const paid = movement.amount_cents < 0;
      return {
        movement,
        counterpart,
        payer: paid ? memberId : counterpart,
        payee: paid ? counterpart : memberId,
        amount: Math.abs(movement.amount_cents),
        paid,
      };
    });
  const settlements = [...candidates.settlements].sort(bySettledOn);

  // The PayPal transaction ID first, then amount and date.
  const byId = uniquePairs(
    sides,
    settlements,
    (side, settlement) =>
      takes(settlement, side) && sameReference(settlement, side),
  );
  const taken = new Set(byId.values());
  const left = sides.filter((side) => !byId.has(side));
  const open = settlements.filter((settlement) => !taken.has(settlement));
  const byAmount = uniquePairs(
    left,
    open,
    (side, settlement) => takes(settlement, side),
  );

  const proposal = (side: Side, settlement: CandidateSettlement | null) => ({
    transaction_id: side.movement.transaction_id,
    counterpart_member_id: side.counterpart,
    settlement_id: settlement?.id ?? null,
  });
  const links = sides.flatMap((side) => {
    const settlement = byId.get(side) ?? byAmount.get(side);
    return settlement === undefined ? [] : [proposal(side, settlement)];
  });
  const creations = left
    .filter((side) => !open.some((settlement) => takes(settlement, side)))
    .map((side) => proposal(side, null));
  return [...links, ...creations];
}

/** The settlement takes the movement: pair, amount, date, side still empty. */
function takes(settlement: CandidateSettlement, side: Side): boolean {
  const ownSide = side.paid
    ? settlement.payer_transaction_id
    : settlement.payee_transaction_id;
  return settlement.payer_member_id === side.payer &&
    settlement.payee_member_id === side.payee &&
    settlement.amount_cents === side.amount &&
    settlement.currency === side.movement.currency &&
    Math.abs(daysBetween(settlement.settled_on, side.movement.movement_date)) <=
      SETTLEMENT_DAYS &&
    ownSide === null;
}

/** The side already linked has the same PayPal transaction ID. */
function sameReference(settlement: CandidateSettlement, side: Side): boolean {
  const reference = side.movement.entry_reference;
  const other = side.paid
    ? settlement.payee_entry_reference
    : settlement.payer_entry_reference;
  return reference !== null && other === reference;
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

/** By date, then by id: the same candidates always give the same result. */
function byDate(a: SettlementMovement, b: SettlementMovement): number {
  return compare(a.movement_date, b.movement_date) ||
    compare(a.transaction_id, b.transaction_id);
}

function bySettledOn(a: CandidateSettlement, b: CandidateSettlement): number {
  return compare(a.settled_on, b.settled_on) || compare(a.id, b.id);
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
