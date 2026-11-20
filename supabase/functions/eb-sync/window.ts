/**
 * Window of the transactions downloaded for an account
 * (sincronizzazione.md, section 4), as pure functions of ISO dates
 * (`YYYY-MM-DD`, in UTC):
 *
 * | Case                              | strategy  | date_from                         |
 * |-----------------------------------|-----------|-----------------------------------|
 * | first sync (no raw row)           | `longest` | start date of the owner           |
 * | first sync of a PayPal account    | `longest` | start date − 90 days              |
 * | later syncs                       | `default` | last successful sync − 15 days,   |
 * |                                   |           | never before the start date       |
 *
 * After `WRONG_TRANSACTIONS_PERIOD` the shorter periods are the most recent
 * of the date asked and today − 89, − 60, − 30 days.
 */

import type { LinkedAccountKind } from "../_shared/normalize/account.ts";

export type Strategy = "longest" | "default";

export interface SyncWindow {
  strategy: Strategy;
  /** Date asked, `YYYY-MM-DD`. */
  dateFrom: string;
}

/** History of a PayPal account before the start date (installments, 7.3). */
export const PAYPAL_HISTORY_DAYS = 90;
/** Overlap of a later sync with the previous one. */
export const OVERLAP_DAYS = 15;
/** Shorter periods after a refused one, in days before today. */
export const SHORTER_PERIOD_DAYS = [89, 60, 30] as const;

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

/** `YYYY-MM-DD` of a moment, in UTC. */
export function isoDay(epochMs: number): string {
  return new Date(epochMs).toISOString().slice(0, 10);
}

/** An ISO date moved by a number of days. */
export function addDays(day: string, days: number): string {
  if (!ISO_DAY.test(day)) throw new RangeError("dates must be YYYY-MM-DD");
  const [year, month, date] = day.split("-").map(Number) as [
    number,
    number,
    number,
  ];
  return isoDay(Date.UTC(year, month - 1, date + days));
}

/** The later of two ISO dates. */
export function laterDay(a: string, b: string): string {
  return a >= b ? a : b;
}

export interface WindowInput {
  kind: LinkedAccountKind;
  /** Start date of the owner of the account. */
  startDate: string;
  /** True when the account has no raw row yet. */
  firstSync: boolean;
  /** Day of the last successful sync of the account, if any. */
  lastSuccess: string | null;
}

export function syncWindow(input: WindowInput): SyncWindow {
  if (input.firstSync) {
    return {
      strategy: "longest",
      dateFrom: input.kind === "paypal"
        ? addDays(input.startDate, -PAYPAL_HISTORY_DAYS)
        : input.startDate,
    };
  }
  const since = input.lastSuccess === null
    ? input.startDate
    : addDays(input.lastSuccess, -OVERLAP_DAYS);
  return { strategy: "default", dateFrom: laterDay(input.startDate, since) };
}

/**
 * The dates to try after the period starting at `dateFrom` was refused:
 * each the later of `dateFrom` and today − 89, − 60, − 30 days, only when
 * more recent than the date tried before.
 */
export function shorterPeriods(dateFrom: string, today: string): string[] {
  const dates: string[] = [];
  let last = dateFrom;
  for (const days of SHORTER_PERIOD_DAYS) {
    const candidate = laterDay(dateFrom, addDays(today, -days));
    if (candidate > last) {
      dates.push(candidate);
      last = candidate;
    }
  }
  return dates;
}
