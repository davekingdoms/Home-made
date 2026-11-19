/**
 * Service script for development (sincronizzazione.md, section 1).
 *
 * Subcommands:
 *   aspsps --country IT   number of banks of the country and whether the
 *                         Sandbox bank "Mock ASPSP" is among them
 * `credentials`, `link` and `sync` arrive with the Edge Functions.
 *
 * Reads EB_APP_ID and EB_KEY_PATH (path of the PEM private key) from the
 * environment. Prints outcomes, codes and counts only: never the key, the JWT
 * or the application ID. From the root of the repository, with the minimum
 * permissions:
 *
 *   deno run --allow-env=EB_APP_ID,EB_KEY_PATH --allow-read=<key file>
 *     --allow-net=api.enablebanking.com supabase/scripts/eb-admin.ts
 *     aspsps --country IT
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

const USAGE = "usage: eb-admin.ts aspsps --country <country code, e.g. IT>";
const MOCK_ASPSP = "Mock ASPSP";

/** Runs a subcommand; returns the exit code (0 ok, 1 failure, 2 usage). */
export async function main(args: string[], io: AdminIo): Promise<number> {
  const [command, ...options] = args;
  switch (command) {
    case "aspsps":
      return await aspsps(options, io);
    default:
      io.printError(USAGE);
      return 2;
  }
}

async function aspsps(options: string[], io: AdminIo): Promise<number> {
  const country = option(options, "country")?.toUpperCase();
  if (country === undefined || !/^[A-Z]{2}$/.test(country)) {
    io.printError(USAGE);
    return 2;
  }
  try {
    const client = await clientFromEnv(io);
    if (client === undefined) return 1;
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

async function clientFromEnv(
  io: AdminIo,
): Promise<EnableBankingClient | undefined> {
  const appId = io.env("EB_APP_ID");
  const keyPath = io.env("EB_KEY_PATH");
  if (!appId || !keyPath) {
    io.printError("error: set EB_APP_ID and EB_KEY_PATH");
    return undefined;
  }
  let privateKey: string;
  try {
    privateKey = await io.readTextFile(keyPath);
  } catch {
    io.printError("error: cannot read the file in EB_KEY_PATH");
    return undefined;
  }
  return new EnableBankingClient({ appId, privateKey, fetch: io.fetch });
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
