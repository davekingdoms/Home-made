import { assert, assertEquals } from "@std/assert";
import { createHandler } from "./handler.ts";
import type {
  EbHandler,
  RpcHandler,
} from "../_shared/testing/fake_supabase.ts";
import {
  ANNA,
  assertNothingSensitive,
  BRUNO,
  fakeProject,
  JWT_ANNA,
  pemPieces,
  PUBLISHABLE_KEY,
  SECRET_KEY,
  SUPABASE_URL,
  testEnv,
} from "../_shared/testing/fake_supabase.ts";
import { json, testdata } from "../_shared/testing/fake_fetch.ts";
import { armor, generateTestKeys, verifyJwt } from "../_shared/testing/rsa.ts";
import { capturedHandler } from "../_shared/testing/console.ts";

const keys = await generateTestKeys();
const aspsps = await testdata("aspsps.json");
const errors = await testdata("errors.json") as Record<string, unknown>;
const APP_ID = "00000000-0000-4000-8000-00000000d99d";
const URL_ = `${SUPABASE_URL}/functions/v1/eb-credentials`;

function setup(options: {
  eb?: Record<string, EbHandler>;
  rpc?: Record<string, RpcHandler>;
  env?: Record<string, string | undefined>;
} = {}) {
  const saved: Record<string, unknown>[] = [];
  const project = fakeProject({
    eb: { "GET /aspsps": () => json(aspsps), ...options.eb },
    rpc: {
      eb_set_credentials: (args) => {
        saved.push(args);
        return new Response(null, { status: 204 });
      },
      ...options.rpc,
    },
  });
  const { handler, lines } = capturedHandler(createHandler({
    env: testEnv(options.env),
    fetch: project.fetch,
  }));
  return { handler, project, saved, lines };
}

function post(body: unknown, headers: Record<string, string> = {
  apikey: SECRET_KEY,
}) {
  return new Request(URL_, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const valid = {
  member_id: ANNA.memberId,
  app_id: APP_ID,
  private_key: keys.pkcs8Pem,
};

/** Nothing of the key, the IDs or the secrets in the logs or the body. */
function assertClean(lines: string[], body: unknown) {
  assertNothingSensitive([...lines, JSON.stringify(body)], [
    ...pemPieces(keys.pkcs8Pem),
    APP_ID,
    ANNA.memberId,
    ANNA.userId,
    SECRET_KEY,
    PUBLISHABLE_KEY,
    JWT_ANNA,
  ]);
}

Deno.test("service: a valid key is proved, then saved for the person", async () => {
  const { handler, project, saved, lines } = setup();
  const response = await handler(post(valid));
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  const body = await response.json();
  assertEquals(body, { ok: true });

  const ebRequest = project.ebRequests[0]!;
  assertEquals(new URL(ebRequest.url).pathname, "/aspsps");
  const token = ebRequest.headers.get("Authorization")!.slice("Bearer ".length);
  const { header } = await verifyJwt(token, keys.publicKey);
  assertEquals(header.kid, APP_ID);

  assertEquals(saved, [{
    user_id: ANNA.userId,
    app_id: APP_ID,
    private_key: keys.pkcs8Pem,
  }]);
  assertEquals(
    project.rpcCalls.map((call) => [call.name, call.apikey]),
    [["eb_service_member", SECRET_KEY], ["eb_set_credentials", SECRET_KEY]],
  );
  assertClean(lines, body);
  assert(lines.length > 0);
});

Deno.test("user: the member comes from the JWT, never from the body", async () => {
  const { handler, saved } = setup();
  const response = await handler(post(
    { app_id: APP_ID, private_key: keys.pkcs8Pem },
    { apikey: PUBLISHABLE_KEY, Authorization: `Bearer ${JWT_ANNA}` },
  ));
  assertEquals(response.status, 200);
  assertEquals(saved[0]?.user_id, ANNA.userId);

  const other = setup();
  const refused = await other.handler(post(
    { ...valid, member_id: BRUNO.memberId },
    { apikey: PUBLISHABLE_KEY, Authorization: `Bearer ${JWT_ANNA}` },
  ));
  assertEquals(refused.status, 400);
  assertEquals(await refused.json(), { error: "invalid_request" });
  assertEquals(other.saved, []);
});

Deno.test("a key refused by Enable Banking saves nothing", async () => {
  const { handler, saved, lines } = setup({
    eb: { "GET /aspsps": () => json(errors.unauthorized, 401) },
  });
  const response = await handler(post(valid));
  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body, { error: "invalid_credentials" });
  assertEquals(saved, []);
  assertClean(lines, body);
});

Deno.test("a PEM that is not a usable key saves nothing and calls nobody", async () => {
  const { handler, project, saved, lines } = setup();
  // Base64 of three zero bytes: a PEM block that holds no key.
  const broken = armor("PRIVATE KEY", "AAAA");
  const response = await handler(post({ ...valid, private_key: broken }));
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_credentials" });
  assertEquals(project.ebRequests.length, 0);
  assertEquals(saved, []);
  assertNothingSensitive(lines, ["PRIVATE KEY", APP_ID]);
});

Deno.test("wrong shapes are invalid requests", async () => {
  const cases: unknown[] = [
    { ...valid, app_id: " " },
    { ...valid, app_id: 12 },
    { ...valid, app_id: "a".repeat(201) },
    { ...valid, private_key: "chiave-di-prova" },
    { ...valid, private_key: undefined },
    { ...valid, private_key: `${keys.pkcs8Pem}${"a".repeat(16 * 1024)}` },
    { ...valid, member_id: "anna" },
    { app_id: APP_ID, private_key: keys.pkcs8Pem },
    [valid],
  ];
  for (const body of cases) {
    const { handler, project, saved } = setup();
    const response = await handler(post(body));
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "invalid_request" });
    assertEquals(project.ebRequests.length, 0);
    assertEquals(saved, []);
  }
});

Deno.test("Enable Banking unavailable: 502 with the code, nothing saved", async () => {
  const { handler, saved } = setup({
    eb: { "GET /aspsps": () => json(errors.aspsp_error, 500) },
  });
  const response = await handler(post(valid));
  assertEquals(response.status, 502);
  assertEquals(await response.json(), { error: "bank_unavailable" });
  assertEquals(saved, []);
});

Deno.test("a member not eligible is refused before any check", async () => {
  const { handler, project } = setup();
  const response = await handler(
    post({ ...valid, member_id: "00000000-0000-4000-8000-0000000000e9" }),
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "member_not_eligible" });
  assertEquals(project.ebRequests.length, 0);
});

Deno.test("no credentials of the caller: 401", async () => {
  const { handler, project } = setup();
  const response = await handler(post(valid, { apikey: "chiave-sbagliata" }));
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "unauthorized" });
  assertEquals(project.rpcCalls.length, 0);
});

Deno.test("a missing variable is internal, without its name", async () => {
  for (
    const missing of [
      "SUPABASE_URL",
      "SUPABASE_SECRET_KEYS",
      "SUPABASE_PUBLISHABLE_KEYS",
    ]
  ) {
    const { handler, lines } = setup({ env: { [missing]: undefined } });
    const response = await handler(post(valid));
    assertEquals(response.status, 500);
    const text = await response.text();
    assertEquals(JSON.parse(text), { error: "internal" });
    assertNothingSensitive([text, ...lines], [missing]);
  }
  const { handler } = setup({ env: { SUPABASE_SECRET_KEYS: "non json" } });
  assertEquals((await handler(post(valid))).status, 500);
});

Deno.test("other methods: 405", async () => {
  const { handler } = setup();
  const response = await handler(new Request(URL_, { method: "GET" }));
  assertEquals(response.status, 405);
  assertEquals(response.headers.get("Allow"), "POST");
  assertEquals(await response.json(), { error: "method_not_allowed" });
});
