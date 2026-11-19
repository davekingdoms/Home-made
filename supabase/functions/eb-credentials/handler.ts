/**
 * `eb-credentials` (sincronizzazione.md, section 2): saves or replaces the
 * Enable Banking application of a person. `POST` with
 * `{member_id?, app_id, private_key}` (`member_id` only from the service).
 *
 * The key is proved first, by signing a JWT and calling `GET /aspsps` with
 * it: a key or an authorization refused is `400 invalid_credentials` and
 * nothing is saved. Then `eb_set_credentials` puts the key in Vault. The
 * key never appears in a response, a log or an error.
 */

import { authenticate } from "../_shared/auth.ts";
import { Db } from "../_shared/db.ts";
import { EbError } from "../_shared/eb/errors.ts";
import { newEbClient } from "../_shared/eb/factory.ts";
import { publishableKey, supabaseEnv } from "../_shared/env.ts";
import type { Handler, HandlerDeps } from "../_shared/handler.ts";
import {
  errorResponse,
  HttpError,
  methodNotAllowed,
  okResponse,
  readJsonObject,
} from "../_shared/http.ts";
import { consoleLogger, stepper } from "../_shared/log.ts";
import { callerMemberId, serviceMember } from "../_shared/member.ts";

/** Same limit as `eb_set_credentials`. */
export const MAX_PRIVATE_KEY_BYTES = 16 * 1024;
const MAX_APP_ID_LENGTH = 200;
const PEM_HEADER = /-----BEGIN [A-Z ]*PRIVATE KEY-----/;

export function createHandler(deps: HandlerDeps): Handler {
  const log = deps.log ?? consoleLogger;
  const newClient = deps.newEbClient ?? newEbClient;

  return async (request) => {
    const step = stepper("eb-credentials", log);
    if (request.method !== "POST") {
      log({ fn: "eb-credentials", step: "method", code: "method_not_allowed" });
      return methodNotAllowed("POST");
    }
    try {
      const { supabase, publishable } = await step("env", () => ({
        supabase: supabaseEnv(deps.env),
        publishable: publishableKey(deps.env),
      }));
      const caller = await step("auth", () =>
        authenticate(request, {
          supabaseUrl: supabase.url,
          secretKeys: supabase.secretKeys,
          publishableKey: publishable,
          fetch: deps.fetch,
        }));
      const { memberId, appId, privateKey } = await step("body", async () => {
        const body = await readJsonObject(request);
        return { memberId: callerMemberId(caller, body), ...credentials(body) };
      });
      const db = new Db({
        url: supabase.url,
        apikey: supabase.secretKey,
        fetch: deps.fetch,
      });
      const member = await step("member", () => serviceMember(db, memberId));

      // A client of this request only, with the credentials received.
      await step("check", async () => {
        try {
          const client = newClient({ appId, privateKey, fetch: deps.fetch });
          await client.getAspsps();
        } catch (error) {
          if (
            error instanceof EbError && error.code === "invalid_credentials"
          ) {
            throw new HttpError(400, "invalid_credentials");
          }
          throw error;
        }
      });

      await step("save", () =>
        db.rpc("eb_set_credentials", {
          user_id: member.userId,
          app_id: appId,
          private_key: privateKey,
        }));
      return okResponse();
    } catch (error) {
      return toResponse(error);
    }
  };
}

/** `app_id` and `private_key` of the body, checked for shape and size. */
function credentials(body: Record<string, unknown>) {
  const appId = body.app_id;
  const privateKey = body.private_key;
  if (
    typeof appId !== "string" || appId.trim() === "" ||
    appId.trim().length > MAX_APP_ID_LENGTH ||
    typeof privateKey !== "string" ||
    new TextEncoder().encode(privateKey).length > MAX_PRIVATE_KEY_BYTES ||
    !PEM_HEADER.test(privateKey)
  ) {
    throw new HttpError(400, "invalid_request");
  }
  return { appId: appId.trim(), privateKey };
}

function toResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return errorResponse(error.status, error.code);
  }
  if (error instanceof EbError) return errorResponse(502, error.code);
  return errorResponse(500, "internal");
}
