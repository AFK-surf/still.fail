// A workspace whose chain moved is made of the chain as it moved and its people's logs (cloud/state.ts `forceOf`, the
// rules' `state4_moved`): the chain never changes once it holds `moved`, so it is read once and kept (cloud/lock.ts
// `carriedOf`, by the kept lock's entries), and the state made again as a log grows or a statement comes steps none of
// its entries. Counted by the rules (`stepped_js`), not timed. 2026-11-15: a 1000-member chain was folded again at
// every making, four fifths of it (handover measurements).
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { wall } from "../src/ops/fibers.ts";
import { bring, dev, handover, station, world } from "./lock-moved-world.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

const NOW = 2_000_000;
mock.method(wall, "now", () => NOW * 1000);

/// The chain entries the rules step while `f` runs.
const stepping = (f: () => void): number => {
  const before: number = rules.stepped_js();
  f();
  return rules.stepped_js() - before;
};

test("the state made again as a log grows and as a statement comes steps none of the chain's entries", () => {
  const w = world();
  const said = handover(w);
  const c = station(w);
  for (const l of [w.alice, w.bob, w.carol]) bring(c, l);
  const first = stepping(() => c.locked());
  // bob's second device on his log
  const phone = dev();
  w.bob.add("device", { key: phone.key.id, id: phone.base.hex, label: "bob's phone", sign_key: phone.signer.id });
  const grown = stepping(() => {
    bring(c, w.bob);
    assert.ok(c.locked()!.state!.devices.has(phone.base.hex), "bob's phone in");
  });
  // alice takes carol out
  w.alice.say("member.remove", { sub: "carol", cancels: [said.carol.h] });
  const stated = stepping(() => {
    bring(c, w.alice);
    assert.equal(c.locked()!.state!.members.has("carol"), false, "carol out");
  });
  console.log(`chain entries stepped: the first making ${first}; again after a log grew ${grown}; after a statement ${stated}`);
  assert.equal(grown, 0, "a log grown: the chain stepped again");
  assert.equal(stated, 0, "a statement: the chain stepped again");
});
