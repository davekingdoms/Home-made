/**
 * Step 4 of `eb-sync` (sincronizzazione.md, 4, 7.3 and 9): the PayPal
 * installment plans of the owner of the connection, before the settlements
 * and the transfers. `installment_candidates` reads the PayPal raw rows and
 * the plans of the member, the rules of `_shared/match/installments.ts`
 * choose the proposals, `apply_installments` checks them again under the
 * lock of the member and writes them. Returns the installments linked and
 * the purchases left because already classified.
 */

import type { Db } from "../_shared/db.ts";
import { HttpError, isRecord } from "../_shared/http.ts";
import {
  type CandidatePlan,
  type InstallmentCandidates,
  type InstallmentRow,
  matchInstallments,
} from "../_shared/match/installments.ts";
import { windowStart } from "../_shared/match/transfers.ts";

/** The counts of the plans of a run. */
export interface InstallmentCounts {
  /** Movements linked to a plan (installments). */
  matchedInstallments: number;
  /** Movements of a purchase left because no longer as created. */
  purchaseAlreadyClassified: number;
}

export const NO_INSTALLMENTS: InstallmentCounts = {
  matchedInstallments: 0,
  purchaseAlreadyClassified: 0,
};

/** The plans of a member after a sync made on `today` (`YYYY-MM-DD`). */
export async function memberInstallments(
  db: Db,
  memberId: string,
  today: string,
): Promise<InstallmentCounts> {
  const since = windowStart(today);
  const candidates = parseInstallmentCandidates(
    await db.rpc("installment_candidates", { member_id: memberId, since }),
  );
  const installments = matchInstallments(candidates, since);
  if (installments.length === 0) return NO_INSTALLMENTS;
  const result = await db.rpc("apply_installments", {
    member_id: memberId,
    installments,
  });
  const creations = installments.filter((plan) => plan.plan_id === null)
    .length;
  const links = installments.reduce(
    (sum, plan) => sum + plan.transaction_ids.length,
    0,
  );
  if (
    !isRecord(result) || !isCount(result.plans_created, creations) ||
    !isCount(result.matched_installments, links) ||
    !isCount(result.purchase_already_classified, creations)
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    matchedInstallments: result.matched_installments,
    purchaseAlreadyClassified: result.purchase_already_classified,
  };
}

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

const isCount = (value: unknown, max: number): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= 0 &&
  value <= max;
const isText = (value: unknown): value is string => typeof value === "string";
const isTextOrNull = (value: unknown): value is string | null =>
  value === null || typeof value === "string";
const isCents = (value: unknown): value is number =>
  typeof value === "number" && Number.isSafeInteger(value);
const isDay = (value: unknown): value is string =>
  isText(value) && ISO_DAY.test(value);

/** The answer of `installment_candidates`, checked field by field. */
export function parseInstallmentCandidates(
  value: unknown,
): InstallmentCandidates {
  if (
    !isRecord(value) || !isDay(value.start_date) ||
    !Array.isArray(value.rows) || !Array.isArray(value.plans)
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    start_date: value.start_date,
    rows: value.rows.map(parseRow),
    plans: value.plans.map(parsePlan),
  };
}

function parseRow(row: unknown): InstallmentRow {
  if (
    !isRecord(row) || !isText(row.raw_id) || !isText(row.account_id) ||
    !isText(row.status) || !isDay(row.movement_date) ||
    !isCents(row.amount_cents) || !isText(row.currency) ||
    !isTextOrNull(row.code) || !isTextOrNull(row.sub_code) ||
    !isTextOrNull(row.creditor_name) || !isTextOrNull(row.transaction_id) ||
    !isTextOrNull(row.installment_plan_id) ||
    typeof row.free !== "boolean" || typeof row.cancelled !== "boolean"
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    raw_id: row.raw_id,
    account_id: row.account_id,
    status: row.status,
    movement_date: row.movement_date,
    amount_cents: row.amount_cents,
    currency: row.currency,
    code: row.code,
    sub_code: row.sub_code,
    creditor_name: row.creditor_name,
    // Only text is read from it (normalizeDescription).
    remittance: row.remittance ?? null,
    transaction_id: row.transaction_id,
    installment_plan_id: row.installment_plan_id,
    free: row.free,
    cancelled: row.cancelled,
  };
}

function parsePlan(row: unknown): CandidatePlan {
  if (
    !isRecord(row) || !isText(row.id) || !isText(row.account_id) ||
    !isTextOrNull(row.purchase_raw_id) || !isDay(row.purchase_date) ||
    !isCents(row.total_cents) || !isCents(row.installments_count) ||
    !isCents(row.installments_before_start) ||
    !(row.next_due_date === null || isDay(row.next_due_date)) ||
    (row.status !== "active" && row.status !== "completed") ||
    typeof row.deleted !== "boolean"
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    id: row.id,
    account_id: row.account_id,
    purchase_raw_id: row.purchase_raw_id,
    purchase_date: row.purchase_date,
    total_cents: row.total_cents,
    installments_count: row.installments_count,
    installments_before_start: row.installments_before_start,
    next_due_date: row.next_due_date,
    status: row.status,
    deleted: row.deleted,
  };
}
