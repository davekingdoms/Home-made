/**
 * A fake project for the tests of the Edge Functions: PostgREST (the SQL
 * functions by name) and Enable Banking behind one `fetch`, no network.
 * All values are invented: Anna and Bruno of "Casa di prova", keys built at
 * run time so that no key-shaped text sits in the sources.
 */

import { assert, assertEquals, assertFalse } from "@std/assert";
import type { EnvGetter } from "../env.ts";
import { fakeFetch, json } from "./fake_fetch.ts";

export const SUPABASE_URL = "https://progetto-di-prova.example.com";
export const EB_HOST = "api.enablebanking.com";
export const REDIRECT_URL = `${SUPABASE_URL}/functions/v1/eb-callback`;
export const RETURN_URL = "https://pagine-di-prova.example.com/bank-link/";

const prefix = (kind: string) => ["sb", kind, ""].join("_");
export const SECRET_KEY = `${prefix("secret")}chiave-di-prova-1`;
export const OTHER_SECRET_KEY = `${prefix("secret")}chiave-di-prova-2`;
export const PUBLISHABLE_KEY = `${prefix("publishable")}chiave-di-prova`;

/** User JWTs: three parts, invented, checked only by the fake PostgREST. */
export const JWT_ANNA = "intestazione.contenuto-anna.firma-anna";
export const JWT_BRUNO = "intestazione.contenuto-bruno.firma-bruno";
export const JWT_FORMER = "intestazione.contenuto-ex.firma-ex";
export const JWT_FORGED = "intestazione.contenuto-falso.firma-falsa";

export const ANNA = {
  memberId: "00000000-0000-4000-8000-0000000000a1",
  userId: "00000000-0000-4000-8000-00000000000a",
  appId: "00000000-0000-4000-8000-00000000a99a",
};
export const BRUNO = {
  memberId: "00000000-0000-4000-8000-0000000000b1",
  userId: "00000000-0000-4000-8000-00000000000b",
  appId: "00000000-0000-4000-8000-00000000b99b",
};
export const HOUSEHOLD_ID = "00000000-0000-4000-8000-0000000000f1";
export const GLOBAL_APP_ID = "00000000-0000-4000-8000-00000000c99c";

export function testEnv(
  overrides: Record<string, string | undefined> = {},
): EnvGetter {
  const env: Record<string, string | undefined> = {
    SUPABASE_URL,
    SUPABASE_SECRET_KEYS: JSON.stringify({
      default: SECRET_KEY,
      altra: OTHER_SECRET_KEY,
    }),
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: PUBLISHABLE_KEY }),
    EB_REDIRECT_URL: REDIRECT_URL,
    APP_RETURN_URL: RETURN_URL,
    ...overrides,
  };
  return (name) => env[name];
}

/** A PostgREST error, with texts that must never be copied anywhere. */
export function pgError(
  status: number,
  code: string,
  message: string,
  details: string | null = null,
): Response {
  return json({ code, message, details, hint: null }, status);
}

export type RpcHandler = (
  args: Record<string, unknown>,
  request: Request,
) => unknown;

export type EbHandler = (request: Request) => Response | Promise<Response>;

export interface RpcCall {
  name: string;
  args: Record<string, unknown>;
  apikey: string | null;
  authorization: string | null;
}

/** A read or write of a table: the URL holds the PostgREST parameters. */
export type RestHandler = (url: URL, request: Request) => unknown;

export interface RestCall {
  /** `METHOD table`, e.g. `GET accounts`. */
  route: string;
  url: URL;
  apikey: string | null;
}

export interface FakeProject {
  fetch: typeof fetch;
  rpcCalls: RpcCall[];
  restCalls: RestCall[];
  ebRequests: Request[];
}

/**
 * `rpc` answers the SQL functions by name (a plain value becomes a 200
 * JSON answer); `rest` answers the tables by `METHOD table`; `eb` answers
 * Enable Banking by `METHOD /path`.
 */
export function fakeProject(handlers: {
  rpc?: Record<string, RpcHandler>;
  rest?: Record<string, RestHandler>;
  eb?: Record<string, EbHandler>;
}): FakeProject {
  const rpc = { ...defaultRpc(), ...handlers.rpc };
  const rpcCalls: RpcCall[] = [];
  const restCalls: RestCall[] = [];
  const ebRequests: Request[] = [];
  const fake = fakeFetch(async (request) => {
    const url = new URL(request.url);
    if (url.host === EB_HOST) {
      ebRequests.push(request.clone());
      const handler = handlers.eb?.[`${request.method} ${url.pathname}`];
      return handler === undefined
        ? json({ error: "NOT_FOUND" }, 404)
        : await handler(request);
    }
    assertEquals(url.origin, SUPABASE_URL, "unexpected host");
    if (!url.pathname.startsWith("/rest/v1/rpc/")) {
      const route = `${request.method} ${
        url.pathname.replace(/^\/rest\/v1\//, "")
      }`;
      restCalls.push({ route, url, apikey: request.headers.get("apikey") });
      const handler = handlers.rest?.[route];
      if (handler === undefined) {
        return pgError(404, "PGRST205", "Could not find the table");
      }
      const result = await handler(url, request);
      return result instanceof Response ? result : json(result);
    }
    const name = url.pathname.replace(/^\/rest\/v1\/rpc\//, "");
    assertEquals(request.method, "POST");
    const args = await request.json() as Record<string, unknown>;
    rpcCalls.push({
      name,
      args,
      apikey: request.headers.get("apikey"),
      authorization: request.headers.get("Authorization"),
    });
    const handler = rpc[name];
    if (handler === undefined) {
      return pgError(404, "PGRST202", "Could not find the function");
    }
    const result = await handler(args, request);
    return result instanceof Response ? result : json(result);
  });
  return { fetch: fake.fetch, rpcCalls, restCalls, ebRequests };
}

/** Members, user JWTs and credentials of Anna and Bruno. */
function defaultRpc(): Record<string, RpcHandler> {
  return {
    current_member_id: (_args, request) => {
      assertEquals(request.headers.get("apikey"), PUBLISHABLE_KEY);
      switch (request.headers.get("Authorization")) {
        case `Bearer ${JWT_ANNA}`:
          return ANNA.memberId;
        case `Bearer ${JWT_BRUNO}`:
          return BRUNO.memberId;
        case `Bearer ${JWT_FORMER}`:
          return null;
        default:
          return pgError(401, "PGRST301", "JWT could not be decoded");
      }
    },
    eb_service_member: (args, request) => {
      assertEquals(request.headers.get("apikey"), SECRET_KEY);
      assertEquals(request.headers.get("Authorization"), null);
      const member = [ANNA, BRUNO].find((m) => m.memberId === args.member_id);
      if (member === undefined) {
        return pgError(400, "P0001", "member_not_eligible");
      }
      return {
        member_id: member.memberId,
        user_id: member.userId,
        household_id: HOUSEHOLD_ID,
        start_date: "2031-03-01",
      };
    },
  };
}

/**
 * Credentials of a person, as `eb_get_credentials` returns them: the
 * application ID and the PEM of the test keys generated for that person.
 */
export function credentialsRpc(
  byUser: Record<string, { appId: string; keys: { pkcs8Pem: string } }>,
): RpcHandler {
  return (args) => {
    const found = byUser[String(args.user_id)];
    if (found === undefined) return [];
    const pem = found.keys.pkcs8Pem;
    return [{ app_id: found.appId, private_key: pem }];
  };
}

/** None of the values appears in any of the texts. */
export function assertNothingSensitive(
  texts: readonly string[],
  values: readonly string[],
): void {
  const all = texts.join("\n");
  for (const value of values) {
    assert(value.length >= 4, "too short to check");
    assertFalse(all.includes(value), "a sensitive value reached the output");
  }
}

/** Distinctive pieces of a PEM key: lines of its body. */
export function pemPieces(pem: string): string[] {
  return pem.split("\n").filter((line) => line.length > 40).slice(0, 3)
    .map((line) => line.slice(0, 32));
}
