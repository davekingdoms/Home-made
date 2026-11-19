import { assert, assertEquals, assertFalse, assertRejects } from "@std/assert";
import {
  EnableBankingClient,
  type EnableBankingClientOptions,
} from "./client.ts";
import { EbError, type SyncErrorCode } from "./errors.ts";
import { importPrivateKey } from "./jwt.ts";
import type { StartAuthRequest } from "./types.ts";
import {
  fakeFetch,
  type Handler,
  json,
  testdata,
} from "../testing/fake_fetch.ts";
import { armor, generateTestKeys, verifyJwt } from "../testing/rsa.ts";

const keys = await generateTestKeys();
const errors = await testdata("errors.json") as Record<
  string,
  Record<string, unknown>
>;

const APP_ID = "00000000-0000-4000-8000-00000000a99a";
const SESSION_ID = "00000000-0000-4000-8000-000000000001";
const ACCOUNT_UID = "00000000-0000-4000-8000-0000000000a1";
const BASE = "https://api.enablebanking.com";
const PAGE_2_KEY = "pagina-2";

const AUTH_REQUEST: StartAuthRequest = {
  access: { valid_until: "2031-08-28T10:00:00Z" },
  aspsp: { name: "Mock ASPSP", country: "IT" },
  state: "00000000-0000-4000-8000-0000000000c1",
  redirect_url: "https://example.com/functions/v1/eb-callback",
  psu_type: "personal",
};

function setup(
  handler: Handler,
  options: Partial<EnableBankingClientOptions> = {},
) {
  const fake = fakeFetch(handler);
  const client = new EnableBankingClient({
    appId: APP_ID,
    privateKey: keys.pkcs8Pem,
    fetch: fake.fetch,
    ...options,
  });
  return { client, requests: fake.requests };
}

async function bearer(request: Request | undefined): Promise<string> {
  const header = request?.headers.get("Authorization") ?? "";
  assert(header.startsWith("Bearer "), "missing Bearer token");
  const token = header.slice("Bearer ".length);
  const { header: jwtHeader, payload } = await verifyJwt(token, keys.publicKey);
  assertEquals(jwtHeader.kid, APP_ID);
  assertEquals(payload.iss, "enablebanking.com");
  assertEquals(payload.aud, "api.enablebanking.com");
  return token;
}

interface CallCase {
  name: string;
  run: (client: EnableBankingClient) => Promise<unknown>;
  method: "GET" | "POST";
  url: string;
  body?: unknown;
  response: string;
}

const CALLS: CallCase[] = [
  {
    name: "getAspsps",
    run: (client) => client.getAspsps("IT"),
    method: "GET",
    url: `${BASE}/aspsps?country=IT`,
    response: "aspsps.json",
  },
  {
    name: "getAspsps without country",
    run: (client) => client.getAspsps(),
    method: "GET",
    url: `${BASE}/aspsps`,
    response: "aspsps.json",
  },
  {
    name: "startAuth",
    run: (client) => client.startAuth(AUTH_REQUEST),
    method: "POST",
    url: `${BASE}/auth`,
    body: AUTH_REQUEST,
    response: "auth.json",
  },
  {
    name: "createSession",
    run: (client) => client.createSession("codice-di-prova"),
    method: "POST",
    url: `${BASE}/sessions`,
    body: { code: "codice-di-prova" },
    response: "session.json",
  },
  {
    name: "getSession",
    run: (client) => client.getSession(SESSION_ID),
    method: "GET",
    url: `${BASE}/sessions/${SESSION_ID}`,
    response: "session-status.json",
  },
  {
    name: "getAccountDetails",
    run: (client) => client.getAccountDetails(ACCOUNT_UID),
    method: "GET",
    url: `${BASE}/accounts/${ACCOUNT_UID}/details`,
    response: "account-details.json",
  },
  {
    name: "getBalances",
    run: (client) => client.getBalances(ACCOUNT_UID),
    method: "GET",
    url: `${BASE}/accounts/${ACCOUNT_UID}/balances`,
    response: "balances.json",
  },
  {
    name: "getTransactions with date_from only",
    run: (client) =>
      client.getTransactions(ACCOUNT_UID, { dateFrom: "2031-03-01" }),
    method: "GET",
    url: `${BASE}/accounts/${ACCOUNT_UID}/transactions?date_from=2031-03-01`,
    response: "transactions-page-1.json",
  },
  {
    name: "getTransactions with every parameter",
    run: (client) =>
      client.getTransactions(ACCOUNT_UID, {
        dateFrom: "2031-03-01",
        dateTo: "2031-03-31",
        strategy: "longest",
        continuationKey: PAGE_2_KEY,
      }),
    method: "GET",
    url: `${BASE}/accounts/${ACCOUNT_UID}/transactions` +
      `?date_from=2031-03-01&date_to=2031-03-31&strategy=longest` +
      `&continuation_key=${PAGE_2_KEY}`,
    response: "transactions-page-2.json",
  },
];

for (const call of CALLS) {
  Deno.test(`${call.name}: method, path, parameters and Authorization`, async () => {
    const response = await testdata(call.response);
    const { client, requests } = setup(() => json(response));

    assertEquals(await call.run(client), response);

    assertEquals(requests.length, 1);
    const request = requests[0]!;
    assertEquals(request.method, call.method);
    assertEquals(request.url, call.url);
    assertEquals(request.headers.get("Accept"), "application/json");
    await bearer(request);
    if (call.body === undefined) {
      assertEquals(request.body, null);
    } else {
      assertEquals(request.headers.get("Content-Type"), "application/json");
      assertEquals(await request.json(), call.body);
    }
  });
}

Deno.test("path segments are encoded", async () => {
  const { client, requests } = setup(() => json({ balances: [] }));
  await client.getBalances("a/b?c");
  assertEquals(requests[0]?.url, `${BASE}/accounts/a%2Fb%3Fc/balances`);
});

Deno.test("baseUrl replaces the production API", async () => {
  const { client, requests } = setup(() => json({ aspsps: [] }), {
    baseUrl: "https://eb.example.com/",
  });
  await client.getAspsps("IT");
  assertEquals(requests[0]?.url, "https://eb.example.com/aspsps?country=IT");
});

Deno.test("dates other than YYYY-MM-DD are refused before any call", async () => {
  const { client, requests } = setup(() => json({ transactions: [] }));
  await assertRejects(
    () => client.getTransactions(ACCOUNT_UID, { dateFrom: "01/03/2031" }),
    RangeError,
  );
  await assertRejects(
    () =>
      client.getTransactions(ACCOUNT_UID, {
        dateFrom: "2031-03-01",
        dateTo: "2031-3-31",
      }),
    RangeError,
  );
  assertEquals(requests.length, 0);
});

Deno.test("the JWT is reused and signed again close to its expiry", async () => {
  let now = 1_930_000_000_000;
  const { client, requests } = setup(() => json({ aspsps: [] }), {
    now: () => now,
  });
  await client.getAspsps();
  await client.getAspsps();
  now += (3600 - 301) * 1000; // 301 s left: still valid
  await client.getAspsps();
  now += 2 * 1000; // 299 s left: renewed
  await client.getAspsps();

  const tokens = await Promise.all(requests.map(bearer));
  assertEquals(tokens[1], tokens[0]);
  assertEquals(tokens[2], tokens[0]);
  assert(tokens[3] !== tokens[0], "the JWT was not renewed");
  const { payload } = await verifyJwt(tokens[3]!, keys.publicKey);
  assertEquals(payload.iat, Math.floor(now / 1000));
  assertEquals(payload.exp, Math.floor(now / 1000) + 3600);
});

Deno.test("PKCS#1 key and imported CryptoKey work too", async () => {
  for (
    const privateKey of [keys.pkcs1Pem, await importPrivateKey(keys.pkcs8Pem)]
  ) {
    const { client, requests } = setup(() => json({ aspsps: [] }), {
      privateKey,
    });
    await client.getAspsps();
    await bearer(requests[0]);
  }
});

Deno.test("invalid key: invalid_credentials, no request sent", async () => {
  const { client, requests } = setup(() => json({ aspsps: [] }), {
    privateKey: armor("PRIVATE KEY", "AAAA"),
  });
  const error = await assertRejects(() => client.getAspsps(), EbError);
  assertEquals(error.code, "invalid_credentials");
  assertEquals(requests.length, 0);
});

Deno.test("empty application ID: invalid_credentials", () => {
  try {
    new EnableBankingClient({ appId: " ", privateKey: keys.pkcs8Pem });
    throw new Error("no error");
  } catch (error) {
    assert(error instanceof EbError);
    assertEquals(error.code, "invalid_credentials");
  }
});

// --- Pagination ---------------------------------------------------------

function pagedHandler(failure?: Response): Handler {
  return async (request) => {
    const key = new URL(request.url).searchParams.get("continuation_key");
    if (key === null) return json(await testdata("transactions-page-1.json"));
    if (failure !== undefined) return failure;
    assertEquals(key, PAGE_2_KEY);
    return json(await testdata("transactions-page-2.json"));
  };
}

Deno.test("getAllTransactions: follows continuation_key to the last page", async () => {
  const { client, requests } = setup(pagedHandler());
  const transactions = await client.getAllTransactions(ACCOUNT_UID, {
    dateFrom: "2031-03-01",
    strategy: "longest",
  });

  assertEquals(
    transactions.map((row) => row.transaction_amount.amount),
    ["12.50", "4.4", "1"],
  );
  assertEquals(requests.length, 2);
  const first = new URL(requests[0]!.url).searchParams;
  const second = new URL(requests[1]!.url).searchParams;
  assertEquals(first.get("continuation_key"), null);
  assertEquals(second.get("continuation_key"), PAGE_2_KEY);
  for (const params of [first, second]) {
    assertEquals(params.get("date_from"), "2031-03-01");
    assertEquals(params.get("strategy"), "longest");
  }
});

Deno.test("getAllTransactions: a failed page fails the whole account", async () => {
  for (
    const [failure, code] of [
      [json(errors.aspsp_error, 500), "bank_unavailable"],
      [json(errors.rate_limited, 429), "rate_limited"],
      [new Response("{", { status: 200 }), "bank_error"],
    ] as const
  ) {
    const { client, requests } = setup(pagedHandler(failure));
    const error = await assertRejects(
      () => client.getAllTransactions(ACCOUNT_UID, { dateFrom: "2031-03-01" }),
      EbError,
    );
    assertEquals(error.code, code);
    assertEquals(requests.length, 2);
  }
});

Deno.test("getAllTransactions: a repeated continuation_key stops", async () => {
  const { client, requests } = setup(() =>
    json({ transactions: [], continuation_key: PAGE_2_KEY })
  );
  const error = await assertRejects(
    () => client.getAllTransactions(ACCOUNT_UID, { dateFrom: "2031-03-01" }),
    EbError,
  );
  assertEquals(error.code, "bank_error");
  assertEquals(requests.length, 2);
});

// --- Errors -------------------------------------------------------------

interface ErrorCase {
  name: string;
  response: () => Response;
  code: SyncErrorCode;
  status: number;
  bankText?: string;
}

const ERROR_CASES: ErrorCase[] = [
  {
    name: "422 WRONG_TRANSACTIONS_PERIOD saying the consent expired",
    response: () => json(errors.wrong_period_consent_expired, 422),
    code: "period_rejected",
    status: 422,
    bankText: "Consent expired",
  },
  {
    name: "429 ASPSP_RATE_LIMIT_EXCEEDED",
    response: () => json(errors.rate_limited, 429),
    code: "rate_limited",
    status: 429,
    bankText: "Rate limit exceeded",
  },
  {
    name: "429 without a body",
    response: () => new Response(null, { status: 429 }),
    code: "rate_limited",
    status: 429,
  },
  {
    name: "401 rejected credentials",
    response: () => json(errors.unauthorized, 401),
    code: "invalid_credentials",
    status: 401,
    bankText: "Unauthorized access",
  },
  {
    name: "EXPIRED_SESSION",
    response: () => json(errors.expired_session, 422),
    code: "consent_expired",
    status: 422,
  },
  {
    name: "REVOKED_SESSION",
    response: () => json(errors.revoked_session, 422),
    code: "consent_revoked",
    status: 422,
  },
  {
    name: "500 ASPSP_ERROR",
    response: () => json(errors.aspsp_error, 500),
    code: "bank_unavailable",
    status: 500,
    bankText: "Error interacting",
  },
  {
    name: "503 with an HTML page",
    response: () =>
      new Response("<html>Servizio non disponibile</html>", { status: 503 }),
    code: "bank_unavailable",
    status: 503,
    bankText: "Servizio non disponibile",
  },
  {
    name: "400 WRONG_REQUEST_PARAMETERS",
    response: () => json(errors.wrong_parameters, 400),
    code: "bank_error",
    status: 400,
    bankText: "Wrong request parameters",
  },
  {
    name: "404 without a body",
    response: () => new Response(null, { status: 404 }),
    code: "bank_error",
    status: 404,
  },
];

for (const errorCase of ERROR_CASES) {
  Deno.test(`error ${errorCase.name} → ${errorCase.code}`, async () => {
    const { client } = setup(errorCase.response);
    const error = await assertRejects(
      () => client.getTransactions(ACCOUNT_UID, { dateFrom: "2031-03-01" }),
      EbError,
    );
    assertEquals(error.code, errorCase.code);
    assertEquals(error.status, errorCase.status);
    if (errorCase.bankText !== undefined) {
      const text = errorCase.bankText;
      assert(JSON.stringify(error.detail ?? "").includes(text), "detail lost");
      assertFalse(error.message.includes(text), "bank text in message");
      assertFalse(String(error.stack).includes(text), "bank text in stack");
      assertFalse(JSON.stringify(error).includes(text), "bank text in JSON");
      assertFalse(Deno.inspect(error).includes(text), "bank text in inspect");
    }
  });
}

Deno.test("timeout before the response: bank_unavailable", async () => {
  const { client } = setup(
    (request) =>
      new Promise((_, reject) => {
        request.signal.addEventListener("abort", () =>
          reject(request.signal.reason));
      }),
    { timeoutMs: 10 },
  );
  const error = await assertRejects(() => client.getAspsps("IT"), EbError);
  assertEquals(error.code, "bank_unavailable");
  assertEquals(error.status, undefined);
});

Deno.test("timeout while reading the body: bank_unavailable", async () => {
  const { client } = setup(
    (request) =>
      new Response(
        new ReadableStream({
          start(controller) {
            request.signal.addEventListener(
              "abort",
              () => controller.error(request.signal.reason),
            );
          },
        }),
      ),
    { timeoutMs: 10 },
  );
  const error = await assertRejects(() => client.getAspsps("IT"), EbError);
  assertEquals(error.code, "bank_unavailable");
});

Deno.test("network failure: bank_unavailable", async () => {
  const { client } = setup(() => {
    throw new TypeError("connection refused");
  });
  const error = await assertRejects(() => client.getAspsps("IT"), EbError);
  assertEquals(error.code, "bank_unavailable");
});

Deno.test("unexpected success body: bank_error", async () => {
  for (const body of ["not json", "[]", JSON.stringify({ transactions: {} })]) {
    const { client } = setup(() => new Response(body, { status: 200 }));
    const error = await assertRejects(
      () => client.getTransactions(ACCOUNT_UID, { dateFrom: "2031-03-01" }),
      EbError,
    );
    assertEquals(error.code, "bank_error");
  }
});
