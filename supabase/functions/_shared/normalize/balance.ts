/**
 * Balances of an account (sincronizzazione.md, 6.5): every balance of
 * `GET /accounts/{uid}/balances` with its sign, currency, type and
 * reference date, the amount in integer cents.
 */

import type { HalBalances } from "../eb/types.ts";
import { amountToCents } from "./amount.ts";

/** A balance in the shape of `complete_bank_link`. */
export interface LinkBalance {
  currency: string;
  balance_type: string;
  amount_cents: number;
  reference_date: string | null;
}

/** A balance that cannot be read. The message never holds the value. */
export class InvalidBalanceError extends Error {
  override readonly name = "InvalidBalanceError";
  readonly code = "bank_error";
}

const CURRENCY = /^[A-Z]{3}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}/;

/**
 * A signed amount of a balance (`-12.5`, `1234.56`) in cents, with the
 * conversion of the transactions: no floating point numbers.
 */
export function balanceCents(amount: unknown): number {
  if (typeof amount !== "string") {
    throw new InvalidBalanceError("invalid amount");
  }
  const negative = amount.startsWith("-");
  const digits = negative || amount.startsWith("+") ? amount.slice(1) : amount;
  try {
    return amountToCents(digits, negative ? "DBIT" : "CRDT").cents;
  } catch {
    throw new InvalidBalanceError("invalid amount");
  }
}

/**
 * All the balances of an account, or an error: an account keeps either all
 * of its balances or none.
 */
export function linkBalances(response: HalBalances): LinkBalance[] {
  return response.balances.map((balance) => {
    const amount: unknown = balance.balance_amount;
    if (typeof amount !== "object" || amount === null) {
      throw new InvalidBalanceError("invalid balance");
    }
    const { currency, amount: value } = amount as {
      currency?: unknown;
      amount?: unknown;
    };
    const type = balance.balance_type;
    if (
      typeof currency !== "string" || !CURRENCY.test(currency) ||
      typeof type !== "string" || type.trim() === ""
    ) {
      throw new InvalidBalanceError("invalid balance");
    }
    const date = balance.reference_date;
    return {
      currency,
      balance_type: type.trim(),
      amount_cents: balanceCents(value),
      reference_date: typeof date === "string" && ISO_DATE.test(date)
        ? date.slice(0, 10)
        : null,
    };
  });
}
