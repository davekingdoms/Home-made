import { assertEquals, assertThrows } from "@std/assert";
import { amountToCents, InvalidAmountError } from "./amount.ts";
import type { CreditDebitIndicator } from "../eb/types.ts";

const CASES: [string, CreditDebitIndicator, number, boolean][] = [
  // Variable decimals (sincronizzazione.md, 6.3 and 12, case 11).
  ["4.4", "CRDT", 440, false],
  ["1", "CRDT", 100, false],
  ["12.50", "CRDT", 1250, false],
  ["12.5", "DBIT", -1250, false],
  ["0.01", "DBIT", -1, false],
  ["1234567.89", "CRDT", 123456789, false],
  ["007.10", "CRDT", 710, false],
  // Sign from credit_debit_indicator.
  ["4.4", "DBIT", -440, false],
  ["0", "DBIT", 0, false],
  ["0.00", "CRDT", 0, false],
  // More than two decimals: half up to the cent, with the signal.
  ["0.005", "CRDT", 1, true],
  ["0.005", "DBIT", -1, true],
  ["0.004", "CRDT", 0, true],
  ["0.0049999", "DBIT", 0, true],
  ["12.345", "CRDT", 1235, true],
  ["12.3449", "CRDT", 1234, true],
  ["9.995", "CRDT", 1000, true],
  ["99.999", "DBIT", -10000, true],
  // Extra zeros lose nothing: no signal.
  ["12.500", "CRDT", 1250, false],
  ["1.0000", "DBIT", -100, false],
];

Deno.test("amountToCents: text to signed integer cents", () => {
  for (const [amount, indicator, cents, rounded] of CASES) {
    assertEquals(
      amountToCents(amount, indicator),
      { cents, rounded },
      `${amount} ${indicator}`,
    );
  }
});

Deno.test("amountToCents: zero is never negative zero", () => {
  assertEquals(Object.is(amountToCents("0.00", "DBIT").cents, 0), true);
});

Deno.test("amountToCents: invalid text is an error without the value", () => {
  const invalid = [
    "",
    " 1.00",
    "1.00 ",
    "-1.00",
    "+1.00",
    "1,50",
    "1.",
    ".5",
    "1.2.3",
    "1e3",
    "NaN",
    "Infinity",
    "0x10",
    "١٢",
    "1234567890123456",
  ];
  for (const amount of invalid) {
    const error = assertThrows(
      () => amountToCents(amount, "DBIT"),
      InvalidAmountError,
      undefined,
      JSON.stringify(amount),
    );
    assertEquals(error.message, "invalid amount");
  }
  assertThrows(
    () => amountToCents(12.5 as unknown as string, "DBIT"),
    InvalidAmountError,
  );
});

Deno.test("amountToCents: unknown indicator is an error", () => {
  for (const indicator of ["", "DEBIT", "crdt", "OTHR"]) {
    assertThrows(
      () => amountToCents("1.00", indicator as CreditDebitIndicator),
      InvalidAmountError,
    );
  }
});

Deno.test("amountToCents: largest safe amount", () => {
  assertEquals(amountToCents("90071992547409.91", "DBIT"), {
    cents: -9007199254740991,
    rounded: false,
  });
  assertThrows(
    () => amountToCents("90071992547409.92", "CRDT"),
    InvalidAmountError,
  );
});
