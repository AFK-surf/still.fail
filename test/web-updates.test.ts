import { test } from "node:test";
import assert from "node:assert/strict";
import { WebUpdates } from "../web/src/core/webUpdates.ts";

const current = "a".repeat(40);
const newer = "b".repeat(40);
const next = "c".repeat(40);

test("detects deployed revision, dismisses only that release, and clears on rollback to current", async () => {
  let value: unknown = { revision: current, version: "0.1.100" };
  const updates = new WebUpdates(current, async () => value);
  await updates.check(0);
  assert.equal(updates.snapshot(), null);
  value = { revision: newer, version: "0.1.101" };
  await updates.check(60_000);
  assert.deepEqual(updates.snapshot(), value);
  updates.dismiss();
  await updates.check(120_000);
  assert.equal(updates.snapshot(), null);
  value = { revision: next, version: "0.1.101" }; // commit count alone is not an identity
  await updates.check(180_000);
  assert.deepEqual(updates.snapshot(), value);
  value = { revision: current, version: "0.1.100" };
  await updates.check(240_000);
  assert.equal(updates.snapshot(), null);
});

test("ignores unavailable/old metadata and retries; throttles repeated wakeups", async () => {
  let reads = 0;
  let value: unknown = null;
  const updates = new WebUpdates(current, async () => { reads++; if (reads === 1) throw new Error("offline"); return value; });
  await updates.check(0);
  await updates.check(1);
  assert.equal(reads, 1);
  for (const [i, invalid] of [null, {}, { version: "0.1.101" }, { revision: newer, version: 101 }, { revision: "bad", version: "0.1.101" }].entries()) {
    value = invalid;
    await updates.check((i + 1) * 60_000);
    assert.equal(updates.snapshot(), null);
  }
  value = { revision: newer, version: "0.1.101" };
  await updates.check(360_000);
  assert.deepEqual(updates.snapshot(), value);
});

test("does not overlap requests or check development builds", async () => {
  let finish!: (value: unknown) => void;
  let reads = 0;
  const updates = new WebUpdates(current, () => { reads++; return new Promise(resolve => { finish = resolve; }); });
  const first = updates.check(0);
  await updates.check(60_000);
  assert.equal(reads, 1);
  finish({ revision: newer, version: "0.1.101" });
  await first;
  assert.ok(updates.snapshot());
  const dev = new WebUpdates(null, async () => { throw new Error("must not request"); });
  await dev.check(0);
  assert.equal(dev.snapshot(), null);
});
