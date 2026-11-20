/**
 * Service script for development (sincronizzazione.md, section 1).
 *
 * Subcommands:
 *   aspsps --country IT      number of banks of the country and whether the
 *                            Sandbox bank "Mock ASPSP" is among them
 *   credentials --member <uuid>
 *                            proves and saves the Enable Banking application
 *                            of EB_APP_ID and EB_KEY_PATH for that member,
 *                            through eb-credentials
 *   link --member <uuid> --bank <name> --country <XX> [--psu personal|business]
 *                            starts a bank link through eb-link-start and
 *                            prints the authorization URL
 *   sync <connection uuid>   syncs a connection through eb-sync (trigger
 *                            admin), waits for the end of the run and prints
 *                            its outcome from sync_runs: status, codes,
 *                            strategy, dates asked and obtained, the counts
 *                            of each account ("account 1", "account 2"…)
 *
 * Environment: EB_APP_ID and EB_KEY_PATH (path of the PEM private key) for
 * `aspsps` and `credentials`; SUPABASE_URL and SB_SECRET_KEY_PATH (path of a
 * file with a secret key of the project, one line) for `credentials`,
 * `link` and `sync`. The secret key is never an argument nor the value of a
 * variable. Prints outcomes, codes and counts only, and for `link` the
 * authorization URL: never the keys, the JWT, the application ID, an
 * amount, a description, a name or the id of an account.
 *
 * From the root of the repository, with the minimum permissions (PowerShell):
 *
 *   deno run --allow-env=EB_APP_ID,EB_KEY_PATH,SUPABASE_URL,SB_SECRET_KEY_PATH
 *     "--allow-read=<key file>,<secret key file>"
 *     "--allow-net=$(([uri]$env:SUPABASE_URL).Host)"
 *     supabase/scripts/eb-admin.ts credentials --member <uuid>
 *
 * `link` and `sync` read only the secret key file; `aspsps` needs only the
 * key file and --allow-net=api.enablebanking.com. The id of the connection
 * goes through a variable, so it stays out of the shell history:
 *
 *   $id = Read-Host "connection id"
 *   deno run --allow-env=EB_APP_ID,EB_KEY_PATH,SUPABASE_URL,SB_SECRET_KEY_PATH
 *     "--allow-read=<secret key file>"
 *     "--allow-net=$(([uri]$env:SUPABASE_URL).Host)"
 *     supabase/scripts/eb-admin.ts sync $id
 */

import { EnableBankingClient } from "../functions/_shared/eb/client.ts";
import { EbError } from "../functions/_shared/eb/errors.ts";

export interface AdminIo {
  env: (name: string) => string | undefined;
  readTextFile: (path: string) => Promise<string>;
  print: (line: string) => void;
  printError: (line: string) => void;
  fetch?: typeof fetch;
  /** Waits between two reads of a running sync. */
  sleep?: (ms: number) => Promise<void>;
}

const USAGE = [
  "usage: eb-admin.ts aspsps --country <country code, e.g. IT>",
  "       eb-admin.ts credentials --member <member uuid>",
  "       eb-admin.ts link --member <member uuid> --bank <bank name> --country <XX> [--psu personal|business]",
  "       eb-admin.ts sync <connection uuid>",
].join("\n");
/** A sync is read every 2 seconds, for at most 6 minutes. */
export const SYNC_POLL_MS = 2_000;
export const SYNC_MAX_POLLS = 180;
const MOCK_ASPSP = "Mock ASPSP";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const COUNTRY = /^[A-Z]{2}$/;
const CODE = /^[a-z_]{1,40}$/;
/** An Edge Function may call Enable Banking and the database in turn. */
const FUNCTION_TIMEOUT_MS = 60_000;

/** Runs a subcommand; returns the exit code (0 ok, 1 failure, 2 usage). */
export async function main(args: string[], io: AdminIo): Promise<number> {
  const [command, ...options] = args;
  switch (command) {
    case "aspsps":
      return await aspsps(options, io);
    case "credentials":
      return await credentials(options, io);
    case "link":
      return await link(options, io);
    case "sync":
      return await sync(options, io);
    default:
      return usage(io);
  }
}

function usage(io: AdminIo): number {
  io.printError(USAGE);
  return 2;
}

async function aspsps(options: string[], io: AdminIo): Promise<number> {
  const country = option(options, "country")?.toUpperCase();
  if (country === undefined || !COUNTRY.test(country)) return usage(io);
  try {
    const app = await appFromEnv(io);
    if (app === undefined) return 1;
    const client = new EnableBankingClient({ ...app, fetch: io.fetch });
    const { aspsps } = await client.getAspsps(country);
    const mock = aspsps.some((aspsp) => aspsp.name === MOCK_ASPSP);
    io.print(`banks in ${country}: ${aspsps.length}`);
    io.print(`${MOCK_ASPSP}: ${mock ? "present" : "missing"}`);
    return 0;
  } catch (error) {
    // Codes only: EbError messages hold the code, the HTTP status and the
    // Enable Banking error code, never the bank's text.
    io.printError(
      `error: ${error instanceof EbError ? error.message : "internal"}`,
    );
    return 1;
  }
}

async function credentials(options: string[], io: AdminIo): Promise<number> {
  const member = option(options, "member");
  if (member === undefined || !UUID.test(member)) return usage(io);
  const project = await projectFromEnv(io);
  if (project === undefined) return 1;
  const app = await appFromEnv(io);
  if (app === undefined) return 1;
  const result = await callFunction(io, project, "eb-credentials", {
    member_id: member,
    app_id: app.appId,
    private_key: app.privateKey,
  });
  if (!result.ok) {
    io.printError(`error: ${result.code}`);
    return 1;
  }
  io.print("credentials: saved");
  return 0;
}

async function link(options: string[], io: AdminIo): Promise<number> {
  const member = option(options, "member");
  const bank = option(options, "bank");
  const country = option(options, "country")?.toUpperCase();
  const psu = option(options, "psu");
  if (
    member === undefined || !UUID.test(member) ||
    bank === undefined || bank.trim() === "" ||
    country === undefined || !COUNTRY.test(country) ||
    (psu !== undefined && psu !== "personal" && psu !== "business")
  ) {
    return usage(io);
  }
  const project = await projectFromEnv(io);
  if (project === undefined) return 1;
  const result = await callFunction(io, project, "eb-link-start", {
    member_id: member,
    aspsp_name: bank,
    aspsp_country: country,
    ...(psu === undefined ? {} : { psu_type: psu }),
  });
  if (!result.ok) {
    io.printError(`error: ${result.code}`);
    return 1;
  }
  const url = result.body.url;
  if (typeof url !== "string" || !/^https:\/\//.test(url)) {
    io.printError("error: internal");
    return 1;
  }
  io.print("authorization URL (open it and finish in the same browser):");
  io.print(url);
  io.print("complete within 30 minutes");
  return 0;
}

/** Columns of the row of the connection and of the rows of the accounts. */
const RUN_COLUMNS = "status,error_code,strategy,history_incomplete";
const ACCOUNT_COLUMNS = [
  "status",
  "error_code",
  "strategy",
  "date_from",
  "history_from",
  "history_incomplete",
  "rows_received",
  "rows_invalid",
  "raw_inserted",
  "transactions_created",
  "skipped_before_start",
  "skipped_status",
  "amounts_rounded",
  "groups_shrunk",
  "booked_then_cancelled",
] as const;
/** Labels of the counts, in the order printed. */
const COUNT_LABELS: [typeof ACCOUNT_COLUMNS[number], string][] = [
  ["rows_received", "received"],
  ["rows_invalid", "invalid"],
  ["raw_inserted", "new"],
  ["transactions_created", "movements"],
  ["skipped_before_start", "before start"],
  ["skipped_status", "status"],
  ["amounts_rounded", "rounded"],
  ["groups_shrunk", "groups shrunk"],
  ["booked_then_cancelled", "booked then cancelled"],
];
const STATUS = /^(running|ok|partial|error|skipped)$/;
const STRATEGY = /^(longest|default)$/;
const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

async function sync(options: string[], io: AdminIo): Promise<number> {
  const [connection, ...rest] = options;
  if (connection === undefined || !UUID.test(connection) || rest.length > 0) {
    return usage(io);
  }
  const project = await projectFromEnv(io);
  if (project === undefined) return 1;
  const started = await callFunction(io, project, "eb-sync", {
    connection_id: connection,
    trigger: "admin",
  });
  if (!started.ok) {
    io.printError(`error: ${started.code}`);
    return 1;
  }
  const runId = started.body.run_id;
  if (typeof runId !== "string" || !UUID.test(runId)) {
    io.printError("error: internal");
    return 1;
  }
  if (started.body.status === "skipped") {
    io.print("sync: skipped (already_running)");
    return 1;
  }

  const sleep = io.sleep ??
    ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  let run: Record<string, unknown> | undefined;
  for (let poll = 0; poll < SYNC_MAX_POLLS; poll++) {
    await sleep(SYNC_POLL_MS);
    const read = await readRows(io, project, {
      select: RUN_COLUMNS,
      id: `eq.${runId}`,
    });
    if (!read.ok) {
      io.printError(`error: ${read.code}`);
      return 1;
    }
    const row = read.rows[0];
    if (row !== undefined && row.status !== "running") {
      run = row;
      break;
    }
  }
  if (run === undefined) {
    io.printError("error: still running, read sync_runs later");
    return 1;
  }

  const accounts = await readRows(io, project, {
    select: ACCOUNT_COLUMNS.join(","),
    run_id: `eq.${runId}`,
    order: "account_id",
  });
  if (!accounts.ok) {
    io.printError(`error: ${accounts.code}`);
    return 1;
  }
  const lines = syncLines(run, accounts.rows);
  if (lines === undefined) {
    io.printError("error: invalid_response");
    return 1;
  }
  for (const line of lines) io.print(line);
  return run.status === "ok" ? 0 : 1;
}

/**
 * The outcome of a run, only from values with a fixed shape (statuses,
 * codes, strategies, dates, counts); undefined if any value has another
 * shape.
 */
function syncLines(
  run: Record<string, unknown>,
  accounts: Record<string, unknown>[],
): string[] | undefined {
  const status = fixed(run.status, STATUS);
  const code = optional(run.error_code, CODE);
  const strategy = optional(run.strategy, STRATEGY);
  if (status === undefined || code === undefined || strategy === undefined) {
    return undefined;
  }
  const lines = [
    `sync: ${status}${code === null ? "" : ` (${code})`}`,
    `strategy: ${strategy ?? "none"}`,
    `accounts: ${accounts.length}`,
  ];
  for (const [index, account] of accounts.entries()) {
    const accountStatus = fixed(account.status, STATUS);
    const accountCode = optional(account.error_code, CODE);
    const accountStrategy = optional(account.strategy, STRATEGY);
    const asked = optional(account.date_from, ISO_DAY);
    const obtained = optional(account.history_from, ISO_DAY);
    const counts = COUNT_LABELS.map(([column, label]) => {
      const value = account[column];
      return typeof value === "number" && Number.isInteger(value) && value >= 0
        ? `${label} ${value}`
        : undefined;
    });
    if (
      accountStatus === undefined || accountCode === undefined ||
      accountStrategy === undefined || asked === undefined ||
      obtained === undefined ||
      typeof account.history_incomplete !== "boolean" ||
      counts.includes(undefined)
    ) {
      return undefined;
    }
    lines.push(
      `account ${index + 1}: ${accountStatus}${
        accountCode === null ? "" : ` (${accountCode})`
      }`,
      `  strategy ${accountStrategy ?? "none"}, asked from ${
        asked ?? "-"
      }, obtained from ${obtained ?? "-"}, history ${
        account.history_incomplete ? "incomplete" : "complete"
      }`,
      `  rows: ${counts.join(", ")}`,
    );
  }
  return lines;
}

/** The value when it is a string of the pattern, else undefined. */
function fixed(value: unknown, pattern: RegExp): string | undefined {
  return typeof value === "string" && pattern.test(value) ? value : undefined;
}

/** Like `fixed`, with null allowed. */
function optional(
  value: unknown,
  pattern: RegExp,
): string | null | undefined {
  return value === null ? null : fixed(value, pattern);
}

type RowsResult =
  | { ok: true; rows: Record<string, unknown>[] }
  | { ok: false; code: string };

/** GET of sync_runs through PostgREST with the secret key in `apikey`. */
async function readRows(
  io: AdminIo,
  project: Project,
  query: Record<string, string>,
): Promise<RowsResult> {
  const doFetch = io.fetch ?? ((input, init) => fetch(input, init));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FUNCTION_TIMEOUT_MS);
  let status: number;
  let text: string;
  try {
    const params = new URLSearchParams(query).toString();
    const response = await doFetch(
      `${project.url}/rest/v1/sync_runs?${params}`,
      {
        headers: { apikey: project.secretKey, Accept: "application/json" },
        signal: controller.signal,
      },
    );
    status = response.status;
    text = await response.text();
  } catch {
    return { ok: false, code: "unavailable" };
  } finally {
    clearTimeout(timer);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = undefined;
  }
  if (status >= 200 && status <= 299 && Array.isArray(parsed)) {
    const rows = parsed.filter((row): row is Record<string, unknown> =>
      typeof row === "object" && row !== null && !Array.isArray(row)
    );
    if (rows.length === parsed.length) return { ok: true, rows };
  }
  const code = typeof parsed === "object" && parsed !== null &&
      !Array.isArray(parsed)
    ? (parsed as Record<string, unknown>).code
    : undefined;
  return {
    ok: false,
    code: typeof code === "string" && /^(PGRST\d{1,4}|[0-9A-Z]{5})$/.test(code)
      ? code
      : `http_${status}`,
  };
}

interface Project {
  url: string;
  secretKey: string;
}

/** SUPABASE_URL and the secret key read from SB_SECRET_KEY_PATH. */
async function projectFromEnv(io: AdminIo): Promise<Project | undefined> {
  const url = io.env("SUPABASE_URL");
  const keyPath = io.env("SB_SECRET_KEY_PATH");
  if (!url || !keyPath || !/^https?:\/\/[^/]+/.test(url)) {
    io.printError("error: set SUPABASE_URL and SB_SECRET_KEY_PATH");
    return undefined;
  }
  let secretKey: string;
  try {
    secretKey = (await io.readTextFile(keyPath)).trim();
  } catch {
    io.printError("error: cannot read the file in SB_SECRET_KEY_PATH");
    return undefined;
  }
  if (secretKey === "" || /\s/.test(secretKey)) {
    io.printError(
      "error: the file in SB_SECRET_KEY_PATH holds one key, one line",
    );
    return undefined;
  }
  return { url: url.replace(/\/+$/, ""), secretKey };
}

/** EB_APP_ID and the private key read from EB_KEY_PATH. */
async function appFromEnv(
  io: AdminIo,
): Promise<{ appId: string; privateKey: string } | undefined> {
  const appId = io.env("EB_APP_ID");
  const keyPath = io.env("EB_KEY_PATH");
  if (!appId || !keyPath) {
    io.printError("error: set EB_APP_ID and EB_KEY_PATH");
    return undefined;
  }
  try {
    return { appId, privateKey: await io.readTextFile(keyPath) };
  } catch {
    io.printError("error: cannot read the file in EB_KEY_PATH");
    return undefined;
  }
}

type FunctionResult =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; code: string };

/** POST to an Edge Function with the secret key in `apikey`. */
async function callFunction(
  io: AdminIo,
  project: Project,
  name: string,
  body: Record<string, unknown>,
): Promise<FunctionResult> {
  const doFetch = io.fetch ?? ((input, init) => fetch(input, init));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FUNCTION_TIMEOUT_MS);
  let status: number;
  let text: string;
  try {
    const response = await doFetch(`${project.url}/functions/v1/${name}`, {
      method: "POST",
      headers: {
        apikey: project.secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    status = response.status;
    text = await response.text();
  } catch {
    return { ok: false, code: "unavailable" };
  } finally {
    clearTimeout(timer);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = undefined;
  }
  const record = typeof parsed === "object" && parsed !== null &&
      !Array.isArray(parsed)
    ? parsed as Record<string, unknown>
    : undefined;
  if (status >= 200 && status <= 299 && record?.ok === true) {
    return { ok: true, body: record };
  }
  const code = record?.error;
  return {
    ok: false,
    code: typeof code === "string" && CODE.test(code) ? code : `http_${status}`,
  };
}

/** Value of `--name value` or `--name=value`. */
function option(args: string[], name: string): string | undefined {
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === `--${name}`) return args[i + 1];
    if (arg?.startsWith(`--${name}=`)) return arg.slice(name.length + 3);
  }
  return undefined;
}

if (import.meta.main) {
  Deno.exit(
    await main(Deno.args, {
      env: (name) => Deno.env.get(name),
      readTextFile: (path) => Deno.readTextFile(path),
      print: (line) => console.log(line),
      printError: (line) => console.error(line),
    }),
  );
}
