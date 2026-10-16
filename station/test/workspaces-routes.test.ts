// One station in two workspaces (docs/multi-workspace.md), as the pages see it: a member of one workspace sees, reads and
// changes only its chats; another workspace's sessions, chats and jobs are none for them (404), its changes are not told
// on their event streams, and each workspace keeps its own archive policy. Chats from before (no workspace) are the
// home workspace's. A real store and readers in a temporary data directory, a hub with runtimes scripted in-process.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Admin } from "../src/api/admin.ts";
import { Events } from "../src/api/events.ts";
import { overview } from "../src/api/overview.ts";
import type { Request } from "../src/api/request.ts";
import { jobSeen, sessionSeen, threadSeen } from "../src/api/seen.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { Readers } from "../src/read/pool.ts";
import { DEFAULT_POLICY, currentPolicy } from "../src/sessions/archive-policy.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { Hub } from "../src/sessions/hub.ts";
import { InternalChat } from "../src/sessions/internal.ts";
import { addToThread, newSession } from "../src/sessions/lifecycle.ts";
import { policyOf } from "../src/sessions/review.ts";
import { Store } from "../src/store/store.ts";
import { archiveTools } from "../src/tools/archive.ts";
import { FakeDriver, settle } from "./hub-fakes.ts";

/// A member of the station's home workspace, and an admin of the workspace it joined.
const home = { sub: "h", email: "h@x", name: "H", role: "member", workspace: "W", device: "d", home: true };
const joined = { sub: "b", email: "b@x", name: "B", role: "admin", workspace: "B", device: "d", home: false };
type Viewer = typeof home;

function rig() {
  const data = mkdtempSync(join(tmpdir(), "ws-"));
  const config = hubConfig({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc", models: ["opus"], workspaces: ["B"] }] }, data);
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const hub = new Hub({
    config: () => config,
    store,
    chats: () => undefined,
    drivers: [new FakeDriver("claude")],
    mcpUrl: "http://127.0.0.1:1/mcp",
    internal: new InternalChat(),
    runners: () => [],
    workspaces: () => ["W", "B"],
  });
  const jobs = new Jobs({ store, data, notify: () => {}, link: () => null });
  hub.setJobs(jobs);
  const readers = new Readers(data, 1);
  const agents = { hub, jobs, accounts: {}, overview: async () => ({}) };
  const admin = new Admin(readers, { store, agents: agents as any });
  const ask = async (viewer: Viewer, method: string, path: string, body?: unknown, query: [string, string][] = []) => {
    const r: Request = { method, path, query, headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer, lang: "en" };
    const a = await admin.handle(r);
    return [a.status, JSON.parse(String(a.body))] as const;
  };
  const close = async () => {
    await hub.shutdown();
    await jobs.shutdown();
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  };
  return { data, store, hub, ask, close };
}

/// A chat of each: the home workspace's (made by its member), one from before workspaces (none), the joined one's.
async function chats(r: ReturnType<typeof rig>) {
  const [, w] = await r.ask(home, "POST", "/sessions", { runtime: "claude", title: "home's" });
  const [, b] = await r.ask(joined, "POST", "/sessions", { runtime: "claude", title: "joined's" });
  const [old, oldChat] = newSession(r.hub, { runtime: "claude", createdBy: "h@x", title: "from before" });
  assert.deepEqual([r.store.getSession(w.key)!.ws, r.store.getSession(b.key)!.ws, r.store.getSession(old)!.ws], ["W", "B", null]);
  return { w: { key: w.key as string, thread: w.thread.id as number }, b: { key: b.key as string, thread: b.thread.id as number }, old: { key: old, thread: oldChat.id } };
}

const job = (id: string, sessionKey: string) => ({ id, sessionKey, name: id, command: "sleep 600", cwd: "/", port: null, token: `t-${id}`, state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });

test("each workspace's members list only its chats: the chat list, sessions, threads and jobs", async () => {
  const r = rig();
  try {
    const c = await chats(r);
    r.store.insertJob(job("jw", c.w.key));
    r.store.insertJob(job("jb", c.b.key));
    const ids = (rows: any[], field: string) => rows.map((x) => x[field]).sort();
    const [, homeChats] = await r.ask(home, "GET", "/chats");
    assert.deepEqual(ids(homeChats, "session"), [c.w.key, c.old.key].sort());
    const [, joinedChats] = await r.ask(joined, "GET", "/chats");
    assert.deepEqual(ids(joinedChats, "session"), [c.b.key]);
    assert.deepEqual(ids((await r.ask(home, "GET", "/sessions"))[1], "key"), [c.w.key, c.old.key].sort());
    assert.deepEqual(ids((await r.ask(joined, "GET", "/sessions"))[1], "key"), [c.b.key]);
    assert.deepEqual(ids((await r.ask(home, "GET", "/threads"))[1], "id"), [c.w.thread, c.old.thread].sort());
    assert.deepEqual(ids((await r.ask(joined, "GET", "/threads"))[1], "id"), [c.b.thread]);
    assert.deepEqual((await r.ask(home, "GET", "/threads", undefined, [["session", c.b.key]]))[1], []);
    assert.deepEqual(ids((await r.ask(home, "GET", "/jobs"))[1], "id"), ["jw"]);
    assert.deepEqual(ids((await r.ask(joined, "GET", "/jobs"))[1], "id"), ["jb"]);
    // A list read again as what changed of it: the same.
    const [, changed] = await r.ask(joined, "POST", "/changed/sessions", { held: {} });
    assert.deepEqual(changed.order, [c.b.key]);
  } finally {
    await r.close();
  }
});

test("another workspace's session, chat or job is none: 404 for each route that names one", async () => {
  const r = rig();
  try {
    const c = await chats(r);
    r.store.insertJob(job("jb", c.b.key));
    const none = (status: number) => assert.equal(status, 404);
    for (const [method, path, body] of [
      ["GET", `/sessions/${c.b.key}`],
      ["GET", `/sessions/${c.b.key}/timeline`],
      ["GET", `/sessions/${c.b.key}/files`],
      ["DELETE", `/sessions/${c.b.key}`],
      ["POST", `/sessions/${c.b.key}/archive`],
      ["POST", `/sessions/${c.b.key}/stop`],
      ["POST", `/sessions/${c.b.key}/title`, { title: "mine now" }],
      ["PUT", `/sessions/${c.b.key}/pin`],
      ["GET", `/threads/${c.b.thread}`],
      ["GET", `/threads/${c.b.thread}/entries`],
      ["POST", `/threads/${c.b.thread}/messages`, { text: "hello" }],
      ["PUT", `/threads/${c.b.thread}/read`, { n: 1 }],
      ["POST", `/threads/${c.b.thread}/archive`],
      ["POST", `/threads/${c.b.thread}/publish/preview`, {}],
      ["GET", "/jobs/jb"],
      ["GET", "/jobs/jb/log"],
      ["POST", "/jobs/jb/stop"],
      // Named in the body: a chat opened with it, or it brought into one's own chat.
      ["POST", "/threads", { session: c.b.key }],
      ["POST", `/threads/${c.w.thread}/sessions`, { session: c.b.key }],
    ] as [string, string, unknown?][]) {
      const [status, answer] = await r.ask(home, method, path, body);
      assert.equal(status, 404, `${method} ${path}: ${JSON.stringify(answer)}`);
    }
    none((await r.ask(joined, "GET", `/sessions/${c.old.key}`))[0]);
    none((await r.ask(joined, "GET", `/threads/${c.w.thread}/entries`))[0]);
    // In a batch as on its own.
    const [, batch] = await r.ask(home, "POST", "/batch", { gets: [`/sessions/${c.b.key}`, `/sessions/${c.w.key}`] });
    assert.deepEqual(batch.answers.map((a: any) => a.status), [404, 200]);
    // Nothing of it changed; its own members still have it all.
    assert.equal(r.store.getSession(c.b.key)!.title, "joined's");
    assert.deepEqual(r.store.threadSessions(c.w.thread).map((m) => m.session), [c.w.key]);
    assert.equal((await r.ask(joined, "GET", `/sessions/${c.b.key}`))[0], 200);
    assert.equal((await r.ask(joined, "GET", `/threads/${c.b.thread}/entries`))[0], 200);
    assert.equal((await r.ask(joined, "GET", "/jobs/jb"))[0], 200);
    // The home workspace's own and those from before are its members'.
    assert.equal((await r.ask(home, "GET", `/sessions/${c.old.key}`))[0], 200);
    assert.equal((await r.ask(home, "GET", `/threads/${c.w.thread}`))[0], 200);
  } finally {
    await r.close();
  }
});

test("a chat takes no session of another workspace", async () => {
  const r = rig();
  try {
    const c = await chats(r);
    assert.throws(() => addToThread(r.hub, c.w.thread, c.b.key), /another workspace/);
    // The home workspace's own and those from before go together.
    addToThread(r.hub, c.w.thread, c.old.key);
    assert.deepEqual(r.store.threadSessions(c.w.thread).map((m) => m.session), [c.w.key, c.old.key]);
  } finally {
    await r.close();
  }
});

test("each workspace keeps its own archive policy: its admins and its agents change it, its chats are reviewed under it", async () => {
  const r = rig();
  try {
    const c = await chats(r);
    const options = DEFAULT_POLICY.options.filter((o) => o.id !== "uncertain");
    // A member who is no admin changes none.
    assert.equal((await r.ask({ ...joined, role: "member" }, "PUT", "/automatic-decisions/policy", { policy: "x", options }))[0], 403);
    assert.equal((await r.ask(joined, "PUT", "/automatic-decisions/policy", { policy: "只看 B 的人要的", options }))[0], 200);
    assert.equal(currentPolicy(r.store, "B").policy, "只看 B 的人要的");
    assert.equal(r.store.archivePolicy(), null, "the home workspace's is as it was");
    assert.equal(policyOf(r.hub, c.b.key).policy, "只看 B 的人要的");
    assert.deepEqual(policyOf(r.hub, c.w.key), DEFAULT_POLICY);
    assert.deepEqual(policyOf(r.hub, c.old.key), DEFAULT_POLICY);
    // An agent reads and changes its own chat's workspace's.
    const [tool] = archiveTools(r.hub);
    assert.equal(JSON.parse(await tool!.run(c.b.key, {})).policy, "只看 B 的人要的");
    await tool!.run(c.w.key, { policy: "主 workspace 的" });
    assert.equal(currentPolicy(r.store).policy, "主 workspace 的");
    assert.equal(currentPolicy(r.store, "B").policy, "只看 B 的人要的");
    assert.equal(policyOf(r.hub, c.old.key).policy, "主 workspace 的");
  } finally {
    await r.close();
  }
});

/// Reads a stream's events as they come.
function reader(body: AsyncIterable<Buffer>) {
  const it = body[Symbol.asyncIterator]();
  const got: { event?: string; data?: any }[] = [];
  void (async () => {
    for (;;) {
      const next = await it.next();
      if (next.done) return;
      const m = /^(?:id: [0-9a-f]+\.\d+\n)?event: (.+)\ndata: (.*)\n\n$/.exec(next.value.toString());
      if (m) got.push({ event: m[1], data: JSON.parse(m[2]!) });
    }
  })();
  return { got, close: () => it.return?.() };
}

test("a viewer's event streams carry only their workspace's changes", async () => {
  const r = rig();
  try {
    const c = await chats(r);
    r.store.insertJob(job("jb", c.b.key));
    const readers: any = {
      read: async (op: string, args: any) => {
        if (op === "chats") return "[]";
        if (op === "summary") return JSON.stringify({ key: args.key });
        if (op === "entries") return JSON.stringify({ entries: [{ n: 1 }] });
        if (op === "thread") return JSON.stringify({ id: args.id });
        if (op === "job") return JSON.stringify({ id: args.id });
        throw new Error(op);
      },
    };
    let listener: (c: any) => void = () => {};
    const events = new Events({
      readers,
      subscribe: (l) => ((listener = l), () => {}),
      host: async () => ({}),
      jobLog: () => null,
      tail: () => "",
      outputAt: () => null,
      sessionExists: (key) => r.store.getSession(key) !== null,
      seen: (viewer, of) => ("session" in of ? sessionSeen(r.store, viewer, of.session) : "thread" in of ? threadSeen(r.store, viewer, of.thread) : jobSeen(r.store, viewer, of.job)),
    });
    const ofHome = reader((await events.open(home, "en", false, [], [])).body as AsyncIterable<Buffer>);
    const ofJoined = reader((await events.open(joined, "en", false, [], [])).body as AsyncIterable<Buffer>);
    await settle();
    for (const change of [
      { type: "session", key: c.b.key },
      { type: "session", key: c.w.key },
      { type: "thread", id: c.b.thread, entries: [{ n: 1 }] },
      { type: "thread", id: c.old.thread, entries: [{ n: 1 }] },
      { type: "job", id: "jb" },
      { type: "jobRemoved", id: "jb", session: c.b.key },
      { type: "sessionRemoved", key: "gone-b", ws: "B" },
      { type: "threadRemoved", id: 99, ws: "B" },
      { type: "sessionRemoved", key: "gone-old", ws: null },
    ]) listener(change);
    await settle();
    const told = (s: ReturnType<typeof reader>) => s.got.map((e) => `${e.event} ${e.data.key ?? e.data.id}`).sort();
    assert.deepEqual(told(ofHome), [`session ${c.w.key}`, "session-removed gone-old", `thread ${c.old.thread}`, `thread-view ${c.old.thread}`].sort());
    assert.deepEqual(told(ofJoined), [`session ${c.b.key}`, "session-removed gone-b", `thread ${c.b.thread}`, `thread-view ${c.b.thread}`, "job jb", "job-removed jb", "thread-removed 99"].sort());
    await ofHome.close();
    await ofJoined.close();
  } finally {
    await r.close();
  }
});

test("the overview says the viewer's workspace, its connects and its chats' counts", async () => {
  const r = rig();
  try {
    await chats(r);
    const cloud: any = {
      state: { origin: "https://still.fail", station: "st1", workspace: "W", workspace_name: "Home", name: "studio" },
      membership: (ws: string) => (ws === "B" ? { workspace: "B", workspace_name: "Bee", name: "studio in B" } : ws === "W" ? { workspace: "W", workspace_name: "Home", name: "studio" } : null),
    };
    const config = () => ({ connects: [{ id: "c-home" }, { id: "c-b", workspace: "B" }, { id: "c-w", workspace: "W" }] });
    const of = async (viewer: Viewer) => (await overview({ store: r.store, hub: r.hub, cloud, config }, viewer, "en")) as any;
    const b = await of(joined);
    assert.deepEqual([b.mesh.workspace, b.mesh.workspaceId, b.mesh.name], ["Bee", "B", "studio in B"]);
    assert.deepEqual(b.connects.map((c: any) => c.id), ["c-b"]);
    assert.equal(b.counts.sessions, 1);
    assert.equal(b.drive.anywhere, undefined, "a joined workspace's members browse only its pinned folders");
    const w = await of(home);
    assert.deepEqual([w.mesh.workspace, w.mesh.workspaceId, w.mesh.name], ["Home", "W", "studio"]);
    assert.deepEqual(w.connects.map((c: any) => c.id), ["c-home", "c-w"]);
    assert.equal(w.counts.sessions, 2);
  } finally {
    await r.close();
  }
});
