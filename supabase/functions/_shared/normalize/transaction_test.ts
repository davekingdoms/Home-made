import { assertEquals, assertFalse, assertRejects } from "@std/assert";
import {
  InvalidRowError,
  normalizeTransaction,
  type TransactionContext,
} from "./transaction.ts";
import { dedupHash } from "./hash.ts";
import type { Transaction } from "../eb/types.ts";

const CREDEM_CACC: TransactionContext = {
  aspspName: "Credito Emiliano",
  cashAccountType: "CACC",
  accountKind: "bank",
};
const PAYPAL: TransactionContext = {
  aspspName: "PayPal",
  cashAccountType: "OTHR",
  accountKind: "paypal",
};
const OTHER_BANK: TransactionContext = {
  aspspName: "Banca di Prova",
  cashAccountType: "CACC",
  accountKind: "bank",
};

const BILL = {
  entry_reference: "0000000000-20310303-0000102-001",
  transaction_amount: { currency: "EUR", amount: "80.5" },
  credit_debit_indicator: "DBIT",
  status: "BOOK",
  booking_date: "2031-03-04",
  value_date: "2031-03-03",
  remittance_information: ["PAGAMENTO  CBILL", " ESEMPIO SERVIZI "],
  bank_transaction_code: { code: "PMNT", sub_code: "BILL" },
  debtor_account: { iban: "IT00A0000000000000000001234" },
} as unknown as Transaction;

Deno.test("a booked outflow: raw fields and movement", async () => {
  const result = await normalizeTransaction(BILL, CREDEM_CACC);
  assertEquals(result.raw, {
    entry_reference: "0000000000-20310303-0000102-001",
    status: "BOOK",
    booking_date: "2031-03-04",
    value_date: "2031-03-03",
    transaction_date: null,
    sign: "D",
    unsigned_amount_cents: 8050,
    currency: "EUR",
    dedup_hash: await dedupHash({
      booking_date: "2031-03-04",
      value_date: "2031-03-03",
      transaction_date: null,
      status: "BOOK",
      sign: "D",
      unsigned_amount_cents: 8050,
      description: "PAGAMENTO CBILL ESEMPIO SERVIZI",
    }),
    payload: BILL,
  });
  assertEquals(result.movement, {
    movement_date: "2031-03-03",
    amount_cents: -8050,
    original_amount_cents: null,
    original_currency: null,
    exchange_rate: null,
    description: "PAGAMENTO CBILL ESEMPIO SERVIZI",
    counterparty: "ESEMPIO SERVIZI",
    counterparty_email: null,
    bank_code: "PMNT/BILL",
  });
  assertFalse(result.amount_rounded);
  assertFalse(result.card_monthly_charge);
});

Deno.test("movement date: value date, else transaction date, else booking date", async () => {
  const base = { ...BILL, value_date: undefined, transaction_date: undefined };
  const cases: [Record<string, unknown>, string][] = [
    [
      { value_date: "2031-02-27", transaction_date: "2031-02-26" },
      "2031-02-27",
    ],
    [{ transaction_date: "2031-02-26" }, "2031-02-26"],
    [{}, "2031-03-04"],
    [{ value_date: null, transaction_date: "" }, "2031-03-04"],
  ];
  for (const [dates, expected] of cases) {
    const result = await normalizeTransaction(
      { ...base, ...dates } as Transaction,
      CREDEM_CACC,
    );
    assertEquals(
      result.movement.movement_date,
      expected,
      JSON.stringify(dates),
    );
  }
});

Deno.test("dates: ISO day, a time part is cut, missing is null", async () => {
  const result = await normalizeTransaction(
    {
      ...BILL,
      booking_date: "2031-03-04T10:00:00Z",
      value_date: null,
      transaction_date: "2031-03-02",
    } as Transaction,
    CREDEM_CACC,
  );
  assertEquals(result.raw.booking_date, "2031-03-04");
  assertEquals(result.raw.value_date, null);
  assertEquals(result.raw.transaction_date, "2031-03-02");
  assertEquals(result.movement.movement_date, "2031-03-02");
});

Deno.test("an inflow is positive with sign C", async () => {
  const result = await normalizeTransaction(
    {
      ...BILL,
      credit_debit_indicator: "CRDT",
      transaction_amount: { currency: "EUR", amount: "1850" },
      remittance_information: ["EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO"],
    } as Transaction,
    CREDEM_CACC,
  );
  assertEquals(result.raw.sign, "C");
  assertEquals(result.raw.unsigned_amount_cents, 185000);
  assertEquals(result.movement.amount_cents, 185000);
  assertEquals(result.movement.counterparty, "DITTA ESEMPIO SRL");
});

Deno.test("more than two decimals: rounded half up, with the signal", async () => {
  const result = await normalizeTransaction(
    {
      ...BILL,
      transaction_amount: { currency: "EUR", amount: "7.125" },
    } as Transaction,
    CREDEM_CACC,
  );
  assertEquals(result.raw.unsigned_amount_cents, 713);
  assertEquals(result.movement.amount_cents, -713);
  assertEquals(result.amount_rounded, true);
});

Deno.test("exchange block: original amount with the sign, currency and rate", async () => {
  const result = await normalizeTransaction(
    {
      ...BILL,
      transaction_amount: { currency: "EUR", amount: "9.20" },
      exchange_rate: {
        unit_currency: "USD",
        exchange_rate: "1.0870",
        instructed_amount: { currency: "USD", amount: "10.0049" },
      },
    } as Transaction,
    PAYPAL,
  );
  assertEquals(result.movement.amount_cents, -920);
  assertEquals(result.movement.original_amount_cents, -1000);
  assertEquals(result.movement.original_currency, "USD");
  assertEquals(result.movement.exchange_rate, "1.0870");
  // The instructed amount had more than two decimals.
  assertEquals(result.amount_rounded, true);
});

Deno.test("exchange block: each part only when present", async () => {
  const rateOnly = await normalizeTransaction(
    { ...BILL, exchange_rate: { exchange_rate: "0.9" } } as Transaction,
    OTHER_BANK,
  );
  assertEquals(rateOnly.movement.original_amount_cents, null);
  assertEquals(rateOnly.movement.original_currency, null);
  assertEquals(rateOnly.movement.exchange_rate, "0.9");
  const empty = await normalizeTransaction(
    { ...BILL, exchange_rate: {} } as Transaction,
    OTHER_BANK,
  );
  assertEquals(empty.movement.exchange_rate, null);
  assertEquals(empty.movement.original_amount_cents, null);
});

Deno.test("bank code: code/sub_code, the code alone, or null", async () => {
  const cases: [unknown, string | null][] = [
    [{ code: "PAYMENT", sub_code: "LOAN" }, "PAYMENT/LOAN"],
    [{ code: "pos" }, "pos"],
    [{ code: "pos", sub_code: " " }, "pos"],
    [{ sub_code: "LOAN" }, null],
    [{ description: "Pagamento" }, null],
    [null, null],
    [undefined, null],
  ];
  for (const [code, expected] of cases) {
    const result = await normalizeTransaction(
      { ...BILL, bank_transaction_code: code } as Transaction,
      OTHER_BANK,
    );
    assertEquals(result.movement.bank_code, expected, JSON.stringify(code));
  }
});

Deno.test("entry reference: trimmed, empty or missing is null", async () => {
  for (const reference of [undefined, null, "", "  "]) {
    const result = await normalizeTransaction(
      { ...BILL, entry_reference: reference } as Transaction,
      CREDEM_CACC,
    );
    assertEquals(result.raw.entry_reference, null);
  }
});

Deno.test("PayPal: counterparty and email of the creditor, in lower case", async () => {
  const result = await normalizeTransaction(
    {
      entry_reference: "PP0000000000000005",
      transaction_amount: { currency: "EUR", amount: "20.00" },
      credit_debit_indicator: "DBIT",
      status: "BOOK",
      transaction_date: "2031-03-06",
      creditor: {
        name: "Bruno Esempio",
        contact_details: { email_address: "Bruno.Paypal@Example.com" },
      },
      bank_transaction_code: { code: "PAYMENT", sub_code: "PAYMENT" },
    } as Transaction,
    PAYPAL,
  );
  assertEquals(result.movement.counterparty, "Bruno Esempio");
  assertEquals(result.movement.counterparty_email, "bruno.paypal@example.com");
  assertEquals(result.movement.description, null);
  assertEquals(result.movement.bank_code, "PAYMENT/PAYMENT");
});

Deno.test("monthly charge of the card on the current account", async () => {
  const result = await normalizeTransaction(
    {
      ...BILL,
      remittance_information: ["ADDEBITO MESE CARTA EGO"],
    } as Transaction,
    CREDEM_CACC,
  );
  assertEquals(result.card_monthly_charge, true);
  assertEquals(result.movement.counterparty, null);
});

Deno.test("statuses kept in the raw rows", async () => {
  for (const status of ["BOOK", "PDNG", "RJCT", "CNCL"]) {
    const result = await normalizeTransaction(
      { ...BILL, status } as Transaction,
      CREDEM_CACC,
    );
    assertEquals(result.raw.status, status);
  }
});

Deno.test("invalid rows: invalid_row, never the value in the message", async () => {
  const secret = "9876.54";
  const cases: [Record<string, unknown>, string][] = [
    [
      { transaction_amount: { currency: "EUR", amount: "9876,54" } },
      "transaction_amount",
    ],
    [{
      transaction_amount: {
        currency: "EUR",
        amount: secret.replace(".", ".."),
      },
    }, "transaction_amount"],
    [
      { transaction_amount: { currency: "EUR", amount: 9876.54 } },
      "transaction_amount",
    ],
    [
      { transaction_amount: { currency: "eur", amount: secret } },
      "transaction_amount",
    ],
    [{ transaction_amount: undefined }, "transaction_amount"],
    [{ credit_debit_indicator: "D" }, "credit_debit_indicator"],
    [{ status: "HOLD" }, "status"],
    [{ status: undefined }, "status"],
    [{ booking_date: "2031-02-30" }, "booking_date"],
    [{ value_date: "04/03/2031" }, "value_date"],
    [{ transaction_date: 20310304 }, "transaction_date"],
    [
      { booking_date: null, value_date: null, transaction_date: null },
      "missing date",
    ],
    [
      {
        exchange_rate: { instructed_amount: { currency: "USD", amount: "x" } },
      },
      "exchange_rate",
    ],
    [{ exchange_rate: { exchange_rate: "1,08" } }, "exchange_rate"],
    [{ exchange_rate: "1.08" }, "exchange_rate"],
  ];
  for (const [change, field] of cases) {
    const error = await assertRejects(
      () =>
        normalizeTransaction(
          { ...BILL, ...change } as Transaction,
          CREDEM_CACC,
        ),
      InvalidRowError,
      undefined,
      JSON.stringify(change),
    );
    assertEquals(error.code, "invalid_row");
    assertEquals(error.message.includes(field), true, error.message);
    for (
      const value of [
        secret,
        "9876",
        "2031-02-30",
        "04/03/2031",
        "1,08",
        "HOLD",
      ]
    ) {
      assertFalse(error.message.includes(value), error.message);
    }
  }
  await assertRejects(
    () => normalizeTransaction(null as unknown as Transaction, CREDEM_CACC),
    InvalidRowError,
  );
});
