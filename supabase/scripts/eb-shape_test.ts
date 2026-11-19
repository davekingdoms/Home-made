import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  classify,
  DATA_KEY,
  keyName,
  main,
  type ShapeIo,
  signals,
} from "./eb-shape.ts";

/**
 * A folder of invented files, in memory: paths with `/`, nothing on disk.
 * The names of the files and folders must never reach the output either.
 */
function memoryFolder(files: Record<string, string>): ShapeIo & {
  out: string[];
  err: string[];
} {
  const out: string[] = [];
  const err: string[] = [];
  return {
    out,
    err,
    readDir: (path) => {
      const prefix = `${path}/`;
      const children = new Map<string, boolean>();
      for (const file of Object.keys(files)) {
        if (!file.startsWith(prefix)) continue;
        const [name, ...rest] = file.slice(prefix.length).split("/");
        children.set(name!, rest.length > 0 || children.get(name!) === true);
      }
      if (children.size === 0) throw new Error("not a folder");
      return (async function* () {
        for (const [name, isDirectory] of children) {
          await Promise.resolve();
          yield { name, isDirectory, isFile: !isDirectory };
        }
      })();
    },
    readTextFile: (path) =>
      files[path] === undefined
        ? Promise.reject(new Error("missing"))
        : Promise.resolve(files[path]!),
    print: (line) => out.push(line),
    printError: (line) => err.push(line),
  };
}

const json = (value: unknown) => JSON.stringify(value);

// Invented data with every kind of value the script must never print.
const PAGE = {
  transactions: [
    {
      entry_reference: "RIF-SEGRETO-000777",
      transaction_amount: { currency: "EUR", amount: "1234.567" },
      credit_debit_indicator: "DBIT",
      status: "BOOK",
      booking_date: "2031-03-02",
      value_date: "2031-03-01T10:20:30Z",
      creditor: {
        name: "Negozio Segretissimo",
        contact_details: { email_address: "negozio.segreto@example.com" },
      },
      debtor_account: { iban: "IT60X0542811101000000123456" },
      remittance_information: [
        "PAGAMENTO A carla.segreta@example.com ",
        "",
      ],
      note_extra: { "luca.segreto@example.com": "valore nascosto" },
    },
    {
      transaction_amount: { currency: "EUR", amount: "77" },
      credit_debit_indicator: "CRDT",
      status: "PDNG",
      transaction_date: "2031-03-03",
      debtor: { name: "BRUNO RISERVATO" },
      remittance_information: ["RICARICA RISERVATA"],
      "2031-03-03": "chiave che e una data",
      "una chiave lunghissima che sembra proprio una frase intera": true,
    },
  ],
  continuation_key: "chiave-di-continuazione-segreta",
  // Saved around the response by whoever downloaded it.
  parametri: { date_from: "2031-02-01" },
  errore: null,
};
const FILES: Record<string, string> = {
  "dati-segreti/conto-di-carla/pagina-uno.json": json(PAGE),
  "dati-segreti/conto-di-carla/pagina-due.JSON": json({
    transactions: [],
    continuation_key: null,
  }),
  "dati-segreti/saldi-di-carla.json": json({
    balances: [{
      name: "Saldo di Carla",
      balance_amount: { currency: "EUR", amount: "-98765.43" },
      balance_type: "CLBD",
      reference_date: "2031-03-04",
    }],
  }),
  "dati-segreti/sessione-di-carla.json": json({
    session_id: "sessione-segreta-123",
    accounts: [{
      uid: "uid-segreto-456",
      account_id: { iban: "IT60 X054 2811 1010 0000 0123 456" },
      name: "Carla Riservata   ",
      cash_account_type: "CACC",
      currency: "EUR",
    }],
    aspsp: { name: "Banca Segreta", country: "ZZ" },
    access: { valid_until: "2031-08-28T10:00:00+00:00" },
  }),
  "dati-segreti/dettaglio.json": json({
    account_id: { iban: "IT00A0000000000000000007777" },
    name: "Carla Riservata",
    cash_account_type: "CACC",
    currency: "EUR",
  }),
  "dati-segreti/risposta-di-errore.json": json({
    code: 422,
    error: "WRONG_TRANSACTIONS_PERIOD",
    message: "Testo segreto della banca",
  }),
  "dati-segreti/altro/lista.json": json([{ campo: "valore-altro" }]),
  "dati-segreti/rotto.json": "{ non è json",
  "dati-segreti/note-segrete.txt": "testo non letto",
};

/** Every string and number of the files, and every name in their paths. */
function secrets(): string[] {
  const found = new Set<string>();
  const collect = (value: unknown) => {
    if (typeof value === "string" && value.trim().length >= 4) {
      found.add(value.trim());
    } else if (typeof value === "number" && String(value).length >= 3) {
      found.add(String(value));
    } else if (Array.isArray(value)) value.forEach(collect);
    else if (typeof value === "object" && value !== null) {
      for (const [key, item] of Object.entries(value)) {
        if (keyName(key) === DATA_KEY) found.add(key);
        collect(item);
      }
    }
  };
  for (const [path, text] of Object.entries(FILES)) {
    for (const part of path.split("/")) found.add(part.replace(/\.\w+$/, ""));
    try {
      collect(JSON.parse(text));
    } catch {
      found.add(text);
    }
  }
  return [...found];
}

function assertNoValues(lines: string[]) {
  const text = lines.join("\n");
  for (const secret of secrets()) {
    assertFalse(text.includes(secret), `the output holds ${secret}`);
  }
  // Pieces of values too: names, amounts, digits of IBAN and references.
  for (
    const piece of [
      "Segret",
      "segret",
      "Riservat",
      "RISERVAT",
      "Carla",
      "carla",
      "1234",
      "9876",
      "0542811",
      "123456",
      "000777",
      "example",
      "2031",
    ]
  ) {
    assertFalse(text.includes(piece), `the output holds ${piece}`);
  }
}

Deno.test("shape: paths, types, counts and signals, never a value", async () => {
  const io = memoryFolder(FILES);
  assertEquals(await main(["dati-segreti"], io), 0);
  assertEquals(io.err, []);
  assertNoValues(io.out);
  const text = io.out.join("\n");
  assert(text.includes("JSON files: 8, unreadable: 1"));
  for (
    const line of [
      "transactions page: 2 files",
      "balances: 1 files",
      "session: 1 files",
      "account details: 1 files",
      "error: 1 files",
      "other: 1 files",
      "  transactions[]: object 2",
      "  transactions[].creditor.contact_details.email_address: string 1; email 1",
      "  transactions[].remittance_information[]: string 3; contains email 1, empty 1, trailing space 1, upper case 1",
      "  transactions[].transaction_amount.amount: string 2; decimal(0) 1, decimal(3) 1",
      "  transactions[].debtor_account.iban: string 1; IBAN 1, upper case 1",
      "  transactions[].booking_date: string 1; ISO date 1",
      "  transactions[].value_date: string 1; ISO date-time 1",
      "  continuation_key: null 1, string 1",
      `  transactions[].${DATA_KEY}: boolean 1, string 1`,
      `  transactions[].note_extra.${DATA_KEY}: string 1`,
      "  accounts[].name: string 1; trailing space 1",
      "  accounts[].account_id.iban: string 1; IBAN 1, upper case 1",
      "  code: number 1",
    ]
  ) {
    assert(io.out.includes(line), line);
  }
});

Deno.test("compare: keys and types missing in the test data, email paths", async () => {
  const testdata = {
    "prova/pagina.json": json({
      transactions: [{
        transaction_amount: { currency: "EUR", amount: "1.00" },
        credit_debit_indicator: "DBIT",
        status: "BOOK",
        booking_date: "2031-03-02",
        remittance_information: ["CAFFE ESEMPIO"],
        creditor: { name: "Bar Esempio" },
      }],
      continuation_key: 5,
    }),
    "prova/saldi.json": json({
      balances: [{
        name: "Saldo",
        balance_amount: { currency: "EUR", amount: "1.00" },
        balance_type: "CLBD",
        reference_date: "2031-03-04",
      }],
    }),
  };
  const io = memoryFolder({ ...FILES, ...testdata });
  assertEquals(await main(["dati-segreti", "--compare", "prova"], io), 0);
  assertNoValues(io.out);
  const start = io.out.findIndex((line) => line.startsWith("compare with"));
  const comparison = io.out.slice(start);
  for (
    const line of [
      "compare with the test data (JSON files: 2, unreadable: 0)",
      "  missing key transactions[].creditor.contact_details.email_address",
      "  missing key transactions[].debtor_account.iban",
      "  missing key transactions[].entry_reference",
      `  missing key transactions[].${DATA_KEY}`,
      "  missing type continuation_key: null",
      "  missing type continuation_key: string",
      "balances: 0 keys missing, 0 types missing in the test data",
      "session: 14 keys missing, 0 types missing in the test data",
      // The keys a saved page adds around the response, listed apart.
      "  outside the response, not compared: errore",
      "  outside the response, not compared: parametri",
      "  outside the response, not compared: parametri.date_from",
      "other: not compared (not an Enable Banking response)",
      "  transactions[].creditor.contact_details.email_address: 1",
      "  transactions[].remittance_information[]: 1",
      "missing in the test data: 34 keys, 2 types",
    ]
  ) {
    assert(comparison.includes(line), line);
  }
  // Keys the test data has are not missing; a hidden key with no email in
  // its value is not an email path; wrapper keys are not missing keys.
  for (
    const absent of [
      "  missing key transactions[].creditor.name",
      `  transactions[].note_extra.${DATA_KEY}: 1`,
      "  missing key parametri",
      "  missing key errore",
      "  missing key []",
    ]
  ) {
    assertFalse(comparison.includes(absent), absent);
  }
});

Deno.test("compare: the test data of the repository against itself", async () => {
  const dir = `${import.meta.dirname}/../functions/_shared/testdata`;
  const out: string[] = [];
  const err: string[] = [];
  const io: ShapeIo = {
    readDir: (path) => Deno.readDir(path),
    readTextFile: (path) => Deno.readTextFile(path),
    print: (line) => out.push(line),
    printError: (line) => err.push(line),
  };
  assertEquals(await main([dir, "--compare", dir], io), 0);
  assertEquals(err, []);
  for (
    const shapeClass of [
      "transactions page",
      "balances",
      "session",
      "account details",
      "error",
    ]
  ) {
    assert(
      out.includes(
        `${shapeClass}: 0 keys missing, 0 types missing in the test data`,
      ),
      shapeClass,
    );
  }
  assertEquals(out.at(-1), "missing in the test data: 0 keys, 0 types");
  for (const party of ["creditor", "debtor"]) {
    assert(
      out.some((line) =>
        line.startsWith(
          `  transactions[].${party}.contact_details.email_address: `,
        )
      ),
      party,
    );
  }
});

Deno.test("usage and unreadable folders: codes, no names", async () => {
  for (
    const args of [
      [],
      ["a", "b"],
      ["a", "--compare"],
      ["a", "--compare", "--other"],
      ["a", "--unknown"],
      ["a", "--compare="],
    ]
  ) {
    const io = memoryFolder(FILES);
    assertEquals(await main(args, io), 2, JSON.stringify(args));
    assertEquals(io.out, []);
  }
  const missing = memoryFolder(FILES);
  assertEquals(await main(["cartella-segreta"], missing), 1);
  assertEquals(missing.err, ["error: cannot read the folder"]);
  const noTestdata = memoryFolder(FILES);
  assertEquals(
    await main(["dati-segreti/", "--compare=prova-segreta"], noTestdata),
    1,
  );
  assertEquals(noTestdata.err, ["error: cannot read the test data folder"]);
  assertNoValues([...noTestdata.out, ...noTestdata.err]);
});

Deno.test("keys that look like data are hidden", () => {
  for (const key of ["name", "entry_reference", "_links", "Psu-Ip-Address"]) {
    assertEquals(keyName(key), key);
  }
  for (
    const key of [
      "anna@example.com",
      "2031-03-01",
      "conto1",
      "Anna Esempio",
      "città",
      "a.b",
      "x".repeat(41),
      "",
    ]
  ) {
    assertEquals(keyName(key), DATA_KEY, key);
  }
});

Deno.test("signals of a string", () => {
  assertEquals(signals(""), ["empty"]);
  assertEquals(signals("   "), ["empty"]);
  assertEquals(signals("anna@example.com"), ["email"]);
  assertEquals(signals("A anna@example.com"), ["contains email"]);
  assertEquals(signals("IT60X0542811101000000123456"), ["IBAN", "upper case"]);
  assertEquals(signals("IT60 X054 2811 1010 0000 0123 456"), [
    "IBAN",
    "upper case",
  ]);
  // The shape of an IBAN without a valid check: a reference, not an IBAN.
  assertEquals(signals("IT00A0000000000000000001234"), ["upper case"]);
  assertEquals(signals("PP0000000000000001"), ["upper case"]);
  assertEquals(signals("2031-03-01"), ["ISO date"]);
  assertEquals(signals("2031-03-01T10:00:00Z"), ["ISO date-time"]);
  assertEquals(signals("12.50"), ["decimal(2)"]);
  assertEquals(signals("-4.4"), ["decimal(1)"]);
  assertEquals(signals("1"), ["decimal(0)"]);
  assertEquals(signals("BAR ESEMPIO "), ["upper case", "trailing space"]);
  assertEquals(signals("Bar Esempio"), []);
});

Deno.test("classes from the shape", () => {
  const first = (body: unknown) => classify(body)[0]![0];
  assertEquals(first({ transactions: [] }), "transactions page");
  assertEquals(
    first([{ transaction_amount: {}, credit_debit_indicator: "DBIT" }]),
    "transactions page",
  );
  assertEquals(first({ balances: [] }), "balances");
  assertEquals(first({ session_id: "x", accounts: [] }), "session");
  assertEquals(
    first({ status: "AUTHORIZED", accounts: [], access: {} }),
    "session",
  );
  assertEquals(first({ cash_account_type: "CACC" }), "account details");
  assertEquals(first({ code: 422, error: "X", message: "m" }), "error");
  assertEquals(
    classify({ a: { error: "X", code: 1 }, b: { error: "Y", message: "m" } })
      .map(([shapeClass]) => shapeClass),
    ["error", "error"],
  );
  assertEquals(first({ aspsps: [] }), "other");
  assertEquals(first([]), "other");
  assertEquals(first("testo"), "other");
});
