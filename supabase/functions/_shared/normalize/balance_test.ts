import { assertEquals, assertFalse, assertThrows } from "@std/assert";
import { balanceCents, InvalidBalanceError, linkBalances } from "./balance.ts";
import type { HalBalances } from "../eb/types.ts";
import { testdata } from "../testing/fake_fetch.ts";

Deno.test("balance amounts: sign, variable decimals, integer cents", () => {
  assertEquals(balanceCents("1234.56"), 123456);
  assertEquals(balanceCents("-50.00"), -5000);
  assertEquals(balanceCents("+4.4"), 440);
  assertEquals(balanceCents("1"), 100);
  assertEquals(balanceCents("-0.00"), 0);
  for (const wrong of ["", "-", "1,50", "--1", "1e3", " 1", undefined, 12]) {
    const error = assertThrows(
      () => balanceCents(wrong),
      InvalidBalanceError,
    );
    assertFalse(error.message.includes(String(wrong)) && wrong !== "");
  }
});

Deno.test("balances of a card: debt negative, available positive", async () => {
  const response = await testdata("balances-card.json") as HalBalances;
  assertEquals(linkBalances(response), [
    {
      currency: "EUR",
      balance_type: "CLBD",
      amount_cents: -5000,
      reference_date: "2031-03-04",
    },
    {
      currency: "EUR",
      balance_type: "OTHR",
      amount_cents: 145000,
      reference_date: null,
    },
  ]);
});

Deno.test("balances of PayPal: one for each currency, dates cut to the day", async () => {
  const response = await testdata("balances-paypal.json") as HalBalances;
  assertEquals(linkBalances(response), [
    {
      currency: "EUR",
      balance_type: "XPCD",
      amount_cents: 2500,
      reference_date: "2031-03-04",
    },
    {
      currency: "USD",
      balance_type: "XPCD",
      amount_cents: 1050,
      reference_date: "2031-03-04",
    },
  ]);
});

Deno.test("a balance that cannot be read fails the whole account", () => {
  const good = {
    name: "Saldo",
    balance_amount: { currency: "EUR", amount: "1.00" },
    balance_type: "CLBD",
  };
  for (
    const wrong of [
      { ...good, balance_amount: { currency: "eur", amount: "1.00" } },
      { ...good, balance_amount: { currency: "EUR", amount: "uno" } },
      { ...good, balance_type: " " },
      { ...good, balance_amount: null },
    ]
  ) {
    assertThrows(
      () => linkBalances({ balances: [good, wrong] } as unknown as HalBalances),
      InvalidBalanceError,
    );
  }
});
