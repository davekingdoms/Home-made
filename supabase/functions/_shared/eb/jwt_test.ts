import { assert, assertEquals, assertRejects } from "@std/assert";
import { EbError } from "./errors.ts";
import { importPrivateKey, signJwt } from "./jwt.ts";
import { armor, generateTestKeys, verifyJwt } from "../testing/rsa.ts";

const keys = await generateTestKeys();
const APP_ID = "00000000-0000-4000-8000-00000000a99a";

for (const format of ["pkcs8Pem", "pkcs1Pem"] as const) {
  Deno.test(`signJwt: RS256 with the claims of Enable Banking (${format})`, async () => {
    const key = await importPrivateKey(keys[format]);
    const token = await signJwt(key, APP_ID, { issuedAt: 1_930_000_000 });

    const { header, payload } = await verifyJwt(token, keys.publicKey);
    assertEquals(header, { typ: "JWT", alg: "RS256", kid: APP_ID });
    assertEquals(payload, {
      iss: "enablebanking.com",
      aud: "api.enablebanking.com",
      iat: 1_930_000_000,
      exp: 1_930_000_000 + 3600,
    });
  });
}

Deno.test("signJwt: issued now, one hour of life", async () => {
  const key = await importPrivateKey(keys.pkcs8Pem);
  const before = Math.floor(Date.now() / 1000);
  const { payload } = await verifyJwt(
    await signJwt(key, APP_ID),
    keys.publicKey,
  );
  const iat = payload.iat as number;
  assert(iat >= before && iat <= before + 5);
  assertEquals(payload.exp, iat + 3600);
});

Deno.test("signJwt: life over 24 hours is refused", async () => {
  const key = await importPrivateKey(keys.pkcs8Pem);
  await assertRejects(
    () => signJwt(key, APP_ID, { ttlSeconds: 24 * 3600 + 1 }),
    RangeError,
  );
});

Deno.test("importPrivateKey: CRLF and escaped line breaks", async () => {
  for (
    const pem of [
      keys.pkcs8Pem.replaceAll("\n", "\r\n"),
      keys.pkcs8Pem.replaceAll("\n", "\\n"),
      keys.pkcs1Pem.replaceAll("\n", "\\n"),
    ]
  ) {
    const key = await importPrivateKey(pem);
    await verifyJwt(await signJwt(key, APP_ID), keys.publicKey);
  }
});

Deno.test("importPrivateKey: unreadable keys are invalid_credentials", async () => {
  const body = keys.pkcs8Pem.split("\n").slice(1, -2).join("\n");
  const cases = [
    "",
    "not a key",
    keys.pkcs8Pem.replace("PRIVATE KEY", "PUBLIC KEY"),
    armor("ENCRYPTED PRIVATE KEY", body),
    armor("PRIVATE KEY", body.slice(0, 200)),
    armor("PRIVATE KEY", "***"),
    // PKCS#1 content declared as PKCS#8.
    keys.pkcs1Pem.replaceAll("RSA PRIVATE KEY", "PRIVATE KEY"),
  ];
  for (const pem of cases) {
    const error = await assertRejects(() => importPrivateKey(pem), EbError);
    assertEquals(error.code, "invalid_credentials");
    assert(
      !error.message.includes(body.slice(0, 16)),
      "key material in message",
    );
  }
});
