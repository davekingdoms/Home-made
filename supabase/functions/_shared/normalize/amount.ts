/**
 * Amounts of the bank rows (sincronizzazione.md, section 6.3): text with `.`
 * as decimal separator and a variable number of decimals (`4.4`, `1`,
 * `12.50`) to integer cents, without floating point numbers. The sign comes
 * from `credit_debit_indicator`: `DBIT` negative, `CRDT` positive.
 */

import type { CreditDebitIndicator } from "../eb/types.ts";

export interface AmountCents {
  /** Integer cents, with the sign. */
  cents: number;
  /**
   * True when the text had non-zero digits beyond the cent: the amount was
   * rounded half up and the caller counts it in `sync_runs`.
   */
  rounded: boolean;
}

/** Invalid amount or indicator. The message never contains the value. */
export class InvalidAmountError extends Error {
  override readonly name = "InvalidAmountError";
}

const UNSIGNED_DECIMAL = /^(\d{1,15})(?:\.(\d{1,20}))?$/;

/**
 * Converts `transaction_amount.amount` and `credit_debit_indicator` to signed
 * cents. More than two decimals are rounded to the cent, half up on the
 * amount sent by the bank (`0.005` → 1 cent, `DBIT` → -1).
 */
export function amountToCents(
  amount: string,
  indicator: CreditDebitIndicator,
): AmountCents {
  if (indicator !== "CRDT" && indicator !== "DBIT") {
    throw new InvalidAmountError("invalid credit_debit_indicator");
  }
  const match = typeof amount === "string"
    ? UNSIGNED_DECIMAL.exec(amount)
    : null;
  if (match === null) throw new InvalidAmountError("invalid amount");

  const units = BigInt(match[1] ?? "0");
  const decimals = match[2] ?? "";
  const cents = BigInt(decimals.slice(0, 2).padEnd(2, "0"));
  const beyond = decimals.slice(2);
  const roundUp = (beyond[0] ?? "0") >= "5";

  const total = units * 100n + cents + (roundUp ? 1n : 0n);
  if (total > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new InvalidAmountError("amount out of range");
  }
  const magnitude = Number(total);
  return {
    cents: magnitude === 0 ? 0 : indicator === "DBIT" ? -magnitude : magnitude,
    rounded: /[1-9]/.test(beyond),
  };
}
