// A station that keeps no lock of a workspace it joined (enrolled by its token alone) protected after that workspace's
// chain moved (「保护」: `station {key}` in an owner's log): the plane's chain, which never names it, is only offered
// (cloud/presence.ts `takeFromPlane`), and it pins it once the state the logs and bodies a station of the workspace
// gives make names its key (mesh/moved-pin.ts `pinMoved`); never by the plane's word alone, never over a lock it pins
// already, and a station of the lock gives it the bodies only once its list names it (person-sync.ts `bodiesGiven`).
// 2026-11-14, the locks' end to end, round 17 run moved: 「保护」 left the station unprotected for good.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { type Entry, entryHash } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { answerLock } from "../src/mesh/lock-sync.ts";
import { pinMoved } from "../src/mesh/moved-pin.ts";
import { WS, WS2, bring, handover, station, world } from "./lock-moved-world.ts";

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
  assert.ok(t.s2.movedOffered.has(WS), "offered");
  assert.equal(await pinMoved(t.s2, t.call, WS, t.peers, t.me), true);
  assert.equal(t.s2.chain(WS)?.state?.head, entryHash(t.w.moved), "the chain pinned");
  assert.ok(t.s2.locked(WS)?.state?.stations.has(t.me), "its state in force names this station");
  assert.equal(t.s2.leftOut(WS), null, "in the workspace by its lock");
  assert.equal(t.s2.movedOffered.has(WS), false, "the offer let go");
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
  assert.equal(t.s2.movedOffered.has(WS), false, "not offered");
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
