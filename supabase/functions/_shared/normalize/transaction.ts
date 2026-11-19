/**
 * A transaction of Enable Banking to the row of `bank_raw_transactions` and
 * the fields of the movement (sincronizzazione.md, sections 5, 6.2, 6.3 and
 * 8), as a pure function: no database, no log.
 */

import type { CreditDebitIndicator, Transaction } from "../eb/types.ts";
import { amountToCents } from "./amount.ts";
import {
  bankFormat,
  counterparty,
  counterpartyEmail,
  isCardMonthlyCharge,
  type TransactionContext,
} from "./counterparty.ts";
import { cleanText, normalizeDescription } from "./description.ts";
import { dedupHash, type Sign } from "./hash.ts";

export type { TransactionContext } from "./counterparty.ts";

/** Statuses kept in the raw rows (schema.md, `bank_raw_transactions`). */
export type RawStatus = "BOOK" | "PDNG" | "RJCT" | "CNCL";

const RAW_STATUSES: readonly string[] = ["BOOK", "PDNG", "RJCT", "CNCL"];

/** A row that cannot be stored. The message names the field, never the value. */
export class InvalidRowError extends Error {
  override readonly name = "InvalidRowError";
  readonly code = "invalid_row";
}

/** The fields of the raw row. */
export interface RawFields {
  entry_reference: string | null;
  status: RawStatus;
  booking_date: string | null;
  value_date: string | null;
  transaction_date: string | null;
  /** `D` for `DBIT`, `C` for `CRDT`. */
  sign: Sign;
  /** Cents without sign, as in the hash. */
  unsigned_amount_cents: number;
  currency: string;
  dedup_hash: string;
  /** The row as the bank sent it. */
  payload: Transaction;
}

/** The fields of the movement (6.2) that come from the row. */
export interface MovementFields {
  /** Value date, else transaction date, else booking date. */
  movement_date: string;
  /** Signed: `DBIT` negative, `CRDT` positive. */
  amount_cents: number;
  /** Amount of the exchange block, with the sign of the movement. */
  original_amount_cents: number | null;
  original_currency: string | null;
  /** Rate of the exchange block as decimal text (`numeric`). */
  exchange_rate: string | null;
  description: string | null;
  counterparty: string | null;
  /** PayPal only, lower case. */
  counterparty_email: string | null;
  /** `code/sub_code`, or the code alone. */
  bank_code: string | null;
}

export interface NormalizedTransaction {
  raw: RawFields;
  movement: MovementFields;
  /** An amount of the row had more than two decimals (counted in sync_runs). */
  amount_rounded: boolean;
  /** The monthly charge of the credit card on the current account (7.1). */
  card_monthly_charge: boolean;
}

const CURRENCY = /^[A-Z]{3}$/;
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})(?:T.*)?$/;
const DECIMAL = /^\d{1,15}(?:\.\d{1,20})?$/;

/**
 * Normalizes one transaction of `GET /accounts/{uid}/transactions` for the
 * account described by `context`. An invalid amount, currency, date or
 * status is an `InvalidRowError` (`invalid_row`).
 */
export async function normalizeTransaction(
  transaction: Transaction,
  context: TransactionContext,
): Promise<NormalizedTransaction> {
  if (typeof transaction !== "object" || transaction === null) {
    throw new InvalidRowError("invalid transaction");
  }
  const row = transaction as Record<string, unknown>;

  const indicator = row.credit_debit_indicator;
  if (indicator !== "CRDT" && indicator !== "DBIT") {
    throw new InvalidRowError("invalid credit_debit_indicator");
  }
  const status = row.status;
  if (typeof status !== "string" || !RAW_STATUSES.includes(status)) {
    throw new InvalidRowError("invalid status");
  }
  const amount = amountOf(
    row.transaction_amount,
    indicator,
    "transaction_amount",
  );
  const original = exchangeOf(row.exchange_rate, indicator);

  const booking = isoDate(row.booking_date, "booking_date");
  const value = isoDate(row.value_date, "value_date");
  const date = isoDate(row.transaction_date, "transaction_date");
  const movementDate = value ?? date ?? booking;
  if (movementDate === null) throw new InvalidRowError("missing date");

  const sign: Sign = indicator === "DBIT" ? "D" : "C";
  const unsignedCents = Math.abs(amount.cents);
  const description = normalizeDescription(row.remittance_information);
  const code = bankCode(row.bank_transaction_code);
  const format = bankFormat(context);
  const source = {
    indicator,
    creditor: row.creditor,
    debtor: row.debtor,
    description,
    code: code.code,
  } as const;

  return {
    raw: {
      entry_reference: cleanText(row.entry_reference),
      status: status as RawStatus,
      booking_date: booking,
      value_date: value,
      transaction_date: date,
      sign,
      unsigned_amount_cents: unsignedCents,
      currency: amount.currency,
      dedup_hash: await dedupHash({
        booking_date: booking,
        value_date: value,
        transaction_date: date,
        status,
        sign,
        unsigned_amount_cents: unsignedCents,
        description,
      }),
      payload: transaction,
    },
    movement: {
      movement_date: movementDate,
      amount_cents: amount.cents,
      original_amount_cents: original.amount?.cents ?? null,
      original_currency: original.amount?.currency ?? null,
      exchange_rate: original.rate,
      description,
      counterparty: counterparty(source, format),
      counterparty_email: counterpartyEmail(source, format),
      bank_code: code.text,
    },
    amount_rounded: amount.rounded || (original.amount?.rounded ?? false),
    card_monthly_charge: isCardMonthlyCharge(description, format),
  };
}

interface Amount {
  cents: number;
  currency: string;
  rounded: boolean;
}

/** An `AmountType` with the sign of the row. */
function amountOf(
  value: unknown,
  indicator: CreditDebitIndicator,
  field: string,
): Amount {
  if (typeof value !== "object" || value === null) {
    throw new InvalidRowError(`invalid ${field}`);
  }
  const { amount, currency } = value as {
    amount?: unknown;
    currency?: unknown;
  };
  if (typeof currency !== "string" || !CURRENCY.test(currency)) {
    throw new InvalidRowError(`invalid ${field}`);
  }
  try {
    const { cents, rounded } = amountToCents(amount as string, indicator);
    return { cents, currency, rounded };
  } catch {
    throw new InvalidRowError(`invalid ${field}`);
  }
}

/** The exchange block: instructed amount and rate, each when present. */
function exchangeOf(
  value: unknown,
  indicator: CreditDebitIndicator,
): { amount: Amount | null; rate: string | null } {
  if (value === undefined || value === null) {
    return { amount: null, rate: null };
  }
  if (typeof value !== "object") {
    throw new InvalidRowError("invalid exchange_rate");
  }
  const block = value as {
    instructed_amount?: unknown;
    exchange_rate?: unknown;
  };
  const instructed = block.instructed_amount;
  const amount = instructed === undefined || instructed === null
    ? null
    : amountOf(instructed, indicator, "exchange_rate.instructed_amount");
  const rate = block.exchange_rate;
  if (rate === undefined || rate === null) return { amount, rate: null };
  if (typeof rate !== "string" || !DECIMAL.test(rate)) {
    throw new InvalidRowError("invalid exchange_rate.exchange_rate");
  }
  return { amount, rate };
}

/** A date as `YYYY-MM-DD` (a time part is cut); missing → null. */
function isoDate(value: unknown, field: string): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") throw new InvalidRowError(`invalid ${field}`);
  const match = ISO_DATE.exec(value);
  if (match === null) throw new InvalidRowError(`invalid ${field}`);
  const [, year, month, day] = match.map(Number) as number[];
  const date = new Date(Date.UTC(year!, month! - 1, day!));
  if (
    date.getUTCFullYear() !== year || date.getUTCMonth() !== month! - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new InvalidRowError(`invalid ${field}`);
  }
  return value.slice(0, 10);
}

/** `code/sub_code`, the code alone, or null; and the code for the formats. */
function bankCode(
  value: unknown,
): { code: string | null; text: string | null } {
  if (typeof value !== "object" || value === null) {
    return { code: null, text: null };
  }
  const block = value as { code?: unknown; sub_code?: unknown };
  const code = cleanText(block.code);
  if (code === null) return { code: null, text: null };
  const sub = cleanText(block.sub_code);
  return { code, text: sub === null ? code : `${code}/${sub}` };
}
