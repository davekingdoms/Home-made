/**
 * Enable Banking API responses used by the sync, from the API reference
 * (https://enablebanking.com/docs/api/reference/). Only the fields we read are
 * typed; the rest stays `unknown`, because the whole payload of a transaction
 * goes into `bank_raw_transactions.payload`. Enum values come from the bank:
 * the normalization checks them before use.
 */

/** A response object: typed fields plus whatever else the API sends. */
export type Open<T> = T & { readonly [field: string]: unknown };

export type PsuType = "personal" | "business";

export type TransactionStatus =
  | "BOOK"
  | "CNCL"
  | "HOLD"
  | "OTHR"
  | "PDNG"
  | "RJCT"
  | "SCHD";

export type CreditDebitIndicator = "CRDT" | "DBIT";

export type TransactionsFetchStrategy = "default" | "longest";

export type SessionStatus =
  | "INVALID"
  | "PENDING_AUTHORIZATION"
  | "RETURNED_FROM_BANK"
  | "AUTHORIZED"
  | "EXPIRED"
  | "CLOSED"
  | "REVOKED"
  | "CANCELLED";

/** Amount as text with `.` as decimal separator and variable decimals. */
export type AmountType = Open<{ currency: string; amount: string }>;

export type Aspsp = Open<{ name: string; country: string }>;

export type AspspData = Open<{
  name: string;
  country: string;
  /** Longest consent the bank grants, in seconds. */
  maximum_consent_validity: number;
  psu_types: PsuType[];
  beta?: boolean;
  required_psu_headers?: string[];
}>;

export type GetAspspsResponse = Open<{ aspsps: AspspData[] }>;

export type Access = Open<{
  valid_until: string;
  balances?: boolean;
  transactions?: boolean;
}>;

/** Body of `POST /auth`, with the fields the sync sends. */
export interface StartAuthRequest {
  access: { valid_until: string };
  aspsp: { name: string; country: string };
  state: string;
  redirect_url: string;
  psu_type: PsuType;
}

export type StartAuthResponse = Open<{
  url: string;
  authorization_id: string;
}>;

export type GenericIdentification = Open<{
  identification: string;
  scheme_name: string;
}>;

export type AccountIdentification = Open<{
  iban?: string;
  other?: GenericIdentification;
}>;

export type AccountResource = Open<{
  uid?: string;
  account_id?: AccountIdentification;
  name?: string;
  product?: string;
  cash_account_type: string;
  currency: string;
  identification_hash: string;
}>;

/** `POST /sessions`. */
export type AuthorizeSessionResponse = Open<{
  session_id: string;
  accounts: AccountResource[];
  aspsp: Aspsp;
  psu_type: PsuType;
  access: Access;
}>;

/** `GET /sessions/{session_id}`. */
export type GetSessionResponse = Open<{
  status: SessionStatus;
  accounts: string[];
  access: Access;
}>;

export type BalanceResource = Open<{
  name: string;
  balance_amount: AmountType;
  balance_type: string;
  reference_date?: string;
}>;

export type HalBalances = Open<{ balances: BalanceResource[] }>;

export type PartyIdentification = Open<{
  name?: string;
  contact_details?: Open<{ email_address?: string }>;
}>;

export type BankTransactionCode = Open<{
  code?: string;
  sub_code?: string;
  description?: string;
}>;

export type ExchangeRate = Open<{
  unit_currency?: string;
  exchange_rate?: string;
  instructed_amount?: AmountType;
}>;

export type Transaction = Open<{
  entry_reference?: string | null;
  transaction_id?: string | null;
  transaction_amount: AmountType;
  credit_debit_indicator: CreditDebitIndicator;
  status: TransactionStatus;
  booking_date?: string | null;
  value_date?: string | null;
  transaction_date?: string | null;
  remittance_information?: string[] | null;
  creditor?: PartyIdentification | null;
  debtor?: PartyIdentification | null;
  creditor_account?: AccountIdentification | null;
  debtor_account?: AccountIdentification | null;
  bank_transaction_code?: BankTransactionCode | null;
  exchange_rate?: ExchangeRate | null;
}>;

/** One page of `GET /accounts/{uid}/transactions`. */
export type HalTransactions = Open<{
  transactions: Transaction[];
  /** Key of the next page; missing or null on the last page. */
  continuation_key?: string | null;
}>;
