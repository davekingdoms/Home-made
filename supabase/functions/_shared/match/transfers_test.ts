/**
 * Automatic transfers (sincronizzazione.md, 7.1 and 12): the cases 6, 7, 8,
 * 9, 18 and 19 on the synthetic data of `_shared/testdata/eb/`, normalized
 * as eb-sync imports them, and each rule on small invented candidates.
 * The pgTAP test `transfer_matching_test.sql` applies the same transfers.
 */

import { assertEquals } from "@std/assert";
import {
  type CandidateAccount,
  type CandidateMovement,
  type Candidates,
  candidatesSince,
  isPaypalCounterparty,
  matchTransfers,
  type TransferProposal,
  windowStart,
} from "./transfers.ts";
import {
  normalizeTransaction,
  type TransactionContext,
} from "../normalize/transaction.ts";
import type { HalTransactions } from "../eb/types.ts";
import { testdata } from "../testing/fake_fetch.ts";

const START_DATE = "2031-03-01";

const CACC: CandidateAccount = {
  id: "conto-credem",
  kind: "bank",
  connection_id: "connessione-credem",
  aspsp_name: "Credito Emiliano",
  cash_account_type: "CACC",
};
const CARD: CandidateAccount = {
  id: "carta-credem",
  kind: "card",
  connection_id: "connessione-credem",
  aspsp_name: "Credito Emiliano",
  cash_account_type: "CARD",
};
const HYPE: CandidateAccount = {
  id: "conto-hype",
  kind: "bank",
  connection_id: "connessione-hype",
  aspsp_name: "HYPE",
  cash_account_type: "CACC",
};
const PAYPAL: CandidateAccount = {
  id: "conto-paypal",
  kind: "paypal",
  connection_id: "connessione-paypal",
  aspsp_name: "PayPal",
  cash_account_type: "OTHR",
};

/** The pages of Anna imported on each account. */
const PAGES: [CandidateAccount, string[]][] = [
  [CACC, [
    "credem-cacc/transactions-page-1.json",
    "credem-cacc/transactions-page-2.json",
  ]],
  [CARD, ["credem-card/transactions-day-1.json"]],
  [HYPE, ["hype/transactions-sync-1.json"]],
  [PAYPAL, ["paypal/transactions-anna-sync-1.json"]],
];

/**
 * The movements of the pages, as `ingest_bank_rows` creates them (`BOOK`,
 * from the start date, not zero), all free; the id is the reference of
 * the bank, else the account and the position of the row.
 */
async function syntheticMovements(): Promise<CandidateMovement[]> {
  const movements: CandidateMovement[] = [];
  for (const [account, paths] of PAGES) {
    const context: TransactionContext = {
      aspspName: account.aspsp_name,
      cashAccountType: account.cash_account_type,
      accountKind: account.kind,
    };
    let position = 0;
    for (const path of paths) {
      const page = await testdata(path) as HalTransactions;
      for (const row of page.transactions) {
        position++;
        const { raw, movement } = await normalizeTransaction(row, context);
        if (
          raw.status !== "BOOK" || movement.movement_date < START_DATE ||
          movement.amount_cents === 0
        ) {
          continue;
        }
        movements.push({
          transaction_id: raw.entry_reference ?? `${account.id}-${position}`,
          account_id: account.id,
          amount_cents: movement.amount_cents,
          currency: raw.currency,
          movement_date: movement.movement_date,
          counterparty: movement.counterparty,
          description: movement.description,
          free: true,
          in_transfer: false,
          cancelled: false,
        });
      }
    }
  }
  return movements;
}

const SYNTHETIC = await syntheticMovements();

/** Anna's accounts and movements; without the accounts left out. */
function anna(without: CandidateAccount[] = []): Candidates {
  const ids = without.map((account) => account.id);
  return {
    accounts: [CACC, CARD, HYPE, PAYPAL].filter((a) => !ids.includes(a.id)),
    movements: SYNTHETIC.filter((m) => !ids.includes(m.account_id))
      .map((m) => ({ ...m })),
  };
}

const ref = (n: string) => `0000000000-2031${n}`;
const CHARGE_CARD = ref("0316-0000111-001");
const CARD_INFLOW = `${CARD.id}-7`;
const DEBIT_PAYPAL_1 = ref("0312-0000108-001");
const DEBIT_PAYPAL_2 = ref("0314-0000109-001");
const PAYMENT_FUNDED = "PP0000000000000007";
const PAYPAL_TO_BANK = "PP0000000000000006";
const BANK_FROM_PAYPAL = ref("0309-0000106-001");
const TOP_UP = ref("0315-0000110-001");
const HYPE_TOP_UP = "HY00000000000001";
const TIE_OUT = ref("0320-0000112-001");
const TIE_IN = ["HY00000000000002", "HY00000000000003"];

const transfer = (
  from: CandidateAccount,
  to: CandidateAccount,
  out: string,
  inflow: string | null = null,
  funded: string | null = null,
): TransferProposal => ({
  from_account_id: from.id,
  to_account_id: to.id,
  out_transaction_id: out,
  in_transaction_id: inflow,
  funded_transaction_id: funded,
});

/** Every movement a proposal touches or funds. */
function touched(proposals: TransferProposal[]): string[] {
  return proposals.flatMap((p) =>
    [p.out_transaction_id, p.in_transaction_id, p.funded_transaction_id]
      .filter((id): id is string => id !== null)
  );
}

Deno.test("synthetic data: the movements of the cases are there", () => {
  const ids = SYNTHETIC.map((m) => m.transaction_id);
  for (
    const id of [
      CHARGE_CARD,
      CARD_INFLOW,
      DEBIT_PAYPAL_1,
      DEBIT_PAYPAL_2,
      PAYMENT_FUNDED,
      PAYPAL_TO_BANK,
      BANK_FROM_PAYPAL,
      TOP_UP,
      HYPE_TOP_UP,
      TIE_OUT,
      ...TIE_IN,
    ]
  ) {
    assertEquals(ids.filter((found) => found === id).length, 1, id);
  }
  const inflow = SYNTHETIC.find((m) => m.transaction_id === CARD_INFLOW)!;
  assertEquals([inflow.amount_cents, inflow.movement_date], [
    12050,
    "2031-03-18",
  ]);
});

Deno.test("cases 6 to 9 and 19: the transfers of the synthetic data, card first, then PayPal, then between two accounts", () => {
  assertEquals(matchTransfers(anna(), START_DATE), [
    // 9: monthly charge of the card, with the inflow on the card 2 days after.
    transfer(CACC, CARD, CHARGE_CARD, CARD_INFLOW),
    // 7: direct debit to PayPal funding the payment of 2 days before; a
    // second one without a payment.
    transfer(CACC, PAYPAL, DEBIT_PAYPAL_1, null, PAYMENT_FUNDED),
    transfer(CACC, PAYPAL, DEBIT_PAYPAL_2),
    // 6: balance of PayPal to the bank: a transfer, never an income.
    transfer(PAYPAL, CACC, PAYPAL_TO_BANK, BANK_FROM_PAYPAL),
    // 8: top-up of the prepaid account, both sides.
    transfer(CACC, HYPE, TOP_UP, HYPE_TOP_UP),
  ]);
});

Deno.test("case 19: an outflow with two inflows on a par stays to classify, with both", () => {
  const ids = touched(matchTransfers(anna(), START_DATE));
  for (const id of [TIE_OUT, ...TIE_IN]) {
    assertEquals(ids.includes(id), false, id);
  }
  // With one of the two inflows already classified, the other is unique.
  const candidates = anna();
  candidates.movements.find((m) => m.transaction_id === TIE_IN[1])!.free =
    false;
  assertEquals(
    matchTransfers(candidates, START_DATE).at(-1),
    transfer(CACC, HYPE, TIE_OUT, TIE_IN[0]),
  );
});

Deno.test("case 7: without a PayPal account the debits to PayPal stay to classify", () => {
  const proposals = matchTransfers(anna([PAYPAL]), START_DATE);
  assertEquals(proposals, [
    transfer(CACC, CARD, CHARGE_CARD, CARD_INFLOW),
    transfer(CACC, HYPE, TOP_UP, HYPE_TOP_UP),
  ]);
  // Not even as a transfer between two accounts.
  const ids = touched(proposals);
  for (const id of [DEBIT_PAYPAL_1, DEBIT_PAYPAL_2, BANK_FROM_PAYPAL]) {
    assertEquals(ids.includes(id), false, id);
  }
});

Deno.test("idempotent: once applied, the same candidates give no transfer", () => {
  const candidates = anna();
  const first = matchTransfers(candidates, START_DATE);
  // What apply_transfers leaves: the sides in a transfer, the funded
  // payment too.
  for (const p of first) {
    for (const movement of candidates.movements) {
      if (
        movement.transaction_id === p.out_transaction_id ||
        movement.transaction_id === p.in_transaction_id
      ) {
        movement.free = false;
        movement.in_transfer = true;
      }
      if (movement.transaction_id === p.funded_transaction_id) {
        movement.in_transfer = true;
      }
    }
  }
  assertEquals(matchTransfers(candidates, START_DATE), []);
  assertEquals(matchTransfers(anna(), START_DATE), first);
});

Deno.test("case 18: the movements of a transfer undone are never matched again", () => {
  const candidates = anna();
  for (const movement of candidates.movements) {
    if ([TOP_UP, HYPE_TOP_UP].includes(movement.transaction_id)) {
      movement.cancelled = true;
    }
  }
  const proposals = matchTransfers(candidates, START_DATE);
  assertEquals(touched(proposals).includes(TOP_UP), false);
  assertEquals(touched(proposals).includes(HYPE_TOP_UP), false);
  assertEquals(proposals.length, 4);

  // A payment in a transfer undone is not funded again.
  const payment = anna();
  payment.movements.find((m) => m.transaction_id === PAYMENT_FUNDED)!
    .cancelled = true;
  assertEquals(
    matchTransfers(payment, START_DATE)[1],
    transfer(CACC, PAYPAL, DEBIT_PAYPAL_1),
  );
});

Deno.test("window: no movement before its first day; a payment of the 7 days before may be funded", () => {
  assertEquals(matchTransfers(anna(), "2031-03-11"), [
    transfer(CACC, CARD, CHARGE_CARD, CARD_INFLOW),
    // The payment of 2031-03-10 is before the window, still funded.
    transfer(CACC, PAYPAL, DEBIT_PAYPAL_1, null, PAYMENT_FUNDED),
    transfer(CACC, PAYPAL, DEBIT_PAYPAL_2),
    transfer(CACC, HYPE, TOP_UP, HYPE_TOP_UP),
  ]);
  assertEquals(windowStart("2031-04-15"), "2031-03-01");
  assertEquals(candidatesSince("2031-04-15"), "2031-02-22");
  assertEquals(candidatesSince("2032-03-01"), "2032-01-09");
});

// The rules one by one, on invented candidates.

const OTHER_BANK: CandidateAccount = {
  id: "conto-altra-banca",
  kind: "bank",
  connection_id: "connessione-altra-banca",
  aspsp_name: "Banca di Prova",
  cash_account_type: "CACC",
};
const OTHER_CARD: CandidateAccount = {
  id: "carta-altra-banca",
  kind: "card",
  connection_id: "connessione-altra-banca",
  aspsp_name: "Banca di Prova",
  cash_account_type: "CARD",
};

function movement(
  id: string,
  account: CandidateAccount,
  date: string,
  amount: number,
  fields: Partial<CandidateMovement> = {},
): CandidateMovement {
  return {
    transaction_id: id,
    account_id: account.id,
    amount_cents: amount,
    currency: "EUR",
    movement_date: date,
    counterparty: null,
    description: null,
    free: true,
    in_transfer: false,
    cancelled: false,
    ...fields,
  };
}

const match = (
  accounts: CandidateAccount[],
  movements: CandidateMovement[],
) => matchTransfers({ accounts, movements }, START_DATE);

const CHARGE = { description: "ADDEBITO MESE CARTA EGO" };
const TO_PAYPAL = { counterparty: "PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A." };

Deno.test("between two accounts: same amount and currency, opposite signs, at most 3 days, different accounts", () => {
  const accounts = [CACC, HYPE];
  assertEquals(
    match(accounts, [
      movement("u", CACC, "2031-03-10", -4000),
      movement("e", HYPE, "2031-03-13", 4000),
    ]),
    [transfer(CACC, HYPE, "u", "e")],
  );
  // The inflow may come first.
  assertEquals(
    match(accounts, [
      movement("u", CACC, "2031-03-10", -4000),
      movement("e", HYPE, "2031-03-07", 4000),
    ]),
    [transfer(CACC, HYPE, "u", "e")],
  );
  for (
    const other of [
      movement("e", HYPE, "2031-03-14", 4000),
      movement("e", HYPE, "2031-03-06", 4000),
      movement("e", HYPE, "2031-03-10", 4001),
      movement("e", HYPE, "2031-03-10", -4000),
      movement("e", HYPE, "2031-03-10", 4000, { currency: "USD" }),
      movement("e", CACC, "2031-03-10", 4000),
    ]
  ) {
    assertEquals(
      match(accounts, [movement("u", CACC, "2031-03-10", -4000), other]),
      [],
    );
  }
});

Deno.test("between two accounts: an inflow with two outflows on a par is not matched", () => {
  assertEquals(
    match([CACC, HYPE, OTHER_BANK], [
      movement("u1", CACC, "2031-03-10", -4000),
      movement("u2", OTHER_BANK, "2031-03-11", -4000),
      movement("e", HYPE, "2031-03-11", 4000),
    ]),
    [],
  );
});

Deno.test("between two accounts with PayPal: the other side has PayPal as counterparty; never two PayPal accounts", () => {
  assertEquals(
    match([CACC, PAYPAL], [
      movement("u", PAYPAL, "2031-03-08", -2500),
      movement("e", CACC, "2031-03-09", 2500, {
        counterparty: "PAYPAL EUROPE S.A R.L. ET CIE S.C.A.",
      }),
    ]),
    [transfer(PAYPAL, CACC, "u", "e")],
  );
  assertEquals(
    match([CACC, PAYPAL], [
      movement("u", PAYPAL, "2031-03-08", -2500),
      movement("e", CACC, "2031-03-09", 2500, { counterparty: "ANNA ESEMPIO" }),
    ]),
    [],
  );
  const second = { ...PAYPAL, id: "conto-paypal-2", connection_id: "c-2" };
  assertEquals(
    match([PAYPAL, second], [
      movement("u", PAYPAL, "2031-03-08", -2500, { counterparty: "PayPal" }),
      movement("e", second, "2031-03-08", 2500, { counterparty: "PayPal" }),
    ]),
    [],
  );
});

Deno.test("card charge: the inflow of the card at most 5 days away, before or after", () => {
  const charge = movement("a", CACC, "2031-03-16", -12050, CHARGE);
  for (const date of ["2031-03-11", "2031-03-21"]) {
    assertEquals(
      match([CACC, CARD], [charge, movement("c", CARD, date, 12050)]),
      [transfer(CACC, CARD, "a", "c")],
    );
  }
  // 6 days away: the transfer without the incoming side.
  assertEquals(
    match([CACC, CARD], [charge, movement("c", CARD, "2031-03-22", 12050)]),
    [transfer(CACC, CARD, "a")],
  );
  // Two possible inflows: the transfer without the incoming side.
  assertEquals(
    match([CACC, CARD], [
      charge,
      movement("c1", CARD, "2031-03-17", 12050),
      movement("c2", CARD, "2031-03-18", 12050),
    ]),
    [transfer(CACC, CARD, "a")],
  );
});

Deno.test("card charge: with two cards in the connection nothing, not even between two accounts", () => {
  const second = { ...CARD, id: "carta-credem-2" };
  assertEquals(
    match([CACC, CARD, second], [
      movement("a", CACC, "2031-03-16", -12050, CHARGE),
      movement("c", CARD, "2031-03-17", 12050),
    ]),
    [],
  );
});

Deno.test("card charge: a card of another connection, or another format, is not the card rule", () => {
  // The only card is of another bank: between two accounts, 3 days at most.
  const accounts = [CACC, OTHER_CARD];
  assertEquals(
    match(accounts, [
      movement("a", CACC, "2031-03-16", -12050, CHARGE),
      movement("c", OTHER_CARD, "2031-03-18", 12050),
    ]),
    [transfer(CACC, OTHER_CARD, "a", "c")],
  );
  assertEquals(
    match(accounts, [
      movement("a", CACC, "2031-03-16", -12050, CHARGE),
      movement("c", OTHER_CARD, "2031-03-20", 12050),
    ]),
    [],
  );
  // The same description on a bank without the format of section 8.
  assertEquals(
    match([OTHER_BANK, OTHER_CARD], [
      movement("a", OTHER_BANK, "2031-03-16", -12050, CHARGE),
      movement("c", OTHER_CARD, "2031-03-20", 12050),
    ]),
    [],
  );
});

Deno.test("to PayPal: the payment of the same amount from 7 days before to the day of the charge", () => {
  const debit = movement("a", CACC, "2031-03-12", -1500, TO_PAYPAL);
  for (const date of ["2031-03-05", "2031-03-12"]) {
    assertEquals(
      match([CACC, PAYPAL], [debit, movement("p", PAYPAL, date, -1500)]),
      [transfer(CACC, PAYPAL, "a", null, "p")],
    );
  }
  for (
    const payment of [
      movement("p", PAYPAL, "2031-03-04", -1500),
      movement("p", PAYPAL, "2031-03-13", -1500),
      movement("p", PAYPAL, "2031-03-10", -1501),
      movement("p", PAYPAL, "2031-03-10", 1500),
      movement("p", PAYPAL, "2031-03-10", -1500, { in_transfer: true }),
      movement("p", PAYPAL, "2031-03-10", -1500, { cancelled: true }),
    ]
  ) {
    assertEquals(match([CACC, PAYPAL], [debit, payment]), [
      transfer(CACC, PAYPAL, "a"),
    ]);
  }
  // A payment already classified is still funded: it is not touched.
  assertEquals(
    match([CACC, PAYPAL], [
      debit,
      movement("p", PAYPAL, "2031-03-10", -1500, { free: false }),
    ]),
    [transfer(CACC, PAYPAL, "a", null, "p")],
  );
});

Deno.test("to PayPal: payments or debits on a par leave the transfer without the funded payment", () => {
  assertEquals(
    match([CACC, PAYPAL], [
      movement("a", CACC, "2031-03-12", -1500, TO_PAYPAL),
      movement("p1", PAYPAL, "2031-03-09", -1500),
      movement("p2", PAYPAL, "2031-03-10", -1500),
    ]),
    [transfer(CACC, PAYPAL, "a")],
  );
  assertEquals(
    match([CACC, PAYPAL], [
      movement("a1", CACC, "2031-03-12", -1500, TO_PAYPAL),
      movement("a2", CACC, "2031-03-13", -1500, TO_PAYPAL),
      movement("p", PAYPAL, "2031-03-10", -1500),
    ]),
    [transfer(CACC, PAYPAL, "a1"), transfer(CACC, PAYPAL, "a2")],
  );
});

Deno.test("to PayPal: from a card too; never from the PayPal account; two PayPal accounts: nothing", () => {
  assertEquals(
    match([CARD, PAYPAL], [
      movement("a", CARD, "2031-03-12", -999, {
        counterparty: "PAYPAL *NEGOZIO",
      }),
    ]),
    [transfer(CARD, PAYPAL, "a")],
  );
  assertEquals(
    match([CACC, PAYPAL], [
      movement("r", PAYPAL, "2031-03-12", -3000, { counterparty: "PayPal" }),
    ]),
    [],
  );
  const second = { ...PAYPAL, id: "conto-paypal-2", connection_id: "c-2" };
  assertEquals(
    match([CACC, HYPE, PAYPAL, second], [
      movement("a", CACC, "2031-03-12", -1500, TO_PAYPAL),
      movement("e", HYPE, "2031-03-12", 1500),
    ]),
    [],
  );
});

Deno.test("only free movements in no transfer undone are touched", () => {
  for (
    const fields of [{ free: false }, { cancelled: true }] as Partial<
      CandidateMovement
    >[]
  ) {
    assertEquals(
      match([CACC, HYPE], [
        movement("u", CACC, "2031-03-10", -4000, fields),
        movement("e", HYPE, "2031-03-10", 4000),
      ]),
      [],
    );
    assertEquals(
      match([CACC, PAYPAL], [
        movement("a", CACC, "2031-03-12", -1500, { ...TO_PAYPAL, ...fields }),
      ]),
      [],
    );
  }
  // A movement of an account not among the candidates is left out.
  assertEquals(
    match([CACC], [
      movement("u", CACC, "2031-03-10", -4000),
      movement("e", HYPE, "2031-03-10", 4000),
    ]),
    [],
  );
});

Deno.test("PayPal as counterparty, in any case", () => {
  assertEquals(
    [
      "PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.",
      "PayPal",
      "PAYPAL *NEGOZIO",
    ].map(isPaypalCounterparty),
    [true, true, true],
  );
  assertEquals(
    [null, "ANNA ESEMPIO", "PAY PAL"].map(isPaypalCounterparty),
    [false, false, false],
  );
});
