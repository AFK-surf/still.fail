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
import { type Entry as StationEntry, bodyHash, entryHash, wsTag } from "../src/cloud/lock.ts";
import { wall } from "../src/ops/fibers.ts";
import { answerLock } from "../src/mesh/lock-sync.ts";
import { bodiesSyncWith } from "../src/mesh/person-sync.ts";
import { inLock, lockPartRoute } from "../src/mesh/serve.ts";
import { Log, WS, WS2, bring, ed, handover, signed, station, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);
const SALT = "ab".repeat(16);
const roles = (c: Cloud) => [...c.locked()!.state!.members].map(([sub, m]) => `${sub} ${m.role}`).sort();

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
    // (s1 holds no `open` of the root's yet: its state is the chain's as it moved, which still says the settings, the
    // members and the stations s0 and s1 (rules/src/lock/state4.mbt `state4_moved`), so it is in force; before the carry
    // it waited and gave nothing till s0's bodies brought it the `open`. Dan is not in it yet: the chain bound bob to no
    // log, so bob's log says nothing there till alice's `member bob` (from s0) binds it)
    assert.equal(s[1]!.waiting(), false, "s1 in force by the chain as it moved, no open of the root's yet");
    assert.deepEqual([...s[1]!.locked()!.state!.members.keys()].sort(), ["alice", "bob", "carol"], "dan not yet: bob's log not bound to him");
    // (each giving only what its state lets it: s1 gives s0, a station its state names, all it keeps; the third, which
    // only the control plane lists, nothing)
    const keeps1 = [...s[1]!.bodies(null).all().keys()].sort();
    assert.deepEqual((answerLock(s[1]!, { method: "lock.bodies.kept" }, WS, w.stations[0]!.hex) as any).hashes.sort(), keeps1);
    assert.deepEqual(answerLock(s[1]!, { method: "lock.bodies.kept" }, WS, w.stations[2]!.hex), { hashes: [] });
    const keyOf = (c: Cloud) => c.state!.station;
    const call = (from: Cloud) => async (peer: string, ws: string | null, request: unknown) => answerLock(s.find((x) => keyOf(x) === peer)!, request, ws ?? WS, keyOf(from));
    const order = first === 0 ? [0, 1] : [1, 0];
    for (let round = 0; round < 2; round++) for (const i of order) await bodiesSyncWith(s[i]!, call(s[i]!), keyOf(s[1 - i]!), WS);
    const all = [...w.alice.bodies.keys(), dan.h].sort();
    for (const c of s) assert.deepEqual([...c.bodies(null).all().keys()].sort(), all);
    for (const c of s) assert.deepEqual([...c.locked()!.state!.members.keys()].sort(), ["alice", "bob", "carol", "dan"]);
    for (const c of s) assert.deepEqual(answerLock(c, { method: "lock.bodies.kept" }, WS, w.stations[2]!.hex), { hashes: [] }, "the third given none, level");
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

test("bodies are given by the list on or off: the root's off reaching one station alone is brought to the other, then its open", async () => {
  const w = world();
  handover(w);
  const s = [station(w, 0), station(w, 1)];
  for (const c of s) for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const keyOf = (c: Cloud) => c.state!.station;
  const call = (from: Cloud) => async (peer: string, ws: string | null, request: unknown) => answerLock(s.find((x) => keyOf(x) === peer)!, request, ws ?? WS, keyOf(from));
  const level = async () => {
    for (let round = 0; round < 2; round++) for (const i of [0, 1]) await bodiesSyncWith(s[i]!, call(s[i]!), keyOf(s[1 - i]!), WS);
  };
  const off = w.alice.say("off", {});
  for (const c of s) personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  s[0]!.takeBodies(null, [off.body]);
  assert.equal(s[0]!.locked(), null);
  assert.notEqual(s[1]!.locked(), null, "s1 has not its body yet");
  // a station the control plane lists and the list does not: none, off
  assert.deepEqual(answerLock(s[0]!, { method: "lock.bodies.kept" }, WS, w.stations[2]!.hex), { hashes: [] });
  await level();
  assert.equal(s[1]!.locked(), null, "brought the off by s0, which is off");
  const open = w.alice.say("open", { ...w.settings, email: "alice@x" });
  for (const c of s) personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  s[1]!.takeBodies(null, [open.body]);
  await level();
  for (const c of s) assert.deepEqual(roles(c), ["alice owner", "bob admin", "carol member"]);
  assert.deepEqual(answerLock(s[0]!, { method: "lock.bodies.kept" }, WS, w.stations[2]!.hex), { hashes: [] });
});

test("while off, a device is given bodies and logs only where the list names that very device", () => {
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  w.alice.say("off", {});
  bring(c, w.alice);
  assert.equal(c.locked(), null);
  const get = (v: any) => (lockPartRoute(c, "bodies", "GET", Buffer.alloc(0), v) as any)[1].bodies.length;
  assert.equal(get(viewerOf("carol", w.carol.app)), c.bodies(null).all().size, "carol's app, named by the list");
  const stranger = { signer: ed(), base: ed() };
  assert.equal(get(viewerOf("carol", stranger)), 0, "a device the list does not name");
  const { lockDevice: _, ...noProof } = viewerOf("carol", w.carol.app);
  assert.equal(get(noProof), 0, "a connection that brought no proof of its base key");
  assert.equal((lockPartRoute(c, "logs", "GET", Buffer.alloc(0), viewerOf("carol", stranger)) as any)[1].chains.length, 0);
  assert.ok((lockPartRoute(c, "logs", "GET", Buffer.alloc(0), viewerOf("carol", w.carol.app)) as any)[1].chains.length >= 3);
});

test("before the chain moved, a station takes the statements' bodies of a handover, and they are the state in force as the moved comes", () => {
  const w = world();
  const said = handover(w);
  const c = station(w, 0, false);
  assert.equal(c.chain(null)?.state?.moved, undefined, "not moved");
  personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  assert.deepEqual(c.takeBodies(null, Object.values(said).map((s) => s.body)), { taken: 5, refused: [] });
  for (const l of [w.bob, w.carol]) bring(c, l);
  c.takeLock([w.first, w.moved], null, true);
  assert.deepEqual(roles(c), ["alice owner", "bob admin", "carol member"]);
});

test("of a chain not moved, /lock/logs gives the logs its `person` entries bind, kept here, to a device the chain lets in (one it does not name is not let in), none bound in another workspace", () => {
  const w = world();
  // bob and carol bind their logs on the chain (alice binds none); dan's log, of another workspace, kept here too
  const bind = (prev: StationEntry, l: Log): StationEntry => signed({ v: 1, ws: WS, seq: prev.seq + 1, prev: entryHash(prev), at: 1000, kind: "person", body: { sub: l.sub, person: l.genesis } }, l.app.signer);
  const p1 = bind(w.first, w.bob), p2 = bind(p1, w.carol);
  const c = station(w, 0, false);
  c.takeLock([w.first, p1, p2]);
  assert.equal(c.chain(null)?.state?.persons.size, 2, "two bound");
  for (const l of [w.bob, w.carol]) bring(c, l, false);
  const dan = new Log("dan");
  personChainsOf(c).keep(dan.genesis, dan.entries, WS2);
  const logs = (v: unknown) => ((lockPartRoute(c, "logs", "GET", Buffer.alloc(0), v as never) as any)[1].chains as { genesis: string }[]).map((x) => x.genesis).sort();
  assert.deepEqual(logs(viewerOf("alice", w.alice.app, "owner")), [w.bob.genesis, w.carol.genesis].sort(), "alice's app, named by the chain: the two bound logs");
  assert.deepEqual(logs(viewerOf("bob", w.bob.app, "admin")), [w.bob.genesis, w.carol.genesis].sort(), "bob's app, on his own log");
  // a device the chain does not name never reaches the route: its connection is refused (inLock, as each is let in
  // and again as the lock changes, stillIn)
  const stranger = viewerOf("alice", { base: ed() }, "owner");
  assert.throws(() => inLock(c, { viewer: stranger, exp: 4102444800, iat: 0, sid: "s" } as never, "owner", stranger.device), "a device the chain does not name is not let in");
  assert.deepEqual(logs(viewerOf("dan", dan.app, "member", WS2)), [], "a device of another workspace");
  // a bound log this station keeps none of is not given
  const c2 = station(w, 1, false);
  c2.takeLock([w.first, p1, p2]);
  bring(c2, w.bob, false);
  assert.deepEqual(((lockPartRoute(c2, "logs", "GET", Buffer.alloc(0), viewerOf("alice", w.alice.app, "owner") as never) as any)[1].chains as { genesis: string }[]).map((x) => x.genesis), [w.bob.genesis], "carol's log, not kept at s1: none");
});
