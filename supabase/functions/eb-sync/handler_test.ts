import { assert, assertEquals, assertFalse } from "@std/assert";
import { createHandler } from "./handler.ts";
import type { NewEbClient } from "../_shared/eb/factory.ts";
import { newEbClient } from "../_shared/eb/factory.ts";
import type { LogEntry } from "../_shared/log.ts";
import type {
  EbHandler,
  RpcHandler,
} from "../_shared/testing/fake_supabase.ts";
import {
  ANNA,
  assertNothingSensitive,
  credentialsRpc,
  fakeProject,
  GLOBAL_APP_ID,
  OTHER_SECRET_KEY,
  pgError,
  PUBLISHABLE_KEY,
  SECRET_KEY,
  SUPABASE_URL,
  testEnv,
} from "../_shared/testing/fake_supabase.ts";
import { json, testdata } from "../_shared/testing/fake_fetch.ts";
import { generateTestKeys, verifyJwt } from "../_shared/testing/rsa.ts";
import { withConsole } from "../_shared/testing/console.ts";

type Page = { transactions: Record<string, unknown>[] };

const annaKeys = await generateTestKeys();
const globalKeys = await generateTestKeys();
const sessionStatus = await testdata("session-status.json") as Record<
  string,
  unknown
>;
const errors = await testdata("errors.json") as Record<string, unknown>;
const caccPage1 = await testdata("credem-cacc/transactions-page-1.json");
const caccPage2 = await testdata("credem-cacc/transactions-page-2.json");
const caccBalances = await testdata("credem-cacc/balances.json");
const cardDay1 = await testdata("credem-card/transactions-day-1.json") as Page;
const cardBalances = await testdata("credem-card/balances.json");
const paypalSync1 = await testdata("paypal/transactions-anna-sync-1.json");
const paypalBalances = await testdata("paypal/balances.json");
const invalidRows = await testdata("transactions-invalid.json") as Page;

const URL_ = `${SUPABASE_URL}/functions/v1/eb-sync`;
const RUN_ID = "00000000-0000-4000-8000-0000000000f9";
const CONNECTION_ID = "00000000-0000-4000-8000-0000000000e1";
const SESSION_ID = "00000000-0000-4000-8000-0000000000c0";
const JOB_SECRET = "segreto-dei-job-di-prova";
const NOW = Date.parse("2031-03-20T10:00:00Z");

interface AccountRow {
  id: string;
  provider_account_id: string;
  kind: string;
  cash_account_type: string;
  archived_at: string | null;
}

const CACC: AccountRow = {
  id: "00000000-0000-4000-8000-0000000000c1",
  provider_account_id: "00000000-0000-4000-8000-00000000c001",
  kind: "bank",
  cash_account_type: "CACC",
  archived_at: null,
};
const CARD: AccountRow = {
  id: "00000000-0000-4000-8000-0000000000c2",
  provider_account_id: "00000000-0000-4000-8000-00000000c002",
  kind: "card",
  cash_account_type: "CARD",
  archived_at: null,
};
const PAYPAL: AccountRow = {
  id: "00000000-0000-4000-8000-0000000000c4",
  provider_account_id: "00000000-0000-4000-8000-00000000e001",
  kind: "paypal",
  cash_account_type: "OTHR",
  archived_at: null,
};
const ARCHIVED: AccountRow = {
  id: "00000000-0000-4000-8000-0000000000c9",
  provider_account_id: "00000000-0000-4000-8000-00000000c009",
  kind: "bank",
  cash_account_type: "CACC",
  archived_at: "2031-03-15T10:00:00+00:00",
};

/** Values of the bank and of the database that never reach a log. */
const SENSITIVE = [
  SESSION_ID,
  CONNECTION_ID,
  RUN_ID,
  JOB_SECRET,
  SECRET_KEY,
  ANNA.userId,
  ANNA.appId,
  ...[CACC, CARD, PAYPAL].flatMap((a) => [a.id, a.provider_account_id]),
  "IT00A0000000000000000001234",
  "2345.67",
  "120.50",
  "EMOLUMENTI",
  "BANCOMAT",
  "DITTA ESEMPIO",
  "CAFFE PROVA",
  "example.com",
  "Credito Emiliano",
];

interface Setup {
  accounts?: AccountRow[];
  connection?: Record<string, unknown> | null;
  /** Accounts that already have raw rows. */
  raw?: string[];
  /** Start of the last successful sync of an account. */
  lastOk?: Record<string, string>;
  eb?: Record<string, EbHandler>;
  rpc?: Record<string, RpcHandler>;
  env?: Record<string, string | undefined>;
  now?: number;
  newEbClient?: NewEbClient;
}

/** Pages by `continuation_key` (the first one under ""); else 404. */
function transactionsRoute(pages: Record<string, unknown>): EbHandler {
  return (request) => {
    const key = new URL(request.url).searchParams.get("continuation_key");
    const page = pages[key ?? ""];
    return page === undefined ? json({ error: "NOT_FOUND" }, 404) : json(page);
  };
}

function setup(options: Setup = {}) {
  const accounts = options.accounts ?? [CACC, CARD];
  const connection = options.connection === undefined
    ? {
      member_id: ANNA.memberId,
      aspsp_name: "Credito Emiliano",
      session_id: SESSION_ID,
      uses_global_app: false,
    }
    : options.connection;
  const ingested: { account_id: string; rows: Record<string, unknown>[] }[] =
    [];
  const balances: Record<string, unknown>[][] = [];
  const finished: Record<string, unknown>[] = [];
  const logs: LogEntry[] = [];
  const pending: Promise<unknown>[] = [];

  const project = fakeProject({
    eb: {
      [`GET /sessions/${SESSION_ID}`]: () => json(sessionStatus),
      [`GET /accounts/${CACC.provider_account_id}/balances`]: () =>
        json(caccBalances),
      [`GET /accounts/${CARD.provider_account_id}/balances`]: () =>
        json(cardBalances),
      [`GET /accounts/${PAYPAL.provider_account_id}/balances`]: () =>
        json(paypalBalances),
      [`GET /accounts/${CACC.provider_account_id}/transactions`]:
        transactionsRoute({ "": caccPage1, "pagina-2": caccPage2 }),
      [`GET /accounts/${CARD.provider_account_id}/transactions`]: () =>
        json(cardDay1),
      [`GET /accounts/${PAYPAL.provider_account_id}/transactions`]: () =>
        json(paypalSync1),
      ...options.eb,
    },
    rest: {
      "GET bank_connections": (url) => {
        assertEquals(url.searchParams.get("id"), `eq.${CONNECTION_ID}`);
        return connection === null ? [] : [connection];
      },
      "GET accounts": (url) => {
        assertEquals(
          url.searchParams.get("connection_id"),
          `eq.${CONNECTION_ID}`,
        );
        return accounts
          .filter((a) =>
            url.searchParams.get("archived_at") !== "is.null" ||
            a.archived_at === null
          )
          .map(({ archived_at: _, ...row }) => row);
      },
      "GET bank_raw_transactions": (url) => {
        const id = url.searchParams.get("account_id")?.slice(3) ?? "";
        return (options.raw ?? []).includes(id) ? [{ id: "riga-1" }] : [];
      },
      "GET sync_runs": (url) => {
        assertEquals(url.searchParams.get("status"), "eq.ok");
        assertEquals(url.searchParams.get("order"), "started_at.desc");
        const id = url.searchParams.get("account_id")?.slice(3) ?? "";
        const startedAt = options.lastOk?.[id];
        return startedAt === undefined ? [] : [{ started_at: startedAt }];
      },
      "POST account_balances": async (url, request) => {
        assertEquals(
          url.searchParams.get("on_conflict"),
          "account_id,currency,balance_type",
        );
        balances.push(await request.json());
        return new Response(null, { status: 201 });
      },
    },
    rpc: {
      sync_secret_matches: (args) => args.secret === JOB_SECRET,
      begin_sync_run: (args) => {
        assertEquals(args.connection_id, CONNECTION_ID);
        return [{ run_id: RUN_ID, status: "running" }];
      },
      eb_get_credentials: credentialsRpc({
        [ANNA.userId]: { appId: ANNA.appId, keys: annaKeys },
      }),
      ingest_bank_rows: (args) => {
        const rows = args.rows as Record<string, unknown>[];
        ingested.push({ account_id: String(args.account_id), rows });
        const booked = rows.filter((row) => row.status === "BOOK").length;
        return [{
          rows_received: rows.length,
          raw_inserted: rows.length,
          transactions_created: booked,
          skipped_before_start: 0,
          skipped_status: rows.length - booked,
          groups_shrunk: 0,
          booked_then_cancelled: 0,
        }];
      },
      finish_sync_run: (args) => {
        finished.push(args);
        return new Response(null, { status: 204 });
      },
      settlement_candidates: () => ({ movements: [], settlements: [] }),
      apply_settlements: (args) => (args.settlements as unknown[]).length,
      transfer_candidates: () => ({ accounts: [], movements: [] }),
      apply_transfers: (args) => (args.transfers as unknown[]).length,
      ...options.rpc,
    },
  });

  const handler = createHandler({
    env: testEnv(options.env),
    fetch: project.fetch,
    newEbClient: options.newEbClient,
    log: (entry) => logs.push(entry),
    now: () => options.now ?? NOW,
    waitUntil: (promise) => pending.push(promise),
  });

  /** The answer, after the work in the background is over. */
  async function call(
    headers: Record<string, string> = { "x-sync-secret": JOB_SECRET },
    body: unknown = { connection_id: CONNECTION_ID, trigger: "admin" },
    method = "POST",
  ) {
    const { result, lines } = await withConsole(async () => {
      const response = await handler(
        new Request(URL_, {
          method,
          headers: { "Content-Type": "application/json", ...headers },
          body: method === "GET" ? undefined : JSON.stringify(body),
        }),
      );
      await Promise.all(pending);
      return response;
    });
    // Everything goes through the logger: nothing on the console.
    assertEquals(lines, []);
    return result;
  }

  return { call, project, ingested, balances, finished, logs };
}

/** The result of the run, as sent to finish_sync_run. */
function closed(finished: Record<string, unknown>[]) {
  assertEquals(finished.length, 1);
  const args = finished[0]!;
  assertEquals(args.run_id, RUN_ID);
  const result = args.result as {
    strategy: string | null;
    matched_settlements: number;
    matched_transfers: number;
    accounts: Record<string, unknown>[];
  };
  assertEquals(Object.keys(result).sort(), [
    "accounts",
    "matched_settlements",
    "matched_transfers",
    "strategy",
  ]);
  return {
    status: args.status,
    errorCode: args.error_code,
    strategy: result.strategy,
    matchedSettlements: result.matched_settlements,
    matchedTransfers: result.matched_transfers,
    accounts: result.accounts,
  };
}

function transactionRequests(requests: Request[], uid: string) {
  return requests
    .map((request) => new URL(request.url))
    .filter((url) => url.pathname === `/accounts/${uid}/transactions`)
    .map((url) => Object.fromEntries(url.searchParams));
}

/** Only fixed fields in the logs, and none of the values of the bank. */
function assertCleanLogs(logs: LogEntry[], extra: string[] = []) {
  for (const entry of logs) {
    for (const key of Object.keys(entry)) {
      assert(["fn", "step", "code", "count"].includes(key));
    }
    assertEquals(entry.fn, "eb-sync");
  }
  assertNothingSensitive(logs.map((entry) => JSON.stringify(entry)), [
    ...SENSITIVE,
    ...extra,
  ]);
}

function logged(logs: LogEntry[], step: string): LogEntry[] {
  return logs.filter((entry) => entry.step === step);
}

Deno.test("202 at once, then the sync of every account with all its pages (case 14)", async () => {
  const { call, project, ingested, balances, finished, logs } = setup();
  const response = await call();
  assertEquals(response.status, 202);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(await response.json(), {
    ok: true,
    run_id: RUN_ID,
    status: "running",
  });

  // First sync of both accounts: longest, from the start date of Anna.
  assertEquals(
    transactionRequests(project.ebRequests, CACC.provider_account_id),
    [
      { date_from: "2031-03-01", strategy: "longest" },
      {
        date_from: "2031-03-01",
        strategy: "longest",
        continuation_key: "pagina-2",
      },
    ],
  );
  assertEquals(
    transactionRequests(project.ebRequests, CARD.provider_account_id),
    [{ date_from: "2031-03-01", strategy: "longest" }],
  );

  // Both pages of the current account in one import, signed amounts.
  assertEquals(ingested.map((i) => [i.account_id, i.rows.length]), [
    [CACC.id, 12],
    [CARD.id, 7],
  ]);
  const salary = ingested[0]!.rows.find((row) =>
    row.entry_reference === "0000000000-20310305-0000105-001"
  )!;
  assertEquals(salary.amount_cents, 185000);
  assertEquals(salary.counterparty, "DITTA ESEMPIO SRL");
  assertEquals(salary.status, "BOOK");
  assertEquals(
    Object.keys(salary).sort(),
    [
      "amount_cents",
      "bank_code",
      "booking_date",
      "counterparty",
      "counterparty_email",
      "currency",
      "dedup_hash",
      "description",
      "entry_reference",
      "exchange_rate",
      "original_amount_cents",
      "original_currency",
      "payload",
      "status",
      "transaction_date",
      "value_date",
    ],
  );
  assert(ingested[1]!.rows.every((row) => (row.amount_cents as number) !== 0));
  assertEquals(ingested[1]!.rows[0]!.amount_cents, -1250);

  // Balances of both accounts, with their sign.
  assertEquals(
    balances.map((rows) =>
      rows.map((b) => [b.account_id, b.balance_type, b.amount_cents])
    ),
    [
      [[CACC.id, "CLBD", 234567]],
      [[CARD.id, "CLBD", -12050], [CARD.id, "OTHR", 137950]],
    ],
  );
  assertEquals(balances[0]![0]!.fetched_at, new Date(NOW).toISOString());

  const run = closed(finished);
  assertEquals(run.status, "ok");
  assertEquals(run.errorCode, null);
  assertEquals(run.strategy, "longest");
  assertEquals(run.accounts.map((a) => a.account_id), [CACC.id, CARD.id]);
  assertEquals(run.accounts[1], {
    account_id: CARD.id,
    status: "ok",
    strategy: "longest",
    date_from: "2031-03-01",
    history_from: "2031-03-01",
    history_incomplete: false,
    rows_received: 7,
    raw_inserted: 7,
    transactions_created: 7,
    skipped_before_start: 0,
    skipped_status: 0,
    groups_shrunk: 0,
    booked_then_cancelled: 0,
    amounts_rounded: 1,
    rows_invalid: 0,
  });

  // Steps with their duration, counts, never a value.
  assert(logged(logs, "transactions_ms").every((e) => e.count! >= 0));
  assertEquals(logged(logs, "transactions").length, 2);
  assertEquals(logged(logs, "rows_received").map((e) => e.count), [12, 7]);
  assertEquals(logged(logs, "ok"), [{ fn: "eb-sync", step: "ok", code: "ok" }]);
  assert(logged(logs, "run_ms").length === 1);
  assertCleanLogs(logs);
});

Deno.test("case 14: a failed page leaves the account out, the connection partial", async () => {
  // The second page answers with an error of the bank.
  const failing = setup({
    eb: {
      [`GET /accounts/${CACC.provider_account_id}/transactions`]: (request) =>
        new URL(request.url).searchParams.has("continuation_key")
          ? json(errors.aspsp_error, 500)
          : json(caccPage1),
    },
  });
  assertEquals((await failing.call()).status, 202);
  assertEquals(failing.ingested.map((i) => i.account_id), [CARD.id]);
  const run = closed(failing.finished);
  assertEquals(run.status, "partial");
  assertEquals(run.errorCode, "bank_unavailable");
  assertEquals(run.accounts[0], {
    account_id: CACC.id,
    status: "error",
    error_code: "bank_unavailable",
    strategy: "longest",
    date_from: "2031-03-01",
  });
  assertEquals(run.accounts[1]?.status, "ok");
  assertCleanLogs(failing.logs, ["Error interacting with ASPSP"]);

  // A second page that is not found is a failure too.
  const missing = setup({
    eb: {
      [`GET /accounts/${CACC.provider_account_id}/transactions`]:
        transactionsRoute({ "": caccPage1 }),
    },
  });
  await missing.call();
  assertEquals(missing.ingested.map((i) => i.account_id), [CARD.id]);
  const partial = closed(missing.finished);
  assertEquals([partial.status, partial.errorCode], ["partial", "bank_error"]);
  assertCleanLogs(missing.logs);
});

Deno.test("case 13: a refused period with a text about the consent: shorter period, history incomplete, still ok", async () => {
  const july = Date.parse("2031-07-15T10:00:00Z");
  const { call, project, finished, logs } = setup({
    now: july,
    accounts: [CARD],
    eb: {
      [`GET /accounts/${CARD.provider_account_id}/transactions`]: (request) =>
        new URL(request.url).searchParams.get("date_from") === "2031-03-01"
          ? json(errors.wrong_period_consent_expired, 422)
          : json(cardDay1),
    },
  });
  await call();
  assertEquals(
    transactionRequests(project.ebRequests, CARD.provider_account_id).map((
      q,
    ) => q.date_from),
    ["2031-03-01", "2031-04-17"],
  );
  const run = closed(finished);
  // Not a consent error: the connection stays active.
  assertEquals(run.status, "ok");
  assertEquals(run.errorCode, null);
  assertEquals(run.accounts[0]?.date_from, "2031-03-01");
  assertEquals(run.accounts[0]?.history_from, "2031-04-17");
  assertEquals(run.accounts[0]?.history_incomplete, true);
  assertEquals(logged(logs, "period_retry").map((e) => e.count), [1]);
  assertCleanLogs(logs, ["Consent expired", "Synthetic bank text"]);
});

Deno.test("case 13: every period refused: the account is not imported, period_rejected", async () => {
  const { call, project, ingested, finished } = setup({
    now: Date.parse("2031-07-15T10:00:00Z"),
    accounts: [CARD],
    eb: {
      [`GET /accounts/${CARD.provider_account_id}/transactions`]: () =>
        json(errors.wrong_period_consent_expired, 422),
    },
  });
  await call();
  assertEquals(
    transactionRequests(project.ebRequests, CARD.provider_account_id).map((
      q,
    ) => q.date_from),
    ["2031-03-01", "2031-04-17", "2031-05-16", "2031-06-15"],
  );
  assertEquals(ingested, []);
  const run = closed(finished);
  assertEquals(run.status, "partial");
  assertEquals(run.errorCode, "period_rejected");
  assertEquals(run.accounts[0]?.error_code, "period_rejected");
});

Deno.test("windows: PayPal the first time from 90 days before the start date", async () => {
  const { call, project, finished } = setup({
    connection: {
      member_id: ANNA.memberId,
      aspsp_name: "PayPal",
      session_id: SESSION_ID,
      uses_global_app: false,
    },
    accounts: [PAYPAL],
  });
  await call();
  assertEquals(
    transactionRequests(project.ebRequests, PAYPAL.provider_account_id),
    [{ date_from: "2030-12-01", strategy: "longest" }],
  );
  const run = closed(finished);
  assertEquals(run.accounts[0]?.date_from, "2030-12-01");
  assertEquals(run.accounts[0]?.status, "ok");
});

Deno.test("windows: later syncs from the last success minus 15 days, never before the start date", async () => {
  const { call, project, finished } = setup({
    raw: [CACC.id, CARD.id],
    lastOk: {
      [CACC.id]: "2031-03-18T06:10:00.123456+00:00",
      [CARD.id]: "2031-03-05T06:10:00+00:00",
    },
  });
  await call();
  // The default strategy is the one of the API: not sent.
  assertEquals(
    transactionRequests(project.ebRequests, CACC.provider_account_id)[0],
    { date_from: "2031-03-03" },
  );
  assertEquals(
    transactionRequests(project.ebRequests, CARD.provider_account_id),
    [{ date_from: "2031-03-01" }],
  );
  const run = closed(finished);
  assertEquals(run.strategy, "default");
  assertEquals(run.accounts.map((a) => [a.strategy, a.date_from]), [
    ["default", "2031-03-03"],
    ["default", "2031-03-01"],
  ]);
});

Deno.test("windows: raw rows without a successful sync start from the start date", async () => {
  const { call, project } = setup({ accounts: [CARD], raw: [CARD.id] });
  await call();
  assertEquals(
    transactionRequests(project.ebRequests, CARD.provider_account_id),
    [{ date_from: "2031-03-01" }],
  );
});

Deno.test("consent expired or revoked: on the connection, nothing downloaded", async () => {
  const cases: [string, EbHandler, number?][] = [
    ["consent_expired", () => json({ ...sessionStatus, status: "EXPIRED" })],
    ["consent_revoked", () => json({ ...sessionStatus, status: "REVOKED" })],
    ["consent_revoked", () => json(errors.revoked_session, 422)],
    ["consent_expired", () => json(errors.expired_session, 422)],
    // Authorized, but the validity is over.
    [
      "consent_expired",
      () => json(sessionStatus),
      Date.parse("2031-08-28T10:00:01Z"),
    ],
  ];
  for (const [code, session, now] of cases) {
    const { call, project, ingested, balances, finished, logs } = setup({
      now,
      eb: { [`GET /sessions/${SESSION_ID}`]: session },
    });
    assertEquals((await call()).status, 202);
    assertEquals(project.ebRequests.length, 1);
    assertEquals(ingested, []);
    assertEquals(balances, []);
    const run = closed(finished);
    assertEquals([run.status, run.errorCode, run.accounts], [
      "error",
      code,
      [],
    ]);
    assertCleanLogs(logs, ["Session is"]);
  }
});

Deno.test("the consent is never deduced from an error of the transactions", async () => {
  const { call, finished } = setup({
    accounts: [CARD],
    eb: {
      [`GET /accounts/${CARD.provider_account_id}/transactions`]: () =>
        json(errors.expired_session, 422),
    },
  });
  await call();
  const run = closed(finished);
  assertEquals(run.status, "partial");
  assertEquals(run.errorCode, "bank_error");
  assertEquals(run.accounts[0]?.error_code, "bank_error");
});

Deno.test("rate limit: the connection stops, the accounts left are skipped", async () => {
  const { call, project, ingested, finished } = setup({
    eb: {
      [`GET /accounts/${CACC.provider_account_id}/transactions`]: () =>
        json(errors.rate_limited, 429),
    },
  });
  await call();
  assertEquals(ingested, []);
  assertEquals(
    project.ebRequests.filter((r) => r.url.includes(CARD.provider_account_id))
      .length,
    0,
  );
  const run = closed(finished);
  assertEquals(run.status, "partial");
  assertEquals(run.errorCode, "rate_limited");
  assertEquals(run.accounts, [
    {
      account_id: CACC.id,
      status: "error",
      error_code: "rate_limited",
      strategy: "longest",
      date_from: "2031-03-01",
    },
    { account_id: CARD.id, status: "skipped" },
  ]);
});

Deno.test("rate limit on the balances or on the session stops too", async () => {
  const balances = setup({
    accounts: [CACC, CARD],
    eb: {
      [`GET /accounts/${CACC.provider_account_id}/balances`]: () =>
        json(errors.rate_limited, 429),
    },
  });
  await balances.call();
  assertEquals(balances.ingested, []);
  assertEquals(closed(balances.finished).errorCode, "rate_limited");

  const session = setup({
    eb: { [`GET /sessions/${SESSION_ID}`]: () => json({}, 429) },
  });
  await session.call();
  const run = closed(session.finished);
  assertEquals([run.status, run.errorCode], ["error", "rate_limited"]);
});

Deno.test("a balance that cannot be read is only logged: the account is ok", async () => {
  const { call, balances, ingested, finished, logs } = setup({
    accounts: [CARD],
    eb: {
      [`GET /accounts/${CARD.provider_account_id}/balances`]: () =>
        json(errors.aspsp_error, 500),
    },
  });
  await call();
  assertEquals(balances, []);
  assertEquals(ingested.length, 1);
  const run = closed(finished);
  assertEquals([run.status, run.errorCode], ["ok", null]);
  assertEquals(logged(logs, "balances")[0]?.code, "bank_unavailable");
});

Deno.test("archived accounts are skipped", async () => {
  const { call, project, ingested, finished } = setup({
    accounts: [CACC, ARCHIVED, CARD],
  });
  await call();
  assert(
    project.restCalls.some((c) =>
      c.route === "GET accounts" &&
      c.url.searchParams.get("archived_at") === "is.null"
    ),
  );
  assertFalse(
    project.ebRequests.some((r) =>
      r.url.includes(ARCHIVED.provider_account_id)
    ),
  );
  assertEquals(ingested.map((i) => i.account_id), [CACC.id, CARD.id]);
  assertEquals(closed(finished).accounts.map((a) => a.account_id), [
    CACC.id,
    CARD.id,
  ]);
});

Deno.test("invalid_row: the row is left out and counted, the account is ok", async () => {
  const { call, ingested, finished, logs } = setup({
    accounts: [CARD],
    eb: {
      [`GET /accounts/${CARD.provider_account_id}/transactions`]: () =>
        json({
          transactions: [
            ...cardDay1.transactions,
            ...invalidRows.transactions,
          ],
          continuation_key: null,
        }),
    },
  });
  await call();
  assertEquals(ingested[0]?.rows.length, 7);
  const run = closed(finished);
  assertEquals([run.status, run.errorCode], ["ok", null]);
  assertEquals(run.accounts[0]?.rows_invalid, 8);
  assertEquals(run.accounts[0]?.rows_received, 7);
  assertEquals(logged(logs, "rows_invalid")[0]?.count, 8);
  assertCleanLogs(logs, ["12,50", "-12.50", "02/03/2031"]);
});

Deno.test("an import that fails: the account keeps its code, the others go on", async () => {
  const detail =
    "Failing row contains (00000000-0000-4000-8000-0000000000c1, CAFFE PROVA).";
  const { call, finished, logs } = setup({
    rpc: {
      ingest_bank_rows: (args) =>
        args.account_id === CACC.id
          ? pgError(400, "P0001", "invalid_rows", detail)
          : [{
            rows_received: 1,
            raw_inserted: 1,
            transactions_created: 1,
            skipped_before_start: 0,
            skipped_status: 0,
            groups_shrunk: 0,
            booked_then_cancelled: 0,
          }],
    },
  });
  await call();
  const run = closed(finished);
  assertEquals(run.status, "partial");
  assertEquals(run.errorCode, "internal");
  assertEquals(run.accounts.map((a) => [a.status, a.error_code]), [
    ["error", "internal"],
    ["ok", undefined],
  ]);
  assertEquals(logged(logs, "ingest")[0]?.code, "invalid_rows");
  assertCleanLogs(logs, [detail, "Failing row"]);
});

Deno.test("credentials: none at all is no_credentials; the global application when linked with it", async () => {
  const none = setup({ rpc: { eb_get_credentials: () => [] } });
  await none.call();
  assertEquals(none.project.ebRequests, []);
  const run = closed(none.finished);
  assertEquals([run.status, run.errorCode], ["error", "no_credentials"]);

  const global = setup({
    connection: {
      member_id: ANNA.memberId,
      aspsp_name: "Credito Emiliano",
      session_id: SESSION_ID,
      uses_global_app: true,
    },
    env: {
      EB_GLOBAL_APP_ID: GLOBAL_APP_ID,
      EB_GLOBAL_PRIVATE_KEY: globalKeys.pkcs8Pem,
    },
  });
  await global.call();
  assertFalse(
    global.project.rpcCalls.some((c) => c.name === "eb_get_credentials"),
  );
  const token = global.project.ebRequests[0]!.headers.get("Authorization")!
    .slice("Bearer ".length);
  assertEquals(
    (await verifyJwt(token, globalKeys.publicKey)).header.kid,
    GLOBAL_APP_ID,
  );
  assertEquals(closed(global.finished).status, "ok");
});

Deno.test("one client for each request, with the key of the owner", async () => {
  const created: string[] = [];
  const spy: NewEbClient = (options) => {
    created.push(options.appId);
    return newEbClient(options);
  };
  const { call, project, logs } = setup({ newEbClient: spy });
  await call();
  await call();
  assertEquals(created, [ANNA.appId, ANNA.appId]);
  for (const request of project.ebRequests) {
    const token = request.headers.get("Authorization")!.slice(
      "Bearer ".length,
    );
    assertEquals(
      (await verifyJwt(token, annaKeys.publicKey)).header.kid,
      ANNA.appId,
    );
    assertCleanLogs(logs, token.split("."));
  }
});

Deno.test("a connection or member that cannot be read: error internal", async () => {
  const gone = setup({ connection: null });
  await gone.call();
  assertEquals(closed(gone.finished).errorCode, "internal");
  assertEquals(gone.project.ebRequests, []);

  const left = setup({
    rpc: {
      eb_service_member: () => pgError(400, "P0001", "member_not_eligible"),
    },
  });
  await left.call();
  const run = closed(left.finished);
  assertEquals([run.status, run.errorCode], ["error", "internal"]);
});

Deno.test("authentication: the secret of the jobs or a secret key, else 401", async () => {
  const cases: [Record<string, string>, number][] = [
    [{}, 401],
    [{ "x-sync-secret": "altro-segreto" }, 401],
    [{ "x-sync-secret": "" }, 401],
    [{ "x-sync-secret": "x".repeat(300) }, 401],
    [{ apikey: PUBLISHABLE_KEY }, 401],
    [{ Authorization: `Bearer ${SECRET_KEY}` }, 401],
    [{ "x-sync-secret": JOB_SECRET }, 202],
    [{ apikey: SECRET_KEY }, 202],
    [{ apikey: OTHER_SECRET_KEY }, 202],
  ];
  for (const [headers, status] of cases) {
    const { call, project } = setup();
    const response = await call(headers);
    assertEquals(response.status, status);
    if (status === 401) {
      assertEquals(await response.json(), { error: "unauthorized" });
      assertFalse(project.rpcCalls.some((c) => c.name === "begin_sync_run"));
    } else {
      await response.body?.cancel();
    }
    if (headers.apikey !== undefined || headers["x-sync-secret"] === "") {
      // A secret key needs no call to the database; an empty secret neither.
      assertFalse(
        project.rpcCalls.some((c) => c.name === "sync_secret_matches"),
      );
    }
  }
});

Deno.test("body: only connection_id and a known trigger, else 400; other methods 405", async () => {
  for (
    const body of [
      { connection_id: "non-un-uuid", trigger: "admin" },
      { connection_id: CONNECTION_ID, trigger: "cron" },
      { connection_id: CONNECTION_ID },
      { connection_id: CONNECTION_ID, trigger: "admin", extra: 1 },
      [CONNECTION_ID, "admin"],
    ]
  ) {
    const { call, project } = setup();
    const response = await call(undefined, body);
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "invalid_request" });
    assertFalse(project.rpcCalls.some((c) => c.name === "begin_sync_run"));
  }
  for (const trigger of ["link", "schedule", "manual", "admin"]) {
    const { call } = setup();
    const response = await call(undefined, {
      connection_id: CONNECTION_ID,
      trigger,
    });
    assertEquals(response.status, 202);
    await response.body?.cancel();
  }
  const { call } = setup();
  const response = await call(undefined, undefined, "GET");
  assertEquals(response.status, 405);
  assertEquals(response.headers.get("Allow"), "POST");
});

Deno.test("a sync already running: 202 skipped, no work; an unknown connection: 404", async () => {
  const running = setup({
    rpc: { begin_sync_run: () => [{ run_id: RUN_ID, status: "skipped" }] },
  });
  const response = await running.call();
  assertEquals(response.status, 202);
  assertEquals(await response.json(), {
    ok: true,
    run_id: RUN_ID,
    status: "skipped",
  });
  assertEquals(running.project.ebRequests, []);
  assertEquals(running.finished, []);
  assertEquals(logged(running.logs, "begin").map((e) => e.code), [
    "ok",
    "already_running",
  ]);

  const unknown = setup({
    rpc: {
      begin_sync_run: () => pgError(400, "P0001", "connection_not_found"),
    },
  });
  const missing = await unknown.call();
  assertEquals(missing.status, 404);
  assertEquals(await missing.json(), { error: "connection_not_found" });
});

Deno.test("missing variables or a database that fails before the answer: 500 internal", async () => {
  const noKeys = setup({ env: { SUPABASE_SECRET_KEYS: undefined } });
  const response = await noKeys.call();
  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "internal" });

  const down = setup({
    rpc: { begin_sync_run: () => pgError(503, "57P01", "terminating") },
  });
  const failed = await down.call();
  assertEquals(failed.status, 500);
  assertEquals(await failed.json(), { error: "internal" });
});

Deno.test("finish_sync_run failing: only its code in the log", async () => {
  const { call, logs } = setup({
    rpc: {
      finish_sync_run: () => pgError(400, "P0001", "invalid_result"),
    },
  });
  assertEquals((await call()).status, 202);
  assertEquals(logged(logs, "finish")[0]?.code, "invalid_result");
  assertCleanLogs(logs);
});

// Step 4: the automatic transfers of the owner (section 7.1).

const HYPE_ID = "00000000-0000-4000-8000-0000000000c3";
const TOP_UP_OUT = "00000000-0000-4000-8000-000000000110";
const TOP_UP_IN = "00000000-0000-4000-8000-000000000131";

/** The top-up of case 8, as transfer_candidates returns it. */
function topUpCandidates(withInflow = true) {
  const movement = (
    id: string,
    accountId: string,
    amount: number,
    description: string,
  ) => ({
    transaction_id: id,
    account_id: accountId,
    amount_cents: amount,
    currency: "EUR",
    movement_date: "2031-03-15",
    counterparty: "ANNA ESEMPIO",
    description,
    free: true,
    in_transfer: false,
    cancelled: false,
  });
  return {
    accounts: [
      {
        id: CACC.id,
        kind: "bank",
        connection_id: CONNECTION_ID,
        aspsp_name: "Credito Emiliano",
        cash_account_type: "CACC",
      },
      {
        id: HYPE_ID,
        kind: "bank",
        connection_id: "00000000-0000-4000-8000-0000000000e2",
        aspsp_name: "HYPE",
        cash_account_type: null,
      },
    ],
    movements: [
      movement(
        TOP_UP_OUT,
        CACC.id,
        -5000,
        "BON. ISTANTANEO A DEBITO ANNA ESEMPIO RICARICA",
      ),
      ...(withInflow
        ? [movement(TOP_UP_IN, HYPE_ID, 5000, "RICARICA DA BONIFICO")]
        : []),
    ],
  };
}

const TOP_UP_VALUES = [
  HYPE_ID,
  TOP_UP_OUT,
  TOP_UP_IN,
  "ANNA ESEMPIO",
  "RICARICA",
];

const rpcNames = (project: { rpcCalls: { name: string }[] }) =>
  project.rpcCalls.map((call) => call.name);

Deno.test("step 4: the transfers of the owner once, after all the accounts, counted on the connection", async () => {
  const { call, project, finished, logs } = setup({
    rpc: { transfer_candidates: () => topUpCandidates() },
  });
  await call();
  const names = rpcNames(project);
  assertEquals(names.slice(names.indexOf("ingest_bank_rows")), [
    "ingest_bank_rows",
    "ingest_bank_rows",
    "settlement_candidates",
    "transfer_candidates",
    "apply_transfers",
    "finish_sync_run",
  ]);
  const candidates = project.rpcCalls.find((c) =>
    c.name === "transfer_candidates"
  )!;
  // The window of 45 days before 2031-03-20, and 7 days for the payments.
  assertEquals(candidates.args, {
    member_id: ANNA.memberId,
    since: "2031-01-27",
  });
  assertEquals(candidates.apikey, SECRET_KEY);
  assertEquals(
    project.rpcCalls.find((c) => c.name === "apply_transfers")!.args,
    {
      member_id: ANNA.memberId,
      transfers: [{
        from_account_id: CACC.id,
        to_account_id: HYPE_ID,
        out_transaction_id: TOP_UP_OUT,
        in_transaction_id: TOP_UP_IN,
        funded_transaction_id: null,
      }],
    },
  );

  const run = closed(finished);
  assertEquals([run.status, run.errorCode, run.matchedTransfers], [
    "ok",
    null,
    1,
  ]);
  assertEquals(logged(logs, "match"), [
    { fn: "eb-sync", step: "match", code: "ok" },
  ]);
  assertEquals(logged(logs, "match_ms").length, 1);
  assert(logged(logs, "match_ms")[0]!.count! >= 0);
  assertEquals(logged(logs, "matched_transfers"), [
    { fn: "eb-sync", step: "matched_transfers", count: 1 },
  ]);
  assertCleanLogs(logs, TOP_UP_VALUES);
});

Deno.test("step 4: also with an account not imported; never without an imported account", async () => {
  const partial = setup({
    rpc: { transfer_candidates: () => topUpCandidates() },
    eb: {
      [`GET /accounts/${CARD.provider_account_id}/transactions`]: () =>
        json(errors.aspsp_error, 500),
    },
  });
  await partial.call();
  const run = closed(partial.finished);
  assertEquals([run.status, run.matchedTransfers], ["partial", 1]);
  assertEquals(
    rpcNames(partial.project).filter((n) => n === "transfer_candidates")
      .length,
    1,
  );

  const none = [
    // The first account hits the rate limit: the other is skipped.
    setup({
      eb: {
        [`GET /accounts/${CACC.provider_account_id}/transactions`]: () =>
          json(errors.rate_limited, 429),
      },
    }),
    // The consent is over: no account.
    setup({
      eb: {
        [`GET /sessions/${SESSION_ID}`]: () =>
          json({ ...sessionStatus, status: "EXPIRED" }),
      },
    }),
  ];
  for (const { call, project, finished, logs } of none) {
    await call();
    assertFalse(rpcNames(project).includes("settlement_candidates"));
    assertFalse(rpcNames(project).includes("transfer_candidates"));
    assertFalse(rpcNames(project).includes("apply_transfers"));
    assertEquals(closed(finished).matchedSettlements, 0);
    assertEquals(closed(finished).matchedTransfers, 0);
    assertEquals(logged(logs, "settle"), []);
    assertEquals(logged(logs, "match"), []);
  }
});

Deno.test("step 4 without transfers to make: apply_transfers is not called", async () => {
  const { call, project, finished, logs } = setup({
    rpc: { transfer_candidates: () => topUpCandidates(false) },
  });
  await call();
  assert(rpcNames(project).includes("transfer_candidates"));
  assertFalse(rpcNames(project).includes("apply_transfers"));
  assertEquals(closed(finished).matchedTransfers, 0);
  assertEquals(logged(logs, "matched_transfers")[0]?.count, 0);
});

Deno.test("step 4 failing: the accounts keep their outcome, only the code in the log, 0 transfers", async () => {
  const detail =
    `Failing row contains (${TOP_UP_OUT}, ANNA ESEMPIO, RICARICA).`;
  const cases: [string, Record<string, RpcHandler>][] = [
    ["member_not_eligible", {
      transfer_candidates: () =>
        pgError(400, "P0001", "member_not_eligible", detail),
    }],
    ["internal", { transfer_candidates: () => ({ accounts: "conti" }) }],
    ["internal", {
      transfer_candidates: () => {
        const candidates = topUpCandidates();
        return {
          ...candidates,
          movements: [{ ...candidates.movements[0], amount_cents: "-5000" }],
        };
      },
    }],
    ["invalid_transfers", {
      transfer_candidates: () => topUpCandidates(),
      apply_transfers: () => pgError(400, "P0001", "invalid_transfers", detail),
    }],
    ["internal", {
      transfer_candidates: () => topUpCandidates(),
      apply_transfers: () => 2,
    }],
    ["internal", {
      transfer_candidates: () => topUpCandidates(),
      apply_transfers: () => "1",
    }],
    ["57014", {
      transfer_candidates: () => topUpCandidates(),
      apply_transfers: () => pgError(500, "57014", "canceling statement"),
    }],
  ];
  for (const [code, rpc] of cases) {
    const { call, finished, logs } = setup({ rpc });
    assertEquals((await call()).status, 202);
    const run = closed(finished);
    assertEquals([run.status, run.errorCode, run.matchedTransfers], [
      "ok",
      null,
      0,
    ]);
    assertEquals(run.accounts.map((a) => a.status), ["ok", "ok"]);
    assertEquals(logged(logs, "match"), [
      { fn: "eb-sync", step: "match", code },
    ]);
    assertEquals(logged(logs, "match_ms").length, 1);
    assertEquals(logged(logs, "matched_transfers")[0]?.count, 0);
    assertCleanLogs(logs, [...TOP_UP_VALUES, "Failing row", "canceling"]);
  }
});

const BRUNO_MEMBER = "00000000-0000-4000-8000-0000000000b1";
const PAYPAL_ID = "00000000-0000-4000-8000-0000000000c4";
const PAYMENT_TO_BRUNO = "00000000-0000-4000-8000-000000000105";

/** The payment of case 5, as settlement_candidates returns it for Anna. */
function paymentCandidates() {
  return {
    movements: [{
      transaction_id: PAYMENT_TO_BRUNO,
      account_id: PAYPAL_ID,
      amount_cents: -2000,
      currency: "EUR",
      movement_date: "2031-03-06",
      entry_reference: "PP0000000000000005",
      counterpart_member_id: BRUNO_MEMBER,
      free: true,
      cancelled: false,
    }],
    settlements: [],
  };
}

const PAYMENT_VALUES = [
  PAYPAL_ID,
  PAYMENT_TO_BRUNO,
  BRUNO_MEMBER,
  "PP0000000000000005",
];

Deno.test("step 4: the settlements of the owner before the transfers, the sides counted on the connection", async () => {
  const { call, project, finished, logs } = setup({
    rpc: {
      settlement_candidates: () => paymentCandidates(),
      transfer_candidates: () => topUpCandidates(),
    },
  });
  await call();
  const names = rpcNames(project);
  assertEquals(names.slice(names.indexOf("settlement_candidates")), [
    "settlement_candidates",
    "apply_settlements",
    "transfer_candidates",
    "apply_transfers",
    "finish_sync_run",
  ]);
  const candidates = project.rpcCalls.find((c) =>
    c.name === "settlement_candidates"
  )!;
  // The window of 45 days before 2031-03-20.
  assertEquals(candidates.args, {
    member_id: ANNA.memberId,
    since: "2031-02-03",
  });
  assertEquals(candidates.apikey, SECRET_KEY);
  assertEquals(
    project.rpcCalls.find((c) => c.name === "apply_settlements")!.args,
    {
      member_id: ANNA.memberId,
      settlements: [{
        transaction_id: PAYMENT_TO_BRUNO,
        counterpart_member_id: BRUNO_MEMBER,
        settlement_id: null,
      }],
    },
  );

  const run = closed(finished);
  assertEquals(
    [run.status, run.errorCode, run.matchedSettlements, run.matchedTransfers],
    ["ok", null, 1, 1],
  );
  assertEquals(logged(logs, "settle"), [
    { fn: "eb-sync", step: "settle", code: "ok" },
  ]);
  assertEquals(logged(logs, "settle_ms").length, 1);
  assert(logged(logs, "settle_ms")[0]!.count! >= 0);
  assertEquals(logged(logs, "matched_settlements"), [
    { fn: "eb-sync", step: "matched_settlements", count: 1 },
  ]);
  assertCleanLogs(logs, [...PAYMENT_VALUES, ...TOP_UP_VALUES]);
});

Deno.test("step 4 without settlements to make: apply_settlements is not called, the transfers go on", async () => {
  const { call, project, finished, logs } = setup({
    rpc: { transfer_candidates: () => topUpCandidates() },
  });
  await call();
  assert(rpcNames(project).includes("settlement_candidates"));
  assertFalse(rpcNames(project).includes("apply_settlements"));
  assert(rpcNames(project).includes("apply_transfers"));
  const run = closed(finished);
  assertEquals([run.matchedSettlements, run.matchedTransfers], [0, 1]);
  assertEquals(logged(logs, "matched_settlements")[0]?.count, 0);
});

Deno.test("step 4 with the settlements failing: the transfers are skipped, only the code in the log, both counts at 0", async () => {
  const detail =
    `Failing row contains (${PAYMENT_TO_BRUNO}, PP0000000000000005).`;
  const cases: [string, Record<string, RpcHandler>][] = [
    ["member_not_eligible", {
      settlement_candidates: () =>
        pgError(400, "P0001", "member_not_eligible", detail),
    }],
    ["internal", {
      settlement_candidates: () => ({ movements: [], settlements: "no" }),
    }],
    ["internal", {
      settlement_candidates: () => {
        const candidates = paymentCandidates();
        return {
          ...candidates,
          movements: [{ ...candidates.movements[0], free: "true" }],
        };
      },
    }],
    ["internal", {
      settlement_candidates: () => ({
        movements: [],
        settlements: [{ id: "s1", settled_on: "6 marzo" }],
      }),
    }],
    ["invalid_settlements", {
      settlement_candidates: () => paymentCandidates(),
      apply_settlements: () =>
        pgError(400, "P0001", "invalid_settlements", detail),
    }],
    ["internal", {
      settlement_candidates: () => paymentCandidates(),
      apply_settlements: () => 2,
    }],
    ["internal", {
      settlement_candidates: () => paymentCandidates(),
      apply_settlements: () => -1,
    }],
    ["40P01", {
      settlement_candidates: () => paymentCandidates(),
      apply_settlements: () => pgError(500, "40P01", "deadlock detected"),
    }],
  ];
  for (const [code, rpc] of cases) {
    const { call, project, finished, logs } = setup({
      rpc: { transfer_candidates: () => topUpCandidates(), ...rpc },
    });
    assertEquals((await call()).status, 202);
    const run = closed(finished);
    assertEquals(
      [run.status, run.errorCode, run.matchedSettlements, run.matchedTransfers],
      ["ok", null, 0, 0],
    );
    assertEquals(run.accounts.map((a) => a.status), ["ok", "ok"]);
    assertEquals(logged(logs, "settle"), [
      { fn: "eb-sync", step: "settle", code },
    ]);
    assertEquals(logged(logs, "settle_ms").length, 1);
    assertFalse(rpcNames(project).includes("transfer_candidates"));
    assertEquals(logged(logs, "match"), []);
    assertEquals(logged(logs, "matched_settlements")[0]?.count, 0);
    assertEquals(logged(logs, "matched_transfers")[0]?.count, 0);
    assertCleanLogs(logs, [...PAYMENT_VALUES, "Failing row", "deadlock"]);
  }
});

Deno.test("step 4 with the transfers failing: the settlements keep their count", async () => {
  const { call, finished, logs } = setup({
    rpc: {
      settlement_candidates: () => paymentCandidates(),
      transfer_candidates: () => pgError(500, "57014", "canceling statement"),
    },
  });
  await call();
  const run = closed(finished);
  assertEquals([run.matchedSettlements, run.matchedTransfers], [1, 0]);
  assertEquals(logged(logs, "match"), [
    { fn: "eb-sync", step: "match", code: "57014" },
  ]);
});
