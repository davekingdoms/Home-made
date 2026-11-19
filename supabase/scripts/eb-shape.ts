/**
 * Shape of Enable Banking responses (sincronizzazione.md, section 12): reads
 * the JSON files of a folder and of its subfolders, sorts them into classes
 * by their shape (transactions page, balances, session, account details,
 * error, other) and prints, for each class, the paths of the keys
 * (`transactions[].creditor.name`), their types, in how many objects they
 * appear and format signals (email, IBAN with a valid check, ISO date,
 * decimal amount with N decimals, upper case, empty, trailing space).
 *
 * It never prints a value nor the name of a file or folder: only counts per
 * class. A key that looks like data (anything but letters, `_` and `-`, so
 * `@` and digits too, or longer than 40 characters) prints as
 * `<chiave-dato>`.
 *
 * With `--compare <testdata>`: for each class, the keys of the folder that
 * the test data lacks, the types the test data never has, and the paths of
 * the transactions that hold strings looking like emails.
 *
 * Files that are not JSON are skipped; JSON that does not parse is counted.
 *
 * From the root of the repository, with the minimum permissions: reading
 * the two folders only, no network, no environment (PowerShell):
 *
 *   deno run "--allow-read=<dir>,<testdata>" supabase/scripts/eb-shape.ts
 *     <dir> --compare <testdata>
 */

export interface ShapeIo {
  readDir: (path: string) => AsyncIterable<{
    name: string;
    isFile: boolean;
    isDirectory: boolean;
  }>;
  readTextFile: (path: string) => Promise<string>;
  print: (line: string) => void;
  printError: (line: string) => void;
}

export const CLASSES = [
  "transactions page",
  "balances",
  "session",
  "account details",
  "error",
  "other",
] as const;

export type ShapeClass = typeof CLASSES[number];

interface PathStats {
  /** Occurrences by JSON type. */
  types: Map<string, number>;
  /** Occurrences by format signal (strings only). */
  signals: Map<string, number>;
}

interface ClassShape {
  files: number;
  paths: Map<string, PathStats>;
}

interface Folder {
  files: number;
  unreadable: number;
  classes: Map<ShapeClass, ClassShape>;
}

const USAGE = "usage: eb-shape.ts <folder> [--compare <test data folder>]";
export const DATA_KEY = "<chiave-dato>";
const PLAIN_KEY = /^[A-Za-z_-]{1,40}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const HAS_EMAIL = /[^\s@]+@[^\s@]+\.[^\s@]+/;
const IBAN = /^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const ISO_DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;
const DECIMAL = /^[+-]?\d+(?:\.(\d+))?$/;

/** Runs the script; returns the exit code (0 ok, 1 failure, 2 usage). */
export async function main(args: string[], io: ShapeIo): Promise<number> {
  const parsed = parseArgs(args);
  if (parsed === undefined) {
    io.printError(USAGE);
    return 2;
  }
  const folder = await readFolder(parsed.dir, io);
  if (folder === undefined) {
    io.printError("error: cannot read the folder");
    return 1;
  }
  printShapes(folder, io);
  if (parsed.compare === undefined) return 0;

  const testdata = await readFolder(parsed.compare, io);
  if (testdata === undefined) {
    io.printError("error: cannot read the test data folder");
    return 1;
  }
  printComparison(folder, testdata, io);
  return 0;
}

function parseArgs(
  args: string[],
): { dir: string; compare?: string } | undefined {
  const positional: string[] = [];
  let compare: string | undefined;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    if (arg === "--compare") {
      compare = args[++i];
      if (compare === undefined || compare.startsWith("--")) return undefined;
    } else if (arg.startsWith("--compare=")) {
      compare = arg.slice("--compare=".length);
    } else if (arg.startsWith("--")) {
      return undefined;
    } else {
      positional.push(arg);
    }
  }
  if (positional.length !== 1 || compare === "") return undefined;
  return { dir: positional[0]!, compare };
}

/** All the JSON files of a folder and of its subfolders, by class. */
async function readFolder(
  dir: string,
  io: ShapeIo,
): Promise<Folder | undefined> {
  const folder: Folder = { files: 0, unreadable: 0, classes: new Map() };
  try {
    await walk(dir.replace(/[\\/]+$/, ""), io, folder);
  } catch {
    return undefined;
  }
  return folder;
}

async function walk(dir: string, io: ShapeIo, folder: Folder) {
  const entries: { name: string; isFile: boolean; isDirectory: boolean }[] = [];
  for await (const entry of io.readDir(dir)) entries.push(entry);
  for (const entry of entries) {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory) {
      await walk(path, io, folder);
    } else if (entry.isFile && entry.name.toLowerCase().endsWith(".json")) {
      folder.files++;
      let body: unknown;
      try {
        body = JSON.parse(await io.readTextFile(path));
      } catch {
        folder.unreadable++;
        continue;
      }
      addDocument(folder, body);
    }
  }
}

function addDocument(folder: Folder, body: unknown) {
  const documents = classify(body);
  const counted = new Set<ShapeClass>();
  for (const [shapeClass, document] of documents) {
    let shape = folder.classes.get(shapeClass);
    if (shape === undefined) {
      shape = { files: 0, paths: new Map() };
      folder.classes.set(shapeClass, shape);
    }
    if (!counted.has(shapeClass)) {
      shape.files++;
      counted.add(shapeClass);
    }
    visit(document, "", shape);
  }
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isTransaction = (value: unknown) =>
  isObject(value) &&
  ("transaction_amount" in value || "credit_debit_indicator" in value);

const isError = (value: unknown) =>
  isObject(value) && typeof value.error === "string" &&
  ("code" in value || "message" in value);

/**
 * The class of a file and the documents to read; a map of errors (name →
 * error) gives one document per error, a bare array of transactions reads
 * as a page.
 */
export function classify(body: unknown): [ShapeClass, unknown][] {
  if (Array.isArray(body)) {
    return body.length > 0 && body.every(isTransaction)
      ? [["transactions page", { transactions: body }]]
      : [["other", body]];
  }
  if (!isObject(body)) return [["other", body]];
  if (Array.isArray(body.transactions)) return [["transactions page", body]];
  if (Array.isArray(body.balances)) return [["balances", body]];
  if (
    "session_id" in body ||
    (Array.isArray(body.accounts) && "access" in body)
  ) {
    return [["session", body]];
  }
  if (typeof body.cash_account_type === "string") {
    return [["account details", body]];
  }
  if (isError(body)) return [["error", body]];
  const values = Object.values(body);
  if (values.length > 0 && values.every(isError)) {
    return values.map((value) => ["error", value]);
  }
  return [["other", body]];
}

/** A key as printed: `<chiave-dato>` when it looks like data. */
export function keyName(key: string): string {
  return PLAIN_KEY.test(key) ? key : DATA_KEY;
}

function visit(value: unknown, path: string, shape: ClassShape) {
  if (Array.isArray(value)) {
    const child = `${path}[]`;
    for (const item of value) {
      record(child, item, shape);
      visit(item, child, shape);
    }
  } else if (isObject(value)) {
    for (const [key, item] of Object.entries(value)) {
      const child = path === "" ? keyName(key) : `${path}.${keyName(key)}`;
      record(child, item, shape);
      visit(item, child, shape);
    }
  }
}

function typeOf(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function record(path: string, value: unknown, shape: ClassShape) {
  let stats = shape.paths.get(path);
  if (stats === undefined) {
    stats = { types: new Map(), signals: new Map() };
    shape.paths.set(path, stats);
  }
  increment(stats.types, typeOf(value));
  if (typeof value === "string") {
    for (const signal of signals(value)) increment(stats.signals, signal);
  }
}

function increment(map: Map<string, number>, key: string) {
  map.set(key, (map.get(key) ?? 0) + 1);
}

/** An IBAN with a valid check (ISO 13616, mod 97), spaces allowed. */
function isIban(text: string): boolean {
  const iban = text.replace(/\s+/g, "");
  if (!IBAN.test(iban)) return false;
  const digits = `${iban.slice(4)}${iban.slice(0, 4)}`
    .replace(/[A-Z]/g, (letter) => String(letter.charCodeAt(0) - 55));
  let rest = 0;
  for (const digit of digits) rest = (rest * 10 + Number(digit)) % 97;
  return rest === 1;
}

/** Format signals of a string: never the string itself. */
export function signals(value: string): string[] {
  const found: string[] = [];
  const text = value.trim();
  if (text === "") return ["empty"];
  if (EMAIL.test(text)) found.push("email");
  else if (HAS_EMAIL.test(text)) found.push("contains email");
  if (isIban(text)) found.push("IBAN");
  if (ISO_DATE.test(text)) found.push("ISO date");
  else if (ISO_DATETIME.test(text)) found.push("ISO date-time");
  const decimal = DECIMAL.exec(text);
  if (decimal !== null) found.push(`decimal(${decimal[1]?.length ?? 0})`);
  // Text in upper case; the `T` and `Z` of a date-time do not count.
  if (
    !ISO_DATETIME.test(text) && text === text.toUpperCase() &&
    text !== text.toLowerCase()
  ) {
    found.push("upper case");
  }
  if (value !== value.trimEnd()) found.push("trailing space");
  return found;
}

function counts(map: Map<string, number>): string {
  return [...map.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, count]) => `${name} ${count}`)
    .join(", ");
}

function printShapes(folder: Folder, io: ShapeIo) {
  io.print(
    `JSON files: ${folder.files}, unreadable: ${folder.unreadable}`,
  );
  for (const shapeClass of CLASSES) {
    const shape = folder.classes.get(shapeClass);
    if (shape === undefined) continue;
    io.print("");
    io.print(`${shapeClass}: ${shape.files} files`);
    for (const path of [...shape.paths.keys()].sort()) {
      const stats = shape.paths.get(path)!;
      const signalText = stats.signals.size === 0
        ? ""
        : `; ${counts(stats.signals)}`;
      io.print(`  ${path}: ${counts(stats.types)}${signalText}`);
    }
  }
}

function printComparison(folder: Folder, testdata: Folder, io: ShapeIo) {
  io.print("");
  io.print(
    `compare with the test data (JSON files: ${testdata.files}, unreadable: ${testdata.unreadable})`,
  );
  let missing = 0;
  for (const shapeClass of CLASSES) {
    const shape = folder.classes.get(shapeClass);
    if (shape === undefined) continue;
    const known = testdata.classes.get(shapeClass)?.paths ?? new Map();
    const absent = [...shape.paths.keys()].filter((path) => !known.has(path))
      .sort();
    const types = [...shape.paths.entries()]
      .filter(([path]) => known.has(path))
      .flatMap(([path, stats]) =>
        [...stats.types.keys()]
          .filter((type) => !known.get(path)!.types.has(type))
          .map((type) => `${path}: ${type}`)
      )
      .sort();
    missing += absent.length;
    io.print(
      `${shapeClass}: ${absent.length} keys missing, ${types.length} types missing in the test data`,
    );
    for (const path of absent) io.print(`  missing key ${path}`);
    for (const type of types) io.print(`  missing type ${type}`);
  }

  io.print("");
  io.print("strings looking like emails in the transactions:");
  const page = folder.classes.get("transactions page");
  const emails = [...page?.paths.entries() ?? []]
    .map(([path, stats]) => {
      const email = (stats.signals.get("email") ?? 0) +
        (stats.signals.get("contains email") ?? 0);
      return [path, email] as const;
    })
    .filter(([, count]) => count > 0)
    .sort(([a], [b]) => a.localeCompare(b));
  if (emails.length === 0) io.print("  none");
  for (const [path, count] of emails) io.print(`  ${path}: ${count}`);
  io.print("");
  io.print(`keys missing in the test data: ${missing}`);
}

if (import.meta.main) {
  Deno.exit(
    await main(Deno.args, {
      readDir: (path) => Deno.readDir(path),
      readTextFile: (path) => Deno.readTextFile(path),
      print: (line) => console.log(line),
      printError: (line) => console.error(line),
    }),
  );
}
