// What one device asks still.fail cloud for as a workspace changes, counted by route: the cloud is the account system
// alone (the root AGENTS.md), and an account's devices share its budget of requests a minute, so a change asks for what
// it changed and nothing more. A workspace's change is told on `/v1/events` to every device of its members, this
// device's own writes' too, and read as it is told (src/sync/cloud.ts `#onEvent`); after a write of its own a device
// reads again only what no event tells (src/sync/cloud.ts `afterWrite`). 2026-11-15, the locks' end to end: of 443
// requests a run made to the cloud, 75 were `/v1/me` and 81 the workspace's view, every account read whole after every
// write and every device of every member reading the workspace whole for a request to be let in that it never shows.
import { Effect } from "effect";
import assert from "node:assert/strict";
import test from "node:test";
import type { FakeHost } from "../src/testing.ts";
import { answers, call } from "./helpers.ts";
import { started, stationReplies } from "./station-fixture.ts";

/// The requests to the cloud since `from`, as "METHOD /path" → how many.
function asked(host: FakeHost, from: number): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const r of host.requests.slice(from)) {
    if (!r.url.startsWith("https://stillfail.test/v1/")) continue;
    const key = `${r.method} ${r.url.replace("https://stillfail.test", "")}`;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

/// A device of the owner's of `ws`, the account reaching `w2` too, at rest.
async function device() {
  const view = { id: "ws", name: "W", role: "owner", members: [{ sub: "s1", role: "owner" }, { sub: "s2", role: "member" }], stations: [{ id: "st", name: "studio", online: true, last_seen: null }] };
  const s = await started(undefined, 0, undefined, (x) => {
    x.cloud.role = "owner";
    x.cloud.also = { name: "W", members: view.members };
    x.cloud.more = [{ id: "w2", name: "日常", role: "owner", members: [] }];
  });
  // The cloud's answers to the writes here: a role changed answers the workspace's view as it is now; an invitation
  // looked at changes nothing.
  stationReplies(s.host, (req) => {
    if (req.method === "PATCH" && req.url.endsWith("/v1/workspaces/ws/members/s2")) return { ...view, members: [view.members[0], { sub: "s2", role: "admin" }] };
    if (req.method === "POST" && req.url.endsWith("/v1/invitations/preview")) return { workspace: { id: "w3", name: "别处" }, role: "member" };
    // (people added: answered with who was added, not with the workspace's view)
    if (req.method === "POST" && req.url.endsWith("/v1/workspaces/ws/members")) return { added: [{ sub: "s3", email: "c@x.com", role: "member" }] };
    return undefined;
  });
  await s.host.time.pass(2_000, 100);
  return s;
}

/// What `run` has the device ask the cloud for, the device brought to rest after it.
async function count(s: Awaited<ReturnType<typeof device>>, run: () => Promise<void> | void): Promise<Record<string, number>> {
  const from = s.host.requests.length;
  await run();
  await s.host.time.pass(5_000, 100);
  return asked(s.host, from);
}

/// A call made, answered.
async function answered(s: Awaited<ReturnType<typeof device>>, ui: number, id: number, name: string, params: unknown) {
  call(s.core, ui, id, name, params);
  let a: Record<string, unknown> | undefined;
  await s.host.time.passUntil(10_000, () => (a ??= answers(s.host.takeEmitted(), id)) !== undefined);
  assert.ok(a && "ok" in a, `${name}: ${JSON.stringify(a)}`);
}

test("what a device asks the cloud for: a change another device made, one it made itself, and a write that changes nothing it holds", async () => {
  const s = await device();
  const ui = s.core.connect();
  const event = (e: unknown) => s.host.socketSend("/v1/events", JSON.stringify(e));
  const counts = {
    // (i) Another device's: its lock alone moved on (an entry a station took, which a device brought the cloud).
    otherLock: await count(s, () => event({ type: "workspace", id: "ws", lock: { head: { seq: 1, hash: "ab".repeat(32), genesis: "cd".repeat(32) }, locked: true } })),
    // (i) An app from before asked to be let in, or that ask was dropped (cloud directory.ts `requestLock`): nothing
    // this device holds or shows of the workspace says those asks.
    otherRequest: await count(s, () => event({ type: "workspace", id: "ws", requests: true })),
    // (i) A member taken out by another device: the account's list (how many are in it) and the workspace changed.
    otherRoster: await count(s, () => (event({ type: "workspaces" }), event({ type: "workspace", id: "ws" }))),
    // (ii) A role changed by this device: the write, then the event the cloud tells every device of its members for it.
    ownRoster: await count(s, async () => {
      await answered(s, ui, 1, "workspace.setRole", { account: "s1", workspace: "ws", member: "s2", role: "admin" });
      event({ type: "workspace", id: "ws" });
    }),
    // (ii) People added by this device: a write the cloud does not answer with the workspace's view, then its event.
    ownAdded: await count(s, async () => {
      await answered(s, ui, 3, "workspace.addMembers", { account: "s1", workspace: "ws", role: "member", emails: ["c@x.com"] });
      event({ type: "workspace", id: "ws" });
    }),
    // (iii) An invitation looked at: a write that changes nothing the device holds, and that the cloud tells nobody.
    nothing: await count(s, () => answered(s, ui, 2, "invitation.preview", { account: "s1", token: "t" })),
  };
  console.log(`COUNTS ${JSON.stringify(counts)}`);
  // (the lock itself read of the cloud: this workspace's station keeps none, as one from before, views/lock.ts)
  assert.deepEqual(counts.otherLock, { "GET /v1/workspaces/ws/lock?after=-1": 1 }, "a lock moved on: the view in place, the lock read where it is kept");
  assert.deepEqual(counts.otherRequest, {}, "an ask to be let in of an app from before: nothing read");
  assert.deepEqual(counts.otherRoster, { "GET /v1/me": 1, "GET /v1/workspaces/ws": 1 }, "the list and the workspace, each once");
  assert.deepEqual(counts.ownRoster, { "PATCH /v1/workspaces/ws/members/s2": 1, "GET /v1/workspaces/ws": 1 }, "the write, and the workspace as its event says");
  assert.deepEqual(counts.ownAdded, { "POST /v1/workspaces/ws/members": 1, "GET /v1/workspaces/ws": 2 }, "the write, that workspace read before it answers, and again as its event says: never the account, the other workspace or the sign-ins");
  assert.deepEqual(counts.nothing, { "POST /v1/invitations/preview": 1 }, "the write alone");
  s.core.close();
});

test("a role changed on this device shows as the cloud answered it, before any event", async () => {
  const s = await device();
  const ui = s.core.connect();
  const from = s.host.requests.length;
  await answered(s, ui, 1, "workspace.setRole", { account: "s1", workspace: "ws", member: "s2", role: "admin" });
  const held = s.core.inner.data.shared({ topic: "workspace", workspace: "ws" }) as { members?: { sub: string; role: string }[] };
  assert.deepEqual(held.members?.find((m) => m.sub === "s2")?.role, "admin");
  assert.deepEqual(asked(s.host, from), { "PATCH /v1/workspaces/ws/members/s2": 1 });
  s.core.close();
});

test("a write in a workspace the cloud does not answer with its view: that workspace is read before the call answers, no event needed", async () => {
  const s = await device();
  const ui = s.core.connect();
  const from = s.host.requests.length;
  await answered(s, ui, 1, "workspace.addMembers", { account: "s1", workspace: "ws", role: "member", emails: ["c@x.com"] });
  assert.deepEqual(asked(s.host, from), { "POST /v1/workspaces/ws/members": 1, "GET /v1/workspaces/ws": 1 }, "read as the call answers, with no event of the cloud's");
  s.core.close();
});

/// A device of the owner's of `ws` as a cloud that versions its views has it (`rev`: the view's version, 1 here).
async function versioned() {
  const view = { id: "ws", name: "W", role: "owner", rev: 1, members: [{ sub: "s1", role: "owner" }, { sub: "s2", role: "member" }], stations: [{ id: "st", name: "studio", online: true, last_seen: null }] };
  const s = await started(undefined, 0, undefined, (x) => {
    x.cloud.role = "owner";
    x.cloud.also = { name: "W", rev: 1, members: view.members };
  });
  const now = () => Math.floor(s.host.nowMs() / 1000);
  stationReplies(s.host, (req) => {
    // (people added: who was added, and the workspace's view as it is now, its version moved on)
    if (req.method === "POST" && req.url.endsWith("/v1/workspaces/ws/members")) return { added: [], joined: ["c@x.com"], already: [], view: { ...view, rev: 2, members: [...view.members, { sub: "s3", role: "member" }] } };
    if (req.method === "POST" && req.url.endsWith("/v1/workspaces/ws/credential")) return { credential: "c", issued_at: now(), expires_at: now() + 3600, relay_url: "https://relay" };
    return undefined;
  });
  await s.host.time.pass(2_000, 100);
  return s;
}

// 2026-11-15, the locks' moved end to end: of alice's 187 requests to the cloud in a minute (her six devices, sixteen
// changes of the list), 49 were `/v1/me` and 61 the workspace's view, each device reading both whole after every change
// a member or a station made, and 23 a member credential, each of a device's dials at once asking for its own.
test("a change the cloud tells with what changed is taken in place; one a device missed, or wrote itself, is read once at most", async () => {
  const s = await versioned();
  const ui = s.core.connect();
  const event = (e: unknown) => s.host.socketSend("/v1/events", JSON.stringify(e));
  const counts = {
    // Another device took a member out: the account's own entry of its list and the member's key, told; the view held
    // is the version before.
    told: await count(s, () => (
      event({ type: "workspaces", entry: { id: "ws", name: "W", role: "owner", created_at: 0, stations: 1, members: 1 } }),
      event({ type: "workspace", id: "ws", rev: [1, 2], gone: { members: ["s2"] } })
    )),
    // A change this device missed (its version not the one before): the view read whole.
    gap: await count(s, () => event({ type: "workspace", id: "ws", rev: [5, 6], put: { members: [{ sub: "s4", role: "member" }] } })),
    // People added on this device: the write's answer carries the view, and the event for it says nothing new.
    own: await count(s, async () => {
      await answered(s, ui, 1, "workspace.addMembers", { account: "s1", workspace: "ws", role: "member", emails: ["c@x.com"] });
      event({ type: "workspace", id: "ws", rev: [1, 2], put: { members: [{ sub: "s3", role: "member" }] } });
    }),
  };
  console.log(`COUNTS ${JSON.stringify(counts)}`);
  assert.deepEqual(counts.told, {}, "told what changed: nothing read");
  assert.deepEqual(counts.gap, { "GET /v1/workspaces/ws": 1 }, "a version missed: the view read once");
  assert.deepEqual(counts.own, { "POST /v1/workspaces/ws/members": 1 }, "the write alone: its answer is the view, its event says nothing new");
  s.core.close();
});

test("the view and the list as told are what reading them would give", async () => {
  const s = await versioned();
  const event = (e: unknown) => s.host.socketSend("/v1/events", JSON.stringify(e));
  const from = s.host.requests.length;
  event({ type: "workspaces", entry: { id: "ws", name: "W2", role: "owner", created_at: 0, stations: 1, members: 2 } });
  event({ type: "workspace", id: "ws", rev: [1, 2], set: { name: "W2" }, put: { members: [{ sub: "s2", role: "admin" }], stations: [{ id: "st", name: "工作室", last_seen: 5 }] } });
  await s.host.time.pass(5_000, 100);
  assert.deepEqual(asked(s.host, from), {});
  const held = s.core.inner.data.shared({ topic: "workspace", workspace: "ws" }) as Record<string, unknown>;
  assert.equal(held.rev, 2);
  assert.equal(held.name, "W2");
  assert.deepEqual(held.members, [{ sub: "s1", role: "owner" }, { sub: "s2", role: "admin" }]);
  // (a station put keeps what the device knows of it that the cloud's entry does not say: whether it is online)
  assert.deepEqual((held.stations as Record<string, unknown>[]).map((x) => [x.id, x.name, x.online, x.last_seen]), [["st", "工作室", true, 5]]);
  const me = s.core.inner.data.record("me", "s1") as { workspaces: Record<string, unknown>[] };
  assert.deepEqual(me.workspaces.find((w) => w.id === "ws"), { id: "ws", name: "W2", role: "owner", created_at: 0, stations: 1, members: 2 });
  s.core.close();
});

test("a device's dials at once ask the cloud for its credential once", async () => {
  const s = await versioned();
  const from = s.host.requests.length;
  const got: string[] = [];
  for (let i = 0; i < 3; i++) s.core.inner.runner.fork(Effect.map(s.core.inner.cloudSync.credential("ws", "k2", false, null), (c) => void got.push(c.credential)));
  await s.host.time.pass(5_000, 100);
  console.log(`CREDENTIAL ${JSON.stringify(asked(s.host, from))}`);
  assert.deepEqual(got, ["c", "c", "c"]);
  assert.deepEqual(asked(s.host, from), { "POST /v1/workspaces/ws/credential": 1 });
  s.core.close();
});
