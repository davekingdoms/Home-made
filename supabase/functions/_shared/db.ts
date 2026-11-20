/**
 * Calls to the SQL functions through PostgREST (`/rest/v1/rpc/<name>`), and
 * the few reads and upserts of tables the server makes, with `fetch` and a
 * timeout for each call: no client library.
 *
 * An error keeps only a code: the key of an exception raised by the
 * function (`P0001` with a message such as `link_not_claimable`), otherwise
 * the SQLSTATE or the PostgREST code. `message`, `details` and `hint` are
 * dropped on arrival: a failed check puts the values of the row in the
 * DETAIL, and they must never reach a log or a response.
 */

import { isRecord } from "./http.ts";

/** Timeout of a single call, body included. */
export const DB_TIMEOUT_MS = 10_000;

const ERROR_KEY = /^[a-z_]{1,40}$/;
const SQLSTATE = /^[0-9A-Z]{5}$/;
const POSTGREST_CODE = /^PGRST\d{1,4}$/;
const FUNCTION_NAME = /^[a-z_]{1,63}$/;
const TABLE_NAME = /^[a-z_]{1,63}$/;
const COLUMN_LIST = /^[a-z_]{1,63}(?:,[a-z_]{1,63})*$/;

/** A failed call, with its code only. */
export class DbError extends Error {
  override readonly name = "DbError";
  /** Key of the exception, SQLSTATE, PostgREST code, or a code of ours. */
  readonly code: string;
  /** HTTP status of the answer, when there was one. */
  readonly status?: number;

  constructor(code: string, status?: number) {
    super(code);
    this.code = code;
    if (status !== undefined) this.status = status;
  }
}

export interface DbOptions {
  /** Project URL. */
  url: string;
  /** `apikey` header: the secret key, or the publishable one with a JWT. */
  apikey: string;
  /** JWT of a user, for the calls made as that user. */
  bearer?: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
}

export class Db {
  readonly #url: string;
  readonly #headers: Record<string, string>;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;

  constructor(options: DbOptions) {
    this.#url = options.url.replace(/\/+$/, "");
    this.#headers = {
      apikey: options.apikey,
      "Content-Type": "application/json",
      Accept: "application/json",
    };
    if (options.bearer !== undefined) {
      this.#headers.Authorization = `Bearer ${options.bearer}`;
    }
    this.#fetch = options.fetch ?? ((input, init) => fetch(input, init));
    this.#timeoutMs = options.timeoutMs ?? DB_TIMEOUT_MS;
  }

  /** Calls a SQL function with named arguments; returns its JSON result. */
  async rpc(
    name: string,
    args: Record<string, unknown> = {},
  ): Promise<unknown> {
    if (!FUNCTION_NAME.test(name)) throw new RangeError("invalid function");
    return await this.#send("POST", `rpc/${name}`, JSON.stringify(args));
  }

  /**
   * Reads the rows of a table with PostgREST parameters (`select`, filters
   * such as `id: "eq.<uuid>"`, `order`, `limit`); returns the array.
   */
  async select(
    table: string,
    query: Record<string, string>,
  ): Promise<unknown[]> {
    if (!TABLE_NAME.test(table)) throw new RangeError("invalid table");
    const params = new URLSearchParams(query).toString();
    const rows = await this.#send("GET", `${table}?${params}`);
    if (!Array.isArray(rows)) throw new DbError("invalid_response");
    return rows;
  }

  /**
   * Inserts the rows of a table, or updates them on a conflict of the
   * columns of `onConflict`: one statement, so all or nothing.
   */
  async upsert(
    table: string,
    rows: readonly Record<string, unknown>[],
    onConflict: string,
  ): Promise<void> {
    if (!TABLE_NAME.test(table)) throw new RangeError("invalid table");
    if (!COLUMN_LIST.test(onConflict)) throw new RangeError("invalid columns");
    const params = new URLSearchParams({ on_conflict: onConflict }).toString();
    await this.#send("POST", `${table}?${params}`, JSON.stringify(rows), {
      Prefer: "resolution=merge-duplicates,return=minimal",
    });
  }

  async #send(
    method: "GET" | "POST",
    path: string,
    body?: string,
    headers: Record<string, string> = {},
  ): Promise<unknown> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeoutMs);
    let status: number;
    let text: string;
    try {
      const response = await this.#fetch(`${this.#url}/rest/v1/${path}`, {
        method,
        headers: { ...this.#headers, ...headers },
        body,
        signal: controller.signal,
      });
      status = response.status;
      text = await response.text();
    } catch {
      throw new DbError("unavailable");
    } finally {
      clearTimeout(timer);
    }

    const parsed = parseJson(text);
    if (status < 200 || status > 299) {
      throw new DbError(errorCode(parsed.value, status), status);
    }
    if (text.trim() === "") return null;
    if (!parsed.ok) throw new DbError("invalid_response", status);
    return parsed.value;
  }
}

/** The code of a PostgREST error, never its texts. */
function errorCode(body: unknown, status: number): string {
  if (isRecord(body) && typeof body.code === "string") {
    if (
      body.code === "P0001" && typeof body.message === "string" &&
      ERROR_KEY.test(body.message)
    ) {
      return body.message;
    }
    if (SQLSTATE.test(body.code) || POSTGREST_CODE.test(body.code)) {
      return body.code;
    }
  }
  return `http_${status}`;
}

function parseJson(text: string): { ok: boolean; value: unknown } {
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, value: undefined };
  }
}
