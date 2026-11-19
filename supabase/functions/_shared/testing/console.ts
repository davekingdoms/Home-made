/**
 * Captures everything written with `console` during a test, to check that
 * no sensitive value reaches the logs, whatever the path that wrote it.
 */

const METHODS = ["log", "info", "warn", "error", "debug"] as const;

export interface CapturedConsole {
  lines: string[];
  restore: () => void;
}

export function captureConsole(): CapturedConsole {
  const lines: string[] = [];
  const original = Object.fromEntries(
    METHODS.map((name) => [name, console[name]]),
  );
  for (const name of METHODS) {
    console[name] = (...args: unknown[]) => {
      lines.push(
        args.map((arg) =>
          typeof arg === "string" ? arg : Deno.inspect(arg, { depth: 10 })
        ).join(" "),
      );
    };
  }
  return { lines, restore: () => Object.assign(console, original) };
}

/**
 * A request handler whose console output is captured on every call: the
 * test output stays quiet, and `lines` holds what the handler wrote.
 */
export function capturedHandler(
  handler: (request: Request) => Promise<Response>,
): { handler: (request: Request) => Promise<Response>; lines: string[] } {
  const lines: string[] = [];
  return {
    lines,
    handler: async (request) => {
      const captured = captureConsole();
      try {
        return await handler(request);
      } finally {
        captured.restore();
        lines.push(...captured.lines);
      }
    },
  };
}

/** Runs `run` with the console captured; returns its result and the lines. */
export async function withConsole<T>(
  run: () => Promise<T>,
): Promise<{ result: T; lines: string[] }> {
  const captured = captureConsole();
  try {
    return { result: await run(), lines: captured.lines };
  } finally {
    captured.restore();
  }
}
