/**
 * Logs of the Edge Functions (sincronizzazione.md, section 11): one fixed
 * object for each step, with the function, the step and a code or a count.
 * Never a value received or read: no state, code, session, URL, JWT, key,
 * application ID, bank, member, email, IBAN or amount.
 */

import { DbError } from "./db.ts";
import { EbError } from "./eb/errors.ts";
import { HttpError } from "./http.ts";
import { InvalidBalanceError } from "./normalize/balance.ts";

export type FunctionName = "eb-credentials" | "eb-link-start" | "eb-callback";

export interface LogEntry {
  fn: FunctionName;
  step: string;
  code?: string;
  count?: number;
}

export type Logger = (entry: LogEntry) => void;

export const consoleLogger: Logger = (entry) => {
  console.log({ ...entry });
};

const CODE = /^[a-z0-9_]{1,40}$|^[0-9A-Z]{5}$|^PGRST\d{1,4}$/;

/**
 * The code of a failure for the logs: the code of our own errors (already
 * free of values), `internal` for anything else, whose message may hold
 * anything.
 */
export function codeOf(error: unknown): string {
  const code = error instanceof EbError || error instanceof DbError ||
      error instanceof HttpError || error instanceof InvalidBalanceError
    ? error.code
    : "internal";
  return CODE.test(code) ? code : "internal";
}

/**
 * Runs the steps of a request: each one leaves one line, with `ok` or the
 * code of its failure, which is then thrown again.
 */
export function stepper(fn: FunctionName, log: Logger) {
  return async function step<T>(name: string, run: () => Promise<T> | T) {
    try {
      const value = await run();
      log({ fn, step: name, code: "ok" });
      return value;
    } catch (error) {
      log({ fn, step: name, code: codeOf(error) });
      throw error;
    }
  };
}
