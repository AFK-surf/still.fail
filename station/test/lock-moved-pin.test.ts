// A station that keeps no lock of a workspace it joined (enrolled by its token alone) protected after that workspace's
// chain moved (「保护」: `station {key}` in an owner's log): the plane's chain, which never names it, is only offered
// (cloud/presence.ts `takeFromPlane`), and it pins it once the state the logs and bodies a station of the workspace
// gives make names its key (mesh/moved-pin.ts `pinMoved`); never by the plane's word alone, never over a lock it pins
// already, and a station of the lock gives it the bodies only once its list names it (person-sync.ts `bodiesGiven`).
// 2026-11-14, the locks' end to end, round 17 run moved: 「保护」 left the station unprotected for good.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { type Entry, entryHash } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { answerLock } from "../src/mesh/lock-sync.ts";
import { pinMoved } from "../src/mesh/moved-pin.ts";
import { WS, WS2, bring, ed, handover, signed, station, viewerOf, world } from "./lock-moved-world.ts";
import { lockRoute } from "../src/mesh/serve.ts";
import { pendingLockPath } from "../src/cloud/state.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

/// The world moved and handed over, station s0 keeping it (the people's logs and bodies brought), and s2, which the
/// chain never named, joined to the workspace by its token alone: its home another, no lock of the workspace pinned.
function setUp(o: { protect?: boolean; pinned?: Entry[] } = {}) {
  const w = world();
  handover(w);
  if (o.protect) w.alice.say("station", { key: w.stations[2]!.hex }, w.ws);
  const s0 = station(w, 0);
  for (const l of [w.alice, w.bob, w.carol]) bring(s0, l);
  const data = mkdtempSync(join(tmpdir(), "lock-moved-pin-"));
  writeState(data, {
    origin: "https://app.still.fail", station: w.stations[2]!.hex, workspace: WS2, workspace_name: "Other", name: "s2", relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: [{ id: w.stations[2]!.hex }], revocations: [],
    joined: [{ workspace: WS, workspace_name: "Team", name: "s2", peers: w.stations.map((s) => ({ id: s.hex })), revocations: [], locked: true }],
  });
  const s2 = new Cloud(data, false);
  if (o.pinned) s2.takeLock(o.pinned, WS);
  // (s2 asking s0 over the mesh, as a station of the workspace: what s0 answers it, `answerLock` with s2 as the peer)
  const asked: string[] = [];
  const call = async (_peer: string, ws: string | null, request: any) => {
    asked.push(String(request?.method));
    return answerLock(s0, request, ws, w.stations[2]!.hex) as any;
  };
  /// The plane bringing s2 the workspace's chain, as its `lock` frame does.
  const plane = (entries: Entry[]) => applyState(s2, JSON.stringify({ type: "lock", workspace: WS, entries }));
  return { w, s0, s2, call, asked, plane, me: w.stations[2]!.hex, peers: [w.stations[0]!.hex] };
}

test("protected after the move: the plane's moved chain offered, not pinned; pinned once s0 gives what makes a state naming it, with the logs and bodies", async () => {
  const t = setUp({ protect: true });
  assert.equal(t.s2.leftOut(WS), "unpinned");
  t.plane([t.w.first, t.w.moved]);
  assert.equal(t.s2.chain(WS), null, "the plane's word pins nothing");
  assert.ok(t.s2.movedOffered?.has(WS) === true, "offered");
  assert.equal(await pinMoved(t.s2, t.call, WS, t.peers, t.me), true);
  assert.equal(t.s2.chain(WS)?.state?.head, entryHash(t.w.moved), "the chain pinned");
  assert.ok(t.s2.locked(WS)?.state?.stations.has(t.me), "its state in force names this station");
  assert.equal(t.s2.leftOut(WS), null, "in the workspace by its lock");
  assert.equal(t.s2.movedOffered?.has(WS) === true, false, "the offer let go");
});

test("not protected (no statement names it): s0 gives it no body, the state made names it not, nothing pinned", async () => {
  const t = setUp();
  t.plane([t.w.first, t.w.moved]);
  assert.equal(await pinMoved(t.s2, t.call, WS, t.peers, t.me), false);
  assert.equal(t.s2.chain(WS), null, "nothing pinned");
  assert.equal(t.s2.leftOut(WS), "unpinned", "as it was");
  assert.ok(t.asked.includes("lock.bodies.kept"), "it asked");
});

test("a chain from the plane that did not move: nothing offered (pinned only where it names this station, as before)", async () => {
  const t = setUp({ protect: true });
  t.plane([t.w.first]);
  assert.equal(t.s2.movedOffered?.has(WS) === true, false, "not offered");
  assert.equal(await pinMoved(t.s2, t.call, WS, t.peers, t.me), false);
  assert.equal(t.s2.chain(WS), null);
});

test("a station that pins a lock of the workspace already: nothing offered replaces it, whatever the state would say", async () => {
  const w0 = world();
  const t = setUp({ protect: true, pinned: [w0.first] });
  const before = t.s2.chain(WS)?.state?.head;
  t.s2.offerMoved(WS, [t.w.first, t.w.moved]);
  assert.equal(await pinMoved(t.s2, t.call, WS, t.peers, t.me), false);
  assert.equal(t.s2.chain(WS)?.state?.head, before, "the lock it pinned kept");
});

// What it pins and on whose word: only a state made of logs and bodies this station checks itself against the chain,
// naming its key by a statement of an owner's or an admin's log; the plane and the station asked only carry them.
// 2026-11-14, the lead's three cases (a made-up chain, a real one replayed, a statement of one who may not add stations).

test("a real moved chain replayed to a station it does not name (its statement names another key): nothing pinned", async () => {
  const t = setUp({ protect: true });
  const other = ed();
  const data = mkdtempSync(join(tmpdir(), "lock-moved-pin-other-"));
  writeState(data, {
    origin: "https://app.still.fail", station: other.hex, workspace: WS2, workspace_name: "Other", name: "s3", relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: [{ id: other.hex }], revocations: [],
    joined: [{ workspace: WS, workspace_name: "Team", name: "s3", peers: t.w.stations.map((s) => ({ id: s.hex })), revocations: [], locked: true }],
  });
  const s3 = new Cloud(data, false);
  applyState(s3, JSON.stringify({ type: "lock", workspace: WS, entries: [t.w.first, t.w.moved] }));
  const call = async (_peer: string, ws: string | null, request: any) => answerLock(t.s0, request, ws, other.hex) as any;
  assert.equal(await pinMoved(s3, call, WS, t.peers, other.hex), false);
  assert.equal(s3.chain(WS), null, "nothing pinned");
  assert.equal(s3.leftOut(WS), "unpinned", "as it was");
});

test("a statement naming it in the log of a member who may not add stations: nothing pinned", async () => {
  const w = world();
  handover(w);
  w.carol.say("station", { key: w.stations[2]!.hex }, w.ws);
  const t = setUp();
  // (the same world as setUp's but carol's statement in it: s0 given carol's log with it)
  const s0 = station(w, 0);
  for (const l of [w.alice, w.bob, w.carol]) bring(s0, l);
  t.s2.offerMoved(WS, [w.first, w.moved]);
  const call = async (_peer: string, ws: string | null, request: any) => answerLock(s0, request, ws, t.me) as any;
  assert.equal(await pinMoved(t.s2, call, WS, [w.stations[0]!.hex], w.stations[2]!.hex), false);
  assert.equal(t.s2.chain(WS), null, "nothing pinned");
});

// A station that pins no lock of a workspace it joined and that its enrollment named none of is unprotected: it lets in
// whoever the plane's credentials say, so its first pin is the plane's word either way (trust on first use), before a
// move (`takeFromPlane`, 2026-11-04) and after; what is never by the plane's word is a lock pinned, or named at
// enrollment, let go or replaced (lock.test.ts, as it is). So a chain the plane made up, naming this station, pins here
// after a move exactly where one before a move does: the unprotected station's first pin, not a hole of the move.
test("a made-up moved chain, its logs signed by keys of its own making, one naming the station: pinned exactly where a made-up chain before a move is", async () => {
  const before = setUp();
  const madeUp = world();
  const named = { ...(madeUp.first.body as any), stations: [{ key: before.me, name: "s2" }] };
  before.plane([signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body: named }, madeUp.alice.app.signer)]);
  const unmoved = before.s2.chain(WS) !== null;
  const t = setUp();
  const fake = world();
  handover(fake);
  fake.alice.say("station", { key: t.me }, fake.ws);
  const s0f = station(fake, 0);
  for (const l of [fake.alice, fake.bob, fake.carol]) bring(s0f, l);
  t.plane([fake.first, fake.moved]);
  const call = async (_peer: string, ws: string | null, request: any) => answerLock(s0f, request, ws, t.me) as any;
  const moved = await pinMoved(t.s2, call, WS, [fake.stations[0]!.hex], t.me);
  console.log(`made-up chain pinned: before a move ${unmoved}, after a move ${moved}`);
  assert.equal(moved, unmoved);
});

// Its home, enrolled by its token alone: the plane's chain pins nothing (lock.test.ts); before a move its first lock is
// what its owner's device brings it (POST /lock, `lockRoute`: the owner's credential, the chain naming that device an
// owner's, the app's 「保护」, `lock.joinStation`). After a move the same door, the chain brought with the logs and
// bodies, pinned only where the state they make lets that device in as an owner's and names this station.
function home(o: { protect?: "alice" | "carol" }) {
  const w = world();
  handover(w);
  if (o.protect !== undefined) w[o.protect].say("station", { key: w.stations[2]!.hex }, w.ws);
  const data = mkdtempSync(join(tmpdir(), "lock-moved-pin-home-"));
  writeState(data, {
    origin: "https://app.still.fail", station: w.stations[2]!.hex, workspace: WS, workspace_name: "Team", name: "s2", relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: w.stations.map((s) => ({ id: s.hex })), revocations: [],
  });
  const s2 = new Cloud(data, false);
  const logs = [w.alice, w.bob, w.carol].map((l) => l.entries);
  const bodies = [w.alice, w.bob, w.carol].flatMap((l) => [...l.bodies.values()]);
  const post = (sub: "alice" | "bob", role: string, said: unknown) => lockRoute(s2, "POST", [], Buffer.from(JSON.stringify(said)), viewerOf(sub, w[sub].app, role, WS) as never);
  return { w, s2, logs, bodies, post };
}

test("its home's, enrolled by its token alone: the moved chain its owner's device brings with the logs and bodies, pinned once their state names it; else nothing", async () => {
  const t = home({ protect: "alice" });
  const r = t.post("alice", "owner", { entries: [t.w.first, t.w.moved], logs: t.logs, bodies: t.bodies });
  assert.equal(r[0], 200, JSON.stringify(r[1]));
  assert.equal(t.s2.chain(null)?.state?.head, entryHash(t.w.moved), "the chain pinned");
  assert.ok(t.s2.locked()?.state?.stations.has(t.w.stations[2]!.hex), "its state in force names this station");
  const n = home({});
  const r2 = n.post("alice", "owner", { entries: [n.w.first, n.w.moved], logs: n.logs, bodies: n.bodies });
  console.log("not protected:", r2[0], JSON.stringify(r2[1]));
  assert.equal(r2[0], 403);
  assert.equal(n.s2.chain(null), null, "nothing pinned");
});

test("its home's: the same chain brought without the logs, by an admin, or naming it by a member's statement: nothing pinned", async () => {
  const t = home({ protect: "alice" });
  const bare = t.post("alice", "owner", { entries: [t.w.first, t.w.moved] });
  const admin = t.post("bob", "admin", { entries: [t.w.first, t.w.moved], logs: t.logs, bodies: t.bodies });
  const m = home({ protect: "carol" });
  const member = m.post("alice", "owner", { entries: [m.w.first, m.w.moved], logs: m.logs, bodies: m.bodies });
  for (const [what, r] of [["without the logs", bare], ["by an admin", admin], ["a member's statement", member]] as const) {
    console.log(`${what}:`, r[0], JSON.stringify(r[1]));
    assert.equal(r[0], 403, what);
  }
  assert.equal(t.s2.chain(null), null);
  assert.equal(m.s2.chain(null), null);
});

test("its home's, enrolled with a lock's hash: the plane's moved chain pinned only where it holds that entry, then its state read of the logs and bodies", async () => {
  for (const holds of [true, false]) {
    const t = home({ protect: "alice" });
    writeFileSync(pendingLockPath(t.s2.data), JSON.stringify({ hash: holds ? entryHash(t.w.first) : entryHash(world().first) }));
    applyState(t.s2, JSON.stringify({ type: "lock", entries: [t.w.first, t.w.moved] }));
    assert.equal(t.s2.chain(null) !== null, holds, holds ? "pinned" : "nothing pinned");
    if (!holds) continue;
    for (const l of [t.w.alice, t.w.bob, t.w.carol]) bring(t.s2, l);
    assert.ok(t.s2.locked()?.state?.stations.has(t.w.stations[2]!.hex), "its state read of the logs and bodies");
  }
});
