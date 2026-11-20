/**
 * `eb-sync` (sincronizzazione.md, sections 1, 4, 5 and 6): syncs one
 * connection. `POST {connection_id, trigger}` without JWT: the secret of
 * the jobs in `x-sync-secret` (checked in SQL by `sync_secret_matches`) or
 * a secret key of the project in `apikey`; anything else is
 * `401 unauthorized`. `trigger` is `link`, `schedule`, `manual` or `admin`.
 *
 * The run is opened by `begin_sync_run` and the answer is `202` at once,
 * `{ok, run_id, status}` (`running`, or `skipped` when a sync of the
 * connection is already running); the work goes on in
 * `EdgeRuntime.waitUntil`, so a call from `pg_net` does not hang:
 *
 * 1. the connection, its owner, and one Enable Banking client of this
 *    request with the credentials of the owner (or the global application,
 *    if the connection was linked with it);
 * 2. consent from `GET /sessions/{id}`: expired or revoked ends the run with
 *    `consent_expired` or `consent_revoked`, which `finish_sync_run` writes
 *    on the connection. The consent is never deduced from an error of the
 *    transactions;
 * 3. for each account not archived: the balances (a failure other than the
 *    rate limit is only logged and the previous balances stay), all the
 *    pages of the transactions of the window (`window.ts`), shorter periods
 *    after `WRONG_TRANSACTIONS_PERIOD`, the normalization (a row refused as
 *    `invalid_row` is left out and counted in `rows_invalid`), then
 *    `ingest_bank_rows`. A failed page leaves the account as it was;
 * 4. once a run, after all the accounts and when at least one of them was
 *    imported (also with `partial`), the automatic transfers of the owner
 *    (`transfers.ts`, section 7.1). Their count goes in `matched_transfers`;
 *    a failure leaves the outcome of the accounts as it is, only its code
 *    in the log, and `matched_transfers` at 0;
 * 5. `finish_sync_run`: `ok` when every account is imported, `partial` with
 *    the code of the first failed account, `error` when the connection
 *    itself fails. A rate limit ends the connection: the accounts left are
 *    skipped, the code is `rate_limited`.
 *
 * Logs: steps with their code and duration, counts; never an amount, a
 * description, a counterparty, an email, an IBAN or a session.
 */

import { matchesAnyKey } from "../_shared/auth.ts";
import { memberCredentials } from "../_shared/credentials.ts";
import { Db, DbError } from "../_shared/db.ts";
import type { EnableBankingClient } from "../_shared/eb/client.ts";
import { EbError, type SyncErrorCode } from "../_shared/eb/errors.ts";
import { newEbClient } from "../_shared/eb/factory.ts";
import type { GetSessionResponse, Transaction } from "../_shared/eb/types.ts";
import { type GlobalApp, globalApp, supabaseEnv } from "../_shared/env.ts";
import type { Handler, HandlerDeps } from "../_shared/handler.ts";
import {
  errorResponse,
  HttpError,
  isRecord,
  jsonResponse,
  methodNotAllowed,
  readJsonObject,
  UUID,
} from "../_shared/http.ts";
import {
  consoleLogger,
  type Logger,
  stepper,
  timedStepper,
} from "../_shared/log.ts";
import { type ServiceMember, serviceMember } from "../_shared/member.ts";
import type { LinkedAccountKind } from "../_shared/normalize/account.ts";
import {
  InvalidBalanceError,
  type LinkBalance,
  linkBalances,
} from "../_shared/normalize/balance.ts";
import {
  InvalidRowError,
  type NormalizedTransaction,
  normalizeTransaction,
} from "../_shared/normalize/transaction.ts";
import { memberTransfers } from "./transfers.ts";
import {
  isoDay,
  shorterPeriods,
  type Strategy,
  type SyncWindow,
  syncWindow,
} from "./window.ts";

export const TRIGGERS = ["link", "schedule", "manual", "admin"] as const;
export type Trigger = typeof TRIGGERS[number];

/** The import of a long history takes longer than a plain call. */
export const INGEST_TIMEOUT_MS = 60_000;
const MAX_SECRET_LENGTH = 256;

/** Counts returned by `ingest_bank_rows`. */
const INGEST_COUNTS = [
  "rows_received",
  "raw_inserted",
  "transactions_created",
  "skipped_before_start",
  "skipped_status",
  "groups_shrunk",
  "booked_then_cancelled",
] as const;

type IngestCounts = Record<typeof INGEST_COUNTS[number], number>;

/** The row of an account for `finish_sync_run`. */
interface AccountResult extends Partial<IngestCounts> {
  account_id: string;
  status: "ok" | "error" | "skipped";
  error_code?: SyncErrorCode;
  strategy?: Strategy;
  date_from?: string;
  history_from?: string;
  history_incomplete?: boolean;
  amounts_rounded?: number;
  rows_invalid?: number;
}

interface Outcome {
  status: "ok" | "partial" | "error";
  errorCode: SyncErrorCode | null;
  accounts: AccountResult[];
  /** Automatic transfers created after the accounts (step 4). */
  matchedTransfers: number;
}

interface Connection {
  memberId: string;
  aspspName: string;
  sessionId: string | null;
  usesGlobalApp: boolean;
}

interface SyncAccount {
  id: string;
  uid: string | null;
  kind: LinkedAccountKind;
  cashAccountType: string | null;
}

/** A row in the shape of `ingest_bank_rows`. */
type IngestRow = Record<string, unknown>;

interface Work {
  deps: HandlerDeps;
  log: Logger;
  now: () => number;
  db: Db;
  ingestDb: Db;
  global: GlobalApp | undefined;
  runId: string;
  connectionId: string;
}

type Step = <T>(name: string, run: () => Promise<T> | T) => Promise<T>;

export function createHandler(deps: HandlerDeps): Handler {
  const log = deps.log ?? consoleLogger;
  const now = deps.now ?? Date.now;
  const waitUntil = deps.waitUntil ?? ((promise: Promise<unknown>) => {
    promise.catch(() => {});
  });

  return async (request) => {
    if (request.method !== "POST") {
      log({ fn: "eb-sync", step: "method", code: "method_not_allowed" });
      return methodNotAllowed("POST");
    }
    const step = stepper("eb-sync", log);
    try {
      const env = await step("env", () => ({
        supabase: supabaseEnv(deps.env),
        global: globalApp(deps.env),
      }));
      const db = new Db({
        url: env.supabase.url,
        apikey: env.supabase.secretKey,
        fetch: deps.fetch,
      });
      await step(
        "auth",
        () => authorize(request, db, env.supabase.secretKeys),
      );
      const { connectionId, trigger } = await step(
        "body",
        async () => syncRequest(await readJsonObject(request)),
      );
      const run = await step(
        "begin",
        () => beginRun(db, connectionId, trigger),
      );
      if (run.status === "skipped") {
        log({ fn: "eb-sync", step: "begin", code: "already_running" });
        return jsonResponse(202, {
          ok: true,
          run_id: run.runId,
          status: "skipped",
        });
      }

      waitUntil(syncConnection({
        deps,
        log,
        now,
        db,
        ingestDb: new Db({
          url: env.supabase.url,
          apikey: env.supabase.secretKey,
          fetch: deps.fetch,
          timeoutMs: INGEST_TIMEOUT_MS,
        }),
        global: env.global,
        runId: run.runId,
        connectionId,
      }));
      return jsonResponse(202, {
        ok: true,
        run_id: run.runId,
        status: "running",
      });
    } catch (error) {
      return error instanceof HttpError
        ? errorResponse(error.status, error.code)
        : errorResponse(500, "internal");
    }
  };
}

/** A secret key in `apikey`, else the secret of the jobs; else 401. */
async function authorize(
  request: Request,
  db: Db,
  secretKeys: readonly string[],
): Promise<void> {
  const apikey = request.headers.get("apikey");
  if (apikey !== null && await matchesAnyKey(apikey, secretKeys)) return;
  const secret = request.headers.get("x-sync-secret");
  if (
    secret !== null && secret !== "" && secret.length <= MAX_SECRET_LENGTH &&
    await db.rpc("sync_secret_matches", { secret }) === true
  ) {
    return;
  }
  throw new HttpError(401, "unauthorized");
}

/** `{connection_id, trigger}` and nothing else. */
function syncRequest(
  body: Record<string, unknown>,
): { connectionId: string; trigger: Trigger } {
  const { connection_id: connectionId, trigger } = body;
  if (
    Object.keys(body).some((key) =>
      key !== "connection_id" && key !== "trigger"
    ) ||
    typeof connectionId !== "string" || !UUID.test(connectionId) ||
    !TRIGGERS.includes(trigger as Trigger)
  ) {
    throw new HttpError(400, "invalid_request");
  }
  return { connectionId, trigger: trigger as Trigger };
}

async function beginRun(
  db: Db,
  connectionId: string,
  trigger: Trigger,
): Promise<{ runId: string; status: "running" | "skipped" }> {
  let rows: unknown;
  try {
    rows = await db.rpc("begin_sync_run", {
      connection_id: connectionId,
      trigger,
    });
  } catch (error) {
    if (error instanceof DbError && error.code === "connection_not_found") {
      throw new HttpError(404, "connection_not_found");
    }
    throw error;
  }
  const row: unknown = Array.isArray(rows) ? rows[0] : undefined;
  if (
    !isRecord(row) || typeof row.run_id !== "string" ||
    (row.status !== "running" && row.status !== "skipped")
  ) {
    throw new HttpError(500, "internal");
  }
  return { runId: row.run_id, status: row.status };
}

/** The work after the answer: never rejects, always tries to close the run. */
async function syncConnection(work: Work): Promise<void> {
  const started = work.now();
  const step: Step = timedStepper("eb-sync", work.log, work.now);
  let outcome: Outcome;
  try {
    outcome = await runSync(work, step);
  } catch (error) {
    outcome = {
      status: "error",
      errorCode: syncCode(error),
      accounts: [],
      matchedTransfers: 0,
    };
  }
  try {
    await step("finish", () =>
      work.db.rpc("finish_sync_run", {
        run_id: work.runId,
        status: outcome.status,
        error_code: outcome.errorCode,
        result: {
          strategy: runStrategy(outcome.accounts),
          matched_transfers: outcome.matchedTransfers,
          accounts: outcome.accounts,
        },
      }));
  } catch {
    // Only the code in the log: a run left running is closed as internal
    // by the next begin_sync_run after 15 minutes.
  }
  work.log({
    fn: "eb-sync",
    step: outcome.status,
    code: outcome.errorCode ?? "ok",
  });
  work.log({
    fn: "eb-sync",
    step: "run_ms",
    count: Math.max(0, work.now() - started),
  });
}

async function runSync(work: Work, step: Step): Promise<Outcome> {
  const connection = await step(
    "connection",
    () => readConnection(work.db, work.connectionId),
  );
  const member = await step(
    "member",
    () => serviceMember(work.db, connection.memberId),
  );
  const client = await step("credentials", async () => {
    const credentials = await memberCredentials(
      work.db,
      work.global,
      member.userId,
      connection.usesGlobalApp ? "global" : "own",
    );
    // A client of this request and person only.
    return (work.deps.newEbClient ?? newEbClient)({
      appId: credentials.appId,
      privateKey: credentials.privateKey,
      fetch: work.deps.fetch,
    });
  });

  const consent = await step("session", async () => {
    if (connection.sessionId === null) throw new HttpError(500, "internal");
    return consentCode(
      await client.getSession(connection.sessionId),
      work.now(),
    );
  });
  if (consent !== null) {
    work.log({ fn: "eb-sync", step: "consent", code: consent });
    return {
      status: "error",
      errorCode: consent,
      accounts: [],
      matchedTransfers: 0,
    };
  }

  const accounts = await step(
    "accounts",
    () => readAccounts(work.db, work.connectionId),
  );
  work.log({ fn: "eb-sync", step: "account_count", count: accounts.length });

  const today = isoDay(work.now());
  const results: AccountResult[] = [];
  let limited = false;
  for (const [index, account] of accounts.entries()) {
    if (limited) {
      results.push({ account_id: account.id, status: "skipped" });
      continue;
    }
    work.log({ fn: "eb-sync", step: "account", count: index + 1 });
    const result = await syncAccount(work, step, {
      client,
      connection,
      member,
      account,
      today,
    });
    results.push(result);
    limited = result.error_code === "rate_limited";
  }

  const matchedTransfers = results.some((result) => result.status === "ok")
    ? await transfers(work, step, member.memberId, today)
    : 0;

  const failed = results.find((result) => result.status === "error");
  if (failed === undefined) {
    return {
      status: "ok",
      errorCode: null,
      accounts: results,
      matchedTransfers,
    };
  }
  return {
    status: "partial",
    errorCode: limited ? "rate_limited" : failed.error_code ?? "internal",
    accounts: results,
    matchedTransfers,
  };
}

/**
 * The automatic transfers of the owner (section 7.1), once a run: a failure
 * leaves only its code in the log (step `match`) and counts 0.
 */
async function transfers(
  work: Work,
  step: Step,
  memberId: string,
  today: string,
): Promise<number> {
  let created = 0;
  try {
    created = await step(
      "match",
      () => memberTransfers(work.db, memberId, today),
    );
  } catch {
    // The accounts keep their outcome; the next run tries again.
  }
  work.log({ fn: "eb-sync", step: "matched_transfers", count: created });
  return created;
}

async function syncAccount(
  work: Work,
  step: Step,
  input: {
    client: EnableBankingClient;
    connection: Connection;
    member: ServiceMember;
    account: SyncAccount;
    today: string;
  },
): Promise<AccountResult> {
  const { client, account } = input;
  const failed = (code: SyncErrorCode, window?: SyncWindow): AccountResult => ({
    account_id: account.id,
    status: "error",
    error_code: code,
    ...(window === undefined
      ? {}
      : { strategy: window.strategy, date_from: window.dateFrom }),
  });
  const uid = account.uid;
  if (uid === null) {
    work.log({ fn: "eb-sync", step: "account_uid", code: "internal" });
    return failed("internal");
  }

  let window: SyncWindow;
  try {
    window = await step(
      "window",
      () => accountWindow(work.db, account, input.member.startDate),
    );
  } catch (error) {
    return failed(syncCode(error));
  }
  work.log({ fn: "eb-sync", step: "strategy", code: window.strategy });

  try {
    const saved = await step(
      "balances",
      () => saveBalances(work, client, account.id, uid),
    );
    work.log({ fn: "eb-sync", step: "balances_saved", count: saved });
  } catch (error) {
    // The previous balances stay; only a rate limit stops the account.
    if (error instanceof EbError && error.code === "rate_limited") {
      return failed("rate_limited", window);
    }
  }

  let download: { transactions: Transaction[]; historyFrom: string };
  try {
    download = await step(
      "transactions",
      () => downloadTransactions(work, client, uid, window, input.today),
    );
  } catch (error) {
    const code = syncCode(error);
    // The consent comes only from the session, never from the transactions.
    return failed(
      code === "consent_expired" || code === "consent_revoked"
        ? "bank_error"
        : code,
      window,
    );
  }
  work.log({
    fn: "eb-sync",
    step: "rows_downloaded",
    count: download.transactions.length,
  });

  try {
    const normalized = await step(
      "normalize",
      () =>
        normalizeRows(download.transactions, {
          aspspName: input.connection.aspspName,
          cashAccountType: account.cashAccountType,
          accountKind: account.kind,
        }),
    );
    work.log({
      fn: "eb-sync",
      step: "rows_invalid",
      count: normalized.invalid,
    });
    work.log({
      fn: "eb-sync",
      step: "amounts_rounded",
      count: normalized.rounded,
    });

    const counts = await step(
      "ingest",
      () => ingest(work.ingestDb, account.id, normalized.rows),
    );
    for (const name of INGEST_COUNTS) {
      work.log({ fn: "eb-sync", step: name, count: counts[name] });
    }
    return {
      account_id: account.id,
      status: "ok",
      strategy: window.strategy,
      date_from: window.dateFrom,
      history_from: download.historyFrom,
      history_incomplete: download.historyFrom > window.dateFrom,
      ...counts,
      amounts_rounded: normalized.rounded,
      rows_invalid: normalized.invalid,
    };
  } catch (error) {
    return failed(syncCode(error), window);
  }
}

/** The window of an account: first sync, or after the last successful one. */
async function accountWindow(
  db: Db,
  account: SyncAccount,
  startDate: string,
): Promise<SyncWindow> {
  const raw = await db.select("bank_raw_transactions", {
    select: "id",
    account_id: `eq.${account.id}`,
    limit: "1",
  });
  const firstSync = raw.length === 0;
  let lastSuccess: string | null = null;
  if (!firstSync) {
    const runs = await db.select("sync_runs", {
      select: "started_at",
      account_id: `eq.${account.id}`,
      status: "eq.ok",
      order: "started_at.desc",
      limit: "1",
    });
    const run: unknown = runs[0];
    if (run !== undefined) {
      const startedAt = isRecord(run) && typeof run.started_at === "string"
        ? Date.parse(run.started_at)
        : Number.NaN;
      if (Number.isNaN(startedAt)) throw new HttpError(500, "internal");
      lastSuccess = isoDay(startedAt);
    }
  }
  return syncWindow({ kind: account.kind, startDate, firstSync, lastSuccess });
}

/** All the balances of the account, the last value of each currency and type. */
async function saveBalances(
  work: Work,
  client: EnableBankingClient,
  accountId: string,
  uid: string,
): Promise<number> {
  const latest = new Map<string, LinkBalance>();
  for (const balance of linkBalances(await client.getBalances(uid))) {
    latest.set(`${balance.currency} ${balance.balance_type}`, balance);
  }
  if (latest.size === 0) return 0;
  const fetchedAt = new Date(work.now()).toISOString();
  await work.db.upsert(
    "account_balances",
    [...latest.values()].map((balance) => ({
      account_id: accountId,
      ...balance,
      fetched_at: fetchedAt,
    })),
    "account_id,currency,balance_type",
  );
  return latest.size;
}

/**
 * All the pages of the window; after `WRONG_TRANSACTIONS_PERIOD` the
 * shorter periods, until one is accepted. `historyFrom` is the date
 * obtained.
 */
async function downloadTransactions(
  work: Work,
  client: EnableBankingClient,
  uid: string,
  window: SyncWindow,
  today: string,
): Promise<{ transactions: Transaction[]; historyFrom: string }> {
  const dates = [window.dateFrom, ...shorterPeriods(window.dateFrom, today)];
  for (const [index, dateFrom] of dates.entries()) {
    try {
      const transactions = await client.getAllTransactions(
        uid,
        window.strategy === "longest"
          ? { dateFrom, strategy: "longest" }
          : { dateFrom },
      );
      return { transactions, historyFrom: dateFrom };
    } catch (error) {
      const shorter = error instanceof EbError &&
        error.code === "period_rejected" && index + 1 < dates.length;
      if (!shorter) throw error;
      work.log({ fn: "eb-sync", step: "period_retry", count: index + 1 });
    }
  }
  throw new EbError("period_rejected");
}

/** The rows for `ingest_bank_rows`; `invalid_row` rows are only counted. */
async function normalizeRows(
  transactions: readonly Transaction[],
  context: Parameters<typeof normalizeTransaction>[1],
): Promise<{ rows: IngestRow[]; invalid: number; rounded: number }> {
  const rows: IngestRow[] = [];
  let invalid = 0;
  let rounded = 0;
  for (const transaction of transactions) {
    let normalized: NormalizedTransaction;
    try {
      normalized = await normalizeTransaction(transaction, context);
    } catch (error) {
      if (error instanceof InvalidRowError) {
        invalid++;
        continue;
      }
      throw error;
    }
    if (normalized.amount_rounded) rounded++;
    rows.push(ingestRow(normalized));
  }
  return { rows, invalid, rounded };
}

/** The raw fields with the signed amount, and the fields of the movement. */
export function ingestRow(normalized: NormalizedTransaction): IngestRow {
  const { raw, movement } = normalized;
  return {
    entry_reference: raw.entry_reference,
    status: raw.status,
    booking_date: raw.booking_date,
    value_date: raw.value_date,
    transaction_date: raw.transaction_date,
    amount_cents: movement.amount_cents,
    currency: raw.currency,
    dedup_hash: raw.dedup_hash,
    payload: raw.payload,
    original_amount_cents: movement.original_amount_cents,
    original_currency: movement.original_currency,
    exchange_rate: movement.exchange_rate,
    description: movement.description,
    counterparty: movement.counterparty,
    counterparty_email: movement.counterparty_email,
    bank_code: movement.bank_code,
  };
}

async function ingest(
  db: Db,
  accountId: string,
  rows: IngestRow[],
): Promise<IngestCounts> {
  const result = await db.rpc("ingest_bank_rows", {
    account_id: accountId,
    rows,
  });
  const row: unknown = Array.isArray(result) ? result[0] : undefined;
  if (!isRecord(row)) throw new HttpError(500, "internal");
  const counts = {} as IngestCounts;
  for (const name of INGEST_COUNTS) {
    const value = row[name];
    if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
      throw new HttpError(500, "internal");
    }
    counts[name] = value;
  }
  return counts;
}

async function readConnection(db: Db, id: string): Promise<Connection> {
  const rows = await db.select("bank_connections", {
    select: "member_id,aspsp_name,session_id,uses_global_app",
    id: `eq.${id}`,
  });
  const row: unknown = rows[0];
  if (
    !isRecord(row) || typeof row.member_id !== "string" ||
    typeof row.aspsp_name !== "string" ||
    (row.session_id !== null && typeof row.session_id !== "string") ||
    typeof row.uses_global_app !== "boolean"
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    memberId: row.member_id,
    aspspName: row.aspsp_name,
    sessionId: row.session_id,
    usesGlobalApp: row.uses_global_app,
  };
}

const ACCOUNT_KINDS: readonly string[] = ["bank", "card", "paypal"];

/** The accounts of the connection not archived, in a fixed order. */
async function readAccounts(db: Db, connectionId: string) {
  const rows = await db.select("accounts", {
    select: "id,provider_account_id,kind,cash_account_type",
    connection_id: `eq.${connectionId}`,
    archived_at: "is.null",
    order: "id",
  });
  return rows.map((row): SyncAccount => {
    if (
      !isRecord(row) || typeof row.id !== "string" ||
      typeof row.kind !== "string" || !ACCOUNT_KINDS.includes(row.kind) ||
      (row.provider_account_id !== null &&
        typeof row.provider_account_id !== "string") ||
      (row.cash_account_type !== null &&
        typeof row.cash_account_type !== "string")
    ) {
      throw new HttpError(500, "internal");
    }
    return {
      id: row.id,
      uid: row.provider_account_id === "" ? null : row.provider_account_id,
      kind: row.kind as LinkedAccountKind,
      cashAccountType: row.cash_account_type,
    };
  });
}

/**
 * The code of a consent that no longer works, from the session: null when
 * it is authorized and still valid.
 */
export function consentCode(
  session: GetSessionResponse,
  nowMs: number,
): SyncErrorCode | null {
  switch (session.status) {
    case "AUTHORIZED": {
      const access: unknown = session.access;
      const validUntil = isRecord(access) ? access.valid_until : undefined;
      const until = typeof validUntil === "string"
        ? Date.parse(validUntil)
        : Number.NaN;
      return !Number.isNaN(until) && until <= nowMs ? "consent_expired" : null;
    }
    case "EXPIRED":
      return "consent_expired";
    case "REVOKED":
    case "CLOSED":
    case "CANCELLED":
    case "INVALID":
      return "consent_revoked";
    default:
      return "bank_error";
  }
}

/** The code of a failure for `sync_runs` (section 4). */
function syncCode(error: unknown): SyncErrorCode {
  if (error instanceof EbError) return error.code;
  if (error instanceof InvalidBalanceError) return "bank_error";
  if (error instanceof HttpError && error.code === "no_credentials") {
    return "no_credentials";
  }
  return "internal";
}

/** `longest` when an account asked for it, else `default`; null without. */
function runStrategy(accounts: readonly AccountResult[]): Strategy | null {
  const strategies = accounts.map((account) => account.strategy);
  if (strategies.includes("longest")) return "longest";
  return strategies.includes("default") ? "default" : null;
}
