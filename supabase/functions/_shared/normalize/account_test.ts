import { assertEquals } from "@std/assert";
import {
  accountIdentifier,
  accountKind,
  defaultDisplayName,
  emailOf,
  linkedAccount,
} from "./account.ts";
import type { AccountResource } from "../eb/types.ts";
import { testdata } from "../testing/fake_fetch.ts";

const bankCard = await testdata("session-bank-card.json") as {
  accounts: AccountResource[];
};
const paypal = await testdata("session-paypal.json") as {
  accounts: AccountResource[];
};

Deno.test("kind: PayPal by bank name, card by CARD, else bank", () => {
  assertEquals(accountKind("PayPal", "OTHR"), "paypal");
  assertEquals(accountKind(" paypal ", "CARD"), "paypal");
  assertEquals(accountKind("Banca di Prova", "CARD"), "card");
  assertEquals(accountKind("Banca di Prova", "CACC"), "bank");
  assertEquals(accountKind("Banca di Prova", undefined), "bank");
});

Deno.test("identifier: IBAN without spaces, else the other identification", () => {
  const [bank, card, savings] = bankCard.accounts;
  assertEquals(accountIdentifier(bank!), "IT60X0542811101000000123456");
  assertEquals(accountIdentifier(card!), "000000******0000");
  assertEquals(accountIdentifier(savings!), "IT00A0000000000000000000003");
  assertEquals(
    accountIdentifier({ cash_account_type: "CACC" } as AccountResource),
    null,
  );
  assertEquals(
    accountIdentifier(
      {
        account_id: { iban: " " },
        cash_account_type: "CACC",
      } as AccountResource,
    ),
    null,
  );
});

Deno.test("default names never use the name sent by the bank", () => {
  assertEquals(
    defaultDisplayName(
      "bank",
      "Banca di Prova",
      undefined,
      "IT60X0542811101000000123456",
    ),
    "Banca di Prova …3456",
  );
  assertEquals(
    defaultDisplayName("bank", "Banca di Prova ", undefined, null),
    "Banca di Prova",
  );
  assertEquals(
    defaultDisplayName("card", "Banca di Prova", "Carta Oro", "0000******1234"),
    "Carta Oro …1234",
  );
  assertEquals(
    defaultDisplayName("card", "Banca di Prova", " ", "0000******1234"),
    "Carta …1234",
  );
  assertEquals(
    defaultDisplayName("card", "Banca di Prova", undefined, null),
    "Carta",
  );
  assertEquals(
    defaultDisplayName("paypal", "PayPal", undefined, "anna@example.com"),
    "anna@example.com",
  );
  assertEquals(
    defaultDisplayName("paypal", "PayPal", undefined, null),
    "PayPal",
  );
});

Deno.test("email: only a value with the shape of an email", () => {
  assertEquals(emailOf(" anna@example.com "), "anna@example.com");
  assertEquals(emailOf("anna@example"), null);
  assertEquals(emailOf("IT60X0542811101000000123456"), null);
  assertEquals(emailOf(null), null);
});

Deno.test("linked accounts of a session: bank, card, no uid", () => {
  const [bank, card, savings] = bankCard.accounts;
  assertEquals(linkedAccount("Banca di Prova", bank!), {
    uid: "00000000-0000-4000-8000-0000000000a1",
    kind: "bank",
    cash_account_type: "CACC",
    currency: "EUR",
    identifier: "IT60X0542811101000000123456",
    display_name: "Banca di Prova …3456",
    paypal_email: null,
  });
  assertEquals(linkedAccount("Banca di Prova", card!), {
    uid: "00000000-0000-4000-8000-0000000000a2",
    kind: "card",
    cash_account_type: "CARD",
    currency: "EUR",
    identifier: "000000******0000",
    display_name: "Carta di Prova Oro …0000",
    paypal_email: null,
  });
  assertEquals(linkedAccount("Banca di Prova", savings!), null);
});

Deno.test("linked account of PayPal: email of the account, several currencies", () => {
  assertEquals(linkedAccount("PayPal", paypal.accounts[0]!), {
    uid: "00000000-0000-4000-8000-0000000000a4",
    kind: "paypal",
    cash_account_type: "OTHR",
    currency: "XXX",
    identifier: "anna.paypal@example.com",
    display_name: "anna.paypal@example.com",
    paypal_email: "anna.paypal@example.com",
  });
});
