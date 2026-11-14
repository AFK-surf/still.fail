// A device reads a moved workspace's logs and bodies by their heads (mesh/serve.ts: GET /lock/heads, POST /lock/given,
// `serves` `heads`): the read and the ask give exactly what the whole reads (GET /lock/logs, GET /lock/bodies) give, to
// the same askers under the same conditions (`givesDevice`, `Cloud.logsOf`), and nothing else. A core of a release under
// LOGS_ANY_FROM_BUILD (api/moved-from.ts) keeps no more than LOGS_BEFORE logs of a workspace, so it is told to update
// (`movedTooOld`, 426) where the state in force is made of more, and nowhere else.
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { LOGS_ANY_FROM_BUILD, LOGS_BEFORE, MOVED_FROM_BUILD, ROOT_OUT_FROM_BUILD } from "../src/api/moved-from.ts";
import { type Entry as StationEntry, bodyHash, entryHash } from "../src/cloud/lock.ts";
import { type Cloud, personChainsOf } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { lockPartRoute, lockRoute, movedFloor, movedTooOld } from "../src/mesh/serve.ts";
import { Log, WS, WS2, bring, ed, handover, signed, station, viewerOf, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);
const NONE = Buffer.alloc(0);
type Viewer = ReturnType<typeof viewerOf> | Omit<ReturnType<typeof viewerOf>, "lockDevice">;

const route = (c: Cloud, part: string, v: Viewer, body?: unknown) => lockPartRoute(c, part, body === undefined ? "GET" : "POST", body === undefined ? NONE : Buffer.from(JSON.stringify(body)), v as never) as [number, any];
const byGenesis = (chains: { genesis: string; entries: unknown[] }[]) => [...chains].sort((a, b) => (a.genesis < b.genesis ? -1 : 1));
const byHash = (bodies: unknown[]) => [...bodies].sort((a, b) => (bodyHash(a)! < bodyHash(b)! ? -1 : 1));

/// What the whole reads give `v`.
function whole(c: Cloud, v: Viewer) {
  const [s1, logs] = route(c, "logs", v);
  const [s2, bodies] = route(c, "bodies", v);
  assert.deepEqual([s1, s2], [200, 200]);
  return { logs: byGenesis(logs.chains), bodies: byHash(bodies.bodies), lacking: [...bodies.lacking].sort() };
}

/// What `v` reads by the heads and then asks for every one named (and `more`, named besides: given nothing for them).
function byHeads(c: Cloud, v: Viewer, more: { logs?: string[]; bodies?: string[] } = {}) {
  const [s1, heads] = route(c, "heads", v);
  assert.equal(s1, 200);
  const [s2, given] = route(c, "given", v, { logs: [...heads.logs.map((x: [string, string]) => x[0]), ...(more.logs ?? [])], bodies: [...heads.bodies, ...(more.bodies ?? [])] });
  assert.equal(s2, 200);
  // each head the hash of the last entry of that log as given
  const last = new Map((given.chains as { genesis: string; entries: StationEntry[] }[]).map((l) => [l.genesis, entryHash(l.entries.at(-1)!)]));
  for (const [g, h] of heads.logs as [string, string][]) assert.equal(h, last.get(g), "a head is its log's last entry's hash");
  assert.deepEqual([...heads.bodies].sort(), (given.bodies as unknown[]).map((b) => bodyHash(b)).sort(), "the bodies named are those given");
  return { logs: byGenesis(given.chains), bodies: byHash(given.bodies), lacking: [...heads.lacking].sort() };
}

const same = (c: Cloud, v: Viewer, what: string, more: { logs?: string[]; bodies?: string[] } = {}) => {
  const w = whole(c, v);
  assert.deepEqual(byHeads(c, v, more), w, `${what}: by the heads, what the whole reads give`);
  return w;
};

test("by the heads, a member's device, one taken out and one left out are given what the whole reads give them; another workspace's nothing; a log or body named that is not given is not", () => {
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  // a log of another workspace kept here, and a statement whose body is not kept here (lacking)
  const dan = new Log("dan");
  personChainsOf(c).keep(dan.genesis, dan.entries, WS2);
  const lost = w.alice.say("member", { sub: "erin", email: "erin@x", lock: dan.genesis, role: "member" });
  personChainsOf(c).keep(w.alice.genesis, w.alice.entries, WS);
  const stranger = { signer: ed(), base: ed() };
  const member = same(c, viewerOf("carol", w.carol.app), "carol's app", { logs: [dan.genesis, "ab".repeat(32)], bodies: ["cd".repeat(32)] });
  assert.ok(member.logs.length >= 3 && member.bodies.length === 5, "the logs and the bodies");
  assert.deepEqual(member.lacking, [lost.h], "lacking as GET /lock/bodies says it");
  same(c, viewerOf("carol", stranger), "a device the list does not name (left out: its connection refused, as the whole reads)");
  // carol taken out by alice
  w.alice.say("member.remove", { sub: "carol" });
  bring(c, w.alice);
  assert.equal(c.locked()!.state!.members.has("carol"), false, "carol out");
  same(c, viewerOf("carol", w.carol.app), "carol's app taken out");
  // another workspace's device: nothing by either
  const other = viewerOf("dan", dan.app, "member", WS2);
  assert.deepEqual(whole(c, other), { logs: [], bodies: [], lacking: [] });
  assert.deepEqual(byHeads(c, other, { logs: [w.alice.genesis], bodies: [...w.alice.bodies.keys()] }), { logs: [], bodies: [], lacking: [] }, "another workspace's device, naming them all: nothing");
});

test("while off, by the heads only to a device the list names, as the whole reads; none to one that brought no proof", () => {
  const w = world();
  handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  w.alice.say("off", {});
  bring(c, w.alice);
  assert.equal(c.locked(), null, "off");
  const named = same(c, viewerOf("carol", w.carol.app), "carol's app, named by the list");
  assert.ok(named.logs.length >= 3 && named.bodies.length > 0);
  const stranger = same(c, viewerOf("carol", { base: ed() }), "a device the list does not name");
  assert.deepEqual(stranger, { logs: [], bodies: [], lacking: [] });
  const { lockDevice: _, ...noProof } = viewerOf("carol", w.carol.app);
  assert.deepEqual(same(c, noProof, "no proof", { logs: [w.alice.genesis], bodies: [...w.alice.bodies.keys()] }), { logs: [], bodies: [], lacking: [] });
});

test("before the chain moved, by the heads the logs its `person` entries bind, as GET /lock/logs; none bound in another workspace", () => {
  const w = world();
  const bind = (prev: StationEntry, l: Log): StationEntry => signed({ v: 1, ws: WS, seq: prev.seq + 1, prev: entryHash(prev), at: 1000, kind: "person", body: { sub: l.sub, person: l.genesis } }, l.app.signer);
  const p1 = bind(w.first, w.bob), p2 = bind(p1, w.carol);
  const c = station(w, 0, false);
  c.takeLock([w.first, p1, p2]);
  for (const l of [w.bob, w.carol]) bring(c, l, false);
  const dan = new Log("dan");
  personChainsOf(c).keep(dan.genesis, dan.entries, WS2);
  const alice = same(c, viewerOf("alice", w.alice.app, "owner"), "alice's app", { logs: [dan.genesis] });
  assert.deepEqual(alice.logs.map((l) => l.genesis), [w.bob.genesis, w.carol.genesis].sort());
  assert.deepEqual(same(c, viewerOf("dan", dan.app, "member", WS2), "another workspace's device"), { logs: [], bodies: [], lacking: [] });
});

test("GET /lock says it serves `heads`", () => {
  const w = world();
  handover(w);
  const c = station(w);
  const [, said] = lockRoute(c, "GET", [], NONE, viewerOf("carol", w.carol.app) as never) as [number, { serves: string[] }];
  assert.ok(said.serves.includes("heads"));
});

// The floor (the highest that applies, `movedFloor`): a core under LOGS_ANY_FROM_BUILD is told to update only where the
// state in force is made of more than LOGS_BEFORE logs. Its tests' devices say a build from the constant itself.
test("a core under LOGS_ANY_FROM_BUILD is told to update where the state in force is made of more than LOGS_BEFORE logs, and not where of LOGS_BEFORE", () => {
  const w = world();
  handover(w);
  // members said by alice, each bound to a log of their own, the state then made of LOGS_BEFORE logs: alice's, bob's,
  // carol's and these
  const more = Array.from({ length: LOGS_BEFORE - 3 }, (_, i) => new Log(`p${i}`));
  for (const l of more) w.alice.say("member", { sub: l.sub, email: `${l.sub}@x`, lock: l.genesis, role: "member" });
  // (kept before the chain moves, so the state is made once, as the moved comes)
  const c = station(w, 0, false);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  for (const l of more) bring(c, l, false);
  c.takeLock([w.first, w.moved], null, true);
  assert.equal(c.needs(null).size, LOGS_BEFORE, "made of LOGS_BEFORE logs");
  const v = viewerOf("bob", w.bob.app, "admin") as never;
  assert.equal(movedFloor(c, WS), MOVED_FROM_BUILD, "LOGS_BEFORE logs: the move's floor");
  assert.equal(movedTooOld(c, v, Math.max(MOVED_FROM_BUILD, ROOT_OUT_FROM_BUILD)), false, "a core of before, from the other floors: not told");
  // one more member
  const last = new Log("plast");
  w.alice.say("member", { sub: last.sub, email: "plast@x", lock: last.genesis, role: "member" });
  bring(c, w.alice);
  bring(c, last, false);
  assert.equal(c.needs(null).size, LOGS_BEFORE + 1, "made of one more");
  assert.equal(movedFloor(c, WS), LOGS_ANY_FROM_BUILD, "the floor told: LOGS_ANY_FROM_BUILD");
  assert.equal(movedTooOld(c, v, LOGS_ANY_FROM_BUILD - 1), true, "a core under it: told to update");
  assert.equal(movedTooOld(c, v, LOGS_ANY_FROM_BUILD), false, "a core from it: not");
  assert.equal(movedTooOld(c, v, 0), false, "an unnumbered build (a development build's): not");
  assert.equal(movedTooOld(c, viewerOf("bob", w.bob.app, "admin", WS2) as never, LOGS_ANY_FROM_BUILD - 1), false, "another workspace of the station's: not");
});
