// After a move the root's person is a member like any other (the lead's, 2026-11-14): that they are in the list, bound
// by the root's log, is an implicit admit (`~root`, rules/src/lock/roster.mbt), which an owner's removal of them takes
// out where its `cancels` names the root's genesis hash; then an owner admits them again by a log begun anew, as any
// member whose every device was lost. The root's log stays what the workspace is rooted in: what its pair says counts
// as an owner's. Each case on the station's own code (`Cloud.locked`, the rules' `state4_moved`), alice the root's
// person (log R), bob an owner by her, carol an admin, dave a member.
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { Cloud } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { Log, bring, handover, station, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

function setUp() {
  const w = world();
  handover(w);
  w.alice.say("member", { sub: "bob", email: "bob@x", lock: w.bob.genesis, role: "owner" });
  w.alice.say("member", { sub: "carol", email: "carol@x", lock: w.carol.genesis, role: "admin" });
  const dave = new Log("dave");
  w.alice.say("member", { sub: "dave", email: "dave@x", lock: dave.genesis, role: "member" });
  const c = station(w, 0);
  for (const l of [w.alice, w.bob, w.carol, dave]) bring(c, l);
  return { w, c, dave };
}
/// What the state in force says of `sub`: their role, the log they are bound by, their email, their devices' ids.
const of = (c: Cloud, sub: string) => {
  const s = c.locked()?.state;
  if (!s) return "no state";
  const m = s.members.get(sub);
  const devices = [...s.devices.values()].filter((d) => d.sub === sub).map((d) => d.id).sort();
  return m === undefined ? { in: false, devices } : { in: true, role: m.role, lock: s.persons.get(sub) ?? "none", email: m.email, devices };
};
const appsOf = (...ls: Log[]) => ls.map((l) => l.app.base.hex).sort();

test("i. an owner's removal of the root's person naming the root's log: they are out, no device of theirs in the state; the owner stays one, what he and the root's log said before and after counts, the state on with its settings", () => {
  const { w, c } = setUp();
  const before = c.locked()!.state!;
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  bring(c, w.bob);
  assert.deepEqual(of(c, "alice"), { in: false, devices: [] });
  assert.equal((of(c, "bob") as any).role, "owner");
  // (after it: the root's log admits erin, bob admits frank; both count)
  const erin = new Log("erin"), frank = new Log("frank");
  w.alice.say("member", { sub: "erin", email: "erin@x", lock: erin.genesis, role: "member" });
  w.bob.say("member", { sub: "frank", email: "frank@x", lock: frank.genesis, role: "member" });
  for (const l of [w.alice, w.bob, erin, frank]) bring(c, l);
  assert.deepEqual([of(c, "erin"), of(c, "frank")].map((x: any) => x.role), ["member", "member"]);
  assert.deepEqual([of(c, "carol"), of(c, "dave")].map((x: any) => x.role), ["admin", "member"]);
  const s = c.locked()!.state!;
  assert.equal(s.disabled, false, "on");
  assert.deepEqual([s.origins, s.rp_id, s.cloud_keys], [before.origins, before.rp_id, before.cloud_keys], "the settings the same");
  assert.equal(s.genesis, w.alice.genesis, "still rooted in her log");
});

test("ii. then the owner's admit of the root's person by a log begun anew: bound by it, an owner, her devices its own, her email the admit's", () => {
  const { w, c } = setUp();
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  const again = new Log("alice");
  w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  for (const l of [w.bob, again]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: again.genesis, email: "alice@new", devices: appsOf(again) });
});

test("iii. the owner's admit of the root's person by another log with no removal binds nothing: she is bound by the root's log as before", () => {
  const { w, c } = setUp();
  const again = new Log("alice");
  w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  for (const l of [w.bob, again]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("iv. an admin's or a member's removal of the root's person naming the root's log does nothing", () => {
  const { w, c, dave } = setUp();
  w.carol.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  dave.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  for (const l of [w.carol, dave]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("v. a removal of the root's person whose `cancels` does not name the root's log (none, or other hashes) does nothing, as before", () => {
  const { w, c } = setUp();
  w.bob.say("member.remove", { sub: "alice", cancels: [] });
  const other = w.bob.say("member", { sub: "erin", email: "erin@x", lock: w.bob.genesis, role: "member" });
  w.bob.say("member.remove", { sub: "alice", cancels: [other.h, w.bob.genesis, w.moved.sig.sig.slice(0, 64)] });
  bring(c, w.bob);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("vi. the root's person's own removal of themselves, on the root's log naming it: out (the root's pair needs nothing)", () => {
  const { w, c } = setUp();
  w.alice.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  bring(c, w.alice);
  assert.deepEqual(of(c, "alice"), { in: false, devices: [] });
  assert.equal((of(c, "bob") as any).role, "owner");
});

test("vii. lost twice: after ii, the owner's removal naming that admit and his admit by a third log: bound by the third", () => {
  const { w, c } = setUp();
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  const r2 = new Log("alice"), r3 = new Log("alice");
  const ii = w.bob.say("member", { sub: "alice", email: "alice@new", lock: r2.genesis, role: "owner" });
  w.bob.say("member.remove", { sub: "alice", cancels: [ii.h] });
  w.bob.say("member", { sub: "alice", email: "alice@third", lock: r3.genesis, role: "owner" });
  for (const l of [w.bob, r2, r3]) bring(c, l);
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: r3.genesis, email: "alice@third", devices: appsOf(r3) });
});

test("viii. the owner's removal of the root's person naming the root's log and, on it, her removal of him: he is out, she in by the root's log", () => {
  const { w, c } = setUp();
  const bobs = [...w.alice.bodies.entries()].find(([, b]) => b.kind === "member" && b.sub === "bob" && b.role === "owner")![0];
  const first = [...w.alice.bodies.entries()].find(([, b]) => b.kind === "member" && b.sub === "bob")![0];
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  w.alice.say("member.remove", { sub: "bob", cancels: [first, bobs] });
  for (const l of [w.bob, w.alice]) bring(c, l);
  assert.deepEqual(of(c, "bob"), { in: false, devices: [] });
  assert.deepEqual(of(c, "alice"), { in: true, role: "owner", lock: w.alice.genesis, email: "alice@x", devices: appsOf(w.alice) });
});

test("ix. every order the logs come in gives the same list", () => {
  const w = world();
  handover(w);
  w.alice.say("member", { sub: "bob", email: "bob@x", lock: w.bob.genesis, role: "owner" });
  w.bob.say("member.remove", { sub: "alice", cancels: [w.alice.genesis] });
  const again = new Log("alice");
  w.bob.say("member", { sub: "alice", email: "alice@new", lock: again.genesis, role: "owner" });
  const orders = [[w.alice, w.bob, w.carol, again], [again, w.carol, w.bob, w.alice], [w.bob, again, w.alice, w.carol]];
  const said = orders.map((ls, i) => {
    const c = station(w, i % 2);
    for (const l of ls) bring(c, l);
    return JSON.stringify(["alice", "bob", "carol"].map((sub) => of(c, sub)));
  });
  assert.deepEqual(new Set(said).size, 1, said.join("\n"));
  assert.equal(JSON.parse(said[0]!)[0].lock, again.genesis);
});

