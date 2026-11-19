import { assertEquals, assertRejects } from "@std/assert";
import { authenticate, matchesAnyKey } from "./auth.ts";
import { HttpError } from "./http.ts";
import {
  ANNA,
  fakeProject,
  JWT_ANNA,
  JWT_FORGED,
  JWT_FORMER,
  OTHER_SECRET_KEY,
  PUBLISHABLE_KEY,
  SECRET_KEY,
  SUPABASE_URL,
} from "./testing/fake_supabase.ts";

function check(headers: Record<string, string>) {
  const project = fakeProject({});
  const request = new Request(`${SUPABASE_URL}/functions/v1/eb-link-start`, {
    method: "POST",
    headers,
  });
  const caller = authenticate(request, {
    supabaseUrl: SUPABASE_URL,
    secretKeys: [SECRET_KEY, OTHER_SECRET_KEY],
    publishableKey: PUBLISHABLE_KEY,
    fetch: project.fetch,
  });
  return { caller, project };
}

async function refused(
  headers: Record<string, string>,
  status: number,
  code: string,
) {
  const { caller, project } = check(headers);
  const error = await assertRejects(() => caller, HttpError);
  assertEquals([error.status, error.code], [status, code]);
  return project;
}

Deno.test("service: any secret key of the project in apikey", async () => {
  for (const key of [SECRET_KEY, OTHER_SECRET_KEY]) {
    const { caller, project } = check({ apikey: key });
    assertEquals(await caller, { kind: "service" });
    assertEquals(project.rpcCalls.length, 0);
  }
});

Deno.test("service: a wrong key is refused", async () => {
  const project = await refused(
    { apikey: `${SECRET_KEY}x` },
    401,
    "unauthorized",
  );
  assertEquals(project.rpcCalls.length, 0);
  await refused({ apikey: PUBLISHABLE_KEY }, 401, "unauthorized");
  await refused({ apikey: "" }, 401, "unauthorized");
});

Deno.test("service: the secret key in Authorization instead of apikey is refused", async () => {
  const project = await refused(
    { Authorization: `Bearer ${SECRET_KEY}` },
    401,
    "unauthorized",
  );
  assertEquals(project.rpcCalls.length, 0);
});

Deno.test("user: a valid JWT gives the member of current_member_id", async () => {
  const { caller, project } = check({
    apikey: PUBLISHABLE_KEY,
    Authorization: `Bearer ${JWT_ANNA}`,
  });
  assertEquals(await caller, { kind: "user", memberId: ANNA.memberId });
  assertEquals(project.rpcCalls.map((call) => call.name), [
    "current_member_id",
  ]);
  assertEquals(project.rpcCalls[0]?.apikey, PUBLISHABLE_KEY);
  assertEquals(project.rpcCalls[0]?.authorization, `Bearer ${JWT_ANNA}`);
});

Deno.test("user: a JWT refused by PostgREST is unauthorized", async () => {
  await refused({ Authorization: `Bearer ${JWT_FORGED}` }, 401, "unauthorized");
});

Deno.test("user: a JWT without an active member is not eligible", async () => {
  await refused(
    { Authorization: `Bearer ${JWT_FORMER}` },
    403,
    "member_not_eligible",
  );
});

Deno.test("nothing, or another scheme, is unauthorized", async () => {
  const cases: Record<string, string>[] = [
    {},
    { Authorization: `Basic ${JWT_ANNA}` },
    { Authorization: "Bearer " },
  ];
  for (const headers of cases) {
    const project = await refused(headers, 401, "unauthorized");
    assertEquals(project.rpcCalls.length, 0);
  }
});

Deno.test("key comparison: equal only to a key, never with no keys", async () => {
  assertEquals(await matchesAnyKey(SECRET_KEY, [SECRET_KEY]), true);
  assertEquals(await matchesAnyKey(SECRET_KEY, [OTHER_SECRET_KEY]), false);
  assertEquals(await matchesAnyKey(SECRET_KEY, []), false);
  assertEquals(await matchesAnyKey("", [""]), false);
  assertEquals(
    await matchesAnyKey(SECRET_KEY.slice(0, -1), [SECRET_KEY]),
    false,
  );
});
