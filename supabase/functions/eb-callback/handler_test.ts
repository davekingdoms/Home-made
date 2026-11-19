import { assert, assertEquals } from "@std/assert";
import { createHandler } from "./handler.ts";
import type { NewEbClient } from "../_shared/eb/factory.ts";
import { newEbClient } from "../_shared/eb/factory.ts";
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
  pgError,
  RETURN_URL,
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
const bankSession = await testdata("session-bank-card.json");
const paypalSession = await testdata("session-paypal.json");
const bankBalances = await testdata("balances.json");
const cardBalances = await testdata("balances-card.json");
const paypalBalances = await testdata("balances-paypal.json");
const errors = await testdata("errors.json") as Record<string, unknown>;

const URL_ = `${SUPABASE_URL}/functions/v1/eb-callback`;
const BANK_REQUEST = "00000000-0000-4000-8000-0000000000c1";
const PAYPAL_REQUEST = "00000000-0000-4000-8000-0000000000c2";
const GLOBAL_REQUEST = "00000000-0000-4000-8000-0000000000c3";
const BRUNO_REQUEST = "00000000-0000-4000-8000-0000000000c4";
const CODE = "codice-di-prova-0001";
const CONNECTION_ID = "00000000-0000-4000-8000-0000000000e1";
const ACCOUNT_UID = {
  bank: "00000000-0000-4000-8000-0000000000a1",
  card: "00000000-0000-4000-8000-0000000000a2",
  paypal: "00000000-0000-4000-8000-0000000000a4",
};
/** Values of the session that must never reach a log or the URL. */
const SESSION_VALUES = [
  "00000000-0000-4000-8000-000000000002",
  "IT60X0542811101000000123456",
  "IT60 X054",
  "000000******0000",
  "Carta di Prova Oro",
  "Banca di Prova",
  "1234.56",
  "123456",
  "-50.00",
  "anna.paypal@example.com",
  ...Object.values(ACCOUNT_UID),
];
/** A DETAIL of a failed write, invented: the values of a row. */
const DETAIL =
  "Key (connection_id, provider_account_id)=(00000000-0000-4000-8000-0000000000e1, conto-di-prova-9) already exists.";

const REQUESTS: Record<string, Record<string, unknown>> = {
  [BANK_REQUEST]: {
    member_id: ANNA.memberId,
    aspsp_name: "Banca di Prova",
    aspsp_country: "IT",
    uses_global_app: false,
  },
  [PAYPAL_REQUEST]: {
    member_id: ANNA.memberId,
    aspsp_name: "PayPal",
    aspsp_country: "IT",
    uses_global_app: false,
  },
  [GLOBAL_REQUEST]: {
    member_id: ANNA.memberId,
    aspsp_name: "Banca di Prova",
    aspsp_country: "IT",
    uses_global_app: true,
  },
  [BRUNO_REQUEST]: {
    member_id: BRUNO.memberId,
    aspsp_name: "Banca di Prova",
    aspsp_country: "IT",
    uses_global_app: false,
  },
};

function setup(options: {
  eb?: Record<string, EbHandler>;
  rpc?: Record<string, RpcHandler>;
  env?: Record<string, string | undefined>;
  newEbClient?: NewEbClient;
} = {}) {
  const finished: Record<string, unknown>[] = [];
  const completed: Record<string, unknown>[] = [];
  const project = fakeProject({
    eb: {
      "POST /sessions": () => json(bankSession),
      [`GET /accounts/${ACCOUNT_UID.bank}/balances`]: () => json(bankBalances),
      [`GET /accounts/${ACCOUNT_UID.card}/balances`]: () => json(cardBalances),
      [`GET /accounts/${ACCOUNT_UID.paypal}/balances`]: () =>
        json(paypalBalances),
      ...options.eb,
    },
    rpc: {
      claim_link_request: (args) => {
        const row = REQUESTS[String(args.id)];
        return row === undefined ? [] : [{ id: args.id, ...row }];
      },
      eb_get_credentials: credentialsRpc({
        [ANNA.userId]: { appId: ANNA.appId, keys: annaKeys },
        [BRUNO.userId]: { appId: BRUNO.appId, keys: brunoKeys },
      }),
      complete_bank_link: (args) => {
        completed.push(args);
        return [{ connection_id: CONNECTION_ID, account_count: 2 }];
      },
      finish_link_request: (args) => {
        finished.push(args);
        return new Response(null, { status: 204 });
      },
      ...options.rpc,
    },
  });
  const { handler, lines } = capturedHandler(createHandler({
    env: testEnv(options.env),
    fetch: project.fetch,
    newEbClient: options.newEbClient,
  }));
  return { handler, project, finished, completed, lines };
}

function callback(query: string, method = "GET") {
  return new Request(`${URL_}${query}`, { method });
}

/** The redirect, with only `esito` and `codice` in its query. */
function assertRedirect(
  response: Response,
  esito: string,
  codice?: string,
) {
  assertEquals(response.status, 302);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(response.headers.get("Referrer-Policy"), "no-referrer");
  const expected = codice === undefined
    ? `${RETURN_URL}?esito=${esito}`
    : `${RETURN_URL}?esito=${esito}&codice=${codice}`;
  assertEquals(response.headers.get("Location"), expected);
}

function assertCleanLogs(lines: string[], extra: string[] = []) {
  assertNothingSensitive(lines, [
    BANK_REQUEST,
    PAYPAL_REQUEST,
    GLOBAL_REQUEST,
    CODE,
    ANNA.memberId,
    ANNA.userId,
    ANNA.appId,
    SECRET_KEY,
    ...SESSION_VALUES,
    ...extra,
  ]);
}

Deno.test("bank and card: connection, accounts and balances in one call", async () => {
  const { handler, completed, finished, lines, project } = setup();
  const response = await handler(
    callback(`?code=${CODE}&state=${BANK_REQUEST}`),
  );
  assertRedirect(response, "ok");

  assertEquals(completed, [{
    request_id: BANK_REQUEST,
    link: {
      session_id: "00000000-0000-4000-8000-000000000002",
      valid_until: "2031-08-28T10:00:00.000000+00:00",
      accounts: [
        {
          uid: ACCOUNT_UID.bank,
          kind: "bank",
          cash_account_type: "CACC",
          currency: "EUR",
          identifier: "IT60X0542811101000000123456",
          display_name: "Banca di Prova …3456",
          paypal_email: null,
          balances: [{
            currency: "EUR",
            balance_type: "CLBD",
            amount_cents: 123456,
            reference_date: "2031-03-04",
          }],
        },
        {
          uid: ACCOUNT_UID.card,
          kind: "card",
          cash_account_type: "CARD",
          currency: "EUR",
          identifier: "000000******0000",
          display_name: "Carta di Prova Oro …0000",
          paypal_email: null,
          balances: [
            {
              currency: "EUR",
              balance_type: "CLBD",
              amount_cents: -5000,
              reference_date: "2031-03-04",
            },
            {
              currency: "EUR",
              balance_type: "OTHR",
              amount_cents: 145000,
              reference_date: null,
            },
          ],
        },
      ],
    },
  }]);
  assertEquals(finished, []);

  const session = project.ebRequests[0]!;
  assertEquals(await session.json(), { code: CODE });
  const token = session.headers.get("Authorization")!.slice("Bearer ".length);
  assertEquals(
    (await verifyJwt(token, annaKeys.publicKey)).header.kid,
    ANNA.appId,
  );

  assert(lines.some((line) => line.includes('step: "accounts_skipped"')));
  assert(lines.some((line) => line.includes("count: 1")));
  assertCleanLogs(lines, token.split("."));
});

Deno.test("PayPal in several currencies: the email of the account", async () => {
  const { handler, completed, lines } = setup({
    eb: { "POST /sessions": () => json(paypalSession) },
  });
  const response = await handler(
    callback(`?state=${PAYPAL_REQUEST}&code=${CODE}`),
  );
  assertRedirect(response, "ok");
  const link = completed[0]?.link as { accounts: unknown[] };
  assertEquals(link.accounts, [{
    uid: ACCOUNT_UID.paypal,
    kind: "paypal",
    cash_account_type: "OTHR",
    currency: "XXX",
    identifier: "anna.paypal@example.com",
    display_name: "anna.paypal@example.com",
    paypal_email: "anna.paypal@example.com",
    balances: [
      {
        currency: "EUR",
        balance_type: "XPCD",
        amount_cents: 2500,
        reference_date: "2031-03-04",
      },
      {
        currency: "USD",
        balance_type: "XPCD",
        amount_cents: 1050,
        reference_date: "2031-03-04",
      },
    ],
  }]);
  assertCleanLogs(lines, ["anna.paypal"]);
});

Deno.test("a balance that cannot be read leaves only that account without balances", async () => {
  const { handler, completed, lines } = setup({
    eb: {
      [`GET /accounts/${ACCOUNT_UID.card}/balances`]: () =>
        json(errors.aspsp_error, 500),
    },
  });
  assertRedirect(
    await handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "ok",
  );
  const accounts = (completed[0]?.link as {
    accounts: { uid: string; balances: unknown[] }[];
  }).accounts;
  assertEquals(accounts.map((a) => [a.uid, a.balances.length]), [
    [ACCOUNT_UID.bank, 1],
    [ACCOUNT_UID.card, 0],
  ]);
  assert(lines.some((line) => line.includes('code: "bank_unavailable"')));
});

Deno.test("state missing, malformed or repeated: link_expired without the database", async () => {
  for (
    const query of [
      `?code=${CODE}`,
      `?code=${CODE}&state=non-uno-uuid`,
      `?code=${CODE}&state=${BANK_REQUEST}&state=${BANK_REQUEST}`,
      "",
    ]
  ) {
    const { handler, project } = setup();
    assertRedirect(await handler(callback(query)), "errore", "link_expired");
    assertEquals(project.rpcCalls.length, 0);
    assertEquals(project.ebRequests.length, 0);
  }
});

Deno.test("unknown, expired or used state: link_expired", async () => {
  const { handler, project, finished } = setup();
  assertRedirect(
    await handler(
      callback(`?code=${CODE}&state=00000000-0000-4000-8000-0000000000ff`),
    ),
    "errore",
    "link_expired",
  );
  assertEquals(project.rpcCalls.map((call) => call.name), [
    "claim_link_request",
  ]);
  assertEquals(finished, []);
});

Deno.test("cancelled by the person: annullato, link_cancelled", async () => {
  const { handler, project, finished } = setup();
  assertRedirect(
    await handler(callback(
      `?error=access_denied&error_description=annullato&state=${BANK_REQUEST}`,
    )),
    "annullato",
    "link_cancelled",
  );
  assertEquals(finished, [{
    request_id: BANK_REQUEST,
    result: "link_cancelled",
  }]);
  assertEquals(project.ebRequests.length, 0);
});

Deno.test("any other error of the bank: link_rejected, even with a code", async () => {
  const { handler, finished, project } = setup();
  assertRedirect(
    await handler(
      callback(`?error=server_error&code=${CODE}&state=${BANK_REQUEST}`),
    ),
    "errore",
    "link_rejected",
  );
  assertEquals(finished, [{
    request_id: BANK_REQUEST,
    result: "link_rejected",
  }]);
  assertEquals(project.ebRequests.length, 0);
});

Deno.test("no code: link_failed", async () => {
  for (
    const query of [`?state=${BANK_REQUEST}`, `?state=${BANK_REQUEST}&code=`]
  ) {
    const { handler, finished } = setup();
    assertRedirect(await handler(callback(query)), "errore", "link_failed");
    assertEquals(finished, [{
      request_id: BANK_REQUEST,
      result: "link_failed",
    }]);
  }
});

Deno.test("an error of Enable Banking: link_failed and nothing completed", async () => {
  const { handler, finished, completed, lines } = setup({
    eb: { "POST /sessions": () => json(errors.wrong_parameters, 400) },
  });
  assertRedirect(
    await handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "errore",
    "link_failed",
  );
  assertEquals(completed, []);
  assertEquals(finished, [{ request_id: BANK_REQUEST, result: "link_failed" }]);
  assertCleanLogs(lines, ["Wrong request parameters"]);
});

Deno.test("an error of the database: its DETAIL reaches neither logs nor URL", async () => {
  const message =
    'duplicate key value violates unique constraint "accounts_provider_account_unique"';
  const { handler, finished, lines } = setup({
    rpc: { complete_bank_link: () => pgError(409, "23505", message, DETAIL) },
  });
  const response = await handler(
    callback(`?code=${CODE}&state=${BANK_REQUEST}`),
  );
  assertRedirect(response, "errore", "link_failed");
  assertEquals(await response.text(), "");
  assertEquals(finished, [{ request_id: BANK_REQUEST, result: "link_failed" }]);
  assert(lines.some((line) => line.includes('code: "23505"')));
  assertCleanLogs(lines, [
    DETAIL,
    "conto-di-prova-9",
    "already exists",
    "violates",
    "accounts_provider_account_unique",
  ]);
});

Deno.test("finish_link_request failing too: same redirect, only the code logged", async () => {
  const { handler, lines } = setup({
    eb: { "POST /sessions": () => json(errors.unauthorized, 401) },
    rpc: {
      finish_link_request: () =>
        pgError(400, "P0001", "link_not_claimable", DETAIL),
    },
  });
  assertRedirect(
    await handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "errore",
    "link_failed",
  );
  assert(lines.some((line) => line.includes('code: "link_not_claimable"')));
  assertCleanLogs(lines, [DETAIL]);
});

Deno.test("a claim that fails: link_failed without an outcome to write", async () => {
  const { handler, finished } = setup({
    rpc: {
      claim_link_request: () => pgError(503, "57P01", "terminating", DETAIL),
    },
  });
  assertRedirect(
    await handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "errore",
    "link_failed",
  );
  assertEquals(finished, []);
});

Deno.test("a member who left, or credentials gone: link_failed", async () => {
  const left = setup({
    rpc: {
      eb_service_member: () => pgError(400, "P0001", "member_not_eligible"),
    },
  });
  assertRedirect(
    await left.handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "errore",
    "link_failed",
  );
  assertEquals(left.project.ebRequests.length, 0);

  const gone = setup({
    rpc: { eb_get_credentials: () => [] },
    env: {
      EB_GLOBAL_APP_ID: GLOBAL_APP_ID,
      EB_GLOBAL_PRIVATE_KEY: globalKeys.pkcs8Pem,
    },
  });
  assertRedirect(
    await gone.handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "errore",
    "link_failed",
  );
  assertEquals(gone.project.ebRequests.length, 0);
  assertEquals(gone.finished, [{
    request_id: BANK_REQUEST,
    result: "link_failed",
  }]);
});

Deno.test("a link started with the global application returns with it", async () => {
  const { handler, project } = setup({
    env: {
      EB_GLOBAL_APP_ID: GLOBAL_APP_ID,
      EB_GLOBAL_PRIVATE_KEY: globalKeys.pkcs8Pem,
    },
  });
  assertRedirect(
    await handler(callback(`?code=${CODE}&state=${GLOBAL_REQUEST}`)),
    "ok",
  );
  assertEquals(
    project.rpcCalls.some((call) => call.name === "eb_get_credentials"),
    false,
  );
  const token = project.ebRequests[0]!.headers.get("Authorization")!
    .slice("Bearer ".length);
  assertEquals(
    (await verifyJwt(token, globalKeys.publicKey)).header.kid,
    GLOBAL_APP_ID,
  );
});

Deno.test("one client for each callback and person", async () => {
  const created: string[] = [];
  const spy: NewEbClient = (options) => {
    created.push(options.appId);
    return newEbClient(options);
  };
  const { handler, project } = setup({ newEbClient: spy });
  assertRedirect(
    await handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "ok",
  );
  const annaCount = project.ebRequests.length;
  assertRedirect(
    await handler(callback(`?code=${CODE}&state=${BRUNO_REQUEST}`)),
    "ok",
  );
  assertEquals(created, [ANNA.appId, BRUNO.appId]);
  const tokens = project.ebRequests.map((request) =>
    request.headers.get("Authorization")!.slice("Bearer ".length)
  );
  for (const token of tokens.slice(0, annaCount)) {
    assertEquals(
      (await verifyJwt(token, annaKeys.publicKey)).header.kid,
      ANNA.appId,
    );
  }
  for (const token of tokens.slice(annaCount)) {
    assertEquals(
      (await verifyJwt(token, brunoKeys.publicKey)).header.kid,
      BRUNO.appId,
    );
    assert(!tokens.slice(0, annaCount).includes(token));
  }
});

Deno.test("missing variables: no return URL is internal, the others link_failed", async () => {
  const noReturn = setup({ env: { APP_RETURN_URL: undefined } });
  const response = await noReturn.handler(
    callback(`?code=${CODE}&state=${BANK_REQUEST}`),
  );
  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "internal" });

  const noKeys = setup({ env: { SUPABASE_SECRET_KEYS: undefined } });
  assertRedirect(
    await noKeys.handler(callback(`?code=${CODE}&state=${BANK_REQUEST}`)),
    "errore",
    "link_failed",
  );
  assertEquals(noKeys.project.rpcCalls.length, 0);
});

Deno.test("other methods: 405, no redirect", async () => {
  for (const method of ["POST", "PUT", "DELETE"]) {
    const { handler, project } = setup();
    const response = await handler(
      callback(`?code=${CODE}&state=${BANK_REQUEST}`, method),
    );
    assertEquals(response.status, 405);
    assertEquals(response.headers.get("Allow"), "GET");
    assertEquals(response.headers.get("Location"), null);
    assertEquals(project.rpcCalls.length, 0);
  }
});
