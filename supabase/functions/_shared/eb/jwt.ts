/**
 * JWT for the Enable Banking API (sincronizzazione.md, section 2): RS256,
 * `kid` = application ID, `iss` = `enablebanking.com`,
 * `aud` = `api.enablebanking.com`, one hour of life (24 hours at most).
 * The key and the token stay in memory: never saved, never logged.
 */

import { EbError } from "./errors.ts";

export const JWT_ISSUER = "enablebanking.com";
export const JWT_AUDIENCE = "api.enablebanking.com";
export const JWT_TTL_SECONDS = 60 * 60;
/** Longest life Enable Banking accepts. */
export const JWT_MAX_TTL_SECONDS = 24 * 60 * 60;

const SIGN_ALGORITHM = { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };

/**
 * Imports an RSA private key from PEM: PKCS#8 (`BEGIN PRIVATE KEY`) or
 * PKCS#1 (`BEGIN RSA PRIVATE KEY`), converted to PKCS#8 for WebCrypto.
 * Escaped line breaks (`\n` as two characters, as in some secret stores) are
 * accepted. A key that cannot be read is `invalid_credentials`.
 */
export async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const block =
    /-----BEGIN (RSA )?PRIVATE KEY-----([\s\S]*?)-----END \1PRIVATE KEY-----/
      .exec(pem);
  if (block === null) {
    throw new EbError("invalid_credentials", { detail: "no PEM private key" });
  }
  const der = base64Decode((block[2] ?? "").replace(/\\[nr]|\s/g, ""));
  if (der === null) {
    throw new EbError("invalid_credentials", { detail: "PEM is not base64" });
  }
  const pkcs8 = block[1] === undefined ? der : pkcs1ToPkcs8(der);
  try {
    return await crypto.subtle.importKey(
      "pkcs8",
      pkcs8,
      SIGN_ALGORITHM,
      false,
      ["sign"],
    );
  } catch {
    throw new EbError("invalid_credentials", { detail: "not an RSA key" });
  }
}

export interface JwtOptions {
  /** Creation time, in seconds since the epoch. */
  issuedAt?: number;
  /** Life of the token, in seconds. */
  ttlSeconds?: number;
}

/** Signs the JWT that goes in `Authorization: Bearer …`. */
export async function signJwt(
  key: CryptoKey,
  appId: string,
  options: JwtOptions = {},
): Promise<string> {
  const ttl = options.ttlSeconds ?? JWT_TTL_SECONDS;
  if (!Number.isInteger(ttl) || ttl <= 0 || ttl > JWT_MAX_TTL_SECONDS) {
    throw new RangeError("JWT life must be between 1 second and 24 hours");
  }
  const iat = options.issuedAt ?? Math.floor(Date.now() / 1000);
  const header = { typ: "JWT", alg: "RS256", kid: appId };
  const payload = { iss: JWT_ISSUER, aud: JWT_AUDIENCE, iat, exp: iat + ttl };
  const signingInput = `${jsonPart(header)}.${jsonPart(payload)}`;
  const signature = await crypto.subtle.sign(
    SIGN_ALGORITHM,
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

function jsonPart(value: unknown): string {
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

function base64Decode(text: string) {
  let binary: string;
  try {
    binary = atob(text);
  } catch {
    return null;
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** `rsaEncryption` AlgorithmIdentifier: OID 1.2.840.113549.1.1.1, NULL. */
const RSA_ALGORITHM_IDENTIFIER = [
  0x30,
  0x0d,
  0x06,
  0x09,
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x01,
  0x01,
  0x05,
  0x00,
];

/**
 * Wraps a PKCS#1 RSAPrivateKey in a PKCS#8 PrivateKeyInfo:
 * SEQUENCE { INTEGER 0, AlgorithmIdentifier, OCTET STRING { pkcs1 } }.
 */
function pkcs1ToPkcs8(pkcs1: Uint8Array) {
  const octetString = [0x04, ...derLength(pkcs1.length)];
  const contentLength = 3 + RSA_ALGORITHM_IDENTIFIER.length +
    octetString.length +
    pkcs1.length;
  const head = [
    0x30,
    ...derLength(contentLength),
    0x02,
    0x01,
    0x00,
    ...RSA_ALGORITHM_IDENTIFIER,
    ...octetString,
  ];
  const out = new Uint8Array(head.length + pkcs1.length);
  out.set(head);
  out.set(pkcs1, head.length);
  return out;
}

function derLength(length: number): number[] {
  if (length < 0x80) return [length];
  const bytes: number[] = [];
  for (let rest = length; rest > 0; rest = Math.floor(rest / 256)) {
    bytes.unshift(rest % 256);
  }
  return [0x80 | bytes.length, ...bytes];
}
