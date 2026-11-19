/**
 * Responses and request bodies of the Edge Functions
 * (sincronizzazione.md, section 3): JSON with `Cache-Control: no-store`,
 * `{ "ok": true, … }` or `{ "error": "<code>" }`. The code is always a
 * fixed key, never a value received.
 */

/** A failure with its HTTP status and the code of the response. */
export class HttpError extends Error {
  override readonly name = "HttpError";
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/** Largest body accepted: a private key of 16 KB, escaped in JSON. */
export const MAX_BODY_BYTES = 64 * 1024;

export const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...headers,
    },
  });
}

export function okResponse(fields: Record<string, unknown> = {}): Response {
  return jsonResponse(200, { ok: true, ...fields });
}

export function errorResponse(
  status: number,
  code: string,
  headers: Record<string, string> = {},
): Response {
  return jsonResponse(status, { error: code }, headers);
}

export function methodNotAllowed(allow: string): Response {
  return errorResponse(405, "method_not_allowed", { Allow: allow });
}

/** The body as a JSON object; anything else is `400 invalid_request`. */
export async function readJsonObject(
  request: Request,
): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (!Number.isFinite(declared) || declared > MAX_BODY_BYTES) {
    throw new HttpError(400, "invalid_request");
  }
  let text: string;
  try {
    text = await request.text();
  } catch {
    throw new HttpError(400, "invalid_request");
  }
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new HttpError(400, "invalid_request");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpError(400, "invalid_request");
  }
  if (!isRecord(parsed)) throw new HttpError(400, "invalid_request");
  return parsed;
}
