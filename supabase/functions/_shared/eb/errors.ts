/**
 * Error codes of the bank sync (sincronizzazione.md, section 4) and the
 * table from Enable Banking errors to those codes.
 *
 * Only codes go to `bank_connections.last_error`, `sync_runs.error_code` and
 * the logs. The bank's own text never enters `message`: at most it stays in
 * `detail`, which is not enumerable, so neither `JSON.stringify` nor
 * `console.log` print it.
 */

/** Codes stored in `last_error` and `error_code` (section 4). */
export const SYNC_ERROR_CODES = [
  "period_rejected",
  "consent_expired",
  "consent_revoked",
  "rate_limited",
  "no_credentials",
  "invalid_credentials",
  "bank_unavailable",
  "bank_error",
  "link_expired",
  "link_cancelled",
  "link_rejected",
  "link_failed",
  "already_running",
  "paypal_email_taken",
  "internal",
] as const;

export type SyncErrorCode = typeof SYNC_ERROR_CODES[number];

export interface EbErrorOptions {
  /** HTTP status of the Enable Banking response, when there was one. */
  status?: number;
  /** `error` field of the Enable Banking response (an enum value). */
  ebError?: string;
  /** Bank or runtime text: never logged, never copied into `message`. */
  detail?: unknown;
}

/** Failure of a call to Enable Banking, already turned into a sync code. */
export class EbError extends Error {
  override readonly name = "EbError";
  readonly code: SyncErrorCode;
  readonly status?: number;
  readonly ebError?: string;
  readonly #detail: unknown;

  constructor(code: SyncErrorCode, options: EbErrorOptions = {}) {
    const ebError = isEbErrorCode(options.ebError)
      ? options.ebError
      : undefined;
    super(describe(code, options.status, ebError));
    this.code = code;
    if (options.status !== undefined) this.status = options.status;
    if (ebError !== undefined) this.ebError = ebError;
    this.#detail = options.detail;
  }

  /** What Enable Banking or the runtime said. Do not log it. */
  get detail(): unknown {
    return this.#detail;
  }
}

/**
 * Enable Banking `error` values with a fixed meaning, whatever the HTTP
 * status. `WRONG_TRANSACTIONS_PERIOD` always means "period too long", even
 * when the bank's message talks about an expired consent (section 4).
 */
const BY_EB_ERROR: Readonly<Record<string, SyncErrorCode>> = {
  WRONG_TRANSACTIONS_PERIOD: "period_rejected",
  ASPSP_RATE_LIMIT_EXCEEDED: "rate_limited",
  EXPIRED_SESSION: "consent_expired",
  REVOKED_SESSION: "consent_revoked",
  CLOSED_SESSION: "consent_revoked",
  UNAUTHORIZED_ACCESS: "invalid_credentials",
  ASPSP_TIMEOUT: "bank_unavailable",
};

/**
 * Sync code for an Enable Banking error response: first the `error` field of
 * the body, then the HTTP status (401 rejected JWT, 429 rate limit, 408 and
 * 5xx unavailable); anything else is `bank_error`.
 */
export function ebErrorCode(status: number, ebError?: string): SyncErrorCode {
  const byError = ebError === undefined ? undefined : BY_EB_ERROR[ebError];
  if (byError !== undefined) return byError;
  if (status === 401) return "invalid_credentials";
  if (status === 429) return "rate_limited";
  if (status === 408 || status >= 500) return "bank_unavailable";
  return "bank_error";
}

/** Enable Banking error codes are upper-case enum values, never free text. */
function isEbErrorCode(value: unknown): value is string {
  return typeof value === "string" && /^[A-Z][A-Z_]{0,63}$/.test(value);
}

function describe(code: SyncErrorCode, status?: number, ebError?: string) {
  const parts = [status === undefined ? "" : `HTTP ${status}`, ebError ?? ""]
    .filter((part) => part !== "");
  return parts.length === 0 ? code : `${code} (${parts.join(", ")})`;
}
