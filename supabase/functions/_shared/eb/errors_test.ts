import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  EbError,
  ebErrorCode,
  SYNC_ERROR_CODES,
  type SyncErrorCode,
} from "./errors.ts";

const TABLE: [
  status: number,
  ebError: string | undefined,
  code: SyncErrorCode,
][] = [
  // The `error` field wins over the status.
  [422, "WRONG_TRANSACTIONS_PERIOD", "period_rejected"],
  [400, "WRONG_TRANSACTIONS_PERIOD", "period_rejected"],
  [500, "WRONG_TRANSACTIONS_PERIOD", "period_rejected"],
  [429, "ASPSP_RATE_LIMIT_EXCEEDED", "rate_limited"],
  [422, "ASPSP_RATE_LIMIT_EXCEEDED", "rate_limited"],
  [401, "EXPIRED_SESSION", "consent_expired"],
  [422, "EXPIRED_SESSION", "consent_expired"],
  [422, "REVOKED_SESSION", "consent_revoked"],
  [422, "CLOSED_SESSION", "consent_revoked"],
  [403, "UNAUTHORIZED_ACCESS", "invalid_credentials"],
  [422, "ASPSP_TIMEOUT", "bank_unavailable"],
  // Then the status.
  [401, undefined, "invalid_credentials"],
  [401, "AUTHORIZATION_NOT_PROVIDED", "invalid_credentials"],
  [429, undefined, "rate_limited"],
  [408, undefined, "bank_unavailable"],
  [500, "ASPSP_ERROR", "bank_unavailable"],
  [502, undefined, "bank_unavailable"],
  [503, undefined, "bank_unavailable"],
  [504, undefined, "bank_unavailable"],
  // Anything else.
  [400, "WRONG_REQUEST_PARAMETERS", "bank_error"],
  [403, "ACCESS_DENIED", "bank_error"],
  [404, "ACCOUNT_DOES_NOT_EXIST", "bank_error"],
  [422, "ASPSP_ERROR", "bank_error"],
  [422, "SOMETHING_NEW", "bank_error"],
  [422, undefined, "bank_error"],
];

Deno.test("ebErrorCode: Enable Banking errors to sync codes", () => {
  for (const [status, ebError, code] of TABLE) {
    assertEquals(ebErrorCode(status, ebError), code, `${status} ${ebError}`);
  }
});

Deno.test("every code of the table is a code of the spec", () => {
  for (const [, , code] of TABLE) assert(SYNC_ERROR_CODES.includes(code));
});

Deno.test("EbError: codes in the message, bank text only in detail", () => {
  const bankText = "Synthetic bank text: the consent has expired";
  const error = new EbError("period_rejected", {
    status: 422,
    ebError: "WRONG_TRANSACTIONS_PERIOD",
    detail: { message: bankText },
  });
  assertEquals(error.name, "EbError");
  assertEquals(error.code, "period_rejected");
  assertEquals(
    error.message,
    "period_rejected (HTTP 422, WRONG_TRANSACTIONS_PERIOD)",
  );
  assertEquals(error.detail, { message: bankText });
  assertFalse(JSON.stringify(error).includes(bankText));
  assertFalse(Deno.inspect(error).includes(bankText));
  assertFalse(String(error).includes(bankText));
});

Deno.test("EbError: free text in the error field is dropped", () => {
  const error = new EbError("bank_error", {
    status: 400,
    ebError: "consent of Anna expired",
  });
  assertEquals(error.ebError, undefined);
  assertEquals(error.message, "bank_error (HTTP 400)");
  assertEquals(new EbError("internal").message, "internal");
});
