import { assertEquals } from "@std/assert";
import { cleanText, normalizeDescription } from "./description.ts";

Deno.test("description: lines joined by a space, spaces reduced, trimmed", () => {
  assertEquals(
    normalizeDescription(["  PAGAMENTO CBILL ", "ESEMPIO   SERVIZI  "]),
    "PAGAMENTO CBILL ESEMPIO SERVIZI",
  );
  assertEquals(
    normalizeDescription(["CAFFE\tESEMPIO\nCITTAPROVA", "ZZ"]),
    "CAFFE ESEMPIO CITTAPROVA ZZ",
  );
  assertEquals(normalizeDescription(["UNA RIGA"]), "UNA RIGA");
});

Deno.test("description: empty or missing is null", () => {
  for (const empty of [[], [""], ["   ", "\t"], null, undefined, "", "  "]) {
    assertEquals(normalizeDescription(empty), null, JSON.stringify(empty));
  }
});

Deno.test("description: lines that are not text are left out", () => {
  assertEquals(
    normalizeDescription(["BAR", 12, null, { a: 1 }, "ESEMPIO"]),
    "BAR ESEMPIO",
  );
  assertEquals(normalizeDescription(42), null);
  assertEquals(normalizeDescription({ text: "BAR" }), null);
});

Deno.test("description: a single string is one line", () => {
  assertEquals(normalizeDescription("  BAR  ESEMPIO "), "BAR ESEMPIO");
});

Deno.test("cleanText: spaces reduced and trimmed, empty or not text is null", () => {
  assertEquals(cleanText("  DITTA   ESEMPIO SRL "), "DITTA ESEMPIO SRL");
  assertEquals(cleanText(" "), null);
  assertEquals(cleanText(undefined), null);
  assertEquals(cleanText(7), null);
});
