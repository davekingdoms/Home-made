import { assertEquals, assertFalse, assertRejects } from "@std/assert";
import { Db, DbError } from "./db.ts";
import { fakeFetch, type Handler, json } from "./testing/fake_fetch.ts";
import { pgError, SECRET_KEY, SUPABASE_URL } from "./testing/fake_supabase.ts";

/** Texts of a failed check: the values of the row, invented. */
const DETAIL = "Failing row contains (anna.paypal@example.com, 123456).";

function setup(handler: Handler, options: { bearer?: string } = {}) {
  const fake = fakeFetch(handler);
  const db = new Db({
    url: `${SUPABASE_URL}/`,
    apikey: SECRET_KEY,
    fetch: fake.fetch,
    timeoutMs: 50,
    ...options,
  });
  return { db, requests: fake.requests };
}

async function failure(db: Db): Promise<DbError> {
  return await assertRejects(() => db.rpc("funzione_di_prova"), DbError);
}

function assertNoTexts(error: DbError) {
  const all = [error.message, JSON.stringify(error), String(error)].join(" ");
  for (const text of [DETAIL, "Failing row", "violates", "anna.paypal"]) {
    assertFalse(all.includes(text));
  }
}

Deno.test("rpc: POST with the named arguments and the secret key only", async () => {
  const { db, requests } = setup(() => json([{ app_id: "app-di-prova" }]));
  assertEquals(await db.rpc("eb_get_credentials", { user_id: "u" }), [
    { app_id: "app-di-prova" },
  ]);
  const request = requests[0]!;
  assertEquals(request.method, "POST");
  assertEquals(request.url, `${SUPABASE_URL}/rest/v1/rpc/eb_get_credentials`);
  assertEquals(request.headers.get("apikey"), SECRET_KEY);
  assertEquals(request.headers.get("Authorization"), null);
  assertEquals(await request.json(), { user_id: "u" });
});

Deno.test("rpc: the JWT of a user goes in Authorization", async () => {
  const { db, requests } = setup(() => json(null), {
    bearer: "intestazione.contenuto.firma",
  });
  assertEquals(await db.rpc("current_member_id"), null);
  assertEquals(
    requests[0]?.headers.get("Authorization"),
    "Bearer intestazione.contenuto.firma",
  );
});

Deno.test("rpc: a void function returns null", async () => {
  const { db } = setup(() => new Response(null, { status: 204 }));
  assertEquals(await db.rpc("eb_set_credentials"), null);
});

Deno.test("errors: the key of a raised exception, never its texts", async () => {
  const { db } = setup(() =>
    pgError(400, "P0001", "link_not_claimable", DETAIL)
  );
  const error = await failure(db);
  assertEquals(error.code, "link_not_claimable");
  assertEquals(error.status, 400);
  assertNoTexts(error);
});

Deno.test("errors: a check violated gives its SQLSTATE without the DETAIL", async () => {
  const { db } = setup(() =>
    pgError(
      400,
      "23514",
      'new row for relation "paypal_emails" violates check constraint',
      DETAIL,
    )
  );
  const error = await failure(db);
  assertEquals(error.code, "23514");
  assertNoTexts(error);
});

Deno.test("errors: a P0001 message that is not a key is not kept", async () => {
  const { db } = setup(() =>
    pgError(400, "P0001", "anna.paypal@example.com is taken", DETAIL)
  );
  const error = await failure(db);
  assertEquals(error.code, "P0001");
  assertNoTexts(error);
});

Deno.test("errors: PostgREST codes, unknown bodies, network, timeout", async () => {
  assertEquals(
    (await failure(setup(() => pgError(401, "PGRST301", "JWT expired")).db))
      .code,
    "PGRST301",
  );
  assertEquals(
    (await failure(setup(() => new Response(DETAIL, { status: 502 })).db))
      .code,
    "http_502",
  );
  assertEquals(
    (await failure(setup(() => Promise.reject(new Error(DETAIL))).db)).code,
    "unavailable",
  );
  const slow = setup((request) =>
    new Promise((_, reject) =>
      request.signal.addEventListener("abort", () => reject(new Error(DETAIL)))
    )
  );
  assertEquals((await failure(slow.db)).code, "unavailable");
  assertEquals(
    (await failure(setup(() => new Response("{", { status: 200 })).db)).code,
    "invalid_response",
  );
});
