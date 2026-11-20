/**
 * Step 4 of `eb-sync` (sincronizzazione.md, 4, 7.1 and 9): the automatic
 * transfers of the owner of the connection. `transfer_candidates` reads the
 * accounts and movements of the member, the rules of
 * `_shared/match/transfers.ts` choose the transfers, `apply_transfers`
 * checks them again under the lock of the member and writes them. Returns
 * the number of transfers created.
 */

import type { Db } from "../_shared/db.ts";
import { HttpError, isRecord } from "../_shared/http.ts";
import {
  type CandidateAccount,
  type CandidateMovement,
  type Candidates,
  candidatesSince,
  matchTransfers,
  windowStart,
} from "../_shared/match/transfers.ts";

/** The transfers of a member after a sync made on `today` (`YYYY-MM-DD`). */
export async function memberTransfers(
  db: Db,
  memberId: string,
  today: string,
): Promise<number> {
  const candidates = parseCandidates(
    await db.rpc("transfer_candidates", {
      member_id: memberId,
      since: candidatesSince(today),
    }),
  );
  const transfers = matchTransfers(candidates, windowStart(today));
  if (transfers.length === 0) return 0;
  const created = await db.rpc("apply_transfers", {
    member_id: memberId,
    transfers,
  });
  if (
    typeof created !== "number" || !Number.isInteger(created) || created < 0 ||
    created > transfers.length
  ) {
    throw new HttpError(500, "internal");
  }
  return created;
}

const ACCOUNT_KINDS: readonly string[] = ["bank", "card", "paypal"];
const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

const isText = (value: unknown): value is string => typeof value === "string";
const isTextOrNull = (value: unknown): value is string | null =>
  value === null || typeof value === "string";

/** The answer of `transfer_candidates`, checked field by field. */
export function parseCandidates(value: unknown): Candidates {
  if (
    !isRecord(value) || !Array.isArray(value.accounts) ||
    !Array.isArray(value.movements)
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    accounts: value.accounts.map(parseAccount),
    movements: value.movements.map(parseMovement),
  };
}

function parseAccount(row: unknown): CandidateAccount {
  if (
    !isRecord(row) || !isText(row.id) || !isText(row.kind) ||
    !ACCOUNT_KINDS.includes(row.kind) || !isText(row.connection_id) ||
    !isText(row.aspsp_name) || !isTextOrNull(row.cash_account_type)
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    id: row.id,
    kind: row.kind as CandidateAccount["kind"],
    connection_id: row.connection_id,
    aspsp_name: row.aspsp_name,
    cash_account_type: row.cash_account_type,
  };
}

function parseMovement(row: unknown): CandidateMovement {
  if (
    !isRecord(row) || !isText(row.transaction_id) || !isText(row.account_id) ||
    typeof row.amount_cents !== "number" ||
    !Number.isSafeInteger(row.amount_cents) || !isText(row.currency) ||
    !isText(row.movement_date) || !ISO_DAY.test(row.movement_date) ||
    !isTextOrNull(row.counterparty) || !isTextOrNull(row.description) ||
    typeof row.free !== "boolean" || typeof row.in_transfer !== "boolean" ||
    typeof row.cancelled !== "boolean"
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    transaction_id: row.transaction_id,
    account_id: row.account_id,
    amount_cents: row.amount_cents,
    currency: row.currency,
    movement_date: row.movement_date,
    counterparty: row.counterparty,
    description: row.description,
    free: row.free,
    in_transfer: row.in_transfer,
    cancelled: row.cancelled,
  };
}
