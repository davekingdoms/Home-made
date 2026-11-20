import { assert, assertEquals, assertFalse } from "@std/assert";
import { type AdminIo, main } from "./eb-admin.ts";
import {
  fakeFetch,
  type Handler,
  json,
  testdata,
} from "../functions/_shared/testing/fake_fetch.ts";
import { generateTestKeys } from "../functions/_shared/testing/rsa.ts";
import {
  SECRET_KEY,
  SUPABASE_URL,
} from "../functions/_shared/testing/fake_supabase.ts";

const keys = await generateTestKeys();
const APP_ID = "00000000-0000-4000-8000-00000000a99a";
const KEY_PATH = "chiave-di-prova.pem";
const SECRET_PATH = "chiave-segreta-di-prova.txt";
const MEMBER_ID = "00000000-0000-4000-8000-0000000000a1";
const FILES: Record<string, string> = {
  [KEY_PATH]: keys.pkcs8Pem,
  [SECRET_PATH]: `${SECRET_KEY}\r\n`,
};

function run(
  args: string[],
  handler: Handler,
  env: Record<string, string> = {
    EB_APP_ID: APP_ID,
    EB_KEY_PATH: KEY_PATH,
    SUPABASE_URL,
    SB_SECRET_KEY_PATH: SECRET_PATH,
  },
  files: Record<string, string> = FILES,
) {
  const fake = fakeFetch(handler);
  const out: string[] = [];
  const err: string[] = [];
  const sleeps: number[] = [];
  const io: AdminIo = {
    env: (name) => env[name],
    readTextFile: (path) => {
      const content = files[path];
      return content === undefined
        ? Promise.reject(new Error("missing"))
        : Promise.resolve(content);
    },
    print: (line) => out.push(line),
    printError: (line) => err.push(line),
    fetch: fake.fetch,
    sleep: (ms) => {
      sleeps.push(ms);
      return Promise.resolve();
    },
  };
  return { done: main(args, io), out, err, sleeps, requests: fake.requests };
}

/** Nothing secret in the output: key, JWT, application ID, key path. */
function assertNoSecrets(lines: string[], requests: Request[]) {
  const text = lines.join("\n");
  const keyBody = keys.pkcs8Pem.split("\n")[1] ?? "";
  for (
    const secret of [
      APP_ID,
      KEY_PATH,
      keyBody.slice(0, 24),
      SECRET_KEY,
      SECRET_PATH,
      SUPABASE_URL,
    ]
  ) {
    assertFalse(text.includes(secret));
  }
  for (const request of requests) {
    if (new URL(request.url).host !== "api.enablebanking.com") continue;
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
  const link = ["link", "--member", MEMBER_ID, "--country", "IT"];
  const cases = [
    [],
    ["sync"],
    ["sync", "anna"],
    ["sync", "00000000-0000-4000-8000-0000000000e1", "altro"],
    ["aspsps"],
    ["aspsps", "--country", "ITA"],
    ["credentials"],
    ["credentials", "--member", "anna"],
    link,
    [...link, "--bank", " "],
    ["link", "--member", MEMBER_ID, "--bank", "Mock ASPSP", "--country", "ITA"],
    [...link, "--bank", "Mock ASPSP", "--psu", "corporate"],
    ["link", "--bank", "Mock ASPSP", "--country", "IT"],
  ];
  for (const args of cases) {
    const { done, err, requests } = run(args, () => json({}));
    assertEquals(await done, 2);
    assertEquals(err.length, 1);
    assertEquals(requests.length, 0);
  }
});

/** The Edge Function, answering from a handler after checking the call. */
function functionCall(
  name: string,
  answer: (body: Record<string, unknown>) => Response,
): Handler {
  return async (request) => {
    assertEquals(request.method, "POST");
    assertEquals(request.url, `${SUPABASE_URL}/functions/v1/${name}`);
    assertEquals(request.headers.get("apikey"), SECRET_KEY);
    assertEquals(request.headers.get("Authorization"), null);
    return answer(await request.json());
  };
}

Deno.test("credentials: the application goes to eb-credentials with the secret key", async () => {
  let sent: Record<string, unknown> | undefined;
  const { done, out, err, requests } = run(
    ["credentials", "--member", MEMBER_ID],
    functionCall("eb-credentials", (body) => {
      sent = body;
      return json({ ok: true });
    }),
  );
  assertEquals(await done, 0);
  assertEquals(out, ["credentials: saved"]);
  assertEquals(err, []);
  assertEquals(sent, {
    member_id: MEMBER_ID,
    app_id: APP_ID,
    private_key: keys.pkcs8Pem,
  });
  assertEquals(requests.length, 1);
  assertNoSecrets([...out, ...err], requests);
});

Deno.test("credentials: a refused key prints the code only", async () => {
  const { done, out, err, requests } = run(
    ["credentials", "--member", MEMBER_ID],
    functionCall(
      "eb-credentials",
      () => json({ error: "invalid_credentials" }, 400),
    ),
  );
  assertEquals(await done, 1);
  assertEquals(out, []);
  assertEquals(err, ["error: invalid_credentials"]);
  assertNoSecrets(err, requests);
});

Deno.test("credentials: environment and files of the keys", async () => {
  const args = ["credentials", "--member", MEMBER_ID];
  const noProject = run(args, () => json({}), {
    EB_APP_ID: APP_ID,
    EB_KEY_PATH: KEY_PATH,
  });
  assertEquals(await noProject.done, 1);
  assertEquals(noProject.err, [
    "error: set SUPABASE_URL and SB_SECRET_KEY_PATH",
  ]);
  assertEquals(noProject.requests.length, 0);

  const noApp = run(args, () => json({}), {
    SUPABASE_URL,
    SB_SECRET_KEY_PATH: SECRET_PATH,
  });
  assertEquals(await noApp.done, 1);
  assertEquals(noApp.err, ["error: set EB_APP_ID and EB_KEY_PATH"]);
  assertEquals(noApp.requests.length, 0);

  const unreadable = run(args, () => json({}), undefined, {
    [KEY_PATH]: keys.pkcs8Pem,
  });
  assertEquals(await unreadable.done, 1);
  assertEquals(unreadable.err, [
    "error: cannot read the file in SB_SECRET_KEY_PATH",
  ]);

  const twoLines = run(args, () => json({}), undefined, {
    ...FILES,
    [SECRET_PATH]: `${SECRET_KEY}\naltro`,
  });
  assertEquals(await twoLines.done, 1);
  assertEquals(twoLines.err, [
    "error: the file in SB_SECRET_KEY_PATH holds one key, one line",
  ]);
  assertEquals(twoLines.requests.length, 0);
});

Deno.test("link: prints the authorization URL and the reminder", async () => {
  let sent: Record<string, unknown> | undefined;
  const url =
    "https://auth.example.com/ais/start?sessionid=00000000-0000-4000-8000-0000000000b1";
  const { done, out, err, requests } = run(
    ["link", "--member", MEMBER_ID, "--bank", "Mock ASPSP", "--country", "it"],
    functionCall("eb-link-start", (body) => {
      sent = body;
      return json({ ok: true, url });
    }),
  );
  assertEquals(await done, 0);
  assertEquals(out, [
    "authorization URL (open it and finish in the same browser):",
    url,
    "complete within 30 minutes",
  ]);
  assertEquals(err, []);
  assertEquals(sent, {
    member_id: MEMBER_ID,
    aspsp_name: "Mock ASPSP",
    aspsp_country: "IT",
  });
  assertNoSecrets([...out, ...err], requests);
});

Deno.test("link: the PSU type when given", async () => {
  let sent: Record<string, unknown> | undefined;
  const { done } = run(
    [
      "link",
      "--member",
      MEMBER_ID,
      "--bank=Mock ASPSP",
      "--country=IT",
      "--psu",
      "business",
    ],
    functionCall("eb-link-start", (body) => {
      sent = body;
      return json({ ok: true, url: "https://auth.example.com/ais/start" });
    }),
  );
  assertEquals(await done, 0);
  assertEquals(sent?.psu_type, "business");
  assertEquals(sent?.aspsp_name, "Mock ASPSP");
});

Deno.test("link: errors of the function, the gateway and the network", async () => {
  const args = [
    "link",
    "--member",
    MEMBER_ID,
    "--bank",
    "Banca di Prova",
    "--country",
    "IT",
  ];
  const notFound = run(args, () => json({ error: "bank_not_found" }, 404));
  assertEquals(await notFound.done, 1);
  assertEquals(notFound.err, ["error: bank_not_found"]);

  const gateway = run(
    args,
    () => new Response("<html>Bad gateway</html>", { status: 502 }),
  );
  assertEquals(await gateway.done, 1);
  assertEquals(gateway.err, ["error: http_502"]);

  const network = run(args, () => Promise.reject(new Error("rete assente")));
  assertEquals(await network.done, 1);
  assertEquals(network.err, ["error: unavailable"]);

  const freeText = run(
    args,
    () => json({ error: "Testo libero della banca" }, 500),
  );
  assertEquals(await freeText.done, 1);
  assertEquals(freeText.err, ["error: http_500"]);

  const noUrl = run(args, () => json({ ok: true }));
  assertEquals(await noUrl.done, 1);
  assertEquals(noUrl.err, ["error: internal"]);
});

const CONNECTION_ID = "00000000-0000-4000-8000-0000000000e1";
const RUN_ID = "00000000-0000-4000-8000-0000000000f9";

/** Two account rows of a run: one imported, one with a failed page. */
const ACCOUNT_ROWS = [
  {
    status: "ok",
    error_code: null,
    strategy: "longest",
    date_from: "2031-03-01",
    history_from: "2031-04-17",
    history_incomplete: true,
    rows_received: 12,
    rows_invalid: 1,
    raw_inserted: 12,
    transactions_created: 11,
    skipped_before_start: 1,
    skipped_status: 0,
    amounts_rounded: 2,
    groups_shrunk: 0,
    booked_then_cancelled: 0,
  },
  {
    status: "error",
    error_code: "bank_unavailable",
    strategy: "longest",
    date_from: "2031-03-01",
    history_from: null,
    history_incomplete: false,
    rows_received: 0,
    rows_invalid: 0,
    raw_inserted: 0,
    transactions_created: 0,
    skipped_before_start: 0,
    skipped_status: 0,
    amounts_rounded: 0,
    groups_shrunk: 0,
    booked_then_cancelled: 0,
  },
];

/**
 * eb-sync and the reads of sync_runs: the row of the run is `running` for
 * `runningPolls` reads, then `run`.
 */
function syncProject(options: {
  start?: () => Response;
  run?: Record<string, unknown>;
  runningPolls?: number;
  accounts?: unknown;
  reads?: URL[];
} = {}): Handler {
  let polls = 0;
  return async (request) => {
    const url = new URL(request.url);
    assertEquals(url.origin, SUPABASE_URL);
    assertEquals(request.headers.get("apikey"), SECRET_KEY);
    assertEquals(request.headers.get("Authorization"), null);
    if (url.pathname === "/functions/v1/eb-sync") {
      assertEquals(request.method, "POST");
      assertEquals(await request.json(), {
        connection_id: CONNECTION_ID,
        trigger: "admin",
      });
      return options.start?.() ??
        json({ ok: true, run_id: RUN_ID, status: "running" }, 202);
    }
    assertEquals(url.pathname, "/rest/v1/sync_runs");
    assertEquals(request.method, "GET");
    options.reads?.push(url);
    if (url.searchParams.get("id") === `eq.${RUN_ID}`) {
      polls++;
      return json([
        polls <= (options.runningPolls ?? 1)
          ? { status: "running", error_code: null, strategy: null }
          : options.run ?? {
            status: "partial",
            error_code: "bank_unavailable",
            strategy: "longest",
            history_incomplete: true,
          },
      ]);
    }
    assertEquals(url.searchParams.get("run_id"), `eq.${RUN_ID}`);
    return json(options.accounts ?? ACCOUNT_ROWS);
  };
}

Deno.test("sync: starts the run, waits for its end, prints codes and counts only", async () => {
  const reads: URL[] = [];
  const { done, out, err, sleeps, requests } = run(
    ["sync", CONNECTION_ID],
    syncProject({ reads, runningPolls: 2 }),
  );
  assertEquals(await done, 1);
  assertEquals(err, []);
  assertEquals(out, [
    "sync: partial (bank_unavailable)",
    "strategy: longest",
    "accounts: 2",
    "account 1: ok",
    "  strategy longest, asked from 2031-03-01, obtained from 2031-04-17, history incomplete",
    "  rows: received 12, invalid 1, new 12, movements 11, before start 1, status 0, rounded 2, groups shrunk 0, booked then cancelled 0",
    "account 2: error (bank_unavailable)",
    "  strategy longest, asked from 2031-03-01, obtained from -, history complete",
    "  rows: received 0, invalid 0, new 0, movements 0, before start 0, status 0, rounded 0, groups shrunk 0, booked then cancelled 0",
  ]);
  assertEquals(sleeps, [2000, 2000, 2000]);
  // The accounts are read in a fixed order, never with their ids.
  const accounts = reads.at(-1)!;
  assertEquals(accounts.searchParams.get("order"), "account_id");
  for (const column of ["account_id", "id", "connection_id", "run_id"]) {
    assertFalse(
      accounts.searchParams.get("select")!.split(",").includes(column),
    );
  }
  assertNoSecrets([...out, ...err], requests);
  assertFalse(out.join("\n").includes(CONNECTION_ID));
  assertFalse(out.join("\n").includes(RUN_ID));
});

Deno.test("sync: a run that ends ok exits with 0", async () => {
  const { done, out } = run(
    ["sync", CONNECTION_ID],
    syncProject({
      run: {
        status: "ok",
        error_code: null,
        strategy: "default",
        history_incomplete: false,
      },
      accounts: [ACCOUNT_ROWS[0]],
    }),
  );
  assertEquals(await done, 0);
  assertEquals(out.slice(0, 3), [
    "sync: ok",
    "strategy: default",
    "accounts: 1",
  ]);
});

Deno.test("sync: a run already in progress is not waited for", async () => {
  const { done, out, sleeps, requests } = run(
    ["sync", CONNECTION_ID],
    syncProject({
      start: () => json({ ok: true, run_id: RUN_ID, status: "skipped" }, 202),
    }),
  );
  assertEquals(await done, 1);
  assertEquals(out, ["sync: skipped (already_running)"]);
  assertEquals(sleeps, []);
  assertEquals(requests.length, 1);
});

Deno.test("sync: errors of the function, of the reads and a run that never ends", async () => {
  const unknown = run(
    ["sync", CONNECTION_ID],
    syncProject({
      start: () => json({ error: "connection_not_found" }, 404),
    }),
  );
  assertEquals(await unknown.done, 1);
  assertEquals(unknown.err, ["error: connection_not_found"]);

  const denied = run(
    ["sync", CONNECTION_ID],
    syncProject({ start: () => json({ error: "unauthorized" }, 401) }),
  );
  assertEquals(await denied.done, 1);
  assertEquals(denied.err, ["error: unauthorized"]);

  const noRun = run(
    ["sync", CONNECTION_ID],
    syncProject({ start: () => json({ ok: true, status: "running" }, 202) }),
  );
  assertEquals(await noRun.done, 1);
  assertEquals(noRun.err, ["error: internal"]);

  const readFails = run(["sync", CONNECTION_ID], async (request) => {
    if (new URL(request.url).pathname.startsWith("/rest/")) {
      return json({ code: "PGRST301", message: "JWT expired" }, 401);
    }
    return await syncProject()(request);
  });
  assertEquals(await readFails.done, 1);
  assertEquals(readFails.err, ["error: PGRST301"]);

  const endless = run(
    ["sync", CONNECTION_ID],
    syncProject({ runningPolls: 10_000 }),
  );
  assertEquals(await endless.done, 1);
  assertEquals(endless.err, ["error: still running, read sync_runs later"]);
  assertEquals(endless.sleeps.length, 180);
});

Deno.test("sync: a value with another shape is never printed", async () => {
  const cases: Record<string, unknown>[] = [
    { ...ACCOUNT_ROWS[0], error_code: "Testo libero della banca" },
    { ...ACCOUNT_ROWS[0], date_from: "01/03/2031" },
    { ...ACCOUNT_ROWS[0], rows_received: "12" },
    { ...ACCOUNT_ROWS[0], status: "<b>ok</b>" },
  ];
  for (const account of cases) {
    const { done, out, err } = run(
      ["sync", CONNECTION_ID],
      syncProject({ accounts: [account] }),
    );
    assertEquals(await done, 1);
    assertEquals(out, []);
    assertEquals(err, ["error: invalid_response"]);
  }
});
