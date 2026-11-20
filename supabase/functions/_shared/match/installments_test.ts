/**
 * PayPal installment plans (sincronizzazione.md, 7.3 and 12): case 4 on
 * the synthetic data of `_shared/testdata/eb/paypal/`, normalized as
 * eb-sync imports them, over two syncs and with the variant, and each rule
 * on small invented candidates. The pgTAP test
 * `installment_matching_test.sql` applies the same proposals.
 */

import { assertEquals } from "@std/assert";
import {
  type CandidatePlan,
  type InstallmentCandidates,
  installmentCount,
  type InstallmentProposal,
  type InstallmentRow,
  matchInstallments,
  merchantOf,
} from "./installments.ts";
import { windowStart } from "./transfers.ts";
import { normalizeTransaction } from "../normalize/transaction.ts";
import type { HalTransactions } from "../eb/types.ts";
import { testdata } from "../testing/fake_fetch.ts";

const START_DATE = "2031-03-01";
const ACCOUNT = "paypal-anna";

/**
 * The raw rows of a page of PayPal as `installment_candidates` returns
 * them: the id is the reference of the bank, the movement (`BOOK`, from the
 * start date, as `ingest_bank_rows` creates it) is `tx-` and the reference,
 * free and in no plan.
 */
async function paypalRows(path: string): Promise<InstallmentRow[]> {
  const page = await testdata(path) as HalTransactions;
  const rows: InstallmentRow[] = [];
  for (const row of page.transactions) {
    const { raw, movement } = await normalizeTransaction(row, {
      aspspName: "PayPal",
      cashAccountType: "OTHR",
      accountKind: "paypal",
    });
    const code = row.bank_transaction_code as
      | { code?: string; sub_code?: string }
      | null;
    const purchase = code?.sub_code === "PAYMENT";
    const isMovement = raw.status === "BOOK" &&
      movement.movement_date >= START_DATE && movement.amount_cents !== 0;
    rows.push({
      raw_id: raw.entry_reference!,
      account_id: ACCOUNT,
      status: raw.status,
      movement_date: movement.movement_date,
      amount_cents: movement.amount_cents,
      currency: raw.currency,
      code: code?.code ?? null,
      sub_code: code?.sub_code ?? null,
      creditor_name: purchase
        ? (row.creditor as { name?: string } | null)?.name ?? null
        : null,
      remittance: purchase ? row.remittance_information : null,
      transaction_id: isMovement ? `tx-${raw.entry_reference}` : null,
      installment_plan_id: null,
      free: isMovement,
      cancelled: false,
    });
  }
  return rows;
}

const SYNC_1 = await paypalRows("paypal/transactions-anna-sync-1.json");
const SYNC_2 = await paypalRows("paypal/transactions-anna-sync-2.json");

/** A sync on the day of the last row: everything is in the window. */
const SINCE = windowStart("2031-04-11");

/** The rows of a sync after the proposals of the previous ones. */
function afterLinks(
  rows: InstallmentRow[],
  links: Record<string, string>,
  deleted: string[] = [],
): InstallmentRow[] {
  return rows.map((row) => {
    const plan = row.transaction_id === null
      ? undefined
      : links[row.transaction_id];
    if (deleted.includes(row.raw_id)) {
      return { ...row, transaction_id: null, free: false };
    }
    return plan === undefined
      ? row
      : { ...row, installment_plan_id: plan, free: false };
  });
}

const plan = (fields: Partial<CandidatePlan> = {}): CandidatePlan => ({
  id: "piano-1",
  account_id: ACCOUNT,
  purchase_raw_id: "acquisto-1",
  purchase_date: "2031-03-02",
  total_cents: 9000,
  installments_count: 3,
  installments_before_start: 0,
  next_due_date: "2031-04-01",
  status: "active",
  deleted: false,
  ...fields,
});

/** A raw row of the account, a movement free from the start date. */
const row = (
  id: string,
  date: string,
  cents: number,
  subCode: "PAYMENT" | "LOAN",
  fields: Partial<InstallmentRow> = {},
): InstallmentRow => ({
  raw_id: id,
  account_id: ACCOUNT,
  status: "BOOK",
  movement_date: date,
  amount_cents: cents,
  currency: "EUR",
  code: "PAYMENT",
  sub_code: subCode,
  creditor_name: subCode === "PAYMENT" ? "Negozio Prova" : null,
  remittance: null,
  transaction_id: date >= START_DATE ? `tx-${id}` : null,
  installment_plan_id: null,
  free: date >= START_DATE,
  cancelled: false,
  ...fields,
});

const candidates = (
  rows: InstallmentRow[],
  plans: CandidatePlan[] = [],
): InstallmentCandidates => ({ start_date: START_DATE, rows, plans });

const match = (rows: InstallmentRow[], plans: CandidatePlan[] = []) =>
  matchInstallments(candidates(rows, plans), SINCE);

const creation = (
  purchase: string,
  first: string,
  merchant: string,
  fields: Partial<InstallmentProposal>,
): InstallmentProposal => ({
  plan_id: null,
  purchase_raw_id: purchase,
  first_raw_id: first,
  merchant,
  installments_before_start: 0,
  installments_paid: 1,
  last_installment_date: "",
  transaction_ids: [],
  ...fields,
});

const update = (
  id: string,
  fields: Partial<InstallmentProposal>,
): InstallmentProposal => ({
  plan_id: id,
  purchase_raw_id: null,
  first_raw_id: null,
  merchant: null,
  installments_before_start: 0,
  installments_paid: 1,
  last_installment_date: "",
  transaction_ids: [],
  ...fields,
});

Deno.test("the number of installments: round(P / L) between 2 and 12, |P − n·L| ≤ n", () => {
  assertEquals(installmentCount(9000, 3000), 3);
  assertEquals(installmentCount(10000, 3333), 3);
  assertEquals(installmentCount(10000, 3334), 3);
  assertEquals(installmentCount(10000, 3300), null);
  assertEquals(installmentCount(3000, 3000), null);
  assertEquals(installmentCount(13000, 1000), null);
  assertEquals(installmentCount(12000, 1000), 12);
  assertEquals(installmentCount(5000, 2000), null);
  assertEquals(installmentCount(0, 1000), null);
});

Deno.test("the merchant: the name, else the description, else PayPal; never the email", () => {
  const purchase = row("a", "2031-03-02", -9000, "PAYMENT");
  assertEquals(
    merchantOf({ ...purchase, creditor_name: "  Negozio   Prova " }),
    "Negozio Prova",
  );
  assertEquals(
    merchantOf({
      ...purchase,
      creditor_name: null,
      remittance: ["Ordine", " Negozio Esempio"],
    }),
    "Ordine Negozio Esempio",
  );
  assertEquals(
    merchantOf({ ...purchase, creditor_name: " ", remittance: [] }),
    "PayPal",
  );
});

Deno.test("case 4, first sync: the plan of the purchase before the start date", () => {
  assertEquals(match(SYNC_1), [
    creation("PP0000000000000001", "PP0000000000000002", "Negozio Esempio", {
      installments_before_start: 1,
      installments_paid: 2,
      last_installment_date: "2031-03-12",
      transaction_ids: ["tx-PP0000000000000003"],
    }),
  ]);
});

Deno.test("case 4, second sync: the third installment completes the plan; the variant", () => {
  const plans = [plan({
    id: "piano-negozio",
    purchase_raw_id: "PP0000000000000001",
    purchase_date: "2031-02-10",
    installments_before_start: 1,
    next_due_date: "2031-04-11",
  })];
  const rows = afterLinks(SYNC_2, {
    "tx-PP0000000000000003": "piano-negozio",
  });
  assertEquals(match(rows, plans), [
    update("piano-negozio", {
      installments_before_start: 1,
      installments_paid: 3,
      last_installment_date: "2031-04-11",
      transaction_ids: ["tx-PP0000000000000004"],
    }),
    creation(
      "PP0000000000000010",
      "PP0000000000000011",
      "Elettronica Esempio",
      {
        installments_paid: 2,
        last_installment_date: "2031-04-04",
        transaction_ids: ["tx-PP0000000000000011", "tx-PP0000000000000012"],
      },
    ),
  ]);
});

Deno.test("case 4: run again, nothing more", () => {
  const plans = [
    plan({
      id: "piano-negozio",
      purchase_raw_id: "PP0000000000000001",
      purchase_date: "2031-02-10",
      installments_before_start: 1,
      next_due_date: null,
      status: "completed",
    }),
    plan({
      id: "piano-elettronica",
      purchase_raw_id: "PP0000000000000010",
      purchase_date: "2031-03-05",
      total_cents: 6000,
      next_due_date: "2031-05-04",
    }),
  ];
  const rows = afterLinks(SYNC_2, {
    "tx-PP0000000000000003": "piano-negozio",
    "tx-PP0000000000000004": "piano-negozio",
    "tx-PP0000000000000011": "piano-elettronica",
    "tx-PP0000000000000012": "piano-elettronica",
  }, ["PP0000000000000010"]);
  assertEquals(match(rows, plans), []);
});

Deno.test("the next installment goes to the oldest plan with that amount and room", () => {
  const rows = [
    row("a1", "2031-03-02", -9000, "PAYMENT"),
    row("r1", "2031-03-02", -3000, "LOAN"),
    row("a2", "2031-03-05", -6000, "PAYMENT"),
    row("r2", "2031-03-05", -3000, "LOAN"),
    // 30 and 27 days after the first ones: the oldest plan.
    row("r3", "2031-04-01", -3000, "LOAN"),
    // 3 days after r3, 30 after r2: the other plan.
    row("r4", "2031-04-04", -3000, "LOAN"),
  ];
  assertEquals(match(rows), [
    creation("a1", "r1", "Negozio Prova", {
      installments_paid: 2,
      last_installment_date: "2031-04-01",
      transaction_ids: ["tx-r1", "tx-r3"],
    }),
    creation("a2", "r2", "Negozio Prova", {
      installments_paid: 2,
      last_installment_date: "2031-04-04",
      transaction_ids: ["tx-r2", "tx-r4"],
    }),
  ]);
});

Deno.test("a complete plan takes no installment; less than 20 days: nothing", () => {
  const rows = [
    row("a1", "2031-03-02", -6000, "PAYMENT"),
    row("r1", "2031-03-02", -3000, "LOAN"),
    row("r2", "2031-03-21", -3000, "LOAN"),
    row("r3", "2031-04-01", -3000, "LOAN"),
    row("r4", "2031-05-01", -3000, "LOAN"),
  ];
  // r2 is 19 days after r1; r3 completes the plan of 2; r4 finds no plan.
  assertEquals(match(rows), [
    creation("a1", "r1", "Negozio Prova", {
      installments_paid: 2,
      last_installment_date: "2031-04-01",
      transaction_ids: ["tx-r1", "tx-r3"],
    }),
  ]);
});

Deno.test("the last installment differs up to n cents, the others 1 cent", () => {
  const rows = [
    row("a1", "2031-03-02", -10000, "PAYMENT"),
    row("r1", "2031-03-02", -3333, "LOAN"),
    // 2 cents away from L: not the second installment.
    row("r2", "2031-04-01", -3335, "LOAN"),
    row("r3", "2031-04-02", -3334, "LOAN"),
    // The third and last one, 1 cent more than allowed for the others.
    row("r4", "2031-05-02", -3335, "LOAN"),
  ];
  assertEquals(match(rows), [
    creation("a1", "r1", "Negozio Prova", {
      installments_paid: 3,
      last_installment_date: "2031-05-02",
      transaction_ids: ["tx-r1", "tx-r3", "tx-r4"],
    }),
  ]);
});

Deno.test("on a par: two first installments, or two purchases, give no plan", () => {
  assertEquals(
    match([
      row("a1", "2031-03-02", -9000, "PAYMENT"),
      row("r1", "2031-03-02", -3000, "LOAN"),
      row("r2", "2031-03-02", -3000, "LOAN"),
    ]),
    [],
  );
  assertEquals(
    match([
      row("a1", "2031-03-02", -9000, "PAYMENT"),
      row("a2", "2031-03-02", -9000, "PAYMENT"),
      row("r1", "2031-03-02", -3000, "LOAN"),
    ]),
    [],
  );
  // Another day, or another amount that is no installment of it: one plan.
  assertEquals(
    match([
      row("a1", "2031-03-02", -9000, "PAYMENT"),
      row("a2", "2031-03-02", -1500, "PAYMENT"),
      row("r1", "2031-03-02", -3000, "LOAN"),
      row("r2", "2031-03-03", -3000, "LOAN"),
    ]).map((proposal) => proposal.purchase_raw_id),
    ["a1"],
  );
});

Deno.test("only BOOK outflows in EUR of PAYMENT/PAYMENT and PAYMENT/LOAN", () => {
  const first = row("r1", "2031-03-02", -3000, "LOAN");
  const purchase = row("a1", "2031-03-02", -9000, "PAYMENT");
  for (
    const other of [
      { status: "PDNG" },
      { currency: "USD" },
      { amount_cents: 9000 },
      { code: "TRANSFER" },
    ]
  ) {
    assertEquals(match([{ ...purchase, ...other }, first]), []);
    assertEquals(match([purchase, { ...first, ...other }]), []);
  }
});

Deno.test("a deleted plan is not made again and keeps its installments", () => {
  const rows = [
    row("a1", "2031-03-02", -9000, "PAYMENT"),
    row("r1", "2031-03-02", -3000, "LOAN", {
      installment_plan_id: "piano-1",
      free: false,
      cancelled: true,
    }),
    row("a2", "2031-03-05", -6000, "PAYMENT"),
    row("r2", "2031-03-05", -3000, "LOAN"),
    // Of the deleted plan (the oldest), not of the other one.
    row("r3", "2031-04-01", -3000, "LOAN", { cancelled: true }),
  ];
  assertEquals(match(rows, [plan({ purchase_raw_id: "a1", deleted: true })]), [
    creation("a2", "r2", "Negozio Prova", {
      last_installment_date: "2031-03-05",
      transaction_ids: ["tx-r2"],
    }),
  ]);
});

Deno.test("a purchase in a deleted transfer, settlement or plan gives no plan", () => {
  assertEquals(
    match([
      row("a1", "2031-03-02", -9000, "PAYMENT", { cancelled: true }),
      row("r1", "2031-03-02", -3000, "LOAN"),
    ]),
    [],
  );
});

Deno.test("a purchase already classified still makes its plan", () => {
  assertEquals(
    match([
      row("a1", "2031-03-02", -9000, "PAYMENT", { free: false }),
      row("r1", "2031-03-02", -3000, "LOAN"),
    ]).map((proposal) => proposal.purchase_raw_id),
    ["a1"],
  );
});

Deno.test("installments counted but not linked: before the window, not free, cancelled", () => {
  const rows = [
    row("a1", "2031-01-02", -12000, "PAYMENT", { transaction_id: null }),
    row("r1", "2031-01-02", -3000, "LOAN", { transaction_id: null }),
    // A movement before the window of 45 days.
    row("r2", "2031-02-01", -3000, "LOAN", {
      transaction_id: "tx-r2",
      free: true,
    }),
    // Classified by hand.
    row("r3", "2031-03-03", -3000, "LOAN", { free: false }),
    // In a deleted transfer.
    row("r4", "2031-04-02", -3000, "LOAN", { cancelled: true }),
  ];
  assertEquals(
    matchInstallments(
      { start_date: "2031-01-01", rows, plans: [] },
      "2031-02-25",
    ),
    [
      creation("a1", "r1", "Negozio Prova", {
        installments_paid: 4,
        last_installment_date: "2031-04-02",
      }),
    ],
  );
});

Deno.test("a plan already there: only what changes", () => {
  const rows = [
    row("a1", "2031-03-02", -9000, "PAYMENT", { transaction_id: null }),
    row("r1", "2031-03-02", -3000, "LOAN", {
      installment_plan_id: "piano-1",
      free: false,
    }),
  ];
  assertEquals(match(rows, [plan()]), []);
  // The second installment.
  assertEquals(
    match([...rows, row("r2", "2031-04-01", -3000, "LOAN")], [plan()]),
    [
      update("piano-1", {
        installments_paid: 2,
        last_installment_date: "2031-04-01",
        transaction_ids: ["tx-r2"],
      }),
    ],
  );
  // The second installment classified by hand: only the dates.
  assertEquals(
    match([
      ...rows,
      row("r2", "2031-04-01", -3000, "LOAN", { free: false }),
    ], [plan()]),
    [
      update("piano-1", {
        installments_paid: 2,
        last_installment_date: "2031-04-01",
      }),
    ],
  );
});

Deno.test("an installment linked to a plan stays with it", () => {
  const plans = [
    plan(),
    plan({
      id: "piano-2",
      purchase_raw_id: "a2",
      purchase_date: "2031-03-05",
      next_due_date: "2031-04-04",
    }),
  ];
  const rows = [
    row("a1", "2031-03-02", -9000, "PAYMENT"),
    row("r1", "2031-03-02", -3000, "LOAN", {
      installment_plan_id: "piano-1",
      free: false,
    }),
    row("a2", "2031-03-05", -9000, "PAYMENT"),
    row("r2", "2031-03-05", -3000, "LOAN", {
      installment_plan_id: "piano-2",
      free: false,
    }),
    // The oldest plan would take it, but it is already of the other one.
    row("r3", "2031-04-04", -3000, "LOAN", {
      installment_plan_id: "piano-2",
      free: false,
    }),
  ];
  assertEquals(match(rows, plans), [
    update("piano-2", {
      installments_paid: 2,
      last_installment_date: "2031-04-04",
    }),
  ]);
});
