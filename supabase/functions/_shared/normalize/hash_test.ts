import { assertEquals, assertMatch, assertNotEquals } from "@std/assert";
import { type DedupFields, dedupHash, dedupText } from "./hash.ts";
import { amountToCents } from "./amount.ts";

const BAR: DedupFields = {
  booking_date: "2031-03-04",
  value_date: "2031-03-02",
  transaction_date: null,
  status: "BOOK",
  sign: "D",
  unsigned_amount_cents: 1250,
  description: "BANCOMAT 02/03/31,ORE 12:34,TESS.00000000 BAR ESEMPIO",
};

Deno.test("hash text: dates, status, sign, cents and description in order", () => {
  assertEquals(
    dedupText(BAR),
    "2031-03-04|2031-03-02||BOOK|D|1250|BANCOMAT 02/03/31,ORE 12:34,TESS.00000000 BAR ESEMPIO",
  );
  assertEquals(
    dedupText({
      booking_date: null,
      value_date: null,
      transaction_date: "2031-03-07",
      status: "PDNG",
      sign: "C",
      unsigned_amount_cents: 0,
      description: null,
    }),
    "||2031-03-07|PDNG|C|0|",
  );
});

Deno.test("hash: SHA-256 in lower-case hexadecimal, values written by hand", async () => {
  // Computed outside the code: printf '%s' '<text>' | sha256sum
  assertEquals(
    await dedupHash(BAR),
    "7922bc101d6c8b9fe869ab7cc5678854626c546fee4b24937e004905fc1f7507",
  );
  assertEquals(
    await dedupHash({
      booking_date: null,
      value_date: null,
      transaction_date: "2031-03-07",
      status: "BOOK",
      sign: "D",
      unsigned_amount_cents: 120,
      description: "CAFFE PROVA CITTAPROVA IT",
    }),
    "41a6e172d6bac4ce7559aecbceaf04310b3f5cf1812412efd0c9f5c677df645c",
  );
  assertEquals(
    await dedupHash({
      booking_date: null,
      value_date: null,
      transaction_date: "2031-03-07",
      status: "PDNG",
      sign: "C",
      unsigned_amount_cents: 0,
      description: null,
    }),
    "e46e065f444f6c94b4f9a1bf434603833857d806d66c097d07bed3fdb062bb0c",
  );
  assertMatch(await dedupHash(BAR), /^[0-9a-f]{64}$/);
});

Deno.test("hash: a different status is a different hash (PDNG then BOOK)", async () => {
  assertNotEquals(
    await dedupHash({ ...BAR, status: "PDNG" }),
    await dedupHash(BAR),
  );
});

Deno.test("hash: every field counts", async () => {
  const base = await dedupHash(BAR);
  const changes: Partial<DedupFields>[] = [
    { booking_date: "2031-03-05" },
    { value_date: null },
    { transaction_date: "2031-03-02" },
    { sign: "C" },
    { unsigned_amount_cents: 1251 },
    { description: "BAR ESEMPIO" },
    { description: null },
  ];
  for (const change of changes) {
    assertNotEquals(
      await dedupHash({ ...BAR, ...change }),
      base,
      JSON.stringify(change),
    );
  }
});

Deno.test("hash: 4.4 and 4.40 give the same hash", async () => {
  const a = amountToCents("4.4", "DBIT").cents;
  const b = amountToCents("4.40", "DBIT").cents;
  assertEquals(
    await dedupHash({ ...BAR, unsigned_amount_cents: Math.abs(a) }),
    await dedupHash({ ...BAR, unsigned_amount_cents: Math.abs(b) }),
  );
});

Deno.test("hash: a missing date and an empty description are empty fields", async () => {
  assertEquals(
    await dedupHash({ ...BAR, description: null }),
    await dedupHash({ ...BAR, description: "" }),
  );
});
