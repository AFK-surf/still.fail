// The station's parts in its own process (src/parts.ts): their routes answered after the platform's, a read-only
// member's writes refused but those a part allows, their overview fields said once each, their tools listed and called
// through the agents' door as they are added.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Admin, agentsRoutes } from "../src/api/admin.ts";
import type { Request } from "../src/api/request.ts";
import { StationParts } from "../src/parts.ts";
import { McpEndpoint } from "../src/tools/mcp.ts";

const member = { sub: "u", email: "a@x", name: "A", role: "member", workspace: "w", device: "d" };
const viewer = { ...member, sub: "v", role: "viewer" };
const readers: any = { names: new Map(), read: async () => "{}" };
const json = (status: number, body: unknown) => ({ status, headers: { "content-type": "application/json" }, body: Buffer.from(JSON.stringify(body)) });

function ask(admin: Admin, who: typeof member, method: string, path: string) {
  const r: Request = { method, path, query: [], headers: {}, body: Buffer.alloc(0), viewer: who, lang: "en" };
  return admin.handle(r).then((a) => [a.status, JSON.parse(String(a.body))] as const);
}

test("a part's routes are answered, after the platform's; a read-only member writes only what it allows", async () => {
  const parts = new StationParts();
  const admin = new Admin(readers, { parts });
  // Added after the admin API was made: taken all the same.
  parts.routes([
    { method: "GET", pattern: /^\/shelf$/, handle: async () => json(200, { books: 1 }) },
    { method: "PUT", pattern: /^\/shelf\/place$/, handle: async (r) => json(200, { by: r.viewer.sub }) },
    { method: "POST", pattern: /^\/shelf$/, handle: async () => json(200, { made: true }) },
  ]);
  parts.viewerMay((r) => r.method === "PUT" && r.path === "/shelf/place");
  assert.deepEqual(await ask(admin, viewer, "GET", "/shelf"), [200, { books: 1 }]);
  assert.deepEqual(await ask(admin, viewer, "PUT", "/shelf/place"), [200, { by: "v" }]);
  assert.equal((await ask(admin, viewer, "POST", "/shelf"))[0], 403);
  assert.deepEqual(await ask(admin, member, "POST", "/shelf"), [200, { made: true }]);
  assert.equal((await ask(admin, member, "GET", "/nothing"))[0], 404);
});

test("a part's overview fields, each said once", async () => {
  const parts = new StationParts();
  parts.overview("shelf", (v) => ({ for: v.sub }));
  assert.deepEqual(await parts.overviewOf(member as any, "en"), { shelf: { for: "u" } });
  assert.throws(() => parts.overview("shelf", () => null), /twice/);
});

test("a part's tools reach the agents' door as they are added", async () => {
  const parts = new StationParts();
  const own = [{ name: "chat_post", description: "", inputSchema: {}, run: async () => "posted" }];
  const mcp = new McpEndpoint(() => "s1", () => [...own, ...parts.allTools()]);
  const call = async (method: string, params: unknown) => (await mcp.handle("POST", "Bearer t", JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }))).body as any;
  assert.deepEqual((await call("tools/list", {})).result.tools.map((t: any) => t.name), ["chat_post"]);
  parts.tools([{ name: "secret_list", description: "", inputSchema: {}, run: async (session) => `listed for ${session}` }]);
  assert.deepEqual((await call("tools/list", {})).result.tools.map((t: any) => t.name), ["chat_post", "secret_list"]);
  assert.equal((await call("tools/call", { name: "secret_list", arguments: {} })).result.content[0].text, "listed for s1");
});

test("the agents' side, made after the admin API: asked for as a request comes, its routes a part", async () => {
  const parts = new StationParts();
  let side: any = undefined;
  const admin = new Admin(readers, { parts, agents: () => side });
  // Before it is made: the sessions' writes wait for it, its own routes are not there yet.
  assert.deepEqual(await ask(admin, member, "POST", "/sessions"), [503, { error: "station starting" }]);
  assert.equal((await ask(admin, member, "GET", "/overview"))[0], 404);
  side = { overview: async (v: { sub: string }) => ({ viewer: v.sub }) };
  parts.routes(agentsRoutes(side, {}));
  assert.deepEqual(await ask(admin, member, "GET", "/overview"), [200, { viewer: "u" }]);
});

test("what a part holds in memory goes over to the next process: given as it hands over, taken up as it comes", () => {
  const before = new StationParts();
  before.carry("shelf", () => ({ books: [1, 2] }), () => assert.fail("nothing came before it"));
  const carried = JSON.parse(JSON.stringify(before.carried()));
  assert.deepEqual(carried, { shelf: { books: [1, 2] } });

  // The next process: what came for a part not made yet waits for it; a part none carried for is left alone.
  const after = new StationParts();
  const took: unknown[] = [];
  after.carry("other", () => null, (what) => took.push(["other", what]));
  after.takeUp(carried);
  assert.equal(took.length, 0);
  after.carry("shelf", () => null, (what) => took.push(what));
  assert.deepEqual(took, [{ books: [1, 2] }]);
  assert.throws(() => after.carry("shelf", () => null, () => {}), /twice/);
});
