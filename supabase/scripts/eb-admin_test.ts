import { assert, assertEquals, assertFalse } from "@std/assert";
import { type AdminIo, main } from "./eb-admin.ts";
import {
  fakeFetch,
  type Handler,
  json,
  testdata,
} from "../functions/_shared/testing/fake_fetch.ts";
import { generateTestKeys } from "../functions/_shared/testing/rsa.ts";

const keys = await generateTestKeys();
const APP_ID = "00000000-0000-4000-8000-00000000a99a";
const KEY_PATH = "chiave-di-prova.pem";

function run(args: string[], handler: Handler, env: Record<string, string> = {
  EB_APP_ID: APP_ID,
  EB_KEY_PATH: KEY_PATH,
}) {
  const fake = fakeFetch(handler);
  const out: string[] = [];
  const err: string[] = [];
  const io: AdminIo = {
    env: (name) => env[name],
    readTextFile: (path) =>
      path === KEY_PATH
        ? Promise.resolve(keys.pkcs8Pem)
        : Promise.reject(new Error("missing")),
    print: (line) => out.push(line),
    printError: (line) => err.push(line),
    fetch: fake.fetch,
  };
  return { done: main(args, io), out, err, requests: fake.requests };
}

/** Nothing secret in the output: key, JWT, application ID, key path. */
function assertNoSecrets(lines: string[], requests: Request[]) {
  const text = lines.join("\n");
  const keyBody = keys.pkcs8Pem.split("\n")[1] ?? "";
  for (const secret of [APP_ID, KEY_PATH, keyBody.slice(0, 24)]) {
    assertFalse(text.includes(secret));
  }
  for (const request of requests) {
    const jwt = request.headers.get("Authorization")?.slice("Bearer ".length) ??
      "";
    assert(jwt.length > 0);
    for (const part of jwt.split(".")) assertFalse(text.includes(part));
  }
}

Deno.test("aspsps: number of banks and Mock ASPSP, nothing else", async () => {
  const aspsps = await testdata("aspsps.json");
  const { done, out, err, requests } = run(
    ["aspsps", "--country", "IT"],
    () => json(aspsps),
  );
  assertEquals(await done, 0);
  assertEquals(out, ["banks in IT: 2", "Mock ASPSP: present"]);
  assertEquals(err, []);
  assertEquals(
    requests[0]?.url,
    "https://api.enablebanking.com/aspsps?country=IT",
  );
  assertNoSecrets([...out, ...err], requests);
});

Deno.test("aspsps: Mock ASPSP missing, --country=xx form", async () => {
  const { done, out } = run(
    ["aspsps", "--country=fi"],
    () => json({ aspsps: [{ name: "Banca di Prova", country: "FI" }] }),
  );
  assertEquals(await done, 0);
  assertEquals(out, ["banks in FI: 1", "Mock ASPSP: missing"]);
});

Deno.test("aspsps: rejected credentials print the code only", async () => {
  const errors = await testdata("errors.json") as Record<string, unknown>;
  const { done, out, err, requests } = run(
    ["aspsps", "--country", "IT"],
    () => json(errors.unauthorized, 401),
  );
  assertEquals(await done, 1);
  assertEquals(out, []);
  assertEquals(err, [
    "error: invalid_credentials (HTTP 401, UNAUTHORIZED_ACCESS)",
  ]);
  assertNoSecrets(err, requests);
});

Deno.test("aspsps: missing environment or unreadable key", async () => {
  const missing = run(["aspsps", "--country", "IT"], () => json({}), {});
  assertEquals(await missing.done, 1);
  assertEquals(missing.err, ["error: set EB_APP_ID and EB_KEY_PATH"]);

  const unreadable = run(["aspsps", "--country", "IT"], () => json({}), {
    EB_APP_ID: APP_ID,
    EB_KEY_PATH: "altro-percorso.pem",
  });
  assertEquals(await unreadable.done, 1);
  assertEquals(unreadable.err, ["error: cannot read the file in EB_KEY_PATH"]);
  assertEquals(unreadable.requests.length, 0);
});

Deno.test("usage errors exit with 2 and call nothing", async () => {
  for (
    const args of [[], ["sync"], ["aspsps"], ["aspsps", "--country", "ITA"]]
  ) {
    const { done, err, requests } = run(args, () => json({}));
    assertEquals(await done, 2);
    assertEquals(err.length, 1);
    assertEquals(requests.length, 0);
  }
});
