// Data outflow (docs/data-outflow.md): a program on this machine asks over the station's socket, the person answers,
// and that program alone reads what it was granted, in the shape of /v1, until the grant is revoked.
import assert from "node:assert/strict";
import { request as http } from "node:http";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { type Identity, OutflowGrants, type Scope } from "../src/outflow/grants.ts";
import { type Ask, OutflowServer, words } from "../src/outflow/server.ts";
import { routes } from "../src/api/routes/outflow.ts";
import { Store, newMessage } from "../src/store/store.ts";
import * as read from "../src/read/store.ts";
import { outflowChats, outflowUsage } from "../src/read/outflow.ts";

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

type Rig = { server: OutflowServer; grants: OutflowGrants; path: string; data: string; asked: Parameters<Ask>[0][]; caller: { now: Identity | null }; answer: { next: Scope[] | null | "busy" }; reads: [string, any][] };

async function rig(options: { ask?: boolean } = {}): Promise<Rig> {
  const data = tempdir();
  const path = join(data, "o.sock");
  let now = 1_000;
  const grants = new OutflowGrants(data, () => ++now);
  const asked: Parameters<Ask>[0][] = [];
  const caller = { now: COMMA as Identity | null };
  const answer = { next: ["usage", "chats"] as Scope[] | null | "busy" };
  const reads: [string, any][] = [];
  const server = new OutflowServer({
    path, grants, lang: () => "en",
    identify: async () => caller.now,
    ask: options.ask === false ? null : async (q) => (asked.push(q), answer.next),
    reads: async (op, args) => {
      reads.push([op, args]);
      return JSON.stringify(op === "outflowUsage" ? { rows: [{ day: "2026-10-28" }, { day: "2026-10-27" }] } : { chats: [{ thread: 1 }] });
    },
  });
  await server.listen();
  after(() => server.close());
  return { server, grants, path, data, asked, caller, answer, reads };
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

const ask = (r: Rig, scopes: string[] = ["usage", "chats"]) => call(r, "POST", "/v1/request", { name: "Comma", purpose: "ROI for your team", scopes });

test("a program asks, the person allows what they leave, and the program reads it with its token until revoked", async () => {
  const r = await rig();
  // Only this user may open the socket.
  assert.equal(statSync(r.path).mode & 0o777, 0o600);
  r.answer.next = ["usage"];
  const granted = await ask(r);
  assert.equal(granted.status, 200);
  assert.deepEqual(granted.body.scopes, ["usage"], "what the person left");
  assert.match(granted.body.token, /^sfo_[A-Za-z0-9_-]{43}$/);
  // The window was told who asks as the system says it, and what it said of itself as its own words.
  assert.equal(r.asked.length, 1);
  assert.deepEqual(r.asked[0]!.identity, COMMA);
  assert.deepEqual(r.asked[0]!.scopes.map((s) => s.id), ["usage", "chats"]);
  assert.equal(r.asked[0]!.words.said, "Comma — ROI for your team");
  assert.match(r.asked[0]!.words.summary!, /Developer ID Application: AFK Inc\. \(D9AAN3VJK8\)/);
  // Kept by its hash alone.
  assert.ok(!readFileSync(join(r.data, "outflow.json"), "utf8").includes(granted.body.token));
  assert.equal(statSync(join(r.data, "outflow.json")).mode & 0o777, 0o600);

  const token = granted.body.token;
  const usage = await call(r, "GET", "/v1/usage?from=0&to=86400000&tz=480", undefined, token);
  assert.equal(usage.status, 200);
  assert.equal(usage.body.rows.length, 2);
  assert.deepEqual(r.reads.at(-1), ["outflowUsage", { from: 0, to: 86_400_000, tz: 480, lang: "en" }]);
  // What was not granted, a span too long, no span.
  assert.equal((await call(r, "GET", "/v1/chats", undefined, token)).status, 403);
  assert.equal((await call(r, "GET", `/v1/usage?from=0&to=${32 * 86_400_000}`, undefined, token)).status, 400);
  assert.equal((await call(r, "GET", "/v1/usage", undefined, token)).status, 400);
  // Its reads are kept, for the person to see.
  const [grant] = r.grants.list();
  assert.deepEqual(grant!.reads.map((x) => [x.scope, x.rows]), [["usage", 2]]);
  assert.equal(grant!.lastReadAt, grant!.reads[0]!.at);

  // The token copied to another program reads nothing; nor does no token.
  r.caller.now = OTHER;
  assert.deepEqual(await call(r, "GET", "/v1/usage?from=0&to=1", undefined, token), { status: 401, body: { error: "this token was given to another program" } });
  r.caller.now = COMMA;
  assert.equal((await call(r, "GET", "/v1/usage?from=0&to=1")).status, 401);

  // Revoked from still.fail (its members' route): refused from then on.
  const [, revoke] = routes(r.grants);
  const viewer = { home: true } as never;
  assert.equal((await revoke!.handle({ viewer, query: [] } as never, [grant!.id])).status, 200);
  assert.deepEqual(await call(r, "GET", "/v1/usage?from=0&to=1", undefined, token), { status: 401, body: { error: "revoked" } });
  assert.equal((await revoke!.handle({ viewer, query: [] } as never, [grant!.id])).status, 404);
});

test("refused, busy, unsupported, and asking again replaces the program's grant", async () => {
  const r = await rig();
  r.answer.next = null;
  assert.deepEqual(await ask(r), { status: 403, body: { error: "refused" } });
  r.answer.next = "busy";
  assert.equal((await ask(r)).status, 409);
  assert.equal((await ask(r, ["messages"])).status, 400, "only the kinds there are");
  assert.equal((await ask(r, [])).status, 400);
  r.caller.now = null;
  r.answer.next = ["usage"];
  assert.equal((await ask(r)).status, 403, "a program the system cannot say is not asked for");
  r.caller.now = COMMA;
  assert.equal(r.grants.list().length, 0);

  const first = await ask(r);
  r.answer.next = ["chats"];
  const second = await ask(r);
  assert.deepEqual(r.grants.list().map((g) => g.scopes), [["chats"]], "the same program holds one grant");
  assert.equal((await call(r, "GET", "/v1/chats", undefined, first.body.token)).status, 401);
  assert.equal((await call(r, "GET", "/v1/chats?since=5", undefined, second.body.token)).status, 200);
  assert.deepEqual(r.reads.at(-1), ["outflowChats", { since: 5 }]);
  // Grants outlive the station process.
  assert.deepEqual(new OutflowGrants(r.data, () => 0).list().map((g) => g.id), r.grants.list().map((g) => g.id));

  const none = await rig({ ask: false });
  assert.equal((await ask(none)).status, 501);
});

test("a program that left before it was answered is given nothing, and its window goes", async () => {
  const data = tempdir();
  const grants = new OutflowGrants(data, () => 1);
  let asked!: () => void;
  const waiting = new Promise<void>((resolve) => (asked = resolve));
  const server = new OutflowServer({
    path: join(data, "o.sock"), grants, lang: () => "en", identify: async () => COMMA, reads: async () => "{}",
    // Answered "allow" only once the window was told the program left.
    ask: ({ left }) => (asked(), new Promise((resolve) => left.addEventListener("abort", () => resolve(["usage"]), { once: true }))),
  });
  await server.listen();
  after(() => server.close());
  const req = http({ socketPath: join(data, "o.sock"), method: "POST", path: "/v1/request" });
  req.on("error", () => {});
  req.end(JSON.stringify({ scopes: ["usage"] }));
  await waiting;
  req.destroy();
  await server.close();
  assert.equal(grants.list().length, 0);
});

test("the window says an unsigned program is unsigned", () => {
  const unsigned: Identity = { path: "/tmp/x/node", valid: true, teamId: null, identifier: "node", signer: null, app: null, sha256: "ab" };
  const w = words("en", unsigned, { name: "", purpose: "" }, ["usage", "chats"]);
  assert.equal(w.heading, "node asks to read your still.fail data");
  assert.equal(w.summary, "Give “Token usage and cost” and “Chats and how they stand” of all this station’s chats to node (an unsigned program) until you revoke it.");
  assert.equal(w.said, "");
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
});
