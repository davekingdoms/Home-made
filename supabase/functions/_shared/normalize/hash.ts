/**
 * Deduplication hash of a bank row (sincronizzazione.md, section 5): SHA-256
 * in lower-case hexadecimal of
 * `booking_date|value_date|transaction_date|status|sign|cents|description`,
 * with ISO dates (empty when missing), sign `D` or `C`, the amount in cents
 * without sign and the normalized description (empty when missing).
 *
 * Only the description can hold `|`, and it is the last field: two different
 * rows never give the same text.
 */

export type Sign = "D" | "C";

export interface DedupFields {
  booking_date: string | null;
  value_date: string | null;
  transaction_date: string | null;
  status: string;
  sign: Sign;
  /** Cents without sign. */
  unsigned_amount_cents: number;
  /** Normalized description (6.3). */
  description: string | null;
}

/** The text that is hashed. */
export function dedupText(fields: DedupFields): string {
  return [
    fields.booking_date ?? "",
    fields.value_date ?? "",
    fields.transaction_date ?? "",
    fields.status,
    fields.sign,
    String(fields.unsigned_amount_cents),
    fields.description ?? "",
  ].join("|");
}

/** SHA-256 of `dedupText`, lower-case hexadecimal (WebCrypto). */
export async function dedupHash(fields: DedupFields): Promise<string> {
  const bytes = new TextEncoder().encode(dedupText(fields));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
