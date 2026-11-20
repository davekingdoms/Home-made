import { createHandler } from "./handler.ts";

/** The runtime of Supabase Edge Functions. */
declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
};

Deno.serve(createHandler({
  env: (name) => Deno.env.get(name),
  waitUntil: (promise) => EdgeRuntime.waitUntil(promise),
}));
