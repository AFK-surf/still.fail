// Data outflow (docs/data-outflow.md): a program on this machine asks over the station's socket, an admin of the
// workspace answers in still.fail, and that program alone reads what it was granted, in the shape of /v1, of this
// station or of every station of the workspace, until the grant is revoked.
import assert from "node:assert/strict";
import { request as http } from "node:http";
import type { Socket } from "node:net";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { type Identity, OutflowGrants, REQUEST_KEPT_MS } from "../src/outflow/grants.ts";
import { OutflowServer, type Workspace } from "../src/outflow/server.ts";
import { TAILCAT_PORT, TailcatLink, VIA_TAILCAT } from "../src/outflow/tailcat.ts";
import { routes } from "../src/api/routes/outflow.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { installOutflowChatIndex, outflowChatIndexStep, outflowChatScopes } from "../src/store/outflow-index.ts";
import type { InWorkspace } from "../src/store/rows.ts";
import * as read from "../src/read/store.ts";
import { outflowChats, outflowMessages, outflowThread, outflowUsage } from "../src/read/outflow.ts";
import { usageOps } from "../src/read/ops-usage.ts";
import { homeRead, peerRead, textOf } from "../src/outflow/peer.ts";
import { bytesOf } from "../src/mesh/bus.ts";

const dirs: string[] = [];
after(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});
// Short: a Unix socket's path has at most 104 bytes on macOS.
const tempdir = () => {
  const d = mkdtempSync(join(tmpdir(), "outflow-"));
  dirs.push(d);
  return d;
};

function readyChats(store: Store, viewer: InWorkspace = { workspace: "\u0000home", home: true }): void {
  installOutflowChatIndex(store.db);
  for (const scope of outflowChatScopes(viewer)) while (!outflowChatIndexStep(store.db, scope).done) { /* bounded batches */ }
}

const COMMA: Identity = { path: "/Applications/Comma.app/Contents/Resources/station/node", valid: true, teamId: "D9AAN3VJK8", identifier: "surf.comma.station", signer: "Developer ID Application: AFK Inc. (D9AAN3VJK8)", app: "Comma", sha256: null };
const OTHER: Identity = { ...COMMA, teamId: "XXXXXXXXXX", signer: "Developer ID Application: Someone (XXXXXXXXXX)" };

const HERE = { id: "st-here", name: "Office", here: true };
const THERE = { id: "st-there", name: "Ann's Mac", here: false };

type Rig = {
  server: OutflowServer; grants: OutflowGrants; path: string; data: string; caller: { now: Identity | null }; reads: [string, any][]; remote: [string, string, any][];
  /// How many requests were asked (each waits for an admin from then on).
  waited: { count: number }; clock: { now: number };
  /// The connections the station was asked who is at the other end of.
  sockets: Socket[];
};

function station(r: Pick<Rig, "reads" | "remote">): Workspace {
  return {
    here: () => HERE,
    stations: async () => [HERE, THERE, QUIET],
    // A station that never answers: the other end of a link gone quiet.
    read: async (id, op, args) =>
      id === QUIET.id ? new Promise<string>(() => {}) : (r.remote.push([id, op, args]), JSON.stringify({ rows: [{ day: "2026-10-29" }], chats: [{ thread: 9 }] })),
  };
}
const QUIET = { id: "st-quiet", name: "Quiet Mac", here: false };

async function rig(): Promise<Rig> {
  const data = tempdir();
  const path = join(data, "o.sock");
  const clock = { now: 1_000 };
  const grants = new OutflowGrants(data, () => ++clock.now);
  const caller = { now: COMMA as Identity | null };
  const reads: [string, any][] = [];
  const remote: [string, string, any][] = [];
  const waited = { count: 0 };
  const sockets: Socket[] = [];
  const server = new OutflowServer({
    path, grants, lang: () => "en", peerWaitMs: 50,
    identify: async (socket) => (sockets.push(socket), caller.now),
    workspace: station({ reads, remote }),
    reads: async (op, args) => {
      reads.push([op, args]);
      const a = args as { thread?: number };
      if (op === "outflowMessages") return a.thread === 404 ? "null" : JSON.stringify({ thread: a.thread, messages: [{ n: 1 }, { n: 2 }, { n: 3 }], last: 3, more: false });
      return JSON.stringify(op === "outflowUsage" ? { rows: [{ day: "2026-10-28" }, { day: "2026-10-27" }] } : { chats: [{ thread: 1 }] });
    },
  });
  await server.listen();
  after(() => server.close());
  const ask = grants.ask.bind(grants);
  grants.ask = (...args) => (waited.count++, ask(...args));
  return { server, grants, path, data, caller, reads, remote, waited, clock, sockets };
}

function call(r: Rig, method: string, path: string, body?: unknown, token?: string): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    const req = http({ socketPath: r.path, method, path, headers: token ? { authorization: `Bearer ${token}` } : {} }, (res) => {
      let text = "";
      res.setEncoding("utf8");
      res.on("data", (c) => (text += c));
      res.on("end", () => resolve({ status: res.statusCode!, body: text ? JSON.parse(text) : null }));
    });
    req.on("error", reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}

const ask = (r: Rig, scopes: string[] = ["usage", "chats"], more: object = {}) => call(r, "POST", "/v1/request", { name: "Comma", purpose: "ROI for your team", scopes, ...more });

/// A request asked: once it waits for an admin.
async function asked(r: Rig, scopes?: string[], more?: object) {
  const want = r.waited.count + 1;
  const answer = ask(r, scopes, more);
  while (r.waited.count < want) await new Promise((resolve) => setImmediate(resolve));
  return { answer };
}

/// A request asked, and its program gone before an answer, once the station heard it go.
async function askAndLeave(r: Rig, scopes: string[] = ["usage", "chats"], more: object = {}) {
  const want = r.waited.count + 1;
  const req = http({ socketPath: r.path, method: "POST", path: "/v1/request" });
  req.on("error", () => {});
  req.end(JSON.stringify({ name: "Comma", purpose: "ROI for your team", scopes, ...more }));
  while (r.waited.count < want) await new Promise((resolve) => setImmediate(resolve));
  req.destroy();
  const socket = r.sockets.at(-1)!;
  if (!socket.destroyed) await new Promise((resolve) => socket.once("close", resolve));
  await new Promise((resolve) => setImmediate(resolve));
}

const ADMIN = { home: true, role: "admin", email: "boss@x" } as never;
const MEMBER = { home: true, role: "member", email: "ann@x" } as never;
/// The station's members' routes: GET /outflow/grants, DELETE /outflow/grants/:id, POST /outflow/requests/:id.
function members(r: Rig) {
  const [list, revoke, answer] = routes(r.grants);
  return {
    list: async (viewer = MEMBER) => JSON.parse((await list!.handle({ viewer, query: [] } as never, [])).body.toString()),
    revoke: async (id: string, viewer = MEMBER) => (await revoke!.handle({ viewer, query: [] } as never, [id])).status,
    answer: async (id: string, given: unknown, viewer = ADMIN) => (await answer!.handle({ viewer, query: [], body: Buffer.from(JSON.stringify(given)) } as never, [id])).status,
  };
}

test("a program asks, an admin allows what they leave in still.fail, and the program reads it with its token until revoked", async () => {
  const r = await rig();
  const m = members(r);
  // Only this user may open the socket.
  assert.equal(statSync(r.path).mode & 0o777, 0o600);
  const asking = (await asked(r)).answer;
  // The members see who asks as the system says it, and what it said of itself; only an admin answers it.
  const [request] = (await m.list()).requests;
  assert.deepEqual(request.identity, COMMA);
  assert.deepEqual(request.said, { name: "Comma", purpose: "ROI for your team" });
  assert.deepEqual([request.scopes, request.reach], [["usage", "chats"], "station"]);
  assert.equal(await m.answer(request.id, { allow: true, scopes: ["usage"] }, MEMBER), 403);
  assert.equal(await m.answer(request.id, { allow: true, scopes: ["usage", "messages"], workspace: true }), 200);
  const granted = await asking;
  assert.equal(granted.status, 200);
  assert.deepEqual([granted.body.scopes, granted.body.reach], [["usage"], "station"], "what the admin left of what it asked, never more");
  assert.match(granted.body.token, /^sfo_[A-Za-z0-9_-]{43}$/);
  assert.deepEqual((await m.list()).requests, []);
  // Kept by its hash alone, with who allowed it.
  assert.ok(!readFileSync(join(r.data, "outflow.json"), "utf8").includes(granted.body.token));
  assert.equal(statSync(join(r.data, "outflow.json")).mode & 0o777, 0o600);
  const [grant] = r.grants.list();
  assert.equal(grant!.allowedBy, "boss@x");

  const token = granted.body.token;
  const usage = await call(r, "GET", "/v1/usage?from=0&to=86400000&tz=480", undefined, token);
  assert.equal(usage.status, 200);
  assert.equal(usage.body.rows.length, 2);
  assert.deepEqual(r.reads.at(-1), ["outflowUsage", { from: 0, to: 86_400_000, tz: 480, lang: "en" }]);
  // What was not granted, a span too long, no span.
  assert.equal((await call(r, "GET", "/v1/chats", undefined, token)).status, 403);
  assert.equal((await call(r, "GET", `/v1/usage?from=0&to=${32 * 86_400_000}`, undefined, token)).status, 400);
  assert.equal((await call(r, "GET", "/v1/usage", undefined, token)).status, 400);
  // This station alone: the others of the workspace are not its to read.
  assert.deepEqual((await call(r, "GET", "/v1/stations", undefined, token)).body, { stations: [HERE] });
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1&station=st-there", undefined, token)).status, 403);
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1&station=st-here", undefined, token)).status, 200, "this one by its id");
  assert.equal(r.remote.length, 0);
  // Its reads are kept, for the members to see.
  assert.deepEqual(r.grants.list()[0]!.reads.map((x) => [x.scope, x.rows]), [["usage", 2], ["usage", 2]]);

  // The token is what reads: the program updated (another build, another hash) reads on; no token reads nothing.
  r.caller.now = OTHER;
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1", undefined, token)).status, 200);
  r.caller.now = COMMA;
  // A token this station never gave (another station's, say) is told so, with which station says it: not "revoked".
  const unknown = { status: 401, body: { error: "unknown token", station: { id: "st-here", name: "Office" } } };
  assert.deepEqual(await call(r, "GET", "/v1/usage?from=0&to=1"), unknown);
  assert.deepEqual(await call(r, "GET", "/v1/usage?from=0&to=1", undefined, "sfo_not-it"), unknown);

  // Revoked from still.fail: refused from then on, said so with the grant and when, after a restart too.
  const before = r.clock.now;
  assert.equal(await m.revoke(grant!.id), 200);
  const at = r.grants.revokedOf(token)!.at;
  assert.ok(at > before);
  assert.deepEqual(await call(r, "GET", "/v1/usage?from=0&to=1", undefined, token), { status: 401, body: { error: "revoked", grant: grant!.id, revokedAt: at } });
  assert.deepEqual(new OutflowGrants(r.data, () => 0).revokedOf(token), { grant: grant!.id, at });
  assert.equal(await m.revoke(grant!.id), 404);
});

test("a request waits as long as no admin answers; asked again, it is the same one; answered meanwhile, the next ask takes it; refused", async () => {
  const r = await rig();
  const m = members(r);
  assert.equal((await ask(r, ["files"])).status, 400, "only the kinds there are");
  assert.equal((await ask(r, [])).status, 400);
  r.caller.now = null;
  assert.equal((await ask(r)).status, 403, "a program the system cannot say is not asked for");
  r.caller.now = COMMA;
  assert.equal(r.grants.asking().length, 0);

  // The program goes (its station restarts) while it waits; asked again (now for the workspace), the same request.
  await askAndLeave(r);
  const [first] = r.grants.asking();
  await askAndLeave(r, ["usage", "chats", "messages"], { workspace: true });
  assert.deepEqual(r.grants.asking().map((q) => [q.id, q.scopes, q.reach]), [[first!.id, ["usage", "chats", "messages"], "workspace"]]);
  // An admin allows it while the program is away; its next ask is given the token at once.
  assert.equal(await m.answer(first!.id, { allow: true, scopes: ["usage", "chats"], workspace: true }), 200);
  assert.equal(await m.answer(first!.id, { allow: false }), 404, "answered once");
  const granted = await ask(r, ["usage", "chats", "messages"], { workspace: true });
  assert.deepEqual([granted.status, granted.body.scopes, granted.body.reach], [200, ["usage", "chats"], "workspace"]);

  // Asking for more replaces the program's grant, once answered.
  const third = (await asked(r, ["chats", "messages"])).answer;
  assert.equal(await m.answer(r.grants.asking()[0]!.id, { allow: true, scopes: ["chats", "messages"] }), 200);
  const second = await third;
  assert.deepEqual(r.grants.list().map((g) => g.scopes), [["chats", "messages"]], "the same program holds one grant");
  assert.equal((await call(r, "GET", "/v1/chats", undefined, granted.body.token)).status, 401);
  assert.equal((await call(r, "GET", "/v1/chats?since=5", undefined, second.body.token)).status, 200);
  assert.deepEqual(r.reads.at(-1), ["outflowChats", { since: 5 }]);

  // Refused: told so once, then asking is anew.
  const fourth = (await asked(r, ["usage"])).answer;
  const id = r.grants.asking()[0]!.id;
  assert.equal(await m.answer(id, { allow: false }), 200);
  assert.deepEqual(await fourth, { status: 403, body: { error: "refused" } });
  const fifth = (await asked(r, ["usage"])).answer;
  assert.notEqual(r.grants.asking()[0]!.id, id);
  // Allowed with nothing left of it is refused.
  assert.equal(await m.answer(r.grants.asking()[0]!.id, { allow: true, scopes: [] }), 200);
  assert.equal((await fifth).status, 403);
  // Grants and requests outlive the station process.
  assert.deepEqual(new OutflowGrants(r.data, () => 0).list().map((g) => g.id), r.grants.list().map((g) => g.id));
});

test("a program that left before it was answered: its grant stands at once, revocable, its token given when it comes back", async () => {
  const r = await rig();
  const m = members(r);
  await askAndLeave(r, ["usage"]);
  const id = r.grants.asking()[0]!.id;
  assert.equal(await m.answer(id, { allow: true, scopes: ["usage"] }), 200);
  // Listed as allowed and not taken yet, with who allowed it: the members see it and can revoke it.
  const listed = (await m.list()).grants;
  assert.deepEqual(listed.map((g: any) => [g.scopes, g.taken, g.allowedBy]), [[["usage"], false, "boss@x"]]);
  assert.deepEqual((await m.list()).requests, [], "no longer asking");
  const got = await ask(r, ["usage"]);
  assert.equal(got.status, 200);
  assert.deepEqual(r.grants.list().map((g) => [g.id, g.taken]), [[listed[0].id, true]], "the same grant, its token given now");
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1", undefined, got.body.token)).status, 200);

  // Revoked before its program came back: gone with its request; asked again, it is a new request for an admin.
  await askAndLeave(r, ["chats"], { key: "other" });
  assert.equal(await m.answer(r.grants.asking()[0]!.id, { allow: true, scopes: ["chats"] }), 200);
  const waiting = r.grants.list().find((g) => !g.taken)!;
  assert.equal(await m.revoke(waiting.id), 200);
  assert.equal(r.grants.list().some((g) => g.id === waiting.id), false);
  await askAndLeave(r, ["chats"], { key: "other" });
  assert.deepEqual(r.grants.asking().map((q) => q.key), ["other"]);

  // No admin answers in a week: the requests go.
  await askAndLeave(r, ["chats"]);
  assert.equal(r.grants.asking().length, 2);
  r.clock.now += REQUEST_KEPT_MS + 1;
  assert.deepEqual((await m.list()).requests, []);
});

test("a request allowed before grants were made at once is one now, listed and revocable", async () => {
  const data = tempdir();
  const { writeFileSync } = await import("node:fs");
  const request = { id: "q1", identity: COMMA, said: { name: "Comma", purpose: "" }, key: "st-1", scopes: ["usage"], reach: "workspace", askedAt: 1, answer: { at: 2, by: "boss@x", allow: true, scopes: ["usage"], reach: "workspace" } };
  writeFileSync(join(data, "outflow.json"), JSON.stringify({ grants: [], requests: [request] }));
  const grants = new OutflowGrants(data, () => 3);
  assert.deepEqual(grants.list().map((g) => [g.key, g.scopes, g.reach, g.allowedBy, g.taken]), [["st-1", ["usage"], "workspace", "boss@x", false]]);
  const taken = grants.take("q1");
  assert.ok(taken !== null && taken !== "refused" && taken.token.startsWith("sfo_"));
  assert.equal(new OutflowGrants(data, () => 4).list()[0]!.taken, true, "kept");
});

test("granted the workspace: the program lists its stations and reads each, the others' asked over the station transport", async () => {
  const r = await rig();
  const m = members(r);
  const asking = (await asked(r, ["usage", "chats"], { workspace: true })).answer;
  assert.equal(await m.answer(r.grants.asking()[0]!.id, { allow: true, scopes: ["usage", "chats"], workspace: true }), 200);
  const { body } = await asking;
  assert.equal(body.reach, "workspace");
  assert.deepEqual((await call(r, "GET", "/v1/stations", undefined, body.token)).body, { stations: [HERE, THERE, QUIET] });
  const there = await call(r, "GET", "/v1/usage?from=0&to=86400000&station=st-there", undefined, body.token);
  assert.deepEqual([there.status, there.body.rows], [200, [{ day: "2026-10-29" }]]);
  assert.deepEqual(r.remote, [["st-there", "outflowUsage", { from: 0, to: 86_400_000, tz: 0, lang: "en" }]]);
  assert.equal((await call(r, "GET", "/v1/chats?station=st-there&since=3", undefined, body.token)).body.chats[0].thread, 9);
  assert.equal((await call(r, "GET", "/v1/chats?station=st-nowhere", undefined, body.token)).status, 404);
  assert.equal((await call(r, "GET", "/v1/chats", undefined, body.token)).body.chats[0].thread, 1, "this station's without one named");
  // A station that never answers is a 504 once its time is up, not a request left hanging.
  assert.deepEqual(await call(r, "GET", "/v1/chats?station=st-quiet", undefined, body.token), { status: 504, body: { error: "that station did not answer within 50 ms" } });
  assert.deepEqual(r.grants.list()[0]!.reads.map((x) => [x.scope, x.station ?? null]), [["usage", "st-there"], ["chats", "st-there"], ["chats", null]]);
});

test("one program asking under keys of its own holds a grant for each key; asking for more under one replaces that one", async () => {
  const r = await rig();
  const m = members(r);
  const grantFor = async (key: string, scopes: string[]) => {
    const asking = (await asked(r, scopes, { key })).answer;
    assert.deepEqual(r.grants.asking().map((q) => q.key), [key]);
    assert.equal(await m.answer(r.grants.asking()[0]!.id, { allow: true, scopes }), 200);
    return (await asking).body.token as string;
  };
  const one = await grantFor("station-1", ["usage"]);
  const two = await grantFor("station-2", ["chats"]);
  assert.deepEqual(r.grants.list().map((g) => g.key).sort(), ["station-1", "station-2"]);
  const more = await grantFor("station-1", ["usage", "messages"]);
  assert.deepEqual(r.grants.list().map((g) => [g.key, g.scopes]).sort(), [["station-1", ["usage", "messages"]], ["station-2", ["chats"]]]);
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1", undefined, one)).status, 401, "replaced");
  assert.equal((await call(r, "GET", "/v1/chats", undefined, two)).status, 200);
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1", undefined, more)).status, 200);
});

test("a program asking for what it already holds gets it at once, no admin asked; each of its tokens reads", async () => {
  const r = await rig();
  const asking = (await asked(r, ["usage", "chats", "messages"], { workspace: true, key: "cft" })).answer;
  assert.equal(await members(r).answer(r.grants.asking()[0]!.id, { allow: true, scopes: ["usage", "chats", "messages"], workspace: true }), 200);
  const first = (await asking).body;
  const waited = r.waited.count;
  // Less than it holds, under another key or none: the same grant, at once.
  for (const [scopes, more] of [[["messages"], {}], [["usage"], { key: "other" }], [["chats"], { workspace: true }]] as const) {
    const again = await ask(r, [...scopes], more);
    assert.deepEqual([again.status, again.body.grant, again.body.reach], [200, first.grant, "workspace"]);
    assert.notEqual(again.body.token, first.token);
    assert.equal((await call(r, "GET", "/v1/chats", undefined, again.body.token)).status, 200);
  }
  assert.equal(r.waited.count, waited, "no request waited for an admin");
  assert.equal((await call(r, "GET", "/v1/chats", undefined, first.token)).status, 200, "the first token still reads");
  assert.deepEqual([r.grants.list().length, r.grants.asking().length], [1, 0]);
  // Another program holds nothing of it.
  r.caller.now = OTHER;
  await askAndLeave(r, ["usage"]);
  assert.equal(r.grants.asking().length, 1);
});

test("asked for the workspace, an admin may leave it to this station", async () => {
  const r = await rig();
  const m = members(r);
  const asking = (await asked(r, ["usage"], { workspace: true })).answer;
  assert.equal(await m.answer(r.grants.asking()[0]!.id, { allow: true, scopes: ["usage"] }), 200);
  const { body } = await asking;
  assert.equal(body.reach, "station");
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1&station=st-there", undefined, body.token)).status, 403);
});

test("v1 usage: a Feishu person's name and email as far as the names book knows them, never their id for a name", () => {
  const dir = tempdir();
  const store = Store.open(join(dir, "stillfail.db"), null);
  after(() => store.close());
  writeFileSync(join(dir, "config.json"), JSON.stringify({ connects: [{ id: "fs", kind: "feishu", feishu: {} }] }));
  writeFileSync(join(dir, "feishu-names.json"), JSON.stringify({
    "u:fs:ou_ada": { person: { name: "Ada", email: "ada@x" }, at: 1 },
    "u:fs:ou_bo": { person: { name: "Bo", email: "" }, at: 1 },
  }));
  store.insertSession({ key: "a", connect: "fs", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1, createdBy: "slack:fs:ou_ada", ws: null } as never);
  const thread = store.openThreadOf("feishu:fs", "oc_1", "om_1", "A group", "slack:fs:ou_ada", "a");
  store.joinThread(thread.id, "a", "feishu:fs");
  const call = (id: string) => ({ id, at: 86_400_000 + 1, model: "claude-opus-5-5", subagent: false, fast: false, input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
  const people = ["slack:fs:ou_ada", "slack:fs:ou_bo", "slack:fs:ou_cy"];
  store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: null }, "claude", people.map((person) => [call(person), { turn: null, person, thread: thread.id, profile: "cc" }]) as never);
  const usage = outflowUsage(read.openStore(dir), "en", 86_400_000, 2 * 86_400_000, 0) as any;
  assert.deepEqual(usage.people, {
    "slack:fs:ou_ada": { name: "Ada", email: "ada@x", via: "feishu" },
    "slack:fs:ou_bo": { name: "Bo", email: null, via: "feishu" },
    "slack:fs:ou_cy": { name: null, email: null, via: "feishu" },
  });
});

test("v1 reads: the home workspace's usage and chats, field by field, no message", () => {
  const dir = tempdir();
  const store = Store.open(join(dir, "stillfail.db"), null);
  after(() => store.close());
  const session = (key: string, ws: string | null) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws } as never);
  session("a", null);
  session("b", "other-ws");
  // Made in the app: it names the home workspace by its id.
  session("c", "ws-home");
  const home = store.openThreadOf("ember", "CHAT", "100.1", "Fix the build", "ann@x", "a");
  const away = store.openThreadOf("ember", "CHAT", "100.2", "Theirs", "bob@x", "b");
  const app = store.openThreadOf("ember", "CHAT", "100.6", "From the app", "ann@x", "c");
  store.joinThread(home.id, "a", "ember");
  store.joinThread(away.id, "b", "ember");
  store.joinThread(app.id, "c", "ember");
  store.insertMessage(newMessage(home.id, "100.3", "person", "ann@x", "a secret plan"));
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "ann@x", thread: home.id });
  store.endTurn("t1", "done", null, "all_done", null);
  const call = (id: string, at: number) => ({ id, at, model: "claude-opus-5-5", subagent: false, fast: false, input: 100, cacheRead: 40, cacheWrite: 10, cacheWriteLong: 0, output: 5, calls: 1, context: null, window: null });
  store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: null }, "claude", [[call("c1", 86_400_000 + 1), { turn: "t1", person: "ann@x", thread: home.id, profile: "cc" }]] as never);
  store.recordUsage("/b.jsonl", { session: "b", offset: 1, model: null }, "claude", [[call("c2", 86_400_000 + 2), { turn: null, person: "bob@x", thread: away.id, profile: "cc" }]] as never);
  const r = read.openStore(dir);

  const usage = outflowUsage(r, "en", 86_400_000, 2 * 86_400_000, 0) as any;
  assert.deepEqual(Object.keys(usage.rows[0]).sort(), ["account", "cacheRead", "cacheWrite", "calls", "cost", "day", "input", "model", "output", "person", "runtime", "session", "thread"].sort());
  assert.deepEqual(usage.rows.map((x: any) => [x.thread, x.person, x.calls, x.input, x.cacheWrite]), [[home.id, "ann@x", 1, 100, 10]], "another workspace's chats are not the station's to give");
  assert.ok(usage.rows[0].cost > 0);
  assert.deepEqual(usage.people, { "ann@x": { name: null, email: "ann@x", via: "cloud" } });
  const otherUsage = outflowUsage(r, "en", 86_400_000, 2 * 86_400_000, 0, { workspace: "other-ws", home: false }) as any;
  assert.deepEqual(otherUsage.rows.map((x: any) => [x.session, x.thread]), [["b", away.id]]);

  readyChats(store);
  const chats = outflowChats(r, 0) as any;
  assert.deepEqual(chats.chats.map((c: any) => [c.thread, c.title, c.state, c.creator?.email, c.surface, c.archived]), [[home.id, "Fix the build", "all_done", "ann@x", "stillfail", false]]);
  assert.ok(!JSON.stringify(chats).includes("secret"), "no message");
  // Only those with something new since.
  const later = home.createdAt + 365 * 86_400_000;
  assert.deepEqual(outflowChats(r, later) as any, { since: later, chats: [] });
  // A page at a time: the latest active first, `next` asks for the rest.
  const second = store.openThreadOf("ember", "CHAT", "100.4", "Ship it", "ann@x", "a");
  store.joinThread(second.id, "a", "ember");
  store.insertMessage(newMessage(second.id, "100.5", "person", "ann@x", "ship"));
  readyChats(store);
  const all = (outflowChats(read.openStore(dir), 0) as any).chats.map((c: any) => c.thread);
  const first = outflowChats(read.openStore(dir), 0, undefined, { limit: 1, before: null }) as any;
  const rest = outflowChats(read.openStore(dir), 0, undefined, { limit: 1, before: first.next }) as any;
  assert.deepEqual([first.chats.map((c: any) => c.thread), first.more, rest.chats.map((c: any) => c.thread), rest.more, rest.next], [[all[0]], true, [all[1]], false, null]);
  assert.equal(all.length, 2);
  // Another station of a workspace this one joined reads that workspace's, as its program's grant there asks.
  readyChats(store, { workspace: "other-ws", home: false });
  const theirs = usageOps.outflowChats!(r, { since: 0, ws: { workspace: "other-ws", home: false } }) as any;
  assert.deepEqual(theirs.chats.map((c: any) => c.title), ["Theirs"]);
  const spent = usageOps.outflowUsage!(r, { lang: "en", from: 0, to: 365 * 86_400_000, tz: 0, ws: { workspace: "other-ws", home: false } }) as any;
  assert.deepEqual([spent.rows.map((x: any) => x.person), spent.to], [["bob@x"], 31 * 86_400_000], "a span of 31 days at most, whoever asks");
  // Read here with the home workspace's id: its chats made in the app too, those that say no workspace as well.
  readyChats(store, { workspace: "ws-home", home: true });
  const own = usageOps.outflowChats!(read.openStore(dir), { since: 0, ws: { workspace: "ws-home", home: true } }) as any;
  assert.deepEqual(own.chats.map((c: any) => c.title).sort(), ["Fix the build", "From the app", "Ship it"]);
});

test("listing chats for a program does not count the chat's unread history", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThreadOf("ember", "CHAT", "100.1", "A chat", "ann@x", "a");
    store.joinThread(thread.id, "a", "ember");
    const entry = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', 'ann@x', 'body', ?)");
    store.db.exec("BEGIN");
    for (let n = 1; n <= 1_000; n++) entry.run(thread.id, n, n);
    store.db.exec("COMMIT");
    store.db.prepare("UPDATE threads SET created_at = 1 WHERE id = ?").run(thread.id);
    store.db.prepare("INSERT INTO entries (thread, n, kind, target, author_kind, author, text, at) VALUES (?, 1001, 'edit', 1000, 'person', 'ann@x', 'edited', 999999)").run(thread.id);
    readyChats(store);
    const reader = read.makeStore(store.db, ".");
    const expected = outflowChats(reader, 0, undefined, { limit: 1, before: null }) as any;
    assert.equal(expected.chats[0].lastActiveAt, read.lastSaid(reader, thread.id)?.createdAt);
    assert.equal(expected.chats[0].lastActiveAt, 1_000, "an edit does not replace the message's original activity time");
    const db = reader.db;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === read.UNREAD) throw new Error("counted unread history");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(reader, "db", { value: traced, configurable: true });
    try { assert.deepEqual(outflowChats(reader, 0, undefined, { limit: 1, before: null }), expected); }
    finally { Object.defineProperty(reader, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("a chat export reads its agents' state without counting pending deliveries", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThreadOf("ember", "CHAT", "pending", "Chat", "ann@x", "a");
    store.joinThread(thread.id, "a", "ember");
    const insert = store.db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (?,?,'a')");
    store.db.exec("BEGIN");
    for (let n=1; n<=500; n++) insert.run(thread.id, n);
    store.db.exec("COMMIT");
    readyChats(store);
    const reader = read.makeStore(store.db, ".");
    const expected = outflowChats(reader, 0, undefined, { limit: 1, before: null });
    const db = reader.db;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("FROM deliveries d INDEXED BY deliveries_pending")) throw new Error("counted pending deliveries");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(reader, "db", { value: traced, configurable: true });
    try { assert.deepEqual(outflowChats(reader, 0, undefined, { limit: 1, before: null }), expected); }
    finally { Object.defineProperty(reader, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("a shared chat's exported agents belong to the requested workspace", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws, runtime] of [["a", "A", "claude"], ["b", "B", "codex"], ["home", null, "gemini"]] as const) {
      store.insertSession({ key, connect: "ember", runtime, profile: "p", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const thread = store.openThreadOf("ember", "CHAT", "shared", "Shared", "ann@x", "a");
    for (const key of ["a", "b", "home"]) store.joinThread(thread.id, key, "ember");
    readyChats(store, { workspace: "A", home: true });
    readyChats(store, { workspace: "B", home: false });
    const reader = read.makeStore(store.db, ".");
    const a = outflowChats(reader, 0, { workspace: "A", home: true }, { limit: 1, before: null }) as any;
    const b = outflowChats(reader, 0, { workspace: "B", home: false }, { limit: 1, before: null }) as any;
    assert.deepEqual(a.chats[0].agents.map((agent: any) => agent.runtime), ["claude", "gemini"]);
    assert.deepEqual(b.chats[0].agents.map((agent: any) => agent.runtime), ["codex"]);
  } finally { store.close(); }
});

test("export pages merge home and workspace chats once, including tied activity times", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["home", null], ["a", "A"], ["b", "B"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws });
    for (const [name, members] of [["one", ["a", "home"]], ["two", ["a"]], ["three", ["home"]], ["four", ["a", "home"]], ["away", ["b"]]] as const) {
      const thread = store.openThreadOf("ember", "CHAT", name, name, "ann@x", members[0]!);
      for (const member of members) store.joinThread(thread.id, member, "ember");
      store.db.prepare("UPDATE threads SET created_at=10 WHERE id=?").run(thread.id);
    }
    const viewer = { workspace: "A", home: true };
    readyChats(store, viewer);
    const reader = read.makeStore(store.db, ".");
    const first = outflowChats(reader, 10, viewer, { limit: 2, before: null }) as any;
    const second = outflowChats(reader, 10, viewer, { limit: 2, before: first.next }) as any;
    assert.deepEqual(first.chats.map((chat: any) => chat.title), ["four", "three"]);
    assert.deepEqual(second.chats.map((chat: any) => chat.title), ["two", "one"]);
    assert.deepEqual([first.more, second.more, second.next], [true, false, null]);
    assert.deepEqual((outflowChats(reader, 11, viewer) as any).chats, []);
  } finally { store.close(); }
});

test("a page of exported chats does not enumerate every session", () => {
  const store = Store.open(":memory:");
  try {
    for (const key of ["a", "b", "c"]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
        createdAt: 1, lastActiveAt: 1, ws: "A" });
      const thread = store.openThreadOf("ember", "CHAT", `chat-${key}`, key, "ann@x", key);
      store.joinThread(thread.id, key, "ember");
      store.db.prepare("UPDATE threads SET created_at = 10 WHERE id = ?").run(thread.id);
    }
    store.db.exec("BEGIN");
    for (let i = 0; i < 200; i++) store.insertSession({ key: `other-${i}`, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w", token: `other-${i}`, createdAt: 1, lastActiveAt: 1, ws: "B" });
    store.db.exec("COMMIT");
    const reader = read.makeStore(store.db, "."), viewer = { workspace: "A", home: false };
    readyChats(store, viewer);
    const first = outflowChats(reader, 0, viewer, { limit: 1, before: null }) as any;
    const second = outflowChats(reader, 0, viewer, { limit: 1, before: first.next }) as any;
    assert.deepEqual(first.chats.map((chat: any) => chat.title), ["c"]);
    assert.deepEqual(second.chats.map((chat: any) => chat.title), ["b"]);
    const db = reader.db;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === "SELECT * FROM sessions ORDER BY last_active_at DESC") throw new Error("enumerated session history");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(reader, "db", { value: traced, configurable: true });
    try {
      assert.deepEqual(outflowChats(reader, 0, viewer, { limit: 1, before: null }), first);
      assert.deepEqual(outflowChats(reader, 0, viewer, { limit: 1, before: first.next }), second);
    } finally { Object.defineProperty(reader, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("messages: a chat's, a page at a time, to a program granted them", async () => {
  const r = await rig();
  const asking = (await asked(r, ["messages"])).answer;
  assert.equal(await members(r).answer(r.grants.asking()[0]!.id, { allow: true, scopes: ["messages"] }), 200);
  const { body } = await asking;
  const page = await call(r, "GET", "/v1/messages?thread=7&after=2&limit=1000", undefined, body.token);
  assert.equal(page.status, 200);
  assert.deepEqual(r.reads.at(-1), ["outflowMessages", { thread: 7, after: 2, limit: 500 }], "a page is at most 500");
  assert.deepEqual(r.grants.list()[0]!.reads.map((x) => [x.scope, x.rows]), [["messages", 3]]);
  assert.equal((await call(r, "GET", "/v1/messages", undefined, body.token)).status, 400, "a chat named");
  await call(r, "GET", "/v1/messages?session=claude-ember%3AC1%3A100.1", undefined, body.token);
  assert.deepEqual(r.reads.at(-1), ["outflowMessages", { session: "claude-ember:C1:100.1", after: 0, limit: 100 }], "a chat by a session of it");
  await call(r, "GET", "/v1/messages?channel=C1&ts=100.1&after=4", undefined, body.token);
  assert.deepEqual(r.reads.at(-1), ["outflowMessages", { channel: "C1", ts: "100.1", after: 4, limit: 100 }], "a chat by its channel and thread ts");
  assert.equal((await call(r, "GET", "/v1/messages?thread=404", undefined, body.token)).status, 404);
  assert.equal((await call(r, "GET", "/v1/chats", undefined, body.token)).status, 403, "only what was granted");
});

test("v1 messages: the home workspace's chat's entries after one, oldest first; another workspace's is none", () => {
  const dir = tempdir();
  const store = Store.open(join(dir, "stillfail.db"), null);
  after(() => store.close());
  const session = (key: string, ws: string | null) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1, ws } as never);
  session("a", null);
  session("b", "other-ws");
  const home = store.openThreadOf("ember", "CHAT", "200.1", "Fix the build", "ann@x", "a");
  const away = store.openThreadOf("ember", "CHAT", "200.2", "Theirs", "bob@x", "b");
  store.joinThread(home.id, "a", "ember");
  store.joinThread(away.id, "b", "ember");
  store.insertMessage(newMessage(home.id, "200.3", "person", "ann@x", "the build fails on main"));
  store.insertMessage(newMessage(home.id, "200.4", "agent", "a", "fixed in #12"));
  store.insertMessage(newMessage(home.id, "200.5", "person", "ann@x", "thanks"));
  store.insertMessage(newMessage(away.id, "200.6", "person", "bob@x", "private"));
  const r = read.openStore(dir);
  const all = outflowMessages(r, home.id, 0, 100) as any;
  assert.deepEqual(all.messages.map((m: any) => [m.authorKind, m.author, m.text]), [["person", "ann@x", "the build fails on main"], ["agent", "a", "fixed in #12"], ["person", "ann@x", "thanks"]]);
  assert.equal(all.more, false);
  const page = outflowMessages(r, home.id, all.messages[0].n, 1) as any;
  assert.deepEqual([page.messages.map((m: any) => m.text), page.more, page.last], [["fixed in #12"], true, all.messages[2].n]);
  assert.equal(outflowMessages(r, away.id, 0, 100), null, "another workspace's chat");
  // A program names the chat by its thread, a session of it, or its channel and thread ts.
  assert.deepEqual([outflowThread(r, { session: "a" }), outflowThread(r, { channel: "CHAT", ts: "200.1" }), outflowThread(r, { session: "nobody" }), outflowThread(r, {})], [home.id, home.id, null, null]);
  assert.equal((usageOps.outflowMessages!(r, { session: "a", limit: 1 }) as any).messages[0].text, "the build fails on main");
  assert.equal(outflowMessages(r, 99_999, 0, 100), null);
});

test("a station's update keeps the socket: the process before, stopping, leaves the next one's", async () => {
  const data = tempdir();
  const path = join(data, "o.sock");
  const grants = new OutflowGrants(data, () => 1);
  const make = (name: string) =>
    new OutflowServer({ path, grants, lang: () => "en", identify: async () => (name === "next" ? null : COMMA), workspace: station({ reads: [], remote: [] }), reads: async () => "{}" });
  const before = make("before");
  await before.listen();
  const next = make("next");
  await next.listen();
  await before.close();
  // what answers there now is the next process (which cannot say who asks: refused)
  const answer = await new Promise<number>((resolve, reject) => {
    const req = http({ socketPath: path, method: "POST", path: "/v1/request" }, (res) => (res.resume(), resolve(res.statusCode!)));
    req.on("error", reject);
    req.end(JSON.stringify({ scopes: ["usage"] }));
  });
  assert.equal(answer, 403);
  assert.equal(statSync(path).mode & 0o777, 0o600);
  await next.close();
  assert.throws(() => statSync(path), "gone with the last");
  // a socket left by a process that ended without closing goes as the next one starts
  const { writeFileSync, readdirSync } = await import("node:fs");
  writeFileSync(join(data, "o-999999-abcdef01.sock"), "");
  const again = make("again");
  await again.listen();
  assert.ok(!readdirSync(data).includes("o-999999-abcdef01.sock"));
  await again.close();
});

test("a process from before this one, stopping, removes the path itself: it is put back once it is gone", async () => {
  const data = tempdir();
  const path = join(data, "o.sock");
  const server = new OutflowServer({ path, grants: new OutflowGrants(data, () => 1), lang: () => "en", identify: async () => COMMA, workspace: station({ reads: [], remote: [] }), reads: async () => "{}" });
  await server.listen();
  const { existsSync, rmSync } = await import("node:fs");
  rmSync(path);
  assert.equal(existsSync(path), false);
  server.previousGone();
  assert.equal(statSync(path).mode & 0o777, 0o600);
  server.previousGone();
  assert.equal(statSync(path).mode & 0o777, 0o600, "a link there stays");
  await server.close();
});

test("another station's read: one of the outflow reads, of the workspace it asks in, its answer as bytes", async () => {
  const asked: [string, any][] = [];
  const answer = peerRead(async (op, args) => (asked.push([op, args]), JSON.stringify({ chats: [{ thread: 3 }] })), () => "ws-home", () => "en");
  const got = await answer("peer", { method: "outflow.read", op: "outflowChats", args: { since: 7, ws: { workspace: "forged", home: true } } }, "ws-home");
  assert.deepEqual(JSON.parse(await textOf(bytesOf(got)!)), { chats: [{ thread: 3 }] });
  assert.deepEqual(asked, [["outflowChats", { since: 7, lang: "en", ws: { workspace: "ws-home", home: true } }]], "the workspace is the transport's, never the request's");
  await answer("peer", { op: "outflowUsage", args: { from: 0, to: 1 } }, "ws-joined");
  assert.deepEqual(asked.at(-1)![1].ws, { workspace: "ws-joined", home: false });
  await assert.rejects(answer("peer", { op: "usage", args: {} }, "ws-home"), /no such read/, "none of the station's other reads");
  await assert.rejects(answer("peer", { op: "outflowChats", args: {} }, undefined), /workspace/);
});

test("this station's own read: of its home workspace by its id, once known", async () => {
  const asked: any[] = [];
  let home: string | null = null;
  const reads = homeRead(async (_op, args) => (asked.push(args), "{}"), () => home);
  await reads("outflowChats", { since: 1 }, "en");
  home = "ws-home";
  await reads("outflowChats", { since: 2 }, "en");
  assert.deepEqual(asked, [{ since: 1 }, { since: 2, ws: { workspace: "ws-home", home: true } }]);
});

/// A request on a TCP port of the loopback, as tailcat forwards one there.
function tcp(port: number, method: string, path: string, body?: unknown, token?: string): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    const req = http({ host: "127.0.0.1", port, method, path, headers: token ? { authorization: `Bearer ${token}` } : {} }, (res) => {
      let text = "";
      res.setEncoding("utf8");
      res.on("data", (c) => (text += c));
      res.on("end", () => resolve({ status: res.statusCode!, body: text ? JSON.parse(text) : null }));
    });
    req.on("error", reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}

test("through the Tailcat link: a program of another machine asks and reads as one here does; anything else on the port is turned away", async () => {
  const r = await rig();
  const m = members(r);
  const through = { now: true };
  const { port, close } = await r.server.listenTcp(0, async () => (through.now ? VIA_TAILCAT : null));
  after(close);
  const asking = tcp(port, "POST", "/v1/request", { name: "Comma", purpose: "usage for the team", scopes: ["usage"], workspace: true, key: "comma" });
  while (r.waited.count < 1) await new Promise((resolve) => setImmediate(resolve));
  const [request] = (await m.list()).requests;
  assert.deepEqual(request.identity, VIA_TAILCAT, "shown as come through Tailcat, nothing it says of itself taken for who it is");
  assert.equal(await m.answer(request.id, { allow: true, scopes: ["usage"], workspace: true }), 200);
  const granted = await asking;
  assert.deepEqual([granted.status, granted.body.reach], [200, "workspace"]);
  assert.equal((await tcp(port, "GET", "/v1/usage?from=0&to=1", undefined, granted.body.token)).status, 200);
  // Not the link's tailcat at the other end (a program of this machine on the port): neither asks nor reads, token or not.
  through.now = false;
  assert.equal((await tcp(port, "GET", "/v1/usage?from=0&to=1", undefined, granted.body.token)).status, 403);
  assert.equal((await tcp(port, "POST", "/v1/request", { scopes: ["usage"] })).status, 403);
  // The socket's programs are not the link's: the link's grant is not theirs to take.
  assert.equal(r.grants.held(COMMA, ["usage"], "workspace"), null);
});

test("the Tailcat link: off until an admin turns it on, kept so; its address once tailcat says it; only the link's tailcat counts on its port", async () => {
  const r = await rig();
  const dir = tempdir();
  // A tailcat that makes its key and, serving, says its address and stays.
  const fake = join(dir, "tailcat");
  writeFileSync(
    fake,
    `#!/bin/sh\nif [ "$1" = genkey ]; then echo '{}' > "$3"; exit 0; fi\necho '{"listenAddr":"tcFAKEADDRESS"}'\nexec sleep 600\n`,
    { mode: 0o755 },
  );
  const changes = { count: 0 };
  const link = new TailcatLink({ data: r.data, server: r.server, command: fake, changed: () => changes.count++, holders: async () => [process.pid] });
  after(() => link.close());
  link.start();
  assert.deepEqual(link.view(), { on: false, state: "off", address: null, port: null, error: null });
  await link.set(true);
  while (link.view().state !== "running") await new Promise((resolve) => setTimeout(resolve, 10));
  const view = link.view();
  assert.equal(view.address, "tcFAKEADDRESS");
  assert.ok(view.port! >= TAILCAT_PORT && view.port! < TAILCAT_PORT + 10);
  assert.ok(statSync(join(r.data, "tailcat", "outflow.private.json")).isFile(), "its key made once, for the same address each start");
  assert.ok(changes.count > 0);
  // This test's process is not the link's tailcat: its requests on the port are refused.
  assert.equal((await tcp(view.port!, "POST", "/v1/request", { scopes: ["usage"] })).status, 403);
  // Kept for the next start; off, the port closes.
  assert.equal(new TailcatLink({ data: r.data, server: r.server, changed: () => {} }).view().on, true);
  await link.set(false);
  assert.deepEqual(link.view(), { on: false, state: "off", address: null, port: null, error: null });
  await assert.rejects(tcp(view.port!, "GET", "/v1/stations"));
  assert.equal(new TailcatLink({ data: r.data, server: r.server, changed: () => {} }).view().on, false);
});

test("the Tailcat link keeps its port across a hand-over: started once the process before is gone, and not after closing", async () => {
  const r = await rig();
  const dir = tempdir();
  const fake = join(dir, "tailcat");
  writeFileSync(fake, `#!/bin/sh\nif [ "$1" = genkey ]; then echo '{}' > "$3"; exit 0; fi\necho '{"listenAddr":"tcFAKEADDRESS"}'\nexec sleep 600\n`, { mode: 0o755 });
  const made = (data: string) => new TailcatLink({ data, server: r.server, command: fake, changed: () => {}, holders: async () => [process.pid] });
  const running = async (link: TailcatLink) => {
    while (link.view().state !== "running") await new Promise((resolve) => setTimeout(resolve, 10));
    return link.view().port!;
  };
  const before = made(r.data);
  after(() => before.close());
  await before.set(true);
  const port = await running(before);
  // While the process before holds the port, the next one has not started its link.
  const next = made(r.data);
  after(() => next.close());
  assert.equal(next.view().state, "off");
  await before.close();
  next.start();
  assert.equal(await running(next), port);
  // A second start leaves it as it is; one after closing starts nothing.
  next.start();
  assert.equal(next.view().state, "running");
  await next.close();
  next.start();
  assert.equal(next.view().state, "off");
});
