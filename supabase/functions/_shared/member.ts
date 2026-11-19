/**
 * The member of a call: from the body for the service, from the JWT for a
 * user; then account, household and start date from `eb_service_member`.
 */

import type { Caller } from "./auth.ts";
import { type Db, DbError } from "./db.ts";
import { HttpError, isRecord, UUID } from "./http.ts";

export interface ServiceMember {
  memberId: string;
  userId: string;
  householdId: string;
  startDate: string;
}

/**
 * The member id of the call: `member_id` of the body for the service (a
 * uuid), the member of the JWT for a user, who never sends one.
 */
export function callerMemberId(
  caller: Caller,
  body: Record<string, unknown>,
): string {
  if (caller.kind === "user") {
    if (body.member_id !== undefined) {
      throw new HttpError(400, "invalid_request");
    }
    return caller.memberId;
  }
  const memberId = body.member_id;
  if (typeof memberId !== "string" || !UUID.test(memberId)) {
    throw new HttpError(400, "invalid_request");
  }
  return memberId;
}

/** `eb_service_member`: an active member with an account, else 403. */
export async function serviceMember(
  db: Db,
  memberId: string,
): Promise<ServiceMember> {
  let row: unknown;
  try {
    row = await db.rpc("eb_service_member", { member_id: memberId });
  } catch (error) {
    if (error instanceof DbError && error.code === "member_not_eligible") {
      throw new HttpError(403, "member_not_eligible");
    }
    throw error;
  }
  if (
    !isRecord(row) || typeof row.member_id !== "string" ||
    typeof row.user_id !== "string" || typeof row.household_id !== "string" ||
    typeof row.start_date !== "string"
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    memberId: row.member_id,
    userId: row.user_id,
    householdId: row.household_id,
    startDate: row.start_date,
  };
}
