/**
 * `eb-link-start` (sincronizzazione.md, section 3, steps 1–4): starts the
 * link of a bank and returns the authorization URL. `POST` with
 * `{member_id?, aspsp_name, aspsp_country, psu_type?}` (`member_id` only
 * from the service; `psu_type` defaults to `personal`).
 *
 * The bank is read from `GET /aspsps` by its exact name; the consent always
 * asks for the longest validity of the bank, minus 10 minutes. The id of
 * the new link request is the `state` sent to Enable Banking.
 */

import { authenticate } from "../_shared/auth.ts";
import { memberCredentials } from "../_shared/credentials.ts";
import { Db, DbError } from "../_shared/db.ts";
import { EbError } from "../_shared/eb/errors.ts";
import { newEbClient } from "../_shared/eb/factory.ts";
import type { PsuType } from "../_shared/eb/types.ts";
import {
  globalApp,
  publishableKey,
  supabaseEnv,
  urlVariable,
} from "../_shared/env.ts";
import type { Handler, HandlerDeps } from "../_shared/handler.ts";
import {
  errorResponse,
  HttpError,
  methodNotAllowed,
  okResponse,
  readJsonObject,
  UUID,
} from "../_shared/http.ts";
import { consoleLogger, stepper } from "../_shared/log.ts";
import { callerMemberId, serviceMember } from "../_shared/member.ts";

/** Margin taken from the longest consent of the bank. */
export const CONSENT_MARGIN_MS = 10 * 60 * 1000;
const MAX_ASPSP_NAME_LENGTH = 200;
const COUNTRY = /^[A-Z]{2}$/;

export function createHandler(deps: HandlerDeps): Handler {
  const log = deps.log ?? consoleLogger;
  const newClient = deps.newEbClient ?? newEbClient;
  const now = deps.now ?? Date.now;

  return async (request) => {
    const step = stepper("eb-link-start", log);
    if (request.method !== "POST") {
      log({ fn: "eb-link-start", step: "method", code: "method_not_allowed" });
      return methodNotAllowed("POST");
    }
    try {
      const env = await step("env", () => ({
        supabase: supabaseEnv(deps.env),
        publishable: publishableKey(deps.env),
        redirectUrl: urlVariable(deps.env, "EB_REDIRECT_URL"),
        global: globalApp(deps.env),
      }));
      const caller = await step("auth", () =>
        authenticate(request, {
          supabaseUrl: env.supabase.url,
          secretKeys: env.supabase.secretKeys,
          publishableKey: env.publishable,
          fetch: deps.fetch,
        }));
      const { memberId, bankName, country, psuType } = await step(
        "body",
        async () => {
          const body = await readJsonObject(request);
          return { memberId: callerMemberId(caller, body), ...bankOf(body) };
        },
      );
      const db = new Db({
        url: env.supabase.url,
        apikey: env.supabase.secretKey,
        fetch: deps.fetch,
      });
      const member = await step("member", () => serviceMember(db, memberId));
      const { client, usesGlobalApp } = await step("credentials", async () => {
        const credentials = await memberCredentials(
          db,
          env.global,
          member.userId,
        );
        // A client of this request and person only.
        return {
          client: newClient({
            appId: credentials.appId,
            privateKey: credentials.privateKey,
            fetch: deps.fetch,
          }),
          usesGlobalApp: credentials.usesGlobalApp,
        };
      });

      const bank = await step("bank", async () => {
        const { aspsps } = await client.getAspsps(country);
        const found = aspsps.find((aspsp) => aspsp.name === bankName);
        if (found === undefined) throw new HttpError(404, "bank_not_found");
        if (
          !Array.isArray(found.psu_types) || !found.psu_types.includes(psuType)
        ) {
          throw new HttpError(400, "invalid_request");
        }
        const validity = found.maximum_consent_validity;
        if (
          typeof validity !== "number" || !Number.isFinite(validity) ||
          validity * 1000 <= CONSENT_MARGIN_MS
        ) {
          throw new EbError("bank_error", { detail: "consent validity" });
        }
        return {
          name: found.name,
          validUntil: new Date(now() + validity * 1000 - CONSENT_MARGIN_MS)
            .toISOString(),
        };
      });

      const state = await step("request", async () => {
        let id: unknown;
        try {
          id = await db.rpc("create_link_request", {
            member_id: member.memberId,
            aspsp_name: bank.name,
            aspsp_country: country,
            psu_type: psuType,
            uses_global_app: usesGlobalApp,
          });
        } catch (error) {
          if (
            error instanceof DbError && error.code === "member_not_eligible"
          ) {
            throw new HttpError(403, "member_not_eligible");
          }
          throw error;
        }
        if (typeof id !== "string" || !UUID.test(id)) {
          throw new HttpError(500, "internal");
        }
        return id;
      });

      const auth = await step("auth_url", () =>
        client.startAuth({
          access: { valid_until: bank.validUntil },
          aspsp: { name: bank.name, country },
          state,
          redirect_url: env.redirectUrl,
          psu_type: psuType,
        }));
      return okResponse({ url: auth.url });
    } catch (error) {
      return toResponse(error);
    }
  };
}

/** Bank, country and PSU type of the body. */
function bankOf(body: Record<string, unknown>) {
  const name = body.aspsp_name;
  const country = body.aspsp_country;
  const psuType = body.psu_type ?? "personal";
  if (
    typeof name !== "string" || name.trim() === "" ||
    name.length > MAX_ASPSP_NAME_LENGTH ||
    typeof country !== "string" || !COUNTRY.test(country) ||
    (psuType !== "personal" && psuType !== "business")
  ) {
    throw new HttpError(400, "invalid_request");
  }
  return { bankName: name, country, psuType: psuType as PsuType };
}

function toResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return errorResponse(error.status, error.code);
  }
  if (error instanceof EbError) return errorResponse(502, error.code);
  return errorResponse(500, "internal");
}
