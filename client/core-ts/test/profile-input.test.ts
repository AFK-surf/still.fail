// A profile's change as the station takes it (ops.ts profileInput).
import assert from "node:assert/strict";
import { test } from "node:test";
import { profileInput } from "../src/ops.ts";

test("a_profiles_models_go_each_once_in_order_however_they_were_ticked", () => {
  assert.deepEqual(profileInput({ models: ["b", "a", "b", 3, "c"], name: "x" }), { models: ["a", "b", "c"], name: "x" });
  assert.deepEqual(profileInput({ name: "x" }), { name: "x" });
  assert.equal(profileInput(null), null);
});
