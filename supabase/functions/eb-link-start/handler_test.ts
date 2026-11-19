import { assert, assertEquals, assertNotStrictEquals } from "@std/assert";
import { CONSENT_MARGIN_MS, createHandler } from "./handler.ts";
import type { EnableBankingClient } from "../_shared/eb/client.ts";
import { type NewEbClient, newEbClient } from "../_shared/eb/factory.ts";
import type {
  EbHandler,
  RpcHandler,
} from "../_shared/testing/fake_supabase.ts";
import {
  ANNA,
  assertNothingSensitive,
  BRUNO,
  credentialsRpc,
  fakeProject,
  GLOBAL_APP_ID,
  JWT_ANNA,
  JWT_BRUNO,
  PUBLISHABLE_KEY,
  REDIRECT_URL,
  SECRET_KEY,
  SUPABASE_URL,
  testEnv,
} from "../_shared/testing/fake_supabase.ts";
import { json, testdata } from "../_shared/testing/fake_fetch.ts";
import { generateTestKeys, verifyJwt } from "../_shared/testing/rsa.ts";
import { capturedHandler } from "../_shared/testing/console.ts";

const annaKeys = await generateTestKeys();
const brunoKeys = await generateTestKeys();
const globalKeys = await generateTestKeys();
const aspsps = await testdata("aspsps.json");
const auth = await testdata("auth.json") as { url: string };
const errors = await testdata("errors.json") as Record<string, unknown>;

const URL_ = `${SUPABASE_URL}/functions/v1/eb-link-start`;
const NOW = Date.UTC(2031, 2, 1, 10, 0, 0);
const REQUEST_ID = "00000000-0000-4000-8000-0000000000c1";
/** maximum_consent_validity of Mock ASPSP in aspsps.json. */
const MOCK_VALIDITY_S = 15552000;

const OWN_CREDENTIALS = {
  [ANNA.userId]: { appId: ANNA.appId, keys: annaKeys },
  [BRUNO.userId]: { appId: BRUNO.appId, keys: brunoKeys },
};

function setup(options: {
  eb?: Record<string, EbHandler>;
  rpc?: Record<string, RpcHandler>;
  env?: Record<string, string | undefined>;
  newEbClient?: NewEbClient;
} = {}) {
  const linkRequests: Record<string, unknown>[] = [];
  const authRequests: unknown[] = [];
  const project = fakeProject({
    eb: {
      "GET /aspsps": () => json(aspsps),
      "POST /auth": async (request) => {
        authRequests.push(await request.json());
        return json(auth);
      },
      ...options.eb,
    },
    rpc: {
      eb_get_credentials: credentialsRpc(OWN_CREDENTIALS),
      create_link_request: (args) => {
        linkRequests.push(args);
        return REQUEST_ID;
      },
      ...options.rpc,
    },
  });
  const { handler, lines } = capturedHandler(createHandler({
    env: testEnv(options.env),
    fetch: project.fetch,
    now: () => NOW,
    newEbClient: options.newEbClient,
  }));
  return { handler, project, linkRequests, authRequests, lines };
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

const mock = {
  member_id: ANNA.memberId,
  aspsp_name: "Mock ASPSP",
  aspsp_country: "IT",
};

async function kidOf(request: Request, publicKey: CryptoKey) {
  const token = request.headers.get("Authorization")!.slice("Bearer ".length);
  return { token, kid: (await verifyJwt(token, publicKey)).header.kid };
}

Deno.test("bank found: a link request and the authorization URL", async () => {
  const { handler, project, linkRequests, authRequests, lines } = setup();
  const response = await handler(post(mock));
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  const body = await response.json();
  assertEquals(body, { ok: true, url: auth.url });

  assertEquals(
    new URL(project.ebRequests[0]!.url).searchParams.get("country"),
    "IT",
  );
  assertEquals(linkRequests, [{
    member_id: ANNA.memberId,
    aspsp_name: "Mock ASPSP",
    aspsp_country: "IT",
    psu_type: "personal",
    uses_global_app: false,
  }]);
  assertEquals(authRequests, [{
    access: {
      valid_until: new Date(NOW + MOCK_VALIDITY_S * 1000 - CONSENT_MARGIN_MS)
        .toISOString(),
    },
    aspsp: { name: "Mock ASPSP", country: "IT" },
    state: REQUEST_ID,
    redirect_url: REDIRECT_URL,
    psu_type: "personal",
  }]);
  assertEquals(
    (authRequests[0] as { access: { valid_until: string } }).access
      .valid_until,
    "2031-08-28T09:50:00.000Z",
  );
  for (const request of project.ebRequests) {
    assertEquals((await kidOf(request, annaKeys.publicKey)).kid, ANNA.appId);
  }

  assertNothingSensitive(lines, [
    auth.url,
    REQUEST_ID,
    ANNA.memberId,
    ANNA.userId,
    ANNA.appId,
    "Mock ASPSP",
    SECRET_KEY,
    ...(await Promise.all(
      project.ebRequests.map((r) => kidOf(r, annaKeys.publicKey)),
    )).flatMap(({ token }) => token.split(".")),
  ]);
});

Deno.test("business PSU on a bank that admits it", async () => {
  const { handler, authRequests } = setup();
  const response = await handler(post({ ...mock, psu_type: "business" }));
  assertEquals(response.status, 200);
  assertEquals((authRequests[0] as { psu_type: string }).psu_type, "business");
});

Deno.test("bank not found: 404, no request, no authorization", async () => {
  const { handler, linkRequests, authRequests } = setup();
  const response = await handler(
    post({ ...mock, aspsp_name: "mock aspsp" }),
  );
  assertEquals(response.status, 404);
  assertEquals(await response.json(), { error: "bank_not_found" });
  assertEquals(linkRequests, []);
  assertEquals(authRequests, []);
});

Deno.test("a PSU type the bank does not admit is an invalid request", async () => {
  const { handler, linkRequests } = setup();
  const response = await handler(post({
    ...mock,
    aspsp_name: "Banca di Prova",
    psu_type: "business",
  }));
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_request" });
  assertEquals(linkRequests, []);
});

Deno.test("wrong bodies are invalid requests", async () => {
  for (
    const body of [
      { ...mock, aspsp_name: " " },
      { ...mock, aspsp_country: "it" },
      { ...mock, aspsp_country: "ITA" },
      { ...mock, psu_type: "corporate" },
      { ...mock, member_id: undefined },
    ]
  ) {
    const { handler, project } = setup();
    const response = await handler(post(body));
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "invalid_request" });
    assertEquals(project.ebRequests.length, 0);
  }
});

Deno.test("without own credentials: the global application", async () => {
  const { handler, project, linkRequests } = setup({
    rpc: { eb_get_credentials: () => [] },
    env: {
      EB_GLOBAL_APP_ID: GLOBAL_APP_ID,
      EB_GLOBAL_PRIVATE_KEY: globalKeys.pkcs8Pem,
    },
  });
  const response = await handler(post(mock));
  assertEquals(response.status, 200);
  assertEquals(linkRequests[0]?.uses_global_app, true);
  for (const request of project.ebRequests) {
    assertEquals(
      (await kidOf(request, globalKeys.publicKey)).kid,
      GLOBAL_APP_ID,
    );
  }
});

Deno.test("without own credentials nor a global application: no_credentials", async () => {
  for (
    const env of [{}, { EB_GLOBAL_APP_ID: GLOBAL_APP_ID }, {
      EB_GLOBAL_PRIVATE_KEY: globalKeys.pkcs8Pem,
    }]
  ) {
    const { handler, project } = setup({
      rpc: { eb_get_credentials: () => [] },
      env,
    });
    const response = await handler(post(mock));
    assertEquals(response.status, 409);
    assertEquals(await response.json(), { error: "no_credentials" });
    assertEquals(project.ebRequests.length, 0);
  }
});

Deno.test("one client for each request and person, no JWT shared", async () => {
  const created: { appId: string; client: EnableBankingClient }[] = [];
  const spy: NewEbClient = (options) => {
    const client = newEbClient(options);
    created.push({ appId: options.appId, client });
    return client;
  };
  const { handler, project } = setup({ newEbClient: spy });

  const asAnna = {
    apikey: PUBLISHABLE_KEY,
    Authorization: `Bearer ${JWT_ANNA}`,
  };
  const asBruno = {
    apikey: PUBLISHABLE_KEY,
    Authorization: `Bearer ${JWT_BRUNO}`,
  };
  const body = { aspsp_name: "Mock ASPSP", aspsp_country: "IT" };
  assertEquals((await handler(post(body, asAnna))).status, 200);
  const annaRequests = project.ebRequests.length;
  assertEquals((await handler(post(body, asBruno))).status, 200);
  assertEquals((await handler(post(body, asAnna))).status, 200);

  assertEquals(created.map((c) => c.appId), [
    ANNA.appId,
    BRUNO.appId,
    ANNA.appId,
  ]);
  assertNotStrictEquals(created[0]!.client, created[1]!.client);
  assertNotStrictEquals(created[0]!.client, created[2]!.client);

  const anna = project.ebRequests.slice(0, annaRequests);
  const bruno = project.ebRequests.slice(annaRequests, 2 * annaRequests);
  const annaTokens = new Set<string>();
  for (const request of anna) {
    const { token, kid } = await kidOf(request, annaKeys.publicKey);
    assertEquals(kid, ANNA.appId);
    annaTokens.add(token);
  }
  for (const request of bruno) {
    const { token, kid } = await kidOf(request, brunoKeys.publicKey);
    assertEquals(kid, BRUNO.appId);
    assert(!annaTokens.has(token), "a JWT of Anna served Bruno");
  }
});

Deno.test("Enable Banking unavailable: 502 with the code", async () => {
  const { handler, linkRequests } = setup({
    eb: { "GET /aspsps": () => json(errors.aspsp_error, 500) },
  });
  const response = await handler(post(mock));
  assertEquals(response.status, 502);
  assertEquals(await response.json(), { error: "bank_unavailable" });
  assertEquals(linkRequests, []);
});

Deno.test("a failed authorization start leaves only the unused request", async () => {
  const { handler, linkRequests } = setup({
    eb: { "POST /auth": () => json(errors.wrong_parameters, 400) },
  });
  const response = await handler(post(mock));
  assertEquals(response.status, 502);
  assertEquals(await response.json(), { error: "bank_error" });
  assertEquals(linkRequests.length, 1);
});

Deno.test("a member not eligible gets no request", async () => {
  const { handler, project } = setup();
  const response = await handler(
    post({ ...mock, member_id: "00000000-0000-4000-8000-0000000000e9" }),
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "member_not_eligible" });
  assertEquals(project.ebRequests.length, 0);
});

Deno.test("a missing redirect URL is internal", async () => {
  const { handler, project } = setup({ env: { EB_REDIRECT_URL: undefined } });
  const response = await handler(post(mock));
  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "internal" });
  assertEquals(project.rpcCalls.length, 0);
});

Deno.test("other methods: 405", async () => {
  const { handler } = setup();
  const response = await handler(new Request(URL_, { method: "PUT" }));
  assertEquals(response.status, 405);
  assertEquals(response.headers.get("Allow"), "POST");
});
