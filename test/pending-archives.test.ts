import assert from "node:assert/strict";
import { test } from "node:test";
import { archiveKey, PendingArchives } from "../web/src/pendingArchives.ts";

test("archive hides immediately, deduplicates clicks, and waits for the list after success", () => {
  const pending = new PendingArchives();
  pending.reconcile(new Set(["a"]));
  let changes = 0;
  const unsubscribe = pending.subscribe(() => changes++);
  assert.equal(pending.begin("a"), true);
  assert.deepEqual([...pending.getSnapshot()], ["a"]);
  assert.equal(pending.begin("a"), false);
  pending.finish("a");
  // The call can answer before the core's coalesced view emission.
  pending.reconcile(new Set(["a"]));
  assert.deepEqual([...pending.getSnapshot()], ["a"]);
  pending.reconcile(new Set());
  assert.equal(pending.getSnapshot().size, 0);
  assert.equal(changes, 2);
  // A later incoming message may bring the archived chat back.
  pending.reconcile(new Set(["a"]));
  assert.equal(pending.getSnapshot().size, 0);
  unsubscribe();
});

test("lists may catch up before the call returns", () => {
  const pending = new PendingArchives();
  pending.reconcile(new Set(["a"]));
  pending.begin("a");
  pending.reconcile(new Set());
  assert.equal(pending.getSnapshot().has("a"), true);
  pending.finish("a");
  assert.equal(pending.getSnapshot().size, 0);
});

test("one failed archive restores only that row while other archives remain hidden", () => {
  const pending = new PendingArchives();
  const a = archiveKey({ station: "w/one", id: "thread:7" });
  const b = archiveKey({ station: "w/two", id: "thread:7" });
  pending.reconcile(new Set([a, b]));
  pending.begin(a);
  pending.begin(b);
  pending.fail(a);
  assert.deepEqual([...pending.getSnapshot()], [b]);
  assert.equal(pending.begin(a), true);
  pending.finish(b);
  // One sidebar filter is still showing b: do not release the override yet.
  pending.reconcile(new Set([a, b]));
  assert.equal(pending.getSnapshot().has(b), true);
  pending.reconcile(new Set([a]));
  assert.deepEqual([...pending.getSnapshot()], [a]);
});

test("a chat restored by new activity is not hidden forever when no snapshot ever omitted it", async () => {
  const pending = new PendingArchives();
  pending.reconcile(new Set(["a", "b"]));
  pending.begin("a");
  pending.begin("b");
  pending.finish("a");
  // New activity brought a back before the coalesced post-write snapshot arrived.
  pending.reconcile(new Set(["a", "b"]));
  await new Promise((resolve) => setTimeout(resolve, 1100));
  assert.equal(pending.getSnapshot().has("a"), false);
  assert.equal(pending.getSnapshot().has("b"), true);
});

test("a settled archive's timer cannot remove a later retry's pending state", async () => {
  const pending = new PendingArchives();
  pending.reconcile(new Set(["a"]));
  pending.begin("a");
  pending.finish("a");
  pending.reconcile(new Set());
  pending.reconcile(new Set(["a"]));
  pending.begin("a");
  await new Promise((resolve) => setTimeout(resolve, 1100));
  assert.equal(pending.getSnapshot().has("a"), true);
});
