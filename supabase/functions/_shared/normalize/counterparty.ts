/**
 * Counterparty of a bank row (sincronizzazione.md, 6.2, 6.3 and 8): the
 * dedicated field when present (creditor on an outflow, debtor on an inflow),
 * otherwise extracted from the description with the format of the bank;
 * null when no format recognizes the description. The counterparty feeds
 * suggestions and rules: it never decides anything alone.
 */

import type { CreditDebitIndicator } from "../eb/types.ts";
import { emailOf, isPaypal, type LinkedAccountKind } from "./account.ts";
import { cleanText } from "./description.ts";

/** The account a row belongs to, as the sync knows it. */
export interface TransactionContext {
  /** Name of the bank (ASPSP) as Enable Banking names it. */
  aspspName: string;
  cashAccountType: string | null;
  accountKind: LinkedAccountKind;
}

/** A supported format (section 8); any other bank has none. */
export type BankFormat = "credem-cacc" | "credem-card" | "hype" | "paypal";

/** The parts of a row the counterparty is read from. */
export interface CounterpartySource {
  indicator: CreditDebitIndicator;
  creditor?: unknown;
  debtor?: unknown;
  /** Normalized description (6.3). */
  description: string | null;
  /** `bank_transaction_code.code`, trimmed. */
  code: string | null;
}

const CREDEM = /\bcredem\b|\bcredito emiliano\b/i;
const HYPE = /\bhype\b/i;

/** The format of the bank and account type; null without one. */
export function bankFormat(context: TransactionContext): BankFormat | null {
  if (context.accountKind === "paypal" || isPaypal(context.aspspName)) {
    return "paypal";
  }
  if (CREDEM.test(context.aspspName)) {
    if (context.accountKind === "card") return "credem-card";
    return context.cashAccountType === "CACC" ? "credem-cacc" : null;
  }
  return HYPE.test(context.aspspName) ? "hype" : null;
}

/** The party on the other side: creditor of an outflow, debtor of an inflow. */
function otherParty(source: CounterpartySource): unknown {
  return source.indicator === "DBIT" ? source.creditor : source.debtor;
}

function partyName(party: unknown): string | null {
  if (typeof party !== "object" || party === null) return null;
  return cleanText((party as { name?: unknown }).name);
}

/**
 * The counterparty of a row: dedicated field first, then the description
 * with the format of the bank.
 */
export function counterparty(
  source: CounterpartySource,
  format: BankFormat | null,
): string | null {
  const dedicated = partyName(otherParty(source));
  if (dedicated !== null) return dedicated;
  if (format === null || source.description === null) return null;
  return FORMATS[format](source.description, source.code);
}

/**
 * The email of the counterparty, PayPal only, in lower case: in the
 * contact details of the creditor (outflow) or of the debtor (inflow).
 */
export function counterpartyEmail(
  source: CounterpartySource,
  format: BankFormat | null,
): string | null {
  if (format !== "paypal") return null;
  const party = otherParty(source);
  if (typeof party !== "object" || party === null) return null;
  const details = (party as { contact_details?: unknown }).contact_details;
  if (typeof details !== "object" || details === null) return null;
  const email = (details as { email_address?: unknown }).email_address;
  if (typeof email !== "string") return null;
  return emailOf(email)?.toLowerCase() ?? null;
}

const CARD_MONTHLY_CHARGE = /^ADDEBITO MESE CARTA\b/i;

/**
 * The description of the monthly charge of the credit card on the current
 * account (section 8, used by the transfers of 7.1).
 */
export function isCardMonthlyCharge(
  description: string | null,
  format: BankFormat | null,
): boolean {
  return format === "credem-cacc" && description !== null &&
    CARD_MONTHLY_CHARGE.test(description);
}

type Extractor = (description: string, code: string | null) => string | null;

interface DescriptionRule {
  pattern: RegExp;
  /** The counterparty from the match; null when the row has none. */
  extract: (match: RegExpExecArray) => string | null;
}

/** First matching rule decides; no matching rule → null. */
function byRules(rules: DescriptionRule[]): Extractor {
  return (description) => {
    for (const rule of rules) {
      const match = rule.pattern.exec(description);
      if (match !== null) return cleanText(rule.extract(match));
    }
    return null;
  };
}

const group = (match: RegExpExecArray) => match[1] ?? null;

/** Words up to the first one holding a digit (IBAN, reference). */
function wordsBeforeDigits(text: string | undefined): string | null {
  const words = (text ?? "").split(" ");
  const end = words.findIndex((word) => /\d/.test(word));
  return words.slice(0, end === -1 ? words.length : end).join(" ");
}

/** Credito Emiliano, current account: the counterparty is in the description. */
const CREDEM_CACC_RULES: DescriptionRule[] = [
  // BANCOMAT 03/02/31,ORE 12:34,TESS.00000000 BAR ESEMPIO
  { pattern: /^BANCOMAT\b.*?\bTESS\.\S*\s+(.+)$/i, extract: group },
  // SEPA DD CORE DA ESEMPIO ENERGIA SPA MANDATO XX000000
  {
    pattern: /^SEPA DD CORE DA\s+(.+?)(?:\s+MANDATO\b.*)?$/i,
    extract: group,
  },
  // EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO
  { pattern: /^EMOLUMENTI\s+(.+?)(?:\s+STIPENDIO\b.*)?$/i, extract: group },
  // PAGAMENTO CBILL ESEMPIO SERVIZI
  { pattern: /^PAGAMENTO CBILL\s+(.+)$/i, extract: group },
  // COMM. PAG. CBILL: the fee of a bill, no counterparty.
  { pattern: /^COMM\. PAG\. CBILL\b/i, extract: () => null },
  // BON. ISTANTANEO A DEBITO ANNA ESEMPIO IT00A… RICARICA: the name ends
  // at the first word with a digit.
  {
    pattern: /^BON\. ISTANTANEO A DEBITO\s+(.+)$/i,
    extract: (match) => wordsBeforeDigits(match[1]),
  },
  // ADDEBITO MESE CARTA …: monthly charge of the card, no counterparty.
  { pattern: CARD_MONTHLY_CHARGE, extract: () => null },
];

/**
 * `NAME CITY XX`: without the two-letter code at the end (country or
 * province) and the last word (the city). At least three words.
 */
function withoutPlace(description: string): string | null {
  const words = description.split(" ");
  if (words.length < 3 || !/^[A-Z]{2}$/.test(words.at(-1) ?? "")) return null;
  return cleanText(words.slice(0, -2).join(" "));
}

const FORMATS: Record<BankFormat, Extractor> = {
  "credem-cacc": byRules(CREDEM_CACC_RULES),
  // ESERCENTE CITTÀ PAESE: FERRAMENTA PROVA CITTAPROVA IT → FERRAMENTA PROVA
  "credem-card": (description) => withoutPlace(description),
  // Card payments (`pos`) only: NOME CITTÀ PROV, CAFFE ESEMPIO CITTAPROVA ZZ
  hype: (description, code) =>
    code?.toLowerCase() === "pos" ? withoutPlace(description) : null,
  // Name and email in the dedicated fields only.
  paypal: () => null,
};
