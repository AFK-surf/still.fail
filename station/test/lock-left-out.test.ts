// A device a moved workspace's list does not name, refused at a station's hello (serve.ts `refusalOf`'s `left`): told
// it is left out and whom to ask (`approvers`), the base ids of the app devices that may let it in and nothing else of
// the list: its person's own where the list names them (the log that binds them), else the owners' and admins'. No
// log, no body, no member's name; a station waiting for the root's log names nobody, so it tells nobody "left out"; a
// device the list names is never given approvers (2026-11-14: such a device was a dead end on real stations).
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { LockRefusal, endpointBytes } from "../src/cloud/lock.ts";
import { wall } from "../src/ops/fibers.ts";
import { refusalOf } from "../src/mesh/serve.ts";
import { WS, bring, dev, ed, handover, station, world } from "./lock-moved-world.ts";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

/// A hello of `d` on endpoint `endpoint`: its base key's proof of the endpoint, as a device's hello carries it.
const helloOf = (d: { base: any }, endpoint: string) => ({ lock: { device: d.base.hex, proof: d.base.sign(endpointBytes(WS, endpoint)) } });
type Refusal = { left?: { approvers: string[] }; out?: unknown; [k: string]: unknown };
const refuse = (c: ReturnType<typeof station>, d: { base: any }, sub: string): Refusal => {
  const endpoint = ed().hex;
  return refusalOf(c, helloOf(d, endpoint), endpoint, new LockRefusal("refused"), undefined, sub) as Refusal;
};

/// The workspace moved, alice's statements and bob's naming dan (a member after the move: dan@x is said in a body
/// alone) given to station 0. erin is no member.
function setUp() {
  const w = world();
  handover(w);
  w.bob.say("member", { sub: "dan", email: "dan@x", lock: ed().hex, role: "member" });
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  assert.equal(c.locked()?.waiting, undefined, "the state in force here");
  return { w, c };
}

/// Nothing of the workspace but the chain (the old one's, every member's to read) and whom to ask.
function holdsNothingElse(r: Refusal) {
  assert.deepEqual(Object.keys(r).filter((k) => !["error", "code", "lock", "entries", "person", "left"].includes(k)), [], "no other field");
  assert.equal(r.out, undefined, "nothing of a removal");
  assert.equal(JSON.stringify(r).includes("dan@x"), false, "no member's name the list says");
  assert.deepEqual(Object.keys(r.left ?? {}), ["approvers"], "only whom to ask");
}

test("a new device of a member the list names: told left out, its person's own app devices to ask, nothing else", () => {
  const { w, c } = setUp();
  const r = refuse(c, dev(), "carol");
  assert.deepEqual(r.left, { approvers: [w.carol.app.base.hex] }, "carol's app alone");
  holdsNothingElse(r);
});

test("a device of someone the list does not name: told left out, the owners' and admins' app devices to ask, nothing else", () => {
  const { w, c } = setUp();
  const r = refuse(c, dev(), "erin");
  assert.deepEqual(new Set(r.left?.approvers), new Set([w.alice.app.base.hex, w.bob.app.base.hex]), "alice's and bob's apps, not carol's");
  assert.equal(r.left?.approvers.length, 2);
  holdsNothingElse(r);
});

test("a station waiting for the root's log tells nobody left out", () => {
  const w = world();
  handover(w);
  const c = station(w);
  bring(c, w.bob);
  assert.equal(c.locked()?.waiting, true, "waiting");
  for (const sub of ["carol", "erin"]) assert.equal(refuse(c, dev(), sub).left, undefined, sub);
});

test("a device the list names is not given approvers", () => {
  const { w, c } = setUp();
  assert.equal(refuse(c, w.carol.app, "carol").left, undefined, "carol's app");
  assert.equal(refuse(c, w.bob.app, "bob").left, undefined, "bob's app");
});

test("no lock moved: nobody told left out", () => {
  const w = world();
  const c = station(w, 0, false);
  assert.equal(refuse(c, dev(), "erin").left, undefined);
});
