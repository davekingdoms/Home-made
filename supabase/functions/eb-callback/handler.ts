/**
 * `eb-callback` (sincronizzazione.md, section 3, steps 6–7): the return from
 * Enable Banking, public (`GET`, no JWT). It always answers `302` towards
 * `APP_RETURN_URL` with `esito` and, unless ok, `codice`: never anything
 * else in the URL.
 *
 * 1. `state` missing or not a uuid: `link_expired`, without the database;
 *    `claim_link_request` without a row: `link_expired`.
 * 2. `error`: `access_denied` is `link_cancelled`, anything else
 *    `link_rejected`; the request takes the code.
 * 3. No `code`: `link_failed`.
 * 4. A new client with the credentials of the request (own application or
 *    the global one, as at the start), `POST /sessions`.
 * 5. Accounts of the session (6.4) and their balances (6.5); an account
 *    without `uid` is skipped, a balance that cannot be read leaves that
 *    account without balances.
 * 6. `complete_bank_link`: connection, accounts, balances, PayPal email,
 *    all in one transaction.
 * 7. Any failure after the claim: `finish_link_request(…, 'link_failed')`.
 * 8. The first sync, at once: `request_bank_sync(connection_id, 'link')`.
 *    The link is complete either way: if the request fails, the outcome
 *    stays ok and only its code reaches the log.
 */

import { memberCredentials } from "../_shared/credentials.ts";
import { Db } from "../_shared/db.ts";
import { newEbClient } from "../_shared/eb/factory.ts";
import type { AuthorizeSessionResponse } from "../_shared/eb/types.ts";
import {
  type GlobalApp,
  globalApp,
  supabaseEnv,
  urlVariable,
} from "../_shared/env.ts";
import type { Handler, HandlerDeps } from "../_shared/handler.ts";
import {
  errorResponse,
  HttpError,
  isRecord,
  methodNotAllowed,
  UUID,
} from "../_shared/http.ts";
import { codeOf, consoleLogger, type Logger, stepper } from "../_shared/log.ts";
import { serviceMember } from "../_shared/member.ts";
import {
  type LinkedAccount,
  linkedAccount,
} from "../_shared/normalize/account.ts";
import {
  type LinkBalance,
  linkBalances,
} from "../_shared/normalize/balance.ts";

type Outcome = "ok" | "annullato" | "errore";
type FailureCode =
  | "link_expired"
  | "link_cancelled"
  | "link_rejected"
  | "link_failed";

interface LinkRequest {
  id: string;
  memberId: string;
  aspspName: string;
  usesGlobalApp: boolean;
}

export function createHandler(deps: HandlerDeps): Handler {
  const log = deps.log ?? consoleLogger;

  return async (request) => {
    if (request.method !== "GET") {
      log({ fn: "eb-callback", step: "method", code: "method_not_allowed" });
      return methodNotAllowed("GET");
    }
    let returnUrl: string;
    try {
      returnUrl = urlVariable(deps.env, "APP_RETURN_URL");
    } catch {
      log({ fn: "eb-callback", step: "env", code: "internal" });
      return errorResponse(500, "internal");
    }
    const outcome = await callback(request, deps, log);
    return redirect(returnUrl, outcome.esito, outcome.codice);
  };
}

async function callback(
  request: Request,
  deps: HandlerDeps,
  log: Logger,
): Promise<{ esito: Outcome; codice?: FailureCode }> {
  const step = stepper("eb-callback", log);
  const params = new URL(request.url).searchParams;
  const fail = (codice: FailureCode) => ({
    esito: codice === "link_cancelled"
      ? "annullato" as const
      : "errore" as const,
    codice,
  });

  const state = single(params, "state");
  if (state === null || !UUID.test(state)) {
    log({ fn: "eb-callback", step: "state", code: "link_expired" });
    return fail("link_expired");
  }

  let server: { db: Db; global: GlobalApp | undefined };
  try {
    const supabase = supabaseEnv(deps.env);
    server = {
      db: new Db({
        url: supabase.url,
        apikey: supabase.secretKey,
        fetch: deps.fetch,
      }),
      global: globalApp(deps.env),
    };
  } catch (error) {
    log({ fn: "eb-callback", step: "env", code: codeOf(error) });
    return fail("link_failed");
  }
  const { db, global } = server;

  let claimed: LinkRequest | null;
  try {
    claimed = await step("claim", () => claim(db, state));
  } catch {
    return fail("link_failed");
  }
  if (claimed === null) {
    log({ fn: "eb-callback", step: "claim", code: "link_expired" });
    return fail("link_expired");
  }
  const linkRequest = claimed;

  const finish = async (codice: Exclude<FailureCode, "link_expired">) => {
    try {
      await step(
        "finish",
        () =>
          db.rpc("finish_link_request", { request_id: state, result: codice }),
      );
    } catch {
      // Only the code in the log: the redirect stays the same.
    }
    return fail(codice);
  };

  if (params.has("error")) {
    const codice = params.get("error") === "access_denied"
      ? "link_cancelled"
      : "link_rejected";
    log({ fn: "eb-callback", step: "bank_error", code: codice });
    return await finish(codice);
  }

  const code = single(params, "code");
  if (code === null || code === "") {
    log({ fn: "eb-callback", step: "code", code: "link_failed" });
    return await finish("link_failed");
  }

  let completed: unknown;
  try {
    const member = await step(
      "member",
      () => serviceMember(db, linkRequest.memberId),
    );
    const client = await step("credentials", async () => {
      const credentials = await memberCredentials(
        db,
        global,
        member.userId,
        linkRequest.usesGlobalApp ? "global" : "own",
      );
      // A client of this request and person only.
      return (deps.newEbClient ?? newEbClient)({
        appId: credentials.appId,
        privateKey: credentials.privateKey,
        fetch: deps.fetch,
      });
    });

    const session = await step("session", () => client.createSession(code));
    const validUntil = sessionValidUntil(session);

    const accounts: (LinkedAccount & { balances: LinkBalance[] })[] = [];
    let skipped = 0;
    for (const resource of session.accounts) {
      const account = linkedAccount(linkRequest.aspspName, resource);
      if (account === null) {
        skipped++;
        continue;
      }
      let balances: LinkBalance[] = [];
      try {
        balances = await step(
          "balances",
          async () => linkBalances(await client.getBalances(account.uid)),
        );
      } catch {
        // The account stays without balances; the code is in the log.
      }
      accounts.push({ ...account, balances });
    }
    log({ fn: "eb-callback", step: "accounts", count: accounts.length });
    if (skipped > 0) {
      log({ fn: "eb-callback", step: "accounts_skipped", count: skipped });
    }

    completed = await step("complete", () =>
      db.rpc("complete_bank_link", {
        request_id: state,
        link: {
          session_id: session.session_id,
          valid_until: validUntil,
          accounts,
        },
      }));
  } catch {
    return await finish("link_failed");
  }

  try {
    await step("sync_request", () => requestFirstSync(db, completed));
  } catch {
    // Only the code in the log: the link is complete, and the first sync
    // comes with the scheduled ones or the service script.
  }
  return { esito: "ok" };
}

/** `request_bank_sync` for the connection returned by `complete_bank_link`. */
async function requestFirstSync(db: Db, completed: unknown): Promise<void> {
  const row: unknown = Array.isArray(completed) ? completed[0] : undefined;
  if (
    !isRecord(row) || typeof row.connection_id !== "string" ||
    !UUID.test(row.connection_id)
  ) {
    throw new HttpError(500, "internal");
  }
  await db.rpc("request_bank_sync", {
    connection_id: row.connection_id,
    trigger: "link",
  });
}

/** The request of the state, claimed once; null if unknown, expired or used. */
async function claim(db: Db, state: string): Promise<LinkRequest | null> {
  const rows = await db.rpc("claim_link_request", { id: state });
  if (!Array.isArray(rows)) throw new HttpError(500, "internal");
  const row: unknown = rows[0];
  if (row === undefined) return null;
  if (
    !isRecord(row) || typeof row.member_id !== "string" ||
    typeof row.aspsp_name !== "string" ||
    typeof row.uses_global_app !== "boolean"
  ) {
    throw new HttpError(500, "internal");
  }
  return {
    id: state,
    memberId: row.member_id,
    aspspName: row.aspsp_name,
    usesGlobalApp: row.uses_global_app,
  };
}

function sessionValidUntil(session: AuthorizeSessionResponse): string {
  const access: unknown = session.access;
  const validUntil = isRecord(access) ? access.valid_until : undefined;
  if (typeof validUntil !== "string") throw new HttpError(502, "bank_error");
  return validUntil;
}

/** The parameter when it appears exactly once, otherwise null. */
function single(params: URLSearchParams, name: string): string | null {
  const values = params.getAll(name);
  return values.length === 1 ? values[0] ?? null : null;
}

function redirect(returnUrl: string, esito: Outcome, codice?: string) {
  const url = new URL(returnUrl);
  url.search = "";
  url.hash = "";
  url.searchParams.set("esito", esito);
  if (codice !== undefined) url.searchParams.set("codice", codice);
  return new Response(null, {
    status: 302,
    headers: {
      Location: url.toString(),
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}
