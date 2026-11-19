/**
 * RSA keys for the tests, generated at run time with WebCrypto: no PEM file
 * is ever stored in the repository, not even a fake one.
 */

import { assert } from "@std/assert";
import { encodeBase64 } from "@std/encoding/base64";
import { decodeBase64Url } from "@std/encoding/base64url";

export interface TestKeys {
  /** PKCS#8 PEM (`BEGIN PRIVATE KEY`). */
  pkcs8Pem: string;
  /** PKCS#1 PEM (`BEGIN RSA PRIVATE KEY`). */
  pkcs1Pem: string;
  publicKey: CryptoKey;
}

export async function generateTestKeys(): Promise<TestKeys> {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  return {
    pkcs8Pem: pem("PRIVATE KEY", pkcs8),
    pkcs1Pem: pem("RSA PRIVATE KEY", pkcs8ToPkcs1(pkcs8)),
    publicKey: pair.publicKey,
  };
}

export interface DecodedJwt {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
}

/** Checks the RS256 signature with the public key and returns the claims. */
export async function verifyJwt(
  token: string,
  publicKey: CryptoKey,
): Promise<DecodedJwt> {
  const [header, payload, signature] = token.split(".");
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    decodeBase64Url(signature ?? ""),
    new TextEncoder().encode(`${header}.${payload}`),
  );
  assert(valid, "JWT signature does not verify with the public key");
  return { header: decodePart(header), payload: decodePart(payload) };
}

function decodePart(part: string | undefined): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(decodeBase64Url(part ?? "")));
}

function pem(label: string, der: Uint8Array): string {
  const lines = encodeBase64(der).match(/.{1,64}/g) ?? [];
  return `${armor(label, lines.join("\n"))}\n`;
}

/**
 * PEM armor around a body, built at run time: no key-shaped text in the
 * sources, where gitleaks would rightly flag it.
 */
export function armor(label: string, body: string): string {
  const line = "-".repeat(5);
  return [
    `${line}BEGIN ${label}${line}`,
    body,
    `${line}END ${label}${line}`,
  ].join("\n");
}

/**
 * Takes the RSAPrivateKey out of a PrivateKeyInfo:
 * SEQUENCE { INTEGER 0, AlgorithmIdentifier, OCTET STRING { pkcs1 } }.
 */
function pkcs8ToPkcs1(der: Uint8Array): Uint8Array {
  let offset = 0;
  const readHeader = (tag: number): number => {
    if (der[offset++] !== tag) throw new Error(`expected DER tag ${tag}`);
    let length = der[offset++] ?? 0;
    if (length & 0x80) {
      let bytes = length & 0x7f;
      length = 0;
      while (bytes-- > 0) length = length * 256 + (der[offset++] ?? 0);
    }
    return length;
  };
  const skip = (tag: number) => {
    const length = readHeader(tag);
    offset += length;
  };
  readHeader(0x30); // PrivateKeyInfo
  skip(0x02); // version
  skip(0x30); // AlgorithmIdentifier
  const length = readHeader(0x04); // privateKey
  return der.slice(offset, offset + length);
}
