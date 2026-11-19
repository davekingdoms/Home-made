import { assertEquals } from "@std/assert";
import {
  bankFormat,
  counterparty,
  counterpartyEmail,
  type CounterpartySource,
  isCardMonthlyCharge,
} from "./counterparty.ts";
import type { CreditDebitIndicator } from "../eb/types.ts";

function source(
  description: string | null,
  indicator: CreditDebitIndicator = "DBIT",
  extra: Partial<CounterpartySource> = {},
): CounterpartySource {
  return { indicator, description, code: null, ...extra };
}

Deno.test("format: from the bank name and the account type", () => {
  const cases: [
    string,
    string | null,
    "bank" | "card" | "paypal",
    string | null,
  ][] = [
    ["Credito Emiliano", "CACC", "bank", "credem-cacc"],
    ["Credem", "CACC", "bank", "credem-cacc"],
    ["CREDITO EMILIANO", "CARD", "card", "credem-card"],
    ["Credito Emiliano", "SVGS", "bank", null],
    ["HYPE", "CACC", "bank", "hype"],
    ["Hype", null, "bank", "hype"],
    ["PayPal", "OTHR", "paypal", "paypal"],
    ["Banca di Prova", "CACC", "bank", null],
    ["Mock ASPSP", "CARD", "card", null],
  ];
  for (const [aspspName, cashAccountType, accountKind, format] of cases) {
    assertEquals(
      bankFormat({ aspspName, cashAccountType, accountKind }),
      format,
      `${aspspName} ${cashAccountType}`,
    );
  }
});

// Section 8: every example, with its counterparty.
const CREDEM_CACC: [string, CreditDebitIndicator, string | null][] = [
  [
    "BANCOMAT 03/02/31,ORE 12:34,TESS.00000000 BAR ESEMPIO",
    "DBIT",
    "BAR ESEMPIO",
  ],
  [
    "SEPA DD CORE DA ESEMPIO ENERGIA SPA MANDATO XX000000",
    "DBIT",
    "ESEMPIO ENERGIA SPA",
  ],
  [
    "SEPA DD CORE DA PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A. MANDATO XX000001",
    "DBIT",
    "PAYPAL (EUROPE) S.A R.L. ET CIE S.C.A.",
  ],
  [
    "EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO",
    "CRDT",
    "DITTA ESEMPIO SRL",
  ],
  ["PAGAMENTO CBILL ESEMPIO SERVIZI", "DBIT", "ESEMPIO SERVIZI"],
  ["COMM. PAG. CBILL", "DBIT", null],
  [
    "BON. ISTANTANEO A DEBITO ANNA ESEMPIO IT00A0000000000000000005678 RICARICA",
    "DBIT",
    "ANNA ESEMPIO",
  ],
  ["ADDEBITO MESE CARTA EGO", "DBIT", null],
];

Deno.test("Credito Emiliano, current account: counterparty from the description", () => {
  for (const [description, indicator, expected] of CREDEM_CACC) {
    assertEquals(
      counterparty(source(description, indicator), "credem-cacc"),
      expected,
      description,
    );
  }
});

Deno.test("Credito Emiliano, current account: variants of the rules", () => {
  const cases: [string, string | null][] = [
    // Without the mandate, the whole name.
    ["SEPA DD CORE DA ESEMPIO ENERGIA SPA", "ESEMPIO ENERGIA SPA"],
    // Without the reason, the whole name.
    ["EMOLUMENTI DITTA ESEMPIO SRL", "DITTA ESEMPIO SRL"],
    // No word with digits: everything after "A DEBITO".
    ["BON. ISTANTANEO A DEBITO BRUNO ESEMPIO", "BRUNO ESEMPIO"],
    // A word with digits right away: no name.
    ["BON. ISTANTANEO A DEBITO IT00A0000000000000000005678 RICARICA", null],
    // Not a known description.
    ["BONIFICO A VOSTRO FAVORE", null],
    ["COMMISSIONI TENUTA CONTO", null],
  ];
  for (const [description, expected] of cases) {
    assertEquals(
      counterparty(source(description), "credem-cacc"),
      expected,
      description,
    );
  }
});

Deno.test("Credito Emiliano, current account: debtor_account on an outflow is not a counterparty", () => {
  const row = source(
    "SEPA DD CORE DA ESEMPIO ENERGIA SPA MANDATO XX000000",
    "DBIT",
    {
      debtor: { name: "ANNA ESEMPIO" },
      creditor: undefined,
    },
  );
  assertEquals(counterparty(row, "credem-cacc"), "ESEMPIO ENERGIA SPA");
});

Deno.test("Credito Emiliano, card: without the country code and the city", () => {
  const cases: [string, string | null][] = [
    ["FERRAMENTA PROVA CITTAPROVA IT", "FERRAMENTA PROVA"],
    ["CAFFE PROVA CITTÀPROVA IT", "CAFFE PROVA"],
    ["LIBRERIA ESEMPIO DUE CITTAPROVA IT", "LIBRERIA ESEMPIO DUE"],
    // Not the format: fewer than three words or no two-letter code.
    ["NEGOZIO IT", null],
    ["PAGAMENTO SALDO CARTA", null],
    ["NEGOZIO PROVA CITTAPROVA ITA", null],
  ];
  for (const [description, expected] of cases) {
    assertEquals(
      counterparty(source(description), "credem-card"),
      expected,
      description,
    );
  }
});

Deno.test("HYPE: card payments without the province and the city", () => {
  assertEquals(
    counterparty(
      source("CAFFE ESEMPIO CITTAPROVA ZZ", "DBIT", { code: "pos" }),
      "hype",
    ),
    "CAFFE ESEMPIO",
  );
  assertEquals(
    counterparty(
      source("CAFFE ESEMPIO CITTAPROVA ZZ", "DBIT", { code: "POS" }),
      "hype",
    ),
    "CAFFE ESEMPIO",
  );
  // Other codes (a top-up `boi`) keep no counterparty from the description.
  assertEquals(
    counterparty(
      source("RICARICA DA CARTA ESEMPIO ZZ", "CRDT", { code: "boi" }),
      "hype",
    ),
    null,
  );
  assertEquals(
    counterparty(source("CAFFE ESEMPIO CITTAPROVA ZZ"), "hype"),
    null,
  );
});

Deno.test("PayPal: name and email of the creditor on an outflow", () => {
  const row = source("Pagamento", "DBIT", {
    creditor: {
      name: " Negozio  Esempio ",
      contact_details: { email_address: " Negozio@Example.COM " },
    },
    debtor: {
      name: "Anna Esempio",
      contact_details: { email_address: "anna.paypal@example.com" },
    },
  });
  assertEquals(counterparty(row, "paypal"), "Negozio Esempio");
  assertEquals(counterpartyEmail(row, "paypal"), "negozio@example.com");
});

Deno.test("PayPal: name and email of the debtor on an inflow", () => {
  const row = source(null, "CRDT", {
    creditor: {
      name: "Bruno Esempio",
      contact_details: { email_address: "bruno.paypal@example.com" },
    },
    debtor: {
      name: "Anna Esempio",
      contact_details: { email_address: "ANNA.PAYPAL@EXAMPLE.COM" },
    },
  });
  assertEquals(counterparty(row, "paypal"), "Anna Esempio");
  assertEquals(counterpartyEmail(row, "paypal"), "anna.paypal@example.com");
});

Deno.test("PayPal: no dedicated field, no counterparty", () => {
  const row = source("Pagamento a Negozio Esempio", "DBIT");
  assertEquals(counterparty(row, "paypal"), null);
  assertEquals(counterpartyEmail(row, "paypal"), null);
  const noEmail = source(null, "DBIT", {
    creditor: { name: "PayPal", contact_details: { email_address: "no" } },
  });
  assertEquals(counterparty(noEmail, "paypal"), "PayPal");
  assertEquals(counterpartyEmail(noEmail, "paypal"), null);
});

Deno.test("email: PayPal only", () => {
  const row = source(null, "DBIT", {
    creditor: {
      name: "Negozio Esempio",
      contact_details: { email_address: "negozio@example.com" },
    },
  });
  assertEquals(counterpartyEmail(row, "credem-cacc"), null);
  assertEquals(counterpartyEmail(row, null), null);
});

Deno.test("dedicated field first, for every format", () => {
  const salary = source(
    "EMOLUMENTI DITTA ESEMPIO SRL STIPENDIO MARZO",
    "CRDT",
    { debtor: { name: "DITTA ESEMPIO SRL" }, creditor: { name: "ANNA" } },
  );
  assertEquals(counterparty(salary, "credem-cacc"), "DITTA ESEMPIO SRL");
  assertEquals(counterparty(salary, null), "DITTA ESEMPIO SRL");
  // An empty name is no name: the description decides.
  const empty = source(
    "PAGAMENTO CBILL ESEMPIO SERVIZI",
    "DBIT",
    { creditor: { name: "   " } },
  );
  assertEquals(counterparty(empty, "credem-cacc"), "ESEMPIO SERVIZI");
});

Deno.test("no format: no counterparty from the description", () => {
  assertEquals(
    counterparty(source("FERRAMENTA PROVA CITTAPROVA IT"), null),
    null,
  );
  assertEquals(counterparty(source(null), "credem-card"), null);
});

Deno.test("monthly charge of the card: current account of Credito Emiliano only", () => {
  assertEquals(
    isCardMonthlyCharge("ADDEBITO MESE CARTA EGO", "credem-cacc"),
    true,
  );
  assertEquals(isCardMonthlyCharge("ADDEBITO MESE CARTA", "credem-cacc"), true);
  assertEquals(isCardMonthlyCharge("ADDEBITO MESE CARTA EGO", "hype"), false);
  assertEquals(isCardMonthlyCharge("ADDEBITO MESE CARTA EGO", null), false);
  assertEquals(
    isCardMonthlyCharge("ADDEBITO MESE CARTACEO", "credem-cacc"),
    false,
  );
  assertEquals(isCardMonthlyCharge(null, "credem-cacc"), false);
});
