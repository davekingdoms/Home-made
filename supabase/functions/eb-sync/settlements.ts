/**
 * Step 4 of `eb-sync` (sincronizzazione.md, 4, 7.2 and 9): the PayPal
 * settlements of the owner of the connection, before the transfers.
 * `settlement_candidates` reads the PayPal movements and the settlements
 * of the member, the rules of `_shared/match/settlements.ts` choose the
 * proposals, `apply_settlements` checks them again under the locks of the
 * members and writes them. Returns the number of movements linked (sides).
 */

import type { Db } from "../_shared/db.ts";
import { HttpError, isRecord } from "../_shared/http.ts";
import {
  type CandidateSettlement,
  matchSettlements,
  type SettlementCandidates,
  type SettlementMovement,
} from "../_shared/match/settlements.ts";
import { windowStart } from "../_shared/match/transfers.ts";

/** The settlements of a member after a sync made on `today` (`YYYY-MM-DD`). */
export async function memberSettlements(
  db: Db,
  memberId: string,
  today: string,
): Promise<number> {
  const since = windowStart(today);
  const candidates = parseSettlementCandidates(
    await db.rpc("settlement_candidates", { member_id: memberId, since }),
  );
  const settlements = matchSettlements(memberId, candidates, since);
  if (settlements.length === 0) return 0;
  const linked = await db.rpc("apply_settlements", {
    member_id: memberId,
    settlements,
  });
  if (
    typeof linked !== "number" || !Number.isInteger(linked) || linked < 0 ||
    linked > settlements.length
  ) {
    throw new HttpError(500, "internal");
  }
  return linked;
}

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

const isText = (value: unknown): value is string => typeof value === "string";
const isTextOrNull = (value: unknown): value is string | null =>
  value === null || typeof value === "string";
const isCents = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value);
const isDay = (value: unknown): value is string =>
  isText(value) && ISO_DAY.test(value);

/** The answer of `settlement_candidates`, checked field by field. */
export function parseSettlementCandidates(
  value: unknown,
): SettlementCandidates {
  if (
    !isRecord(value) || !Array.isArray(value.movements) ||
    !Array.isArray(value.settlements)
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    movements: value.movements.map(parseMovement),
    settlements: value.settlements.map(parseSettlement),
  };
}

function parseMovement(row: unknown): SettlementMovement {
  if (
    !isRecord(row) || !isText(row.transaction_id) || !isText(row.account_id) ||
    !isCents(row.amount_cents) || !isText(row.currency) ||
    !isDay(row.movement_date) || !isTextOrNull(row.entry_reference) ||
    !isTextOrNull(row.counterpart_member_id) ||
    typeof row.free !== "boolean" || typeof row.cancelled !== "boolean"
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    transaction_id: row.transaction_id,
    account_id: row.account_id,
    amount_cents: row.amount_cents,
    currency: row.currency,
    movement_date: row.movement_date,
    entry_reference: row.entry_reference,
    counterpart_member_id: row.counterpart_member_id,
    free: row.free,
    cancelled: row.cancelled,
  };
}

function parseSettlement(row: unknown): CandidateSettlement {
  if (
    !isRecord(row) || !isText(row.id) || !isText(row.payer_member_id) ||
    !isText(row.payee_member_id) || !isCents(row.amount_cents) ||
    !isText(row.currency) || !isDay(row.settled_on) ||
    !isTextOrNull(row.payer_transaction_id) ||
    !isTextOrNull(row.payee_transaction_id) ||
    !isTextOrNull(row.payer_entry_reference) ||
    !isTextOrNull(row.payee_entry_reference)
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    id: row.id,
    payer_member_id: row.payer_member_id,
    payee_member_id: row.payee_member_id,
    amount_cents: row.amount_cents,
    currency: row.currency,
    settled_on: row.settled_on,
    payer_transaction_id: row.payer_transaction_id,
    payee_transaction_id: row.payee_transaction_id,
    payer_entry_reference: row.payer_entry_reference,
    payee_entry_reference: row.payee_entry_reference,
  };
}
