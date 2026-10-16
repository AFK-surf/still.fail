// Chats shared with other workspaces (src/xshare/index.ts, docs/chat-share.md): two workspaces' stations, each told only
// its own workspace's roster, and the station transport as a direct call that checks what peer.ts checks (a station of
// another workspace is asked only when this one shares chats with it or from it).
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Refused } from "../src/jobs/remote.ts";
import { ChatShares } from "../src/xshare/index.ts";
import { Cloud } from "../src/cloud/state.ts";

const X = "x".repeat(64);
const X2 = "2".repeat(64);
const P = "p".repeat(64);
const Q = "q".repeat(64);
const R = "r".repeat(64);
const S = "s".repeat(64);
const W1 = "01W1";
const W2 = "01W2";

/// What the control plane says of one workspace: its stations.
class Roster {
  listeners = new Set<() => void>();
  workspace: string;
  name: string;
  stations: { id: string; name: string }[];
  constructor(workspace: string, name: string, stations: { id: string; name: string }[]) {
    this.workspace = workspace;
    this.name = name;
    this.stations = stations;
  }
  cloudFor(station: string) {
    const roster = this;
    // On Cloud's own methods (memberships, home…), its state this roster.
    return Object.defineProperties(Object.create(Cloud.prototype), Object.getOwnPropertyDescriptors({
      peersCurrent: true,
      lock: null,
      get state() {
        return { station, workspace: roster.workspace, workspace_name: roster.name, peers: roster.stations, revocations: [] } as any;
      },
      listen(f: () => void) {
        roster.listeners.add(f);
        return () => roster.listeners.delete(f);
      },
    })) as any;
  }
  tell() {
    for (const f of this.listeners) f();
  }
}

/// The store's chat_shares, as the module uses it.
class Shares {
  rows = new Map<string, any>();
  chatShare(k: string) {
    return this.rows.get(k) ?? null;
  }
  chatShares() {
    return new Map(this.rows);
  }
  setChatShare(k: string, to: any[], write: boolean, by: string) {
    if (to.length === 0) this.rows.delete(k);
    else this.rows.set(k, { to, write, by, at: 1 });
  }
  subscribe() {
    return () => {};
  }
  getThread() {
    return null;
  }
}

type Station = { id: string; roster: Roster; xshare: ChatShares; inbox: any[] };
const all = new Map<string, Station>();
const down = new Set<string>();

function station(id: string, roster: Roster): Station {
  const inbox: any[] = [];
  const store = new Shares();
  const me: Station = { id, roster, inbox, xshare: null as any };
  me.xshare = new ChatShares({
    data: mkdtempSync(join(tmpdir(), "xshare-")),
    store: store as any,
    cloud: roster.cloudFor(id),
    ask: async (to, request) => {
      const other = all.get(to);
      if (!other || down.has(to)) throw new Error("peer unavailable");
      const workspace = typeof request?.workspace === "string" ? request.workspace : roster.workspace;
      // peer.ts: this workspace's stations, or another's this station shares chats with.
      if (workspace === roster.workspace) {
        if (!roster.stations.some((s) => s.id === to) || other.roster !== roster) throw new Error("peer is not another station in this workspace");
        return other.xshare.inside(id, request);
      }
      if (!me.xshare.reaches(to, workspace)) throw new Error("that station is of another workspace that shares no chat with this one");
      if (other.roster.workspace !== workspace) throw new Error("station is outside this workspace");
      try {
        return await other.xshare.outside(id, request);
      } catch (e) {
        throw new Refused((e as Error).message);
      }
    },
    link: (chat) => `https://app.still.fail/o/${roster.workspace}/${id}/${chat}`,
    title: (chat) => `title of ${chat}`,
    touches: (request) => [request?.args?.chat ?? request?.chat ?? request?.to].filter((c) => typeof c === "string"),
    inbox: async (peer, request) => (inbox.push({ peer, request }), { ok: true }),
  });
  all.set(id, me);
  return me;
}

const settle = async (...stations: Station[]) => {
  for (let i = 0; i < 4; i++) {
    await new Promise((r) => setImmediate(r));
    await Promise.all(stations.map((s) => s.xshare.reconcile()));
  }
};

/// Asks `to` as `from` would over the transport (as another workspace's station).
const outside = (from: Station, to: Station, request: any) => to.xshare.outside(from.id, request);

test("a chat shared with another workspace reaches its stations once a member said to take it, and is read-only unless written to", async () => {
  all.clear();
  down.clear();
  const w1 = new Roster(W1, "Team", [{ id: X, name: "studio" }, { id: X2, name: "mini" }]);
  const w2 = new Roster(W2, "Home", [{ id: P, name: "laptop" }, { id: Q, name: "desk" }]);
  const x = station(X, w1);
  station(X2, w1);
  const p = station(P, w2);
  const q = station(Q, w2);

  await x.xshare.share("c1", [{ workspace: W2, name: "Home", stations: w2.stations }], false, "a@x");
  await settle(x, p, q);
  // Nobody in W2 said to take chats from X yet: refused.
  assert.deepEqual(p.xshare.borrowed(), []);
  await p.xshare.trust(W1, "Team", X, "studio");
  await settle(p);
  assert.deepEqual(p.xshare.borrowed().map((b) => [b.chat, b.workspaceName, b.write, b.link]), [["c1", "Team", false, `https://app.still.fail/o/${W1}/${X}/c1`]]);
  // Q hears X when X tells it again, and takes P's word that W2 takes chats from it.
  await settle(x, q);
  assert.deepEqual(q.xshare.borrowed().map((b) => b.chat), ["c1"]);

  // Reading the shared chat is let through; another chat, writing, a task, a station of no workspace it is shared with: not.
  await outside(p, x, { method: "session.read", tool: "chat_read", args: { chat: "c1" } });
  assert.equal(x.inbox.length, 1);
  await assert.rejects(outside(p, x, { method: "session.read", tool: "chat_read", args: { chat: "c2" } }), /not shared with your workspace/);
  await assert.rejects(outside(p, x, { method: "session.message", to: "c1", text: "hi" }), /read only/);
  await assert.rejects(outside(p, x, { method: "task.prepare" }), /not open to other workspaces/);
  await assert.rejects(outside(p, x, { method: "session.create" }), /not open to other workspaces/);
  const s = station(S, new Roster("01W3", "Else", [{ id: S, name: "stranger" }]));
  await assert.rejects(outside(s, x, { method: "session.read", tool: "chat_read", args: { chat: "c1" } }), /shares no chat with your workspace/);
  // A station nobody vouched for cannot list chats at P.
  await assert.rejects(outside(s, p, { method: "xshare.changed", chat: "evil", from: "01W3", link: `https://app.still.fail/o/01W3/${S}/evil`, version: 1 }), /no member/);
  assert.deepEqual(p.xshare.borrowed().map((b) => b.chat), ["c1"]);

  // Written to once allowed.
  await x.xshare.share("c1", [{ workspace: W2, name: "Home", stations: w2.stations }], true, "a@x");
  await settle(x, p, q);
  await outside(p, x, { method: "session.message", to: "c1", text: "hi" });
  assert.equal(x.inbox.length, 2);
  assert.equal(p.xshare.borrowed()[0]!.write, true);

  // No longer shared: each station hears it, and is refused.
  await x.xshare.share("c1", [], false, "a@x");
  await settle(x, p, q);
  assert.deepEqual(p.xshare.borrowed(), []);
  assert.deepEqual(q.xshare.borrowed(), []);
  await assert.rejects(outside(p, x, { method: "session.read", tool: "chat_read", args: { chat: "c1" } }));
});

test("the stations of the workspace a chat is shared with are kept current by them, not by the control plane", async () => {
  all.clear();
  down.clear();
  const w1 = new Roster(W1, "Team", [{ id: X, name: "studio" }]);
  const w2 = new Roster(W2, "Home", [{ id: P, name: "laptop" }, { id: Q, name: "desk" }]);
  const x = station(X, w1);
  const p = station(P, w2);
  const q = station(Q, w2);
  await p.xshare.trust(W1, "Team", X, "studio");
  await x.xshare.share("c1", [{ workspace: W2, name: "Home", stations: w2.stations }], false, "a@x");
  await settle(x, p, q);
  assert.equal(q.xshare.borrowed().length, 1);

  // R joins W2, Q leaves it: W2's stations tell X, which tells R and refuses Q.
  w2.stations = [{ id: P, name: "laptop" }, { id: R, name: "new" }];
  const r = station(R, w2);
  w2.tell();
  await settle(p, r, x);
  await settle(x, r);
  assert.deepEqual(r.xshare.borrowed().map((b) => b.chat), ["c1"]);
  await assert.rejects(outside(q, x, { method: "session.read", tool: "chat_read", args: { chat: "c1" } }), /shares no chat/);
  await outside(r, x, { method: "session.read", tool: "chat_read", args: { chat: "c1" } });

  // Away when it was shared: told once it is back.
  down.add(R);
  await x.xshare.share("c2", [{ workspace: W2, name: "Home", stations: w2.stations }], false, "a@x");
  await settle(x, p);
  assert.deepEqual(r.xshare.borrowed().map((b) => b.chat), ["c1"]);
  down.delete(R);
  await settle(x, r);
  assert.deepEqual(r.xshare.borrowed().map((b) => b.chat).sort(), ["c1", "c2"]);
});

test("a session that wrote to another workspace may be answered by it, no other", async () => {
  all.clear();
  down.clear();
  const w1 = new Roster(W1, "Team", [{ id: X, name: "studio" }]);
  const w2 = new Roster(W2, "Home", [{ id: P, name: "laptop" }]);
  const x = station(X, w1);
  const p = station(P, w2);
  await p.xshare.trust(W1, "Team", X, "studio");
  await x.xshare.share("c1", [{ workspace: W2, name: "Home", stations: w2.stations }], true, "a@x");
  await settle(x, p);
  // P's session s1 writes to c1: addressed to W1, and X may answer s1 from now on.
  assert.deepEqual(p.xshare.address(X, { method: "session.message", session: "s1", to: "c1" }), { method: "session.message", session: "s1", to: "c1", workspace: W1 });
  assert.equal(x.xshare.address(P, { method: "session.message", session: "c1", to: "s1" }).workspace, W2);
  await outside(x, p, { method: "session.message", session: "c1", to: "s1", text: "answer" });
  assert.equal(p.inbox.length, 1);
  await assert.rejects(outside(x, p, { method: "session.message", session: "c1", to: "s2", text: "unasked" }), /shares no chat/);
  // A station of this workspace is asked as before: nothing added.
  assert.deepEqual(p.xshare.address(P, { method: "session.read" }), { method: "session.read" });
  // One asking for a workspace of its own it says (`as`, docs/multi-workspace.md) reaches what is shared with that one.
  await outside(p, x, { method: "session.read", args: { chat: "c1" }, as: W2 });
  await assert.rejects(outside(p, x, { method: "session.read", args: { chat: "c1" }, as: "01W9" }), /shares no chat/);
});

test("the pages share a chat (its starter or a manager) and say which station to take chats from; its view says with whom", async () => {
  const { Admin } = await import("../src/api/admin.ts");
  const { Store } = await import("../src/store/store.ts");
  const { openStore } = await import("../src/read/store.ts");
  const { thread: threadView } = await import("../src/read/sessions.ts");
  const dir = mkdtempSync(join(tmpdir(), "xshare-routes-"));
  const store = Store.open(join(dir, "stillfail.db"), join(dir, "archive"));
  store.insertSession({ key: "s1", connect: "ds", runtime: "claude", profile: "cc", workspace: "/w/s1", token: "t", createdAt: 1, lastActiveAt: 1 });
  const chat = store.openThreadOf("ember", "EMBER", "1.1", null, "a@x", "s1");
  const roster = new Roster(W1, "Team", [{ id: X, name: "studio" }]);
  const xshare = new ChatShares({
    data: dir, store, cloud: roster.cloudFor(X),
    ask: async () => {
      throw new Error("peer unavailable");
    },
    link: (c) => `https://app.still.fail/o/${W1}/${X}/${c}`, title: (c) => c, touches: () => [], inbox: async () => ({}),
  });
  const admin = new Admin({ names: new Map(), read: async () => "{}" } as any, { store, agents: { xshare } as any });
  const ask = async (email: string, role: string, method: string, path: string, body: unknown) => {
    const viewer = { sub: email, email, name: email, role, workspace: W1, device: "d" };
    const a = await admin.handle({ method, path, query: [], headers: {}, body: Buffer.from(JSON.stringify(body)), viewer, lang: "en" } as any);
    return [a.status, JSON.parse(String(a.body))] as const;
  };
  const to = [{ workspace: W2, name: "Home", stations: [{ id: P, name: "laptop" }] }];
  assert.equal((await ask("b@x", "member", "PUT", "/sessions/s1/xshare", { to, write: false }))[0], 403);
  assert.equal((await ask("a@x", "member", "PUT", "/sessions/nope/xshare", { to, write: false }))[0], 404);
  assert.equal((await ask("a@x", "member", "PUT", "/sessions/s1/xshare", { to: [{ workspace: W1, name: "self", stations: [{ id: P, name: "x" }] }], write: false }))[0], 400);
  const [status, body] = await ask("a@x", "member", "PUT", "/sessions/s1/xshare", { to, write: true });
  assert.equal(status, 200);
  assert.deepEqual([body.xshare.to, body.xshare.write, body.xshare.by], [[{ workspace: W2, name: "Home" }], true, "a@x"]);
  const reader = openStore(dir);
  const view = threadView(reader, { sub: "a", email: "a@x", name: "A", role: "member", workspace: W1, device: "d" }, String(chat.id), "en");
  assert.deepEqual([view.xshare.to, view.xshare.write], [[{ workspace: W2, name: "Home" }], true]);
  // The chats' rows say it too, by the workspaces' ids.
  const { chats } = await import("../src/read/views.ts");
  const viewer = { sub: "a", email: "a@x", name: "A", role: "member", workspace: W1, device: "d" };
  assert.deepEqual(chats(reader, viewer, false).find((r: any) => r.id === "s1")?.xshare, { to: [W2], write: true });
  // A manager may stop it.
  assert.deepEqual(await ask("c@x", "admin", "PUT", "/sessions/s1/xshare", { to: [], write: false }), [200, { xshare: null }]);
  assert.equal(threadView(reader, { sub: "a", email: "a@x", name: "A", role: "member", workspace: W1, device: "d" }, String(chat.id), "en").xshare, null);
  assert.equal(chats(reader, viewer, false).find((r: any) => r.id === "s1")?.xshare, undefined);
  // Any member says this workspace takes chats from a station of another.
  assert.deepEqual(await ask("b@x", "member", "PUT", "/xshare/hosts", { workspace: W2, name: "Home", station: P, stationName: "laptop" }), [200, { ok: true }]);
  assert.equal((await ask("b@x", "member", "PUT", "/xshare/hosts", { workspace: W1, name: "self", station: P }))[0], 400);
  assert.equal(xshare.workspaceOf(P), W2);
  await xshare.close();
  store.close();
});
