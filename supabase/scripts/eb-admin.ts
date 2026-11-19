/**
 * Service script for development (sincronizzazione.md, section 1).
 *
 * Subcommands:
 *   aspsps --country IT      number of banks of the country and whether the
 *                            Sandbox bank "Mock ASPSP" is among them
 *   credentials --member <uuid>
 *                            proves and saves the Enable Banking application
 *                            of EB_APP_ID and EB_KEY_PATH for that member,
 *                            through eb-credentials
 *   link --member <uuid> --bank <name> --country <XX> [--psu personal|business]
 *                            starts a bank link through eb-link-start and
 *                            prints the authorization URL
 * `sync` arrives with the sync functions.
 *
 * Environment: EB_APP_ID and EB_KEY_PATH (path of the PEM private key) for
 * `aspsps` and `credentials`; SUPABASE_URL and SB_SECRET_KEY_PATH (path of a
 * file with a secret key of the project, one line) for `credentials` and
 * `link`. The secret key is never an argument nor the value of a variable.
 * Prints outcomes and codes only, and for `link` the authorization URL:
 * never the keys, the JWT or the application ID.
 *
 * From the root of the repository, with the minimum permissions (PowerShell):
 *
 *   deno run --allow-env=EB_APP_ID,EB_KEY_PATH,SUPABASE_URL,SB_SECRET_KEY_PATH
 *     "--allow-read=<key file>,<secret key file>"
 *     "--allow-net=$(([uri]$env:SUPABASE_URL).Host)"
 *     supabase/scripts/eb-admin.ts credentials --member <uuid>
 *
 * `link` reads only the secret key file; `aspsps` needs only the key file
 * and --allow-net=api.enablebanking.com.
 */

import { EnableBankingClient } from "../functions/_shared/eb/client.ts";
import { EbError } from "../functions/_shared/eb/errors.ts";

export interface AdminIo {
  env: (name: string) => string | undefined;
  readTextFile: (path: string) => Promise<string>;
  print: (line: string) => void;
  printError: (line: string) => void;
  fetch?: typeof fetch;
}

const USAGE = [
  "usage: eb-admin.ts aspsps --country <country code, e.g. IT>",
  "       eb-admin.ts credentials --member <member uuid>",
  "       eb-admin.ts link --member <member uuid> --bank <bank name> --country <XX> [--psu personal|business]",
].join("\n");
const MOCK_ASPSP = "Mock ASPSP";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const COUNTRY = /^[A-Z]{2}$/;
const CODE = /^[a-z_]{1,40}$/;
/** An Edge Function may call Enable Banking and the database in turn. */
const FUNCTION_TIMEOUT_MS = 60_000;

/** Runs a subcommand; returns the exit code (0 ok, 1 failure, 2 usage). */
export async function main(args: string[], io: AdminIo): Promise<number> {
  const [command, ...options] = args;
  switch (command) {
    case "aspsps":
      return await aspsps(options, io);
    case "credentials":
      return await credentials(options, io);
    case "link":
      return await link(options, io);
    default:
      return usage(io);
  }
}

function usage(io: AdminIo): number {
  io.printError(USAGE);
  return 2;
}

async function aspsps(options: string[], io: AdminIo): Promise<number> {
  const country = option(options, "country")?.toUpperCase();
  if (country === undefined || !COUNTRY.test(country)) return usage(io);
  try {
    const app = await appFromEnv(io);
    if (app === undefined) return 1;
    const client = new EnableBankingClient({ ...app, fetch: io.fetch });
    const { aspsps } = await client.getAspsps(country);
    const mock = aspsps.some((aspsp) => aspsp.name === MOCK_ASPSP);
    io.print(`banks in ${country}: ${aspsps.length}`);
    io.print(`${MOCK_ASPSP}: ${mock ? "present" : "missing"}`);
    return 0;
  } catch (error) {
    // Codes only: EbError messages hold the code, the HTTP status and the
    // Enable Banking error code, never the bank's text.
    io.printError(
      `error: ${error instanceof EbError ? error.message : "internal"}`,
    );
    return 1;
  }
}

async function credentials(options: string[], io: AdminIo): Promise<number> {
  const member = option(options, "member");
  if (member === undefined || !UUID.test(member)) return usage(io);
  const project = await projectFromEnv(io);
  if (project === undefined) return 1;
  const app = await appFromEnv(io);
  if (app === undefined) return 1;
  const result = await callFunction(io, project, "eb-credentials", {
    member_id: member,
    app_id: app.appId,
    private_key: app.privateKey,
  });
  if (!result.ok) {
    io.printError(`error: ${result.code}`);
    return 1;
  }
  io.print("credentials: saved");
  return 0;
}

async function link(options: string[], io: AdminIo): Promise<number> {
  const member = option(options, "member");
  const bank = option(options, "bank");
  const country = option(options, "country")?.toUpperCase();
  const psu = option(options, "psu");
  if (
    member === undefined || !UUID.test(member) ||
    bank === undefined || bank.trim() === "" ||
    country === undefined || !COUNTRY.test(country) ||
    (psu !== undefined && psu !== "personal" && psu !== "business")
  ) {
    return usage(io);
  }
  const project = await projectFromEnv(io);
  if (project === undefined) return 1;
  const result = await callFunction(io, project, "eb-link-start", {
    member_id: member,
    aspsp_name: bank,
    aspsp_country: country,
    ...(psu === undefined ? {} : { psu_type: psu }),
  });
  if (!result.ok) {
    io.printError(`error: ${result.code}`);
    return 1;
  }
  const url = result.body.url;
  if (typeof url !== "string" || !/^https:\/\//.test(url)) {
    io.printError("error: internal");
    return 1;
  }
  io.print("authorization URL (open it and finish in the same browser):");
  io.print(url);
  io.print("complete within 30 minutes");
  return 0;
}

interface Project {
  url: string;
  secretKey: string;
}

/** SUPABASE_URL and the secret key read from SB_SECRET_KEY_PATH. */
async function projectFromEnv(io: AdminIo): Promise<Project | undefined> {
  const url = io.env("SUPABASE_URL");
  const keyPath = io.env("SB_SECRET_KEY_PATH");
  if (!url || !keyPath || !/^https?:\/\/[^/]+/.test(url)) {
    io.printError("error: set SUPABASE_URL and SB_SECRET_KEY_PATH");
    return undefined;
  }
  let secretKey: string;
  try {
    secretKey = (await io.readTextFile(keyPath)).trim();
  } catch {
    io.printError("error: cannot read the file in SB_SECRET_KEY_PATH");
    return undefined;
  }
  if (secretKey === "" || /\s/.test(secretKey)) {
    io.printError(
      "error: the file in SB_SECRET_KEY_PATH holds one key, one line",
    );
    return undefined;
  }
  return { url: url.replace(/\/+$/, ""), secretKey };
}

/** EB_APP_ID and the private key read from EB_KEY_PATH. */
async function appFromEnv(
  io: AdminIo,
): Promise<{ appId: string; privateKey: string } | undefined> {
  const appId = io.env("EB_APP_ID");
  const keyPath = io.env("EB_KEY_PATH");
  if (!appId || !keyPath) {
    io.printError("error: set EB_APP_ID and EB_KEY_PATH");
    return undefined;
  }
  try {
    return { appId, privateKey: await io.readTextFile(keyPath) };
  } catch {
    io.printError("error: cannot read the file in EB_KEY_PATH");
    return undefined;
  }
}

type FunctionResult =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; code: string };

/** POST to an Edge Function with the secret key in `apikey`. */
async function callFunction(
  io: AdminIo,
  project: Project,
  name: string,
  body: Record<string, unknown>,
): Promise<FunctionResult> {
  const doFetch = io.fetch ?? ((input, init) => fetch(input, init));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FUNCTION_TIMEOUT_MS);
  let status: number;
  let text: string;
  try {
    const response = await doFetch(`${project.url}/functions/v1/${name}`, {
      method: "POST",
      headers: {
        apikey: project.secretKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    status = response.status;
    text = await response.text();
  } catch {
    return { ok: false, code: "unavailable" };
  } finally {
    clearTimeout(timer);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = undefined;
  }
  const record = typeof parsed === "object" && parsed !== null &&
      !Array.isArray(parsed)
    ? parsed as Record<string, unknown>
    : undefined;
  if (status >= 200 && status <= 299 && record?.ok === true) {
    return { ok: true, body: record };
  }
  const code = record?.error;
  return {
    ok: false,
    code: typeof code === "string" && CODE.test(code) ? code : `http_${status}`,
  };
}

/** Value of `--name value` or `--name=value`. */
function option(args: string[], name: string): string | undefined {
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === `--${name}`) return args[i + 1];
    if (arg?.startsWith(`--${name}=`)) return arg.slice(name.length + 3);
  }
  return undefined;
}

if (import.meta.main) {
  Deno.exit(
    await main(Deno.args, {
      env: (name) => Deno.env.get(name),
      readTextFile: (path) => Deno.readTextFile(path),
      print: (line) => console.log(line),
      printError: (line) => console.error(line),
    }),
  );
}
