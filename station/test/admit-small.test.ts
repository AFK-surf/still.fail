// A short offscreen job is not a build: let one run beside a busy build, without opening the queue to a crowd.
import assert from "node:assert/strict";
import { test } from "node:test";
import { pick, type Pressure } from "../src/jobs/admit.ts";

test("one small task can run beside a busy build, but still waits for critical memory and another small task", () => {
  const build = { id: "build", screen: false };
  const picture = { id: "picture", session: "a", queuedAt: 1, screen: false, small: true };
  const next = { id: "next", session: "b", queuedAt: 2, screen: false, small: true };
  const room = { pressure: "normal" as Pressure };
  const never = () => null;
  assert.deepEqual(pick([picture], [build], room, never), { start: picture });
  assert.deepEqual(pick([next], [build, { id: "picture", screen: false, small: true }], room, never), { wait: "small" });
  assert.deepEqual(pick([picture], [build], { ...room, pressure: "critical" }, never), { wait: "memory" });
});

test("under high memory pressure a small task still starts, and only it (#4355)", () => {
  const build = { id: "build", screen: false };
  const look = { id: "look", session: "a", queuedAt: 2, screen: false, small: true };
  const other = { id: "other", session: "b", queuedAt: 1, screen: false };
  const high = { pressure: "high" as Pressure };
  const never = () => null;
  assert.deepEqual(pick([other, look], [build], high, never), { start: look });
  assert.deepEqual(pick([other], [], high, never), { wait: "memory" });
  assert.deepEqual(pick([look], [build, { id: "x", screen: false, small: true }], high, never), { wait: "small" });
});

test("small tasks are fair between sessions and do not hold up a ready ordinary task", () => {
  const a = { id: "a", session: "a", queuedAt: 1, screen: false, small: true };
  const b = { id: "b", session: "b", queuedAt: 2, screen: false, small: true };
  const normal = { id: "normal", session: "a", queuedAt: 3, screen: false };
  const room = { pressure: "normal" as Pressure };
  const last = (session: string) => session === "a" ? 10 : null;
  assert.deepEqual(pick([a, b], [], room, last), { start: b });
  assert.deepEqual(pick([a, normal], [{ id: "other", screen: false, small: true }], room, last), { start: normal });
  assert.deepEqual(pick([a], [{ id: "other", screen: false, small: true }], { ...room, pressure: "critical" }, last), { wait: "memory" });
});
