// Where a workspace's chain moved to its people's own logs (`moved {root}`, station/test/lock-roster4-model.ts D5,
// reading B), the station's state in force is the one the rules work out of the root's log, the logs the statements
// bind and the bodies kept, by this station's clock (cloud/state.ts `locked`): members and roles, each bound log's
// app devices, web devices until their `exp`, stations, settings; admission goes by it; off is a state and a later
// `open` puts it on again; a statement whose body is not here is not in force and is said lacking; without the root's
// log or its `open` nobody is let in; the chain changing branch to one without `moved` makes the folded chain the
// state again. What reads the chain itself (its seq, head) still reads the chain's.
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { LockRefusal, entryHash, fold } from "../src/cloud/lock.ts";
import { NOT_GIVEN, personChainsOf } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { inLock, inLockBringing, lockHead, lockPartRoute, stillIn } from "../src/mesh/serve.ts";
import { Log, WS, bring, dev, ed, handover, signed, station, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
let clock = NOW;
mock.method(wall, "now", () => clock * 1000);

const as = (sub: string, d: { signer: any; base: any }, role = "member") => ({ viewer: viewerOf(sub, d, role), exp: NOW + 10 * 86400, iat: NOW, sid: "s" });
const roles = (s: any) => [...s.members].map(([sub, m]: [string, any]) => `${sub} ${m.role} ${m.email}`).sort();

test("a chain with moved: the state is the people's logs', its seq and head the chain's", () => {
  clock = NOW;
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const s = c.locked()!.state!;
  assert.deepEqual(roles(s), ["alice owner alice@x", "bob admin bob@x", "carol member carol@x"]);
  assert.deepEqual(new Map(s.persons), new Map([["alice", w.alice.genesis], ["bob", w.bob.genesis], ["carol", w.carol.genesis]]));
  assert.deepEqual([...s.devices.keys()].sort(), [w.alice, w.bob, w.carol].map((l) => l.app.base.hex).sort());
  assert.deepEqual([...s.stations.keys()].sort(), [w.stations[0]!.hex, w.stations[1]!.hex].sort());
  assert.deepEqual([s.origins, s.rp_id], [w.settings.origins, w.settings.rp_id]);
  assert.equal(c.locked()!.waiting, undefined);
  // (the chain's own: what the sync and the cloud's copy read)
  assert.deepEqual(lockHead(c), { seq: 1, hash: entryHash(w.moved), genesis: entryHash(w.first) });
  assert.equal(c.chain()!.state!.moved, w.alice.genesis);
  // What the old chain said is gone from it: its third station, its own list
  assert.equal(c.locked()!.state!.stations.has(w.stations[2]!.hex), false);
});

test("web devices count by this station's clock: in until their exp, out after it", () => {
  clock = NOW;
  const w = world();
  handover(w);
  const web = ed();
  w.carol.add("web", { id: web.hex, label: "browser", exp: NOW + 86400 }, w.carol.app.key, NOW);
  // (one dated ahead of this station's clock by more than ten minutes does not count yet)
  const later = ed();
  w.carol.add("web", { id: later.hex, label: "later", exp: NOW + 7200 + 86400 }, w.carol.app.key, NOW + 7200);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const webs = () => [...c.locked()!.state!.devices.values()].filter((d) => d.kind === "web").map((d) => d.id).sort();
  assert.deepEqual(webs(), [web.hex]);
  clock = NOW + 7200 - 600;
  assert.deepEqual(webs(), [web.hex, later.hex].sort());
  clock = NOW + 86400;
  assert.deepEqual(webs(), [later.hex]);
  clock = NOW + 7200 + 86400;
  assert.deepEqual(webs(), []);
  clock = NOW;
});

test("admission goes by it: a member's app in; a device taken off its log out at once; a member a removal takes out out", () => {
  clock = NOW;
  const w = world();
  const said = handover(w);
  const c = station(w);
  const phone = dev();
  w.carol.add("device", { key: phone.key.id, id: phone.base.hex, label: "phone", sign_key: phone.signer.id });
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const carol = as("carol", w.carol.app);
  assert.equal(inLock(c, carol, "member", carol.viewer.device).viewer.role, "member");
  const p = as("carol", phone);
  const inP = inLock(c, p, "member", p.viewer.device);
  assert.equal(inP.viewer.role, "member");
  // carol takes her phone off her own log: out at once
  w.carol.add("device.remove", { key: phone.key.id });
  bring(c, w.carol, false);
  assert.throws(() => stillIn(c, inP, "member", p.viewer.device), LockRefusal);
  // bob (an admin) takes carol out
  w.bob.say("member.remove", { sub: "carol", cancels: [said.carol.h] });
  bring(c, w.bob);
  assert.equal(c.locked()!.state!.members.has("carol"), false);
  assert.throws(() => stillIn(c, carol, "member", carol.viewer.device), LockRefusal);
  // the bob of the old chain's own device is in still, an admin
  const bob = as("bob", w.bob.app, "admin");
  assert.equal(inLock(c, bob, "admin", bob.viewer.device).viewer.role, "admin");
});

test("a member a statement lets in whose log this station never heard: in, with their log brought at the hello", () => {
  clock = NOW;
  const w = world();
  handover(w);
  const dan = new Log("dan");
  w.alice.say("member", { sub: "dan", email: "dan@x", lock: dan.genesis, role: "member" });
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.equal(c.locked()!.state!.members.get("dan")?.role, "member");
  const d = as("dan", dan.app);
  assert.throws(() => inLock(c, d, "member", d.viewer.device), LockRefusal);
  const inD = inLockBringing(c, d, "member", d.viewer.device, { lock: { person: dan.entries } });
  assert.equal(inD.viewer.role, "member");
  assert.ok(personChainsOf(c).heardIn(WS).some(([g]) => g === dan.genesis), "the log a statement binds counts as heard there");
});

test("off is a state: the lock answers as one turned off, nothing let go, and a later open puts it on again", () => {
  clock = NOW;
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  w.alice.say("off", {});
  bring(c, w.alice);
  assert.equal(c.locked(), null);
  assert.notEqual(c.chain(), null, "its chain is kept");
  const kept = c.bodies(null).all().size;
  w.alice.say("open", { ...w.settings, email: "alice@x" });
  bring(c, w.alice);
  assert.ok(c.bodies(null).all().size > kept);
  assert.deepEqual(roles(c.locked()!.state!), ["alice owner alice@x", "bob admin bob@x", "carol member carol@x"]);
  // an admin's `off` is no one's: only the root's
  w.bob.say("off", {});
  bring(c, w.bob);
  assert.notEqual(c.locked(), null);
});

test("a body lacking: its statement not in force, said lacking, in force once brought", () => {
  clock = NOW;
  const w = world();
  const said = handover(w);
  const c = station(w);
  personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  for (const l of [w.bob, w.carol]) bring(c, l);
  c.takeBodies(null, [...w.alice.bodies.values()].filter((b) => b.kind !== "member" || b.sub !== "carol"));
  assert.equal(c.locked()!.state!.members.has("carol"), false);
  // (and what came after it in alice's log stands on it: not in force either, `prev`)
  assert.equal(c.locked()!.state!.stations.size, 0);
  assert.deepEqual(c.lacking(null), [said.carol.h]);
  const v = as("alice", w.alice.app, "owner");
  assert.deepEqual((lockPartRoute(c, "bodies", "GET", Buffer.alloc(0), v.viewer) as any)[1].lacking, [said.carol.h]);
  c.takeBodies(null, [said.carol.body]);
  assert.equal(c.locked()!.state!.members.get("carol")?.role, "member");
  assert.equal(c.locked()!.state!.stations.size, 2);
  assert.deepEqual(c.lacking(null), []);
});

test("without the root's log, or its open, nobody is let in, never by the folded chain; the next device that brings them mends it", () => {
  clock = NOW;
  const w = world();
  handover(w);
  const c = station(w);
  bring(c, w.bob);
  assert.equal(c.locked()!.waiting, true);
  assert.equal(c.locked()!.state!.members.size, 0);
  const bob = as("bob", w.bob.app, "admin");
  assert.throws(() => inLock(c, bob, "admin", bob.viewer.device), (e: unknown) => e instanceof LockRefusal && e.message === NOT_GIVEN);
  // no station is the workspace's but by the chain's, and those are asked only for the lock's own (mesh/peer.ts)
  assert.equal(c.waiting(), true);
  // alice's app brings her log and its bodies at its hello
  const a = as("alice", w.alice.app, "owner");
  const inA = inLockBringing(c, a, "owner", a.viewer.device, { lock: { person: w.alice.entries, bodies: [...w.alice.bodies.values()] } });
  assert.equal(inA.viewer.role, "owner");
  assert.equal(c.locked()!.waiting, undefined);
  assert.equal(inLock(c, bob, "admin", bob.viewer.device).viewer.role, "admin");
});

test("while it waits, a connection let in before is given no bodies and no logs; once on again, it is", () => {
  clock = NOW;
  const w = world();
  const said = handover(w);
  const c = station(w);
  for (const l of [w.bob, w.carol]) bring(c, l);
  // alice's log and every body of hers but the open: no open in force, so it waits
  personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  c.takeBodies(null, [...w.alice.bodies.values()].filter((b) => b.kind !== "open"));
  assert.equal(c.waiting(), true);
  assert.ok(c.bodies(null).all().size > 0);
  const v = as("alice", w.alice.app, "owner").viewer;
  const part = (p: string) => (lockPartRoute(c, p, "GET", Buffer.alloc(0), v) as any)[1];
  assert.deepEqual(part("bodies"), { bodies: [], lacking: [] }, "bodies to nobody while it waits");
  assert.deepEqual(part("logs"), { chains: [] }, "logs to nobody while it waits");
  c.takeBodies(null, [said.open.body]);
  assert.equal(c.waiting(), false);
  assert.equal(part("bodies").bodies.length, c.bodies(null).all().size);
  assert.equal(part("logs").chains.length, 3);
});

test("the chain changing branch to one without moved makes the folded chain the state again, and back", () => {
  clock = NOW;
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.equal(c.locked()!.state!.stations.size, 2);
  // An entry after the genesis that wins over the `moved` (the owner's removal of a device beats it at their parent):
  // the chain the fork choice gives has no `moved`.
  const removal = signed({ v: 1, ws: WS, seq: 1, prev: entryHash(w.first), at: 1000, kind: "device.remove", body: { id: w.carol.app.base.hex } }, w.alice.app.signer);
  c.takeLock([w.first, removal], null, true);
  assert.deepEqual(c.lockAfter(-1).map(entryHash), [entryHash(w.first), entryHash(removal)], "a removal beats the moved at their parent");
  assert.equal(c.locked()!.state!.moved, undefined);
  assert.equal(c.locked()!.state!.devices.has(w.carol.app.base.hex), false, "the folded chain's state");
  assert.equal(c.locked()!.state!.head, entryHash(removal));
  // and moved again after it: the people's state again
  const again = signed({ v: 1, ws: WS, seq: 2, prev: entryHash(removal), at: 1000, kind: "moved", body: { root: w.alice.genesis } }, w.alice.app.signer);
  c.takeLock([again], null, true);
  assert.equal(c.chain()!.state!.moved, w.alice.genesis);
  assert.equal(c.locked()!.state!.devices.has(w.carol.app.base.hex), true);
  assert.equal(c.locked()!.state!.stations.size, 2);
});
