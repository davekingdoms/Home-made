/**
 * Normalization of the synthetic Enable Banking data
 * (`_shared/testdata/eb/`, sincronizzazione.md, section 12): every row of
 * every page, and the cases that the normalization alone can check.
 */

import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "@std/assert";
import {
  InvalidRowError,
  type NormalizedTransaction,
  normalizeTransaction,
  type TransactionContext,
} from "./transaction.ts";
import { linkedAccount } from "./account.ts";
import { linkBalances } from "./balance.ts";
import type {
  AccountResource,
  HalBalances,
  HalTransactions,
} from "../eb/types.ts";
import { testdata } from "../testing/fake_fetch.ts";

const START_DATE = "2031-03-01";
const INVALID = "transactions-invalid.json";

/** The account of each folder: the root holds the generic responses. */
const CONTEXTS: Record<string, TransactionContext> = {
  "": { aspspName: "Mock ASPSP", cashAccountType: "CACC", accountKind: "bank" },
  "credem-cacc": {
    aspspName: "Credito Emiliano",
    cashAccountType: "CACC",
    accountKind: "bank",
  },
  "credem-card": {
    aspspName: "Credito Emiliano",
    cashAccountType: "CARD",
    accountKind: "card",
  },
  hype: { aspspName: "HYPE", cashAccountType: "CACC", accountKind: "bank" },
  paypal: {
    aspspName: "PayPal",
    cashAccountType: "OTHR",
    accountKind: "paypal",
  },
};

/** Paths, relative to `testdata/eb/`, of the pages of transactions. */
async function transactionPages(): Promise<string[]> {
  const root = new URL("../testdata/eb/", import.meta.url);
  const pages: string[] = [];
  async function walk(folder: string) {
    for await (const entry of Deno.readDir(new URL(folder, root))) {
      const path = `${folder}${entry.name}`;
      if (entry.isDirectory) await walk(`${path}/`);
      else if (entry.isFile && entry.name.endsWith(".json")) {
        const body = await testdata(path) as { transactions?: unknown };
        if (Array.isArray(body.transactions)) pages.push(path);
      }
    }
  }
  await walk("");
  return pages.sort();
}

function contextOf(path: string): TransactionContext {
  const folder = path.includes("/") ? path.slice(0, path.indexOf("/")) : "";
  const context = CONTEXTS[folder];
  assert(context !== undefined, `no account for the folder of ${path}`);
  return context;
}

async function page(path: string): Promise<NormalizedTransaction[]> {
  const body = await testdata(path) as HalTransactions;
  return await Promise.all(
    body.transactions.map((row) => normalizeTransaction(row, contextOf(path))),
  );
}

const counterparties = (rows: NormalizedTransaction[]) =>
  rows.map((row) => row.movement.counterparty);

Deno.test("test data: every row of every page normalizes", async () => {
  const pages = (await transactionPages()).filter((path) => path !== INVALID);
  for (
    const folder of ["credem-cacc/", "credem-card/", "hype/", "paypal/"]
  ) {
    assert(pages.some((path) => path.startsWith(folder)), folder);
  }
  let rows = 0;
  for (const path of pages) {
    const normalized = await page(path);
    assert(normalized.length > 0, path);
    rows += normalized.length;
  }
  assert(rows >= 50, `${rows} rows`);
});

Deno.test("test data: the rows built for the error are invalid_row", async () => {
  const body = await testdata(INVALID) as HalTransactions;
  assert(body.transactions.length >= 5);
  for (const [index, row] of body.transactions.entries()) {
    const error = await assertRejects(
      () => normalizeTransaction(row, contextOf(INVALID)),
      InvalidRowError,
      undefined,
      `row ${index}`,
    );
    assertEquals(error.code, "invalid_row");
  }
});

Deno.test("case 1: identical rows without reference share the hash", async () => {
  const day1 = await page("credem-card/transactions-day-1.json");
  const day2 = await page("credem-card/transactions-day-2.json");
  const coffee = day1.filter((row) =>
    row.movement.description === "CAFFE PROVA CITTAPROVA IT"
  );
  assertEquals(coffee.length, 2);
  assertEquals(coffee[0]!.raw.dedup_hash, coffee[1]!.raw.dedup_hash);
  assertEquals(coffee[0]!.raw.entry_reference, null);
  const hash = coffee[0]!.raw.dedup_hash;
  const count = (rows: NormalizedTransaction[]) =>
    rows.filter((row) => row.raw.dedup_hash === hash).length;
  assertEquals(count(day1), 2);
  // Downloaded again the day after, the window holds a third one.
  assertEquals(count(day2), 3);
  // The other rows are the same rows, with the same hashes.
  const others = (rows: NormalizedTransaction[]) =>
    rows.map((row) => row.raw.dedup_hash).filter((h) => h !== hash);
  assertEquals(others(day2), others(day1));
  assertEquals(new Set(others(day1)).size, others(day1).length);
});

Deno.test("case 2: bill and fee with references -001 and -002", async () => {
  const rows = await page("credem-cacc/transactions-page-1.json");
  const bill = rows.find((row) =>
    row.raw.entry_reference?.endsWith("-0000102-001")
  );
  const fee = rows.find((row) =>
    row.raw.entry_reference?.endsWith("-0000102-002")
  );
  assert(bill !== undefined && fee !== undefined);
  assertEquals(
    bill.raw.entry_reference!.slice(0, -4),
    fee.raw.entry_reference!.slice(0, -4),
  );
  assertEquals(bill.movement.counterparty, "ESEMPIO SERVIZI");
  assertEquals(bill.movement.amount_cents, -8000);
  assertEquals(fee.movement.counterparty, null);
  assertEquals(fee.movement.amount_cents, -150);
});

Deno.test("case 3: value date before the start date, booking date after", async () => {
  const rows = await page("credem-cacc/transactions-page-1.json");
  const row = rows.find((row) =>
    row.raw.entry_reference?.endsWith("-0000101-001")
  );
  assert(row !== undefined);
  assertEquals(row.raw.value_date, "2031-02-27");
  assertEquals(row.raw.booking_date, "2031-03-02");
  assertEquals(row.movement.movement_date, "2031-02-27");
  assert(row.movement.movement_date < START_DATE);
  assert(row.raw.booking_date! >= START_DATE);
});

Deno.test("case 10: RJCT and CNCL rows keep their status", async () => {
  const paypal = await page("paypal/transactions-anna-sync-1.json");
  const hype = await page("hype/transactions-sync-1.json");
  const rejected = paypal.filter((row) => row.raw.status === "RJCT");
  const cancelled = hype.filter((row) => row.raw.status === "CNCL");
  assertEquals(rejected.length, 1);
  assertEquals(cancelled.length, 1);
  assertEquals(rejected[0]!.movement.amount_cents, -1200);
  assertEquals(cancelled[0]!.movement.counterparty, "NEGOZIO PROVA");
});

Deno.test("case 11: amounts 4.4, 1, 12.50 and a rounded one", async () => {
  const rows = await page("credem-card/transactions-day-1.json");
  const amount = (description: string) => {
    const row = rows.find((row) => row.movement.description === description);
    assert(row !== undefined, description);
    return [
      row.raw.unsigned_amount_cents,
      row.movement.amount_cents,
      row.amount_rounded,
    ];
  };
  assertEquals(amount("EDICOLA PROVA CITTAPROVA IT"), [440, -440, false]);
  assertEquals(amount("PARCHEGGIO PROVA CITTAPROVA IT"), [100, -100, false]);
  assertEquals(amount("FERRAMENTA PROVA CITTAPROVA IT"), [1250, -1250, false]);
  assertEquals(amount("LIBRERIA ESEMPIO CITTAPROVA IT"), [713, -713, true]);
  assertEquals(amount("PAGAMENTO SALDO CARTA"), [12050, 12050, false]);
});

Deno.test("case 12: names with trailing spaces or empty are not default names", async () => {
  const credem = await testdata("credem-cacc/session.json") as {
    accounts: AccountResource[];
  };
  const hype = await testdata("hype/session.json") as {
    accounts: AccountResource[];
  };
  const [bank, card] = credem.accounts;
  assertEquals(bank!.name, "Anna Esempio   ");
  assertEquals(
    linkedAccount("Credito Emiliano", bank!)?.display_name,
    "Credito Emiliano …1234",
  );
  assertEquals(
    linkedAccount("Credito Emiliano", card!)?.display_name,
    "Carta di Prova …0001",
  );
  assertEquals(hype.accounts[0]!.name, "");
  assertEquals(
    linkedAccount("HYPE", hype.accounts[0]!)?.display_name,
    "HYPE …5678",
  );
  const details = (folder: string) =>
    testdata(`${folder}/account-details.json`) as Promise<{ name: string }>;
  assertEquals((await details("credem-cacc")).name, "Anna Esempio   ");
  assertEquals((await details("hype")).name, "");
});

Deno.test("case 15: balances of account, card, PayPal and prepaid account", async () => {
  const balances = async (path: string) =>
    linkBalances(await testdata(path) as HalBalances).map((
      balance,
    ) => [balance.balance_type, balance.currency, balance.amount_cents]);
  assertEquals(await balances("credem-cacc/balances.json"), [
    ["CLBD", "EUR", 234567],
  ]);
  assertEquals(await balances("credem-card/balances.json"), [
    ["CLBD", "EUR", -12050],
    ["OTHR", "EUR", 137950],
  ]);
  assertEquals(await balances("paypal/balances.json"), [
    ["XPCD", "EUR", 4210],
    ["XPCD", "USD", 750],
  ]);
  assertEquals(await balances("hype/balances.json"), [
    ["ITBD", "EUR", 8420],
    ["ITAV", "EUR", 8040],
  ]);
});

Deno.test("case 16: PDNG back as BOOK, with and without reference", async () => {
  const before = await page("hype/transactions-sync-1.json");
  const after = await page("hype/transactions-sync-2.json");
  const withReference = (rows: NormalizedTransaction[]) =>
    rows.find((row) => row.raw.entry_reference === "HY00000000000004");
  const withoutReference = (rows: NormalizedTransaction[]) =>
    rows.find((row) =>
      row.movement.description === "PANETTERIA PROVA CITTAPROVA ZZ"
    );
  for (const pick of [withReference, withoutReference]) {
    const pending = pick(before);
    const booked = pick(after);
    assert(pending !== undefined && booked !== undefined);
    assertEquals(pending.raw.status, "PDNG");
    assertEquals(booked.raw.status, "BOOK");
    assertEquals(pending.raw.entry_reference, booked.raw.entry_reference);
    assertEquals(pending.movement.movement_date, booked.movement.movement_date);
    assertEquals(pending.movement.amount_cents, booked.movement.amount_cents);
    // A different group: the booked row is no copy of the pending one.
    assertNotEquals(pending.raw.dedup_hash, booked.raw.dedup_hash);
  }
});

Deno.test("case 17: salary with its counterparty", async () => {
  const rows = await page("credem-cacc/transactions-page-1.json");
  const salary = rows.find((row) =>
    row.raw.entry_reference?.endsWith("-0000105-001")
  );
  assert(salary !== undefined);
  assertEquals(salary.raw.sign, "C");
  assertEquals(salary.movement.amount_cents, 185000);
  assertEquals(
    salary.movement.description,
    "EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO",
  );
  assertEquals(salary.movement.counterparty, "DITTA ESEMPIO SRL");
});

Deno.test("formats on the test data: counterparties and signals", async () => {
  const page1 = await page("credem-cacc/transactions-page-1.json");
  assertEquals(counterparties(page1), [
    "PIZZERIA ESEMPIO",
    "ESEMPIO SERVIZI",
    null,
    "BAR ESEMPIO",
    "DITTA ESEMPIO SRL",
    "PAYPAL EUROPE S.A R.L. ET CIE S.C.A.",
    "ESEMPIO ENERGIA SPA",
  ]);
  const page2 = await page("credem-cacc/transactions-page-2.json");
  assertEquals(counterparties(page2), [
    "PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.",
    "PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.",
    "ANNA ESEMPIO",
    null,
    "ANNA ESEMPIO",
  ]);
  assertEquals(page2.map((row) => row.card_monthly_charge), [
    false,
    false,
    false,
    true,
    false,
  ]);
  assertEquals(
    counterparties(await page("credem-card/transactions-day-1.json")),
    [
      "FERRAMENTA PROVA",
      "EDICOLA PROVA",
      "PARCHEGGIO PROVA",
      "LIBRERIA ESEMPIO",
      "CAFFE PROVA",
      "CAFFE PROVA",
      null,
    ],
  );
  assertEquals(counterparties(await page("hype/transactions-sync-1.json")), [
    "CAFFE ESEMPIO",
    "ANNA ESEMPIO",
    "ANNA ESEMPIO",
    "NEGOZIO PROVA",
    "ANNA ESEMPIO",
    "PANETTERIA PROVA",
    "BRUNO ESEMPIO",
  ]);
  const anna = await page("paypal/transactions-anna-sync-1.json");
  assertEquals(counterparties(anna), [
    "Negozio Esempio",
    "PayPal",
    "Elettronica Esempio",
    "Bruno Esempio",
    null,
    "Libreria Esempio",
    "Negozio Prova",
    "PayPal",
    "App Esempio",
  ]);
  assertEquals(anna.map((row) => row.movement.counterparty_email), [
    "negozio@example.com",
    null,
    "elettronica@example.com",
    "bruno.paypal@example.com",
    null,
    "libreria@example.com",
    "negozio.prova@example.com",
    null,
    "app@example.com",
  ]);
  assertEquals(anna.map((row) => row.movement.bank_code), [
    "PAYMENT/PAYMENT",
    "PAYMENT/LOAN",
    "PAYMENT/PAYMENT",
    "PAYMENT/PAYMENT",
    null,
    "PAYMENT/PAYMENT",
    "PAYMENT/PAYMENT",
    "PAYMENT/LOAN",
    "PAYMENT/PAYMENT",
  ]);
  const exchange = anna.at(-1)!.movement;
  assertEquals(
    [
      exchange.amount_cents,
      exchange.original_amount_cents,
      exchange.original_currency,
      exchange.exchange_rate,
    ],
    [-920, -1000, "USD", "1.0870"],
  );
  const bruno = await page("paypal/transactions-bruno.json");
  assertEquals(counterparties(bruno), ["Anna Esempio"]);
  assertEquals(
    bruno[0]!.movement.counterparty_email,
    "anna.paypal@example.com",
  );
});
