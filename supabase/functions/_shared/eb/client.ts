/**
 * Client of the Enable Banking API (sincronizzazione.md, sections 1–4):
 * JWT, calls, pagination, errors turned into sync codes.
 *
 * Every call has its own timeout; a failure is always an `EbError` with a
 * code, never the bank's text. `fetch` can be injected for tests.
 */

import { EbError, ebErrorCode } from "./errors.ts";
import { importPrivateKey, JWT_TTL_SECONDS, signJwt } from "./jwt.ts";
import type {
  AccountResource,
  AuthorizeSessionResponse,
  GetAspspsResponse,
  GetSessionResponse,
  HalBalances,
  HalTransactions,
  StartAuthRequest,
  StartAuthResponse,
  Transaction,
  TransactionsFetchStrategy,
} from "./types.ts";

export const EB_BASE_URL = "https://api.enablebanking.com";
/** Timeout of a single call, body included. */
export const EB_TIMEOUT_MS = 20_000;
/** Safety stop for a bank that never ends its pages. */
export const EB_MAX_PAGES = 1_000;
/** A cached JWT is renewed when less than this is left of its life. */
const JWT_RENEW_MARGIN_SECONDS = 5 * 60;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export interface EnableBankingClientOptions {
  /** Application ID: the `kid` of the JWT. */
  appId: string;
  /** PEM (PKCS#8 or PKCS#1) or a key already imported for RS256 signing. */
  privateKey: string | CryptoKey;
  fetch?: typeof fetch;
  baseUrl?: string;
  timeoutMs?: number;
  /** Clock in milliseconds since the epoch, for tests. */
  now?: () => number;
}

export interface TransactionsQuery {
  /** ISO date `YYYY-MM-DD`. */
  dateFrom: string;
  /** ISO date `YYYY-MM-DD`; missing = up to today. */
  dateTo?: string;
  /** Missing = the API default (`default`). */
  strategy?: TransactionsFetchStrategy;
  continuationKey?: string;
}

type Guard<T> = (body: unknown) => body is T;

interface RequestOptions {
  query?: Record<string, string | undefined>;
  body?: unknown;
}

export class EnableBankingClient {
  readonly #appId: string;
  readonly #privateKey: string | CryptoKey;
  readonly #fetch: typeof fetch;
  readonly #baseUrl: string;
  readonly #timeoutMs: number;
  readonly #now: () => number;
  #key: Promise<CryptoKey> | undefined;
  #jwt: { token: string; expiresAt: number } | undefined;

  constructor(options: EnableBankingClientOptions) {
    if (options.appId.trim() === "") {
      throw new EbError("invalid_credentials", {
        detail: "empty application ID",
      });
    }
    this.#appId = options.appId;
    this.#privateKey = options.privateKey;
    this.#fetch = options.fetch ?? ((input, init) => fetch(input, init));
    this.#baseUrl = (options.baseUrl ?? EB_BASE_URL).replace(/\/+$/, "");
    this.#timeoutMs = options.timeoutMs ?? EB_TIMEOUT_MS;
    this.#now = options.now ?? Date.now;
  }

  /** `GET /aspsps`: the banks available, optionally of one country. */
  async getAspsps(country?: string): Promise<GetAspspsResponse> {
    return await this.#request("GET", "/aspsps", isAspsps, {
      query: { country },
    });
  }

  /** `POST /auth`: starts the authorization and returns its URL. */
  async startAuth(request: StartAuthRequest): Promise<StartAuthResponse> {
    return await this.#request("POST", "/auth", isStartAuth, { body: request });
  }

  /** `POST /sessions`: turns the code of the redirect into a session. */
  async createSession(code: string): Promise<AuthorizeSessionResponse> {
    return await this.#request("POST", "/sessions", isAuthorizedSession, {
      body: { code },
    });
  }

  /** `GET /sessions/{session_id}`: status and validity of the consent. */
  async getSession(sessionId: string): Promise<GetSessionResponse> {
    return await this.#request(
      "GET",
      `/sessions/${segment(sessionId)}`,
      isSession,
    );
  }

  /** `GET /accounts/{uid}/details`. */
  async getAccountDetails(accountUid: string): Promise<AccountResource> {
    return await this.#request(
      "GET",
      `/accounts/${segment(accountUid)}/details`,
      isAccount,
    );
  }

  /** `GET /accounts/{uid}/balances`. */
  async getBalances(accountUid: string): Promise<HalBalances> {
    return await this.#request(
      "GET",
      `/accounts/${segment(accountUid)}/balances`,
      isBalances,
    );
  }

  /** `GET /accounts/{uid}/transactions`: one page. */
  async getTransactions(
    accountUid: string,
    query: TransactionsQuery,
  ): Promise<HalTransactions> {
    checkDate(query.dateFrom);
    if (query.dateTo !== undefined) checkDate(query.dateTo);
    return await this.#request(
      "GET",
      `/accounts/${segment(accountUid)}/transactions`,
      isTransactionsPage,
      {
        query: {
          date_from: query.dateFrom,
          date_to: query.dateTo,
          strategy: query.strategy,
          continuation_key: query.continuationKey,
        },
      },
    );
  }

  /**
   * All the pages of `GET /accounts/{uid}/transactions`, following
   * `continuation_key` with the same query until the last page. A failed
   * page rejects the whole call: a partial list is never returned.
   */
  async getAllTransactions(
    accountUid: string,
    query: Omit<TransactionsQuery, "continuationKey">,
  ): Promise<Transaction[]> {
    const transactions: Transaction[] = [];
    const seenKeys = new Set<string>();
    let continuationKey: string | undefined;
    for (let page = 1; page <= EB_MAX_PAGES; page++) {
      const result = await this.getTransactions(accountUid, {
        ...query,
        continuationKey,
      });
      for (const transaction of result.transactions) {
        transactions.push(transaction);
      }
      const next = result.continuation_key;
      if (next === undefined || next === null || next === "") {
        return transactions;
      }
      if (seenKeys.has(next)) {
        throw new EbError("bank_error", {
          detail: "repeated continuation_key",
        });
      }
      seenKeys.add(next);
      continuationKey = next;
    }
    throw new EbError("bank_error", { detail: "too many pages" });
  }

  async #request<T>(
    method: "GET" | "POST",
    path: string,
    guard: Guard<T>,
    options: RequestOptions = {},
  ): Promise<T> {
    const url = new URL(this.#baseUrl + path);
    for (const [name, value] of Object.entries(options.query ?? {})) {
      if (value !== undefined) url.searchParams.set(name, value);
    }
    const headers: Record<string, string> = {
      Authorization: `Bearer ${await this.#token()}`,
      Accept: "application/json",
    };
    let body: string | undefined;
    if (options.body !== undefined) {
      headers["Content-Type"] = "application/json";
      body = JSON.stringify(options.body);
    }

    const { status, text } = await this.#send(url, { method, headers, body });
    const parsed = parseJson(text);
    if (status < 200 || status > 299) {
      const ebError = isRecord(parsed) && typeof parsed.error === "string"
        ? parsed.error
        : undefined;
      throw new EbError(ebErrorCode(status, ebError), {
        status,
        ebError,
        detail: parsed ?? text,
      });
    }
    if (!guard(parsed)) {
      throw new EbError("bank_error", {
        status,
        detail: "unexpected response",
      });
    }
    return parsed;
  }

  /** One HTTP exchange within the timeout; network failures are unavailability. */
  async #send(
    url: URL,
    init: RequestInit,
  ): Promise<{ status: number; text: string }> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeoutMs);
    try {
      const response = await this.#fetch(url, {
        ...init,
        signal: controller.signal,
      });
      return { status: response.status, text: await response.text() };
    } catch (error) {
      throw new EbError("bank_unavailable", { detail: error });
    } finally {
      clearTimeout(timer);
    }
  }

  /** The JWT of this client, signed again when close to its expiry. */
  async #token(): Promise<string> {
    const now = Math.floor(this.#now() / 1000);
    if (
      this.#jwt !== undefined &&
      this.#jwt.expiresAt - now > JWT_RENEW_MARGIN_SECONDS
    ) {
      return this.#jwt.token;
    }
    const privateKey = this.#privateKey;
    this.#key ??= typeof privateKey === "string"
      ? importPrivateKey(privateKey)
      : Promise.resolve(privateKey);
    const token = await signJwt(await this.#key, this.#appId, {
      issuedAt: now,
      ttlSeconds: JWT_TTL_SECONDS,
    });
    this.#jwt = { token, expiresAt: now + JWT_TTL_SECONDS };
    return token;
  }
}

function segment(value: string): string {
  if (value === "") throw new RangeError("empty path segment");
  return encodeURIComponent(value);
}

function checkDate(value: string): void {
  if (!ISO_DATE.test(value)) throw new RangeError("dates must be YYYY-MM-DD");
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const isAspsps: Guard<GetAspspsResponse> = (body): body is GetAspspsResponse =>
  isRecord(body) && Array.isArray(body.aspsps);

const isStartAuth: Guard<StartAuthResponse> = (
  body,
): body is StartAuthResponse => isRecord(body) && typeof body.url === "string";

const isAuthorizedSession: Guard<AuthorizeSessionResponse> = (
  body,
): body is AuthorizeSessionResponse =>
  isRecord(body) && typeof body.session_id === "string" &&
  Array.isArray(body.accounts);

const isSession: Guard<GetSessionResponse> = (
  body,
): body is GetSessionResponse =>
  isRecord(body) && typeof body.status === "string";

const isAccount: Guard<AccountResource> = (body): body is AccountResource =>
  isRecord(body);

const isBalances: Guard<HalBalances> = (body): body is HalBalances =>
  isRecord(body) && Array.isArray(body.balances);

const isTransactionsPage: Guard<HalTransactions> = (
  body,
): body is HalTransactions =>
  isRecord(body) && Array.isArray(body.transactions) &&
  (body.continuation_key === undefined || body.continuation_key === null ||
    typeof body.continuation_key === "string");
