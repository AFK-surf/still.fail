// Data outflow (docs/data-outflow.md): a program on this machine asks over the station's socket, an admin of the
// workspace answers in still.fail, and that program alone reads what it was granted, in the shape of /v1, of this
// station or of every station of the workspace, until the grant is revoked.
import assert from "node:assert/strict";
import { request as http } from "node:http";
import type { Socket } from "node:net";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { type Identity, OutflowGrants, REQUEST_KEPT_MS } from "../src/outflow/grants.ts";
import { OutflowServer, type Workspace } from "../src/outflow/server.ts";
import { routes } from "../src/api/routes/outflow.ts";
import { Store, newMessage } from "../src/store/store.ts";
import * as read from "../src/read/store.ts";
import { outflowChats, outflowMessages, outflowThread, outflowUsage } from "../src/read/outflow.ts";
import { usageOps } from "../src/read/ops-usage.ts";
import { peerRead, textOf } from "../src/outflow/peer.ts";
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
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1")).status, 401);
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1", undefined, "sfo_not-it")).status, 401);

  // Revoked from still.fail: refused from then on.
  assert.equal(await m.revoke(grant!.id), 200);
  assert.deepEqual(await call(r, "GET", "/v1/usage?from=0&to=1", undefined, token), { status: 401, body: { error: "revoked" } });
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

test("v1 reads: the home workspace's usage and chats, field by field, no message", () => {
  const dir = tempdir();
  const store = Store.open(join(dir, "stillfail.db"), null);
  after(() => store.close());
  const session = (key: string, ws: string | null) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws } as never);
  session("a", null);
  session("b", "other-ws");
  const home = store.openThreadOf("ember", "EMBER", "100.1", "Fix the build", "ann@x", "a");
  const away = store.openThreadOf("ember", "EMBER", "100.2", "Theirs", "bob@x", "b");
  store.joinThread(home.id, "a", "ember");
  store.joinThread(away.id, "b", "ember");
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
  assert.deepEqual(usage.people, { "ann@x": { email: "ann@x", via: "cloud" } });

  const chats = outflowChats(r, 0) as any;
  assert.deepEqual(chats.chats.map((c: any) => [c.thread, c.title, c.state, c.creator?.email, c.surface, c.archived]), [[home.id, "Fix the build", "all_done", "ann@x", "stillfail", false]]);
  assert.ok(!JSON.stringify(chats).includes("secret"), "no message");
  // Only those with something new since.
  const later = home.createdAt + 365 * 86_400_000;
  assert.deepEqual(outflowChats(r, later) as any, { since: later, chats: [] });
  // A page at a time: the latest active first, `next` asks for the rest.
  const second = store.openThreadOf("ember", "EMBER", "100.4", "Ship it", "ann@x", "a");
  store.joinThread(second.id, "a", "ember");
  store.insertMessage(newMessage(second.id, "100.5", "person", "ann@x", "ship"));
  const all = (outflowChats(read.openStore(dir), 0) as any).chats.map((c: any) => c.thread);
  const first = outflowChats(read.openStore(dir), 0, undefined, { limit: 1, before: null }) as any;
  const rest = outflowChats(read.openStore(dir), 0, undefined, { limit: 1, before: first.next }) as any;
  assert.deepEqual([first.chats.map((c: any) => c.thread), first.more, rest.chats.map((c: any) => c.thread), rest.more, rest.next], [[all[0]], true, [all[1]], false, null]);
  assert.equal(all.length, 2);
  // Another station of a workspace this one joined reads that workspace's, as its program's grant there asks.
  const theirs = usageOps.outflowChats!(r, { since: 0, ws: { workspace: "other-ws", home: false } }) as any;
  assert.deepEqual(theirs.chats.map((c: any) => c.title), ["Theirs"]);
  const spent = usageOps.outflowUsage!(r, { lang: "en", from: 0, to: 365 * 86_400_000, tz: 0, ws: { workspace: "other-ws", home: false } }) as any;
  assert.deepEqual([spent.rows.map((x: any) => x.person), spent.to], [["bob@x"], 31 * 86_400_000], "a span of 31 days at most, whoever asks");
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
  const home = store.openThreadOf("ember", "EMBER", "200.1", "Fix the build", "ann@x", "a");
  const away = store.openThreadOf("ember", "EMBER", "200.2", "Theirs", "bob@x", "b");
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
  assert.deepEqual([outflowThread(r, { session: "a" }), outflowThread(r, { channel: "EMBER", ts: "200.1" }), outflowThread(r, { session: "nobody" }), outflowThread(r, {})], [home.id, home.id, null, null]);
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
