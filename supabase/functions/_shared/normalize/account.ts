/**
 * Accounts of a new Enable Banking session (sincronizzazione.md, 6.4): kind,
 * identifier, default name and the email of a PayPal account, as pure
 * functions of the account resource and the name of the bank.
 */

import type { AccountResource } from "../eb/types.ts";

export type LinkedAccountKind = "bank" | "card" | "paypal";

/** An account in the shape of `complete_bank_link`, without balances. */
export interface LinkedAccount {
  uid: string;
  kind: LinkedAccountKind;
  cash_account_type: string | null;
  currency: string;
  identifier: string | null;
  display_name: string;
  paypal_email: string | null;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_EMAIL_LENGTH = 254;

/** The bank is PayPal, as Enable Banking names it. */
export function isPaypal(aspspName: string): boolean {
  return aspspName.trim().toLowerCase() === "paypal";
}

/** `paypal` for PayPal, `card` for `CARD`, otherwise `bank`. */
export function accountKind(
  aspspName: string,
  cashAccountType: unknown,
): LinkedAccountKind {
  if (isPaypal(aspspName)) return "paypal";
  return cashAccountType === "CARD" ? "card" : "bank";
}

/** The IBAN, otherwise `account_id.other.identification`; else null. */
export function accountIdentifier(account: AccountResource): string | null {
  const accountId: unknown = account.account_id;
  if (typeof accountId !== "object" || accountId === null) return null;
  const { iban, other } = accountId as { iban?: unknown; other?: unknown };
  if (typeof iban === "string" && iban.trim() !== "") {
    return iban.replace(/\s+/g, "").toUpperCase();
  }
  if (typeof other === "object" && other !== null) {
    const identification = (other as { identification?: unknown })
      .identification;
    if (typeof identification === "string" && identification.trim() !== "") {
      return identification.trim();
    }
  }
  return null;
}

/** The identifier when it has the shape of an email, else null. */
export function emailOf(identifier: string | null): string | null {
  if (identifier === null) return null;
  const value = identifier.trim();
  return value.length <= MAX_EMAIL_LENGTH && EMAIL.test(value) ? value : null;
}

/**
 * Default name of the account: bank name + " …" + last 4 digits of the
 * IBAN; for a card the product (or "Carta") + " …" + last 4 digits; for
 * PayPal the email of the account. The name sent by the bank is never used
 * (often it is the holder).
 */
export function defaultDisplayName(
  kind: LinkedAccountKind,
  aspspName: string,
  product: unknown,
  identifier: string | null,
): string {
  const bank = aspspName.trim();
  if (kind === "paypal") return emailOf(identifier) ?? identifier ?? bank;
  const last4 = lastDigits(identifier);
  const base = kind === "card"
    ? (typeof product === "string" && product.trim() !== ""
      ? product.trim()
      : "Carta")
    : bank;
  return last4 === null ? base : `${base} …${last4}`;
}

/** The account for `complete_bank_link`; null without `uid`. */
export function linkedAccount(
  aspspName: string,
  account: AccountResource,
): LinkedAccount | null {
  const uid = account.uid;
  if (typeof uid !== "string" || uid.trim() === "") return null;
  const kind = accountKind(aspspName, account.cash_account_type);
  const identifier = accountIdentifier(account);
  return {
    uid,
    kind,
    cash_account_type: typeof account.cash_account_type === "string"
      ? account.cash_account_type
      : null,
    currency: typeof account.currency === "string" ? account.currency : "",
    identifier,
    display_name: defaultDisplayName(
      kind,
      aspspName,
      account.product,
      identifier,
    ),
    paypal_email: kind === "paypal" ? emailOf(identifier) : null,
  };
}

function lastDigits(identifier: string | null): string | null {
  const digits = (identifier ?? "").replace(/\D/g, "");
  return digits.length >= 4 ? digits.slice(-4) : null;
}
