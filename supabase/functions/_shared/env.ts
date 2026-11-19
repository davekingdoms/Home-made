/**
 * Environment of the Edge Functions (sincronizzazione.md, section 1).
 *
 * From the platform: `SUPABASE_URL`, `SUPABASE_SECRET_KEYS` and
 * `SUPABASE_PUBLISHABLE_KEYS` (JSON objects with one key for each name).
 * Secrets of the functions: `EB_REDIRECT_URL`, `APP_RETURN_URL` and the
 * optional global application (`EB_GLOBAL_APP_ID`, `EB_GLOBAL_PRIVATE_KEY`).
 *
 * A missing or malformed variable is `500 internal`: neither its name nor
 * its value ever reaches a response or a log.
 */

import { HttpError, isRecord } from "./http.ts";

export type EnvGetter = (name: string) => string | undefined;

export interface SupabaseEnv {
  /** Project URL, without the trailing slash. */
  url: string;
  /** Every secret key of the project: a service caller may use any. */
  secretKeys: readonly string[];
  /** The key the functions use for their own calls to PostgREST. */
  secretKey: string;
}

export interface GlobalApp {
  appId: string;
  privateKey: string;
}

function internal(): HttpError {
  return new HttpError(500, "internal");
}

/** `SUPABASE_URL` and the secret keys. */
export function supabaseEnv(env: EnvGetter): SupabaseEnv {
  const url = httpUrl(env("SUPABASE_URL"));
  const keys = keyDictionary(env("SUPABASE_SECRET_KEYS"));
  return {
    url: url.replace(/\/+$/, ""),
    secretKeys: [...keys.values()],
    secretKey: keys.get("default") ?? [...keys.values()][0] ?? "",
  };
}

/** The publishable key for the calls made with the JWT of a user. */
export function publishableKey(env: EnvGetter): string {
  const keys = keyDictionary(env("SUPABASE_PUBLISHABLE_KEYS"));
  return keys.get("default") ?? [...keys.values()][0] ?? "";
}

/** An http(s) URL from a variable. */
export function urlVariable(env: EnvGetter, name: string): string {
  return httpUrl(env(name));
}

/** The global application, when both of its variables are set. */
export function globalApp(env: EnvGetter): GlobalApp | undefined {
  const appId = env("EB_GLOBAL_APP_ID")?.trim();
  const privateKey = env("EB_GLOBAL_PRIVATE_KEY");
  if (!appId || !privateKey?.trim()) return undefined;
  return { appId, privateKey };
}

function httpUrl(value: string | undefined): string {
  if (!value) throw internal();
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw internal();
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") throw internal();
  return value;
}

/** A JSON object of non-empty strings, with at least one entry. */
function keyDictionary(value: string | undefined): Map<string, string> {
  if (!value) throw internal();
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    throw internal();
  }
  if (!isRecord(parsed)) throw internal();
  const keys = new Map<string, string>();
  for (const [name, key] of Object.entries(parsed)) {
    if (typeof key === "string" && key !== "") keys.set(name, key);
  }
  if (keys.size === 0) throw internal();
  return keys;
}
