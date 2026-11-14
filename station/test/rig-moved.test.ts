// A rig (a station that only runs tasks) taken into a workspace whose chain moved comes up as its person's as in one
// whose chain did not: it pins the chain by the hash its enrollment named (`enroll --rig … --lock <hash>`, the only
// thing it trusts), and where that chain moved it waits for what its state is made of. Meanwhile it is asked, and
// answers, what its person signed for it (`rig.added`, `rig.proof`: mesh/peer.ts `heardWaiting`), which a station
// takes it in by (rigs/adds.ts); a station then gives it the logs and bodies as it gives a station its list names
// (cloud/state.ts `givenTo`, person-sync.ts `followPersons`), which it checks against the chain it pinned. 2026-11-14,
// the rigs' end to end run on a moved workspace (#6153 moved it by itself): vouched for, never reached, never known.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock, test } from "node:test";
import { entryHash } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, pendingLockPath, writeState } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { answerLock } from "../src/mesh/lock-sync.ts";
import { heardWaiting } from "../src/mesh/peer.ts";
import { bodiesGiven, bodiesSyncWith, personSyncWith } from "../src/mesh/person-sync.ts";
import { personChainsOf } from "../src/mesh/serve.ts";
import { WS, bring, ed, handover, station, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

/// The moved world, station s0 keeping it; a rig of alice's enrolled with the hash of the chain's genesis (its pending
/// lock), the plane having brought it the chain as it moved.
function setUp() {
  const w = world();
  handover(w);
  const s0 = station(w, 0);
  for (const l of [w.alice, w.bob, w.carol]) bring(s0, l);
  const rig = ed();
  const data = mkdtempSync(join(tmpdir(), "rig-moved-"));
  writeState(data, {
    origin: "https://app.still.fail", station: rig.hex, workspace: WS, workspace_name: "Team", name: "build-box", relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: w.stations.map((s) => ({ id: s.hex })), revocations: [],
    rig: { owner: "alice", owner_email: "alice@x", owner_name: "alice", person: w.alice.genesis },
  });
  writeFileSync(pendingLockPath(data), JSON.stringify({ hash: entryHash(w.first) }));
  const r = new Cloud(data, false);
  applyState(r, JSON.stringify({ type: "lock", entries: [w.first, w.moved] }));
  // (s0 lists it as a rig of the workspace, signed for or not as `vouched` says)
  const listed = { id: rig.hex, name: "build-box", owner: "alice", owner_email: "alice@x", owner_name: "alice" };
  s0.update((st) => void (st.rigs = [listed]));
  return { w, s0, r, rig, listed };
}

test("a rig whose pinned chain moved, waiting for its state: answers a station what its person signed for it, and the lock's own, nothing else", () => {
  const t = setUp();
  assert.equal(t.r.chain(null)?.state?.head, entryHash(t.w.moved), "the chain pinned by its enrollment's hash");
  assert.equal(t.r.waiting(null), true, "waiting for the logs");
  const heard = ["rig.added", "rig.proof", "lock.person.offer", "lock.bodies.offer", "remote.start", "rig.grant"].map((m) => `${m} ${heardWaiting(t.r, m)}`);
  console.log(heard.join(", "));
  assert.deepEqual(heard, ["rig.added true", "rig.proof true", "lock.person.offer true", "lock.bodies.offer true", "remote.start false", "rig.grant false"]);
  // (a whole station waiting is asked the lock's own alone, as before)
  assert.equal(heardWaiting(t.s0, "rig.proof"), false);
});

test("a station gives a rig its person signed for every body, as a station its list names; one not signed for, none", () => {
  const t = setUp();
  t.s0.rigVouched = () => false;
  assert.equal(bodiesGiven(t.s0, WS, t.rig.hex).size, 0, "not signed for: none");
  t.s0.rigVouched = () => true;
  assert.equal(bodiesGiven(t.s0, WS, t.rig.hex).size, t.s0.bodies(null).all().size, "signed for: all");
  assert.ok(t.s0.bodies(null).all().size > 0);
});

test("turned off, a key the control plane names a rig is given no body unless its person signed for it", () => {
  const t = setUp();
  t.w.alice.say("off", {});
  bring(t.s0, t.w.alice);
  assert.equal(t.s0.locked(), null, "off");
  t.s0.rigVouched = () => false;
  const none = bodiesGiven(t.s0, WS, t.rig.hex).size;
  console.log(`off, not signed for: ${none} of ${t.s0.bodies(null).all().size}`);
  assert.equal(none, 0, "not signed for: none");
  t.s0.rigVouched = () => true;
  assert.equal(bodiesGiven(t.s0, WS, t.rig.hex).size, t.s0.bodies(null).all().size, "signed for: all, off too");
});

test("the rig brought level by the station: the logs and bodies taken against the chain it pinned, its state in force made, no longer waiting", async () => {
  const t = setUp();
  t.s0.rigVouched = () => true;
  const call = async (_peer: string, ws: string | null, request: any) => answerLock(t.r, request, ws, t.w.stations[0]!.hex) as any;
  await personSyncWith(personChainsOf(t.s0), call, t.rig.hex, WS);
  await bodiesSyncWith(t.s0, call, t.rig.hex, WS);
  const l = t.r.locked();
  console.log(`rig: waiting ${t.r.waiting(null)}, bodies ${t.r.bodies(null).all().size}/${t.s0.bodies(null).all().size}, stations ${[...(l?.state?.stations.keys() ?? [])].map((k) => k.slice(0, 8)).join(" ")}`);
  assert.equal(t.r.waiting(null), false);
  assert.equal(t.r.bodies(null).all().size, t.s0.bodies(null).all().size, "every body the station keeps");
  assert.ok(l?.state?.stations.has(t.w.stations[0]!.hex), "s0 a station of its state, so it may send it tasks");
  assert.ok(l?.state?.members.get("alice")?.role === "owner");
});
