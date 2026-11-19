/**
 * Enable Banking credentials of a person (sincronizzazione.md, section 2):
 * the own application from `eb_get_credentials` (key read from Vault);
 * without it the global application, if both of its variables are set
 * (`uses_global_app = true`); otherwise `no_credentials`.
 */

import type { Db } from "./db.ts";
import type { GlobalApp } from "./env.ts";
import { HttpError, isRecord } from "./http.ts";

export interface EbCredentials {
  appId: string;
  privateKey: string;
  usesGlobalApp: boolean;
}

/**
 * `auto`: own application, else the global one. `own` and `global`: only
 * that one, for the return of a link started with it.
 */
export type CredentialsSource = "auto" | "own" | "global";

export async function memberCredentials(
  db: Db,
  global: GlobalApp | undefined,
  userId: string,
  source: CredentialsSource = "auto",
): Promise<EbCredentials> {
  if (source !== "global") {
    const rows = await db.rpc("eb_get_credentials", { user_id: userId });
    if (!Array.isArray(rows)) throw new HttpError(500, "internal");
    const row: unknown = rows[0];
    if (row !== undefined) {
      if (
        !isRecord(row) || typeof row.app_id !== "string" ||
        typeof row.private_key !== "string"
      ) {
        throw new HttpError(500, "internal");
      }
      return {
        appId: row.app_id,
        privateKey: row.private_key,
        usesGlobalApp: false,
      };
    }
    if (source === "own") throw new HttpError(409, "no_credentials");
  }
  if (global === undefined) throw new HttpError(409, "no_credentials");
  return { ...global, usesGlobalApp: true };
}
