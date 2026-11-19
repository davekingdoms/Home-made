/**
 * Clients of Enable Banking for the Edge Functions: **one for each request
 * and person**. A client keeps its JWT in its own instance, so it is
 * created inside the request handler with the credentials of that member
 * (or of the global application) and never lives at module level or in a
 * shared cache, where a JWT of a person could serve another one.
 */

import {
  EnableBankingClient,
  type EnableBankingClientOptions,
} from "./client.ts";

export type NewEbClient = (
  options: EnableBankingClientOptions,
) => EnableBankingClient;

export const newEbClient: NewEbClient = (options) =>
  new EnableBankingClient(options);
