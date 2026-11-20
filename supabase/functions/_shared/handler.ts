/**
 * What a request handler of the Edge Functions receives: the environment,
 * and for the tests a fake `fetch` (PostgREST and Enable Banking), the
 * factory of the Enable Banking clients, the logger, the clock and the
 * keeper of the work that goes on after the response.
 */

import type { NewEbClient } from "./eb/factory.ts";
import type { EnvGetter } from "./env.ts";
import type { Logger } from "./log.ts";

export interface HandlerDeps {
  env: EnvGetter;
  fetch?: typeof fetch;
  newEbClient?: NewEbClient;
  log?: Logger;
  /** Milliseconds since the epoch. */
  now?: () => number;
  /**
   * Keeps the function alive for work after the response
   * (`EdgeRuntime.waitUntil` on the platform).
   */
  waitUntil?: (promise: Promise<unknown>) => void;
}

export type Handler = (request: Request) => Promise<Response>;
