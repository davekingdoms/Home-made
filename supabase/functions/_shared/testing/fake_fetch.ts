/** A `fetch` that records the requests and answers from a handler: no network. */

export type Handler = (request: Request) => Response | Promise<Response>;

export interface FakeFetch {
  fetch: typeof fetch;
  requests: Request[];
}

export function fakeFetch(handler: Handler): FakeFetch {
  const requests: Request[] = [];
  const fetch: typeof globalThis.fetch = (input, init) => {
    const request = new Request(input, init);
    requests.push(request.clone());
    return Promise.resolve(handler(request));
  };
  return { fetch, requests };
}

/** JSON response with the given status. */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Synthetic Enable Banking response from `_shared/testdata/eb/`. */
export async function testdata(name: string): Promise<unknown> {
  const url = new URL(`../testdata/eb/${name}`, import.meta.url);
  return JSON.parse(await Deno.readTextFile(url));
}
