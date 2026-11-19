/**
 * Description of a bank row (sincronizzazione.md, 6.3): the
 * `remittance_information` lines joined by a space, runs of white space
 * reduced to one, trimmed; empty → null.
 */

/** Runs of white space to one space, trimmed; empty → null. */
export function cleanText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.replace(/\s+/g, " ").trim();
  return text === "" ? null : text;
}

/**
 * The normalized description of `remittance_information`. Lines that are not
 * text are left out; a single string counts as one line.
 */
export function normalizeDescription(remittance: unknown): string | null {
  const lines = Array.isArray(remittance) ? remittance : [remittance];
  return cleanText(
    lines.filter((line): line is string => typeof line === "string").join(" "),
  );
}
