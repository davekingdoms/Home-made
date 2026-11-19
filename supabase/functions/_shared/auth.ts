/**
 * Authentication of the Edge Functions (sincronizzazione.md, section 1):
 *
 * - **service**: a secret key of Supabase (`sb_secret_…`) in the `apikey`
 *   header, compared with every value of `SUPABASE_SECRET_KEYS` in constant
 *   time; the member then arrives in the body. Never in `Authorization`.
 * - **user**: the Supabase JWT in `Authorization: Bearer …`, checked by
 *   PostgREST while calling `current_member_id()` with it (and the
 *   publishable key as `apikey`); `null` is `403 member_not_eligible`.
 * - neither: `401 unauthorized`.
 */

import { Db, DbError } from "./db.ts";
import { HttpError, UUID } from "./http.ts";

export type Caller =
  | { kind: "service" }
  | { kind: "user"; memberId: string };

export interface AuthOptions {
  supabaseUrl: string;
  secretKeys: readonly string[];
  publishableKey: string;
  fetch?: typeof fetch;
}

const JWT = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

export async function authenticate(
  request: Request,
  options: AuthOptions,
): Promise<Caller> {
  const apikey = request.headers.get("apikey");
  if (apikey !== null && await matchesAnyKey(apikey, options.secretKeys)) {
    return { kind: "service" };
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length).trim()
    : "";
  // A secret key is not a JWT: in this header it is refused here.
  if (!JWT.test(token)) throw new HttpError(401, "unauthorized");

  const db = new Db({
    url: options.supabaseUrl,
    apikey: options.publishableKey,
    bearer: token,
    fetch: options.fetch,
  });
  let memberId: unknown;
  try {
    memberId = await db.rpc("current_member_id");
  } catch (error) {
    if (
      error instanceof DbError &&
      (error.status === 401 || error.status === 403)
    ) {
      throw new HttpError(401, "unauthorized");
    }
    throw error;
  }
  if (memberId === null) throw new HttpError(403, "member_not_eligible");
  if (typeof memberId !== "string" || !UUID.test(memberId)) {
    throw new HttpError(500, "internal");
  }
  return { kind: "user", memberId };
}

/**
 * True if the candidate equals one of the keys. The SHA-256 digests are
 * compared byte by byte without stopping early, and every key is compared:
 * the time does not depend on where or whether the values differ.
 */
export async function matchesAnyKey(
  candidate: string,
  keys: readonly string[],
): Promise<boolean> {
  const wanted = await digest(candidate);
  let found = 0;
  for (const key of keys) {
    const other = await digest(key);
    let diff = 0;
    for (let i = 0; i < wanted.length; i++) {
      diff |= (wanted[i] ?? 0) ^ (other[i] ?? 0);
    }
    // 1 when diff is 0, else 0, without a branch.
    found |= 1 ^ ((diff | -diff) >>> 31);
  }
  return candidate !== "" && found === 1;
}

async function digest(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}
