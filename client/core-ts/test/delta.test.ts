// The Rust core's delta.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply, diff, largerThan } from "../src/delta.ts";

function roundTrip(old: unknown, next: unknown) {
  const ops = diff(old, next);
  const patched = apply(structuredClone(old), ops);
  assert.deepEqual(patched, next, `ops ${JSON.stringify(ops)}`);
  return ops;
}

test("equal_values_need_no_ops", () => {
  assert.deepEqual(roundTrip({ a: [1, { b: null }] }, { a: [1, { b: null }] }), []);
});

test("a_grown_array_is_one_append", () => {
  const ops = roundTrip({ detail: { timeline: [1, 2], usage: { n: 1 } } }, { detail: { timeline: [1, 2, 3, 4], usage: { n: 1 } } });
  assert.deepEqual(ops, [{ path: ["detail", "timeline"], append: [3, 4] }]);
});

test("an_edited_item_is_one_set", () => {
  const ops = roundTrip({ items: [{ text: "a" }, { text: "b" }] }, { items: [{ text: "a" }, { text: "bc" }] });
  assert.deepEqual(ops, [{ path: ["items", 1, "text"], set: "bc" }]);
});

test("keys_are_added_and_removed", () => {
  const ops = roundTrip({ state: "offline", message: "断了" }, { state: "online", since: 5 });
  assert.equal(ops.length, 3);
  for (const op of [{ path: ["state"], set: "online" }, { path: ["since"], set: 5 }, { path: ["message"], remove: true }]) {
    assert.ok(ops.some((o) => JSON.stringify(o) === JSON.stringify(op)), JSON.stringify(ops));
  }
});

test("anything_else_is_set_whole", () => {
  assert.deepEqual(roundTrip({ a: [1, 2, 3] }, { a: [1, 2] }), [{ path: ["a"], set: [1, 2] }]);
  assert.deepEqual(roundTrip({ a: [1, 2] }, { a: [0, 1, 2] }), [{ path: ["a"], set: [0, 1, 2] }]);
  roundTrip({ a: { b: 1 } }, { a: [1] });
  assert.deepEqual(roundTrip([1], "x"), [{ path: [], set: "x" }]);
});

test("ops_parse_back", () => {
  const ops = diff({ a: [1], b: { c: 1 }, d: 0 }, { a: [1, 2], b: { c: 2 } });
  assert.deepEqual(JSON.parse(JSON.stringify(ops)), ops);
});

test("knows_when_ops_outgrow_the_value", () => {
  const small = { state: "online" };
  assert.ok(largerThan(diff({ state: "offline" }, small), small));
  const long = { timeline: Array.from({ length: 100 }, (_, i) => `message ${i}`) };
  const longer = { timeline: [...long.timeline, "one more"] };
  assert.ok(!largerThan(diff(long, longer), longer));
});
