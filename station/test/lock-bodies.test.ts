// A station keeps the bodies of a workspace's statements (cloud/lock-bodies.ts): each taken only where an entry it keeps
// commits to it under the workspace's tag (rules/src/lock/body.mbt, the model's `bodyRefusal`), given only inside the
// workspace (the model's `admits`, `admitsBefore`, `bodiesFor`): to a device let in there and to a station its own state
// names, never to a station only the control plane names nor to another workspace's; the one a removal takes out is
// given that removal and its `prev` chain alone. Two stations come level in them whatever order they came in; a
// restart keeps them.
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { Cloud, personChainsOf } from "../src/cloud/state.ts";
import { BODY_MOST } from "../src/cloud/lock-bodies.ts";
import { bodyHash, wsTag } from "../src/cloud/lock.ts";
import { wall } from "../src/ops/fibers.ts";
import { answerLock } from "../src/mesh/lock-sync.ts";
import { bodiesSyncWith } from "../src/mesh/person-sync.ts";
import { lockPartRoute } from "../src/mesh/serve.ts";
import { WS, WS2, bring, handover, station, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);
const SALT = "ab".repeat(16);

test("a body is taken only for its commitment: each of the rules' refusals", () => {
  const w = world();
  const said = handover(w);
  const c = station(w);
  personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  const why = (b: unknown) => c.takeBodies(null, [b]).refused[0]?.why ?? null;
  // another workspace's
  assert.equal(why({ ...said.open.body, ws: WS2 }), "it names no workspace this keeper keeps");
  // no entry kept commits to it (changed after it was committed)
  assert.equal(why({ ...said.bob.body, role: "owner" }), "no entry it keeps commits to it");
  // committed under another workspace's tag in that log
  const other = { ...said.bob.body, salt: SALT };
  w.alice.add("ws", { t: wsTag(WS2, w.alice.genesis), h: bodyHash(other) });
  // a shape no statement has, and a `prev` that is no statement before it in that log
  const boss = { ...said.carol.body, role: "boss", salt: SALT };
  w.alice.add("ws", { t: wsTag(WS, w.alice.genesis), h: bodyHash(boss) });
  const astray = { ...said.carol.body, prev: "cd".repeat(32), salt: SALT };
  w.alice.add("ws", { t: wsTag(WS, w.alice.genesis), h: bodyHash(astray) });
  personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  assert.equal(why(other), "its entry's tag is not its workspace's in that log");
  assert.match(why(boss) ?? "", /^its shape: /);
  assert.equal(why(astray), "its prev is not a statement before it in that log");
  assert.equal(why({ ...said.open.body, padding: "x".repeat(BODY_MOST) }), "a body this long is no statement");
  assert.equal(c.bodies(null).all().size, 0, "none of them kept");
  // and those committed to: taken, once
  assert.deepEqual(c.takeBodies(null, [...w.alice.bodies.values()]), { taken: 5, refused: [] });
  assert.deepEqual(c.takeBodies(null, [...w.alice.bodies.values()]), { taken: 0, refused: [] });
});

test("bodies are given to a member's device let in and to a station of the state; not to one only the control plane names, nor to another workspace's", () => {
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const kept = c.bodies(null).all().size;
  assert.equal(kept, 5);
  const get = (v: any) => (lockPartRoute(c, "bodies", "GET", Buffer.alloc(0), v) as any)[1].bodies.length;
  assert.equal(get(viewerOf("carol", w.carol.app)), kept);
  // a device asking in another workspace this station keeps no lock in: none
  assert.equal(get(viewerOf("carol", w.carol.app, "member", WS2)), 0);
  // a station of the state: all; the third, which the control plane lists and the state does not: none
  const kept1 = answerLock(c, { method: "lock.bodies.kept" }, WS, w.stations[1]!.hex) as any;
  assert.equal(kept1.hashes.length, kept);
  const all = [...c.bodies(null).all().keys()];
  assert.deepEqual(answerLock(c, { method: "lock.bodies.kept" }, WS, w.stations[2]!.hex), { hashes: [] });
  assert.deepEqual(answerLock(c, { method: "lock.bodies.get", hashes: all }, WS, w.stations[2]!.hex), { bodies: [] });
  assert.equal((answerLock(c, { method: "lock.bodies.get", hashes: all }, WS, w.stations[1]!.hex) as any).bodies.length, kept);
  // none said: none given
  assert.deepEqual(answerLock(c, { method: "lock.bodies.kept" }, WS), { hashes: [] });
});

test("the station a removal takes out is given that removal and its prev chain alone", () => {
  const w = world();
  const said = handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.ok(c.locked()!.state!.stations.has(w.stations[1]!.hex));
  // bob, an admin, admits dan, then takes s1 out
  const dan = w.bob.say("member", { sub: "dan", email: "dan@x", lock: "ef".repeat(32), role: "member" });
  const out = w.bob.say("station.remove", { key: w.stations[1]!.hex, cancels: [said.s1.h] });
  bring(c, w.bob);
  assert.equal(c.locked()!.state!.stations.has(w.stations[1]!.hex), false);
  const given = (answerLock(c, { method: "lock.bodies.kept" }, WS, w.stations[1]!.hex) as any).hashes.sort();
  assert.deepEqual(given, [dan.h, out.h].sort(), "the removal and the statement its prev names");
  const got = answerLock(c, { method: "lock.bodies.get", hashes: [...c.bodies(null).all().keys()] }, WS, w.stations[1]!.hex) as any;
  assert.deepEqual(got.bodies.map((b: unknown) => bodyHash(b)).sort(), [dan.h, out.h].sort());
});

test("two stations come level in bodies in any order of arrival, each giving only what its state lets it", async () => {
  for (const first of [0, 1]) {
    const w = world();
    handover(w);
    const dan = w.bob.say("member", { sub: "dan", email: "dan@x", lock: "ef".repeat(32), role: "member" });
    const s = [station(w, 0), station(w, 1)];
    for (const c of s) for (const l of [w.alice, w.bob, w.carol]) personChainsOf(c).keep(l.genesis, l.entries, WS);
    // s0 is given alice's bodies (in an order drawn by `first`), s1 two of them and bob's, which s0 lacks
    const bodies = [...w.alice.bodies.values()];
    s[0]!.takeBodies(null, first === 0 ? bodies : [...bodies].reverse());
    s[1]!.takeBodies(null, [dan.body, ...bodies.slice(3)]);
    assert.equal(s[1]!.waiting(), true, "s1 has no open in force yet");
    const keyOf = (c: Cloud) => c.state!.station;
    const call = (from: Cloud) => async (peer: string, ws: string | null, request: unknown) => answerLock(s.find((x) => keyOf(x) === peer)!, request, ws ?? WS, keyOf(from));
    const order = first === 0 ? [0, 1] : [1, 0];
    for (let round = 0; round < 2; round++) for (const i of order) await bodiesSyncWith(s[i]!, call(s[i]!), keyOf(s[1 - i]!), WS);
    const all = [...w.alice.bodies.keys(), dan.h].sort();
    for (const c of s) assert.deepEqual([...c.bodies(null).all().keys()].sort(), all);
    for (const c of s) assert.deepEqual([...c.locked()!.state!.members.keys()].sort(), ["alice", "bob", "carol", "dan"]);
  }
});

test("a restart keeps the bodies, and the state they make", () => {
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const again = new Cloud(c.data, false);
  assert.deepEqual([...again.bodies(null).all().keys()].sort(), [...c.bodies(null).all().keys()].sort());
  assert.deepEqual([...again.locked()!.state!.members.keys()].sort(), ["alice", "bob", "carol"]);
});
