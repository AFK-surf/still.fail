// A short offscreen job is not a build: let one run beside a busy build, without opening the queue to a crowd.
import assert from "node:assert/strict";
import { test } from "node:test";
import { pick, type Pressure } from "../src/jobs/admit.ts";

test("one small task can run beside a busy build, but still waits for memory and another small task", () => {
  const build = { id: "build", screen: false };
  const picture = { id: "picture", session: "a", queuedAt: 1, screen: false, small: true };
  const next = { id: "next", session: "b", queuedAt: 2, screen: false, small: true };
  const room = { busy: 1, pressure: "normal" as Pressure };
  const never = () => null;
  assert.deepEqual(pick([picture], [build], room, 0, 0, never), { start: picture });
  assert.deepEqual(pick([next], [build, { id: "picture", screen: false, small: true }], room, 0, 0, never), { wait: "busy", cause: "small" });
  assert.deepEqual(pick([picture], [build], { ...room, pressure: "high" }, 0, 0, never), { wait: "memory" });
});

test("small tasks are fair between sessions and do not hold up a ready ordinary task", () => {
  const a = { id: "a", session: "a", queuedAt: 1, screen: false, small: true };
  const b = { id: "b", session: "b", queuedAt: 2, screen: false, small: true };
  const normal = { id: "normal", session: "a", queuedAt: 3, screen: false };
  const room = { busy: 0, pressure: "normal" as Pressure };
  const last = (session: string) => session === "a" ? 10 : null;
  assert.deepEqual(pick([a, b], [], room, 20, null, last), { start: b });
  assert.deepEqual(pick([a, normal], [{ id: "other", screen: false, small: true }], room, 20, null, last), { start: normal });
  assert.deepEqual(pick([a], [{ id: "other", screen: false, small: true }], { ...room, pressure: "critical" }, 20, null, last), { wait: "memory" });
});
