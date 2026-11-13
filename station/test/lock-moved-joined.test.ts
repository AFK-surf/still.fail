// A workspace whose chain moved, turned off by its root (`off`), is off to every station that keeps its chain, a joined
// one too: whether it is in safe mode is what its root's log says, which the cloud never reads (it keeps the chain, whose
// last entry is `moved` for good, and keeps calling it locked). So a joined station goes by the chain it pinned, never
// by the plane's `locked` (cloud/state.ts `leftOut`): off, it takes the workspace's members as with no lock, asking
// the plane for nothing; on again, by the state in force. A station whose home is such a workspace takes a joined
// unlocked one's members while its home is off, and none while it is on (`home`); asked to join one, on the machine
// or over the mesh, it refuses before asking the plane while its home is on, and asks while it is off (cli.ts).
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { type Entry, LockRefusal, entryHash } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, type Joined, writeState } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { inLock } from "../src/mesh/serve.ts";
import { joinWorkspace } from "../src/cli.ts";
import { WS, WS2, type World, bring, dev, handover, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

const as = (sub: string, d: { base: any }, ws = WS) => ({ viewer: viewerOf(sub, d, "member", ws), exp: NOW + 10 * 86400, iat: NOW, sid: "s" });
const joinedTo = (w: World, ws: string, locked: boolean): Joined => ({ workspace: ws, workspace_name: ws, name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), revocations: [], ...(locked ? { locked: true as const } : {}) });

/// Station s0 of `w`, home in `home` and joined to `joined`; the moved chain pinned in `w.ws` (whichever of the two
/// that is); `homeLock`, a lock of its home's own pinned.
function stationIn(w: World, home: string, joined: Joined, homeLock: Entry[] | null = null): Cloud {
  const data = mkdtempSync(join(tmpdir(), "lock-moved-joined-"));
  writeState(data, {
    origin: "https://app.still.fail", station: w.stations[0]!.hex, workspace: home, workspace_name: home, name: "s0", relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: w.stations.map((s) => ({ id: s.hex })), revocations: [], joined: [joined],
  });
  const c = new Cloud(data, false);
  const ws = w.ws === home ? null : w.ws;
  c.takeLock([w.first], ws);
  c.takeLock([w.first, w.moved], ws, true);
  if (homeLock !== null) c.takeLock(homeLock);
  return c;
}

/// The plane's `state` frame as a cloud of today sends it after a handover: the moved workspace `locked` (its chain's
/// last entry is not `disable`), its head the chain's `moved`. What the station sends back.
function planeSays(c: Cloud, w: World, home: string): unknown[] {
  const sent: unknown[] = [];
  const lock = { seq: 1, hash: entryHash(w.moved), genesis: entryHash(w.first) };
  applyState(c, JSON.stringify({
    type: "state", workspace: home, workspace_name: home, name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), grant_keys: { keys: [] }, revocations: [], lock: null,
    workspaces: [{ ...joinedTo(w, w.ws, true), lock }],
  }), (f) => sent.push(f));
  return sent;
}

const inWs = (c: Cloud, ws: string) => c.memberships().some((m) => m.workspace === ws);

test("a joined station of a moved workspace turned off: in it, members let in as with no lock, nothing asked of the plane; on again, by the state in force", () => {
  const w = world();
  handover(w);
  const c = stationIn(w, WS2, joinedTo(w, WS, true));
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.equal(c.locked(WS)?.waiting, undefined, "the state in force");
  assert.equal(c.leftOut(WS), null, "on: in");
  w.alice.say("off", {});
  bring(c, w.alice);
  assert.equal(c.locked(WS), null, "off");
  assert.deepEqual(planeSays(c, w, WS2), [], "nothing asked of the plane");
  assert.equal(c.leftOut(WS), null, "off: not left out for the plane's `locked`");
  assert.ok(inWs(c, WS), "off: its members taken");
  const erin = as("erin", dev());
  assert.equal(inLock(c, erin, "member", erin.viewer.device).viewer.role, "member", "a member's device let in as with no lock");
  w.alice.say("open", { ...w.settings, email: "alice@x" });
  bring(c, w.alice);
  assert.deepEqual(planeSays(c, w, WS2), [], "nothing asked of the plane");
  assert.equal(c.leftOut(WS), null, "on again: in");
  assert.ok(inWs(c, WS));
  const carol = as("carol", w.carol.app);
  assert.equal(inLock(c, carol, "member", carol.viewer.device).viewer.role, "member", "a device the state names in");
  const again = as("erin", dev());
  assert.throws(() => inLock(c, again, "member", again.viewer.device), LockRefusal, "one it does not name out");
});

test("a joined station of a moved workspace turned off, its own home locked: left out as its home's (`home`), not `unpinned`", () => {
  const w = world();
  handover(w);
  const h = world(WS2);
  const c = stationIn(w, WS2, joinedTo(w, WS, true), [h.first]);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.notEqual(c.locked(), null, "its home locked");
  assert.equal(c.leftOut(WS), null, "on: in");
  w.alice.say("off", {});
  bring(c, w.alice);
  planeSays(c, w, WS2);
  assert.equal(c.leftOut(WS), "home");
  assert.equal(inWs(c, WS), false);
});

test("a station whose home is a moved workspace: a joined unlocked one's members none while on, taken while off, none on again", () => {
  const w = world();
  handover(w);
  const c = stationIn(w, WS, joinedTo(w, WS2, false));
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.notEqual(c.locked(), null, "on");
  assert.equal(c.leftOut(WS2), "home");
  w.alice.say("off", {});
  bring(c, w.alice);
  assert.equal(c.locked(), null, "off");
  assert.equal(c.leftOut(WS2), null);
  assert.ok(inWs(c, WS2));
  w.alice.say("open", { ...w.settings, email: "alice@x" });
  bring(c, w.alice);
  assert.equal(c.leftOut(WS2), "home");
  assert.equal(inWs(c, WS2), false);
});

test("joining from a home whose chain moved: refused before the plane is asked while it is on, asked while it is off", async () => {
  const w = world();
  handover(w);
  const c = stationIn(w, WS, joinedTo(w, WS2, false));
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const asked: string[] = [];
  const fetched = mock.method(globalThis, "fetch", async (url: string) => {
    asked.push(String(url));
    return new Response(JSON.stringify({ error: "enrollment_not_found" }), { status: 404 });
  });
  try {
    const LOCKED = /this station's workspace is locked/;
    // (on the machine, its files read there; over the mesh, the running station's state)
    for (const opts of [{ atMachine: true }, { cloud: c }]) await assert.rejects(joinWorkspace(c.data, "tok", undefined, opts), LOCKED, "on");
    assert.deepEqual(asked, [], "the plane not asked");
    w.alice.say("off", {});
    bring(c, w.alice);
    for (const opts of [{ atMachine: true }, { cloud: c }]) await assert.rejects(joinWorkspace(c.data, "tok", undefined, opts), (e: Error) => !LOCKED.test(e.message), "off: asked");
    assert.equal(asked.length, 2, "the plane asked, once each way");
  } finally {
    fetched.mock.restore();
  }
});
