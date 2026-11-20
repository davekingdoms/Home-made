/**
 * PayPal settlements (sincronizzazione.md, 7.2 and 12): case 5 on the
 * synthetic data of `_shared/testdata/eb/paypal/`, normalized as eb-sync
 * imports them, from both sides and in both orders, and each rule on small
 * invented candidates. The pgTAP test `settlement_matching_test.sql`
 * applies the same proposals.
 */

import { assertEquals } from "@std/assert";
import {
  type CandidateSettlement,
  matchSettlements,
  type SettlementCandidates,
  type SettlementMovement,
  type SettlementProposal,
} from "./settlements.ts";
import { windowStart } from "./transfers.ts";
import { normalizeTransaction } from "../normalize/transaction.ts";
import type { HalTransactions } from "../eb/types.ts";
import { testdata } from "../testing/fake_fetch.ts";

const START_DATE = "2031-03-01";
const ANNA = "membro-anna";
const BRUNO = "membro-bruno";
const CARLA = "membro-carla";

/** The PayPal emails of the household: what SQL compares, never sent. */
const EMAILS: Record<string, string> = {
  "anna.paypal@example.com": ANNA,
  "bruno.paypal@example.com": BRUNO,
};

/**
 * The movements of a page of PayPal, as `ingest_bank_rows` creates them
 * (`BOOK`, from the start date, not zero) and `settlement_candidates`
 * returns them for `member`: the id is the reference of the bank, the
 * counterpart is the other member of the household with that email.
 */
async function paypalMovements(
  member: string,
  path: string,
): Promise<SettlementMovement[]> {
  const page = await testdata(path) as HalTransactions;
  const movements: SettlementMovement[] = [];
  for (const row of page.transactions) {
    const { raw, movement } = await normalizeTransaction(row, {
      aspspName: "PayPal",
      cashAccountType: "OTHR",
      accountKind: "paypal",
    });
    if (
      raw.status !== "BOOK" || movement.movement_date < START_DATE ||
      movement.amount_cents === 0
    ) {
      continue;
    }
    const counterpart = movement.counterparty_email === null
      ? undefined
      : EMAILS[movement.counterparty_email];
    movements.push({
      transaction_id: raw.entry_reference!,
      account_id: `paypal-${member}`,
      amount_cents: movement.amount_cents,
      currency: raw.currency,
      movement_date: movement.movement_date,
      entry_reference: raw.entry_reference,
      counterpart_member_id: counterpart === undefined || counterpart === member
        ? null
        : counterpart,
      free: true,
      cancelled: false,
    });
  }
  return movements;
}

const ANNA_SYNC = await paypalMovements(
  ANNA,
  "paypal/transactions-anna-sync-1.json",
);
const BRUNO_SYNC = await paypalMovements(
  BRUNO,
  "paypal/transactions-bruno.json",
);
const ANNA_PAYS = "PP0000000000000005";
const BRUNO_RECEIVES = "PP0000000000000101";

/** A sync made in the window of all the synthetic data. */
const TODAY = "2031-03-20";
const SINCE = windowStart(TODAY);

/**
 * A small database of settlements: applies the proposals as
 * `apply_settlements` does (links first, a creation only without a
 * settlement that would take the movement) and returns the movements as
 * the next `settlement_candidates` sees them.
 */
class Household {
  settlements: CandidateSettlement[] = [];
  readonly movements: Record<string, SettlementMovement[]>;
  private next = 1;

  constructor(movements: Record<string, SettlementMovement[]>) {
    this.movements = Object.fromEntries(
      Object.entries(movements).map(([member, list]) => [
        member,
        list.map((m) => ({ ...m })),
      ]),
    );
  }

  candidates(member: string): SettlementCandidates {
    return {
      movements: this.movements[member]!.map((m) => ({ ...m })),
      settlements: this.settlements
        .filter((s) => [s.payer_member_id, s.payee_member_id].includes(member))
        .map((s) => ({ ...s })),
    };
  }

  /** Matches and applies for the member; returns the sides linked. */
  sync(member: string): number {
    const proposals = matchSettlements(member, this.candidates(member), SINCE);
    let linked = 0;
    for (const proposal of proposals) {
      const movement = this.movements[member]!.find((m) =>
        m.transaction_id === proposal.transaction_id
      )!;
      const paid = movement.amount_cents < 0;
      if (proposal.settlement_id === null) {
        const id = `conguaglio-${this.next++}`;
        this.settlements.push({
          id,
          payer_member_id: paid ? member : proposal.counterpart_member_id,
          payee_member_id: paid ? proposal.counterpart_member_id : member,
          amount_cents: Math.abs(movement.amount_cents),
          currency: movement.currency,
          settled_on: movement.movement_date,
          payer_transaction_id: paid ? movement.transaction_id : null,
          payee_transaction_id: paid ? null : movement.transaction_id,
          payer_entry_reference: paid ? movement.entry_reference : null,
          payee_entry_reference: paid ? null : movement.entry_reference,
        });
      } else {
        const settlement = this.settlements.find((s) =>
          s.id === proposal.settlement_id
        )!;
        if (paid) {
          settlement.payer_transaction_id = movement.transaction_id;
          settlement.payer_entry_reference = movement.entry_reference;
        } else {
          settlement.payee_transaction_id = movement.transaction_id;
          settlement.payee_entry_reference = movement.entry_reference;
        }
      }
      movement.free = false;
      linked++;
    }
    return linked;
  }
}

Deno.test("case 5: Anna first creates the settlement, Bruno the day after links to it", () => {
  const household = new Household({ [ANNA]: ANNA_SYNC, [BRUNO]: BRUNO_SYNC });
  assertEquals(
    matchSettlements(ANNA, household.candidates(ANNA), SINCE),
    [{
      transaction_id: ANNA_PAYS,
      counterpart_member_id: BRUNO,
      settlement_id: null,
    }],
  );
  assertEquals(household.sync(ANNA), 1);
  assertEquals(
    matchSettlements(BRUNO, household.candidates(BRUNO), SINCE),
    [{
      transaction_id: BRUNO_RECEIVES,
      counterpart_member_id: ANNA,
      settlement_id: "conguaglio-1",
    }],
  );
  assertEquals(household.sync(BRUNO), 1);
  assertEquals(household.settlements, [{
    id: "conguaglio-1",
    payer_member_id: ANNA,
    payee_member_id: BRUNO,
    amount_cents: 2000,
    currency: "EUR",
    settled_on: "2031-03-06",
    payer_transaction_id: ANNA_PAYS,
    payee_transaction_id: BRUNO_RECEIVES,
    payer_entry_reference: ANNA_PAYS,
    payee_entry_reference: BRUNO_RECEIVES,
  }]);

  // Again, from both sides: nothing more.
  assertEquals(household.sync(ANNA), 0);
  assertEquals(household.sync(BRUNO), 0);
  assertEquals(household.settlements.length, 1);
});

Deno.test("case 5 in the other order: Bruno creates it on his date, Anna links to it", () => {
  const household = new Household({ [ANNA]: ANNA_SYNC, [BRUNO]: BRUNO_SYNC });
  assertEquals(household.sync(BRUNO), 1);
  assertEquals(household.sync(ANNA), 1);
  assertEquals(household.sync(BRUNO), 0);
  assertEquals(
    household.settlements.map((s) => [
      s.payer_member_id,
      s.payee_member_id,
      s.amount_cents,
      s.settled_on,
      s.payer_transaction_id,
      s.payee_transaction_id,
    ]),
    [[ANNA, BRUNO, 2000, "2031-03-07", ANNA_PAYS, BRUNO_RECEIVES]],
  );
});

Deno.test("case 5: only the payment to Bruno; the other emails of the page are of no member", () => {
  const counterparts = ANNA_SYNC.filter((m) => m.counterpart_member_id);
  assertEquals(counterparts.map((m) => m.transaction_id), [ANNA_PAYS]);
  assertEquals(
    BRUNO_SYNC.filter((m) => m.counterpart_member_id).map((m) =>
      m.transaction_id
    ),
    [BRUNO_RECEIVES],
  );
});

// Small invented candidates.

const movement = (
  id: string,
  amount: number,
  day: string,
  counterpart: string | null = BRUNO,
  extra: Partial<SettlementMovement> = {},
): SettlementMovement => ({
  transaction_id: id,
  account_id: "paypal-anna",
  amount_cents: amount,
  currency: "EUR",
  movement_date: day,
  entry_reference: `PP-${id}`,
  counterpart_member_id: counterpart,
  free: true,
  cancelled: false,
  ...extra,
});

const settlement = (
  id: string,
  payer: string,
  payee: string,
  amount: number,
  day: string,
  extra: Partial<CandidateSettlement> = {},
): CandidateSettlement => ({
  id,
  payer_member_id: payer,
  payee_member_id: payee,
  amount_cents: amount,
  currency: "EUR",
  settled_on: day,
  payer_transaction_id: null,
  payee_transaction_id: null,
  payer_entry_reference: null,
  payee_entry_reference: null,
  ...extra,
});

const match = (
  movements: SettlementMovement[],
  settlements: CandidateSettlement[] = [],
) => matchSettlements(ANNA, { movements, settlements }, SINCE);

const create = (id: string, counterpart = BRUNO): SettlementProposal => ({
  transaction_id: id,
  counterpart_member_id: counterpart,
  settlement_id: null,
});
const link = (
  id: string,
  settlementId: string,
  counterpart = BRUNO,
): SettlementProposal => ({
  transaction_id: id,
  counterpart_member_id: counterpart,
  settlement_id: settlementId,
});

Deno.test("an outflow is paid by Anna, an inflow received by her", () => {
  const settlements = [
    settlement("s-paga", ANNA, BRUNO, 1500, "2031-03-10"),
    settlement("s-riceve", BRUNO, ANNA, 1500, "2031-03-10"),
  ];
  assertEquals(match([movement("t1", -1500, "2031-03-10")], settlements), [
    link("t1", "s-paga"),
  ]);
  assertEquals(match([movement("t2", 1500, "2031-03-10")], settlements), [
    link("t2", "s-riceve"),
  ]);
});

Deno.test("a manual settlement takes the movement, like any origin", () => {
  // "Segna come pagato": no side, created by Anna (origin is not read).
  assertEquals(
    match([movement("t1", -2000, "2031-03-08")], [
      settlement("s-manuale", ANNA, BRUNO, 2000, "2031-03-06"),
    ]),
    [link("t1", "s-manuale")],
  );
});

Deno.test("a settlement takes the movement only with pair, amount, currency, 3 days and its side empty", () => {
  const t = movement("t1", -2000, "2031-03-10");
  const others = [
    settlement("s-importo", ANNA, BRUNO, 2001, "2031-03-10"),
    settlement("s-valuta", ANNA, BRUNO, 2000, "2031-03-10", {
      currency: "USD",
    }),
    settlement("s-4-giorni", ANNA, BRUNO, 2000, "2031-03-14"),
    settlement("s-4-giorni-prima", ANNA, BRUNO, 2000, "2031-03-06"),
    settlement("s-verso", BRUNO, ANNA, 2000, "2031-03-10"),
    settlement("s-carla", ANNA, CARLA, 2000, "2031-03-10"),
    settlement("s-lato-pieno", ANNA, BRUNO, 2000, "2031-03-10", {
      payer_transaction_id: "altro",
    }),
  ];
  // None takes it: a new settlement.
  assertEquals(match([t], others), [create("t1")]);
  // 3 days before and after are still in.
  assertEquals(
    match([t], [settlement("s-3-giorni", ANNA, BRUNO, 2000, "2031-03-13")]),
    [link("t1", "s-3-giorni")],
  );
  assertEquals(
    match([t], [settlement("s-3-prima", ANNA, BRUNO, 2000, "2031-03-07")]),
    [link("t1", "s-3-prima")],
  );
  // The side of Bruno already linked: Anna's side is still empty.
  assertEquals(
    match([t], [
      settlement("s-bruno", ANNA, BRUNO, 2000, "2031-03-11", {
        payee_transaction_id: "lato-bruno",
        payee_entry_reference: "PP-diverso",
      }),
    ]),
    [link("t1", "s-bruno")],
  );
});

Deno.test("nothing for other currencies, no member, Anna herself, not free, cancelled, before the window", () => {
  assertEquals(
    match([
      movement("usd", -2000, "2031-03-10", BRUNO, { currency: "USD" }),
      movement("nessuno", -2000, "2031-03-10", null),
      movement("se-stessa", -2000, "2031-03-10", ANNA),
      movement("classificato", -2000, "2031-03-10", BRUNO, { free: false }),
      movement("annullato", -2000, "2031-03-10", BRUNO, { cancelled: true }),
      movement("vecchio", -2000, "2031-02-01"),
    ]),
    [],
  );
  assertEquals(SINCE, "2031-02-03");
});

Deno.test("three members: Anna pays Bruno and Carla the same day and amount, two settlements", () => {
  assertEquals(
    match([
      movement("a-bruno", -1000, "2031-03-10", BRUNO),
      movement("a-carla", -1000, "2031-03-10", CARLA),
    ]),
    [create("a-bruno", BRUNO), create("a-carla", CARLA)],
  );
  // With the settlement of Bruno already there, each goes to its own.
  assertEquals(
    match([
      movement("a-bruno", -1000, "2031-03-10", BRUNO),
      movement("a-carla", -1000, "2031-03-10", CARLA),
    ], [settlement("s-bruno", ANNA, BRUNO, 1000, "2031-03-10")]),
    [link("a-bruno", "s-bruno", BRUNO), create("a-carla", CARLA)],
  );
});

Deno.test("two equal payments to Bruno without a settlement: not on a par, two settlements", () => {
  assertEquals(
    match([
      movement("t2", -1000, "2031-03-10"),
      movement("t1", -1000, "2031-03-10"),
    ]),
    [create("t1"), create("t2")],
  );
});

Deno.test("on a par: nothing, and no new settlement either", () => {
  // Two movements for one settlement.
  assertEquals(
    match([
      movement("t1", -1000, "2031-03-10"),
      movement("t2", -1000, "2031-03-11"),
    ], [settlement("s1", ANNA, BRUNO, 1000, "2031-03-10")]),
    [],
  );
  // One movement for two settlements.
  assertEquals(
    match([movement("t1", -1000, "2031-03-10")], [
      settlement("s1", ANNA, BRUNO, 1000, "2031-03-09"),
      settlement("s2", ANNA, BRUNO, 1000, "2031-03-11"),
    ]),
    [],
  );
  // A tie next to a movement that has its own settlement.
  assertEquals(
    match([
      movement("t1", -1000, "2031-03-10"),
      movement("t2", -1000, "2031-03-11"),
      movement("t3", -3000, "2031-03-12"),
    ], [
      settlement("s1", ANNA, BRUNO, 1000, "2031-03-10"),
      settlement("s3", ANNA, BRUNO, 3000, "2031-03-12"),
    ]),
    [link("t3", "s3")],
  );
});

Deno.test("the same PayPal ID on both sides goes first and settles the tie", () => {
  // Two settlements for one movement: the one whose side of Bruno has the
  // same ID.
  assertEquals(
    match([movement("t1", -1000, "2031-03-10")], [
      settlement("s1", ANNA, BRUNO, 1000, "2031-03-09", {
        payee_transaction_id: "b1",
        payee_entry_reference: "PP-altro",
      }),
      settlement("s2", ANNA, BRUNO, 1000, "2031-03-11", {
        payee_transaction_id: "b2",
        payee_entry_reference: "PP-t1",
      }),
    ]),
    [link("t1", "s2")],
  );
  // Two movements for one settlement: the one with the same ID links, the
  // other one has no settlement left and creates its own.
  assertEquals(
    match([
      movement("t1", -1000, "2031-03-10"),
      movement("t2", -1000, "2031-03-10"),
    ], [
      settlement("s1", ANNA, BRUNO, 1000, "2031-03-10", {
        payee_transaction_id: "b2",
        payee_entry_reference: "PP-t2",
      }),
    ]),
    [link("t2", "s1"), create("t1")],
  );
  // The same ID on the side of Anna (an inflow) reads the side of Bruno as
  // payer.
  assertEquals(
    match([movement("t1", 1000, "2031-03-10")], [
      settlement("s1", BRUNO, ANNA, 1000, "2031-03-10", {
        payer_transaction_id: "b1",
        payer_entry_reference: "PP-x",
      }),
      settlement("s2", BRUNO, ANNA, 1000, "2031-03-10", {
        payer_transaction_id: "b2",
        payer_entry_reference: "PP-t1",
      }),
    ]),
    [link("t1", "s2")],
  );
  // The ID alone is not enough: amount and date still have to hold.
  assertEquals(
    match([movement("t1", -1000, "2031-03-10")], [
      settlement("s1", ANNA, BRUNO, 1200, "2031-03-10", {
        payee_transaction_id: "b1",
        payee_entry_reference: "PP-t1",
      }),
    ]),
    [create("t1")],
  );
});

Deno.test("the links come before the creations; the same candidates give the same proposals", () => {
  const movements = [
    movement("t1", -500, "2031-03-09"),
    movement("t2", -700, "2031-03-10"),
  ];
  const settlements = [settlement("s2", ANNA, BRUNO, 700, "2031-03-10")];
  const expected = [link("t2", "s2"), create("t1")];
  assertEquals(match(movements, settlements), expected);
  assertEquals(
    match([...movements].reverse(), [...settlements].reverse()),
    expected,
  );
});
