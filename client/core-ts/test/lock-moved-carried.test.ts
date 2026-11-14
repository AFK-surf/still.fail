// The state in force of a moved workspace on a device (src/lock-moved.ts `inForce`, which views/lock.ts `inForceOf`
// makes as anything it is made of changes): the chain as it moved is read once for the chain held (the `lock`
// record's entries, the object the database's cache holds until it is written) and kept, so the state made again as a
// person's log grows or a statement comes steps none of its entries; a chain held anew (another array, or the same
// one grown) is read again. Counted by the rules (`stepped_js`), not timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { bring as _bring, dev, handover, world } from "../../../station/test/lock-moved-world.ts";
import type { Entry } from "../src/lock.ts";
import { inForce } from "../src/lock-moved.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";

void _bring;
const stepping = (f: () => void): number => {
  const before: number = rules.stepped_js();
  f();
  return rules.stepped_js() - before;
};

test("made again as a log grows and as a statement comes, the chain held steps none of its entries; another chain is read", () => {
  const w = world();
  const said = handover(w);
  const entries = [w.first, w.moved] as unknown as Entry[];
  const logs = () => new Map([w.alice, w.bob, w.carol].map((l) => [l.genesis, [...l.entries] as unknown as Entry[]]));
  const bodies = () => [...w.alice.bodies.values()];
  const made = (es: readonly Entry[]) => inForce(w.ws, es, logs(), bodies(), 2_000_000_000);
  const first = stepping(() => assert.equal(made(entries).said, "on"));
  const phone = dev();
  w.bob.add("device", { key: phone.key.id, id: phone.base.hex, label: "bob's phone", sign_key: phone.signer.id });
  const grown = stepping(() => assert.ok(made(entries).f.devices.has(phone.base.hex), "bob's phone in"));
  w.alice.say("member.remove", { sub: "carol", cancels: [said.carol.h] });
  const stated = stepping(() => assert.equal(made(entries).f.members.has("carol"), false, "carol out"));
  const other = stepping(() => made([...entries]));
  console.log(`chain entries stepped: the first making ${first}; again after a log grew ${grown}; after a statement ${stated}; a copy of the chain ${other}`);
  assert.equal(grown, 0, "a log grown: the chain stepped again");
  assert.equal(stated, 0, "a statement: the chain stepped again");
  assert.ok(other > 0, "another array is read anew");
  // (the same array pushed onto in place is not the chain it was: an entry after `moved` folds to nothing, so waiting)
  const held = [...entries];
  assert.equal(made(held).said, "on");
  held.push({ ...w.moved, seq: 2 } as unknown as Entry);
  assert.equal(made(held).said, "waiting", "an array grown in place is read again");
});
