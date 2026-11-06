import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { PersonVerifier } from "../src/mesh/person-verifier.ts";
import { wall } from "../src/ops/fibers.ts";

test("the personal verifier cancels its deadlines, stops when idle and refuses a timed-out check", async () => {
  const original = wall.after;
  const timers: { ms: number; cancelled: boolean; fire: () => void }[] = [];
  wall.after = (ms, run) => {
    const timer = { ms, cancelled: false, fire: () => { if (!timer.cancelled) run(); } };
    timers.push(timer);
    return () => { timer.cancelled = true; };
  };
  const verifier = new PersonVerifier(mkdtempSync(join(tmpdir(), "person-verifier-clock-")));
  try {
    await assert.rejects(verifier.snapshot("carol", [], []));
    assert.equal(timers[0]?.ms, 30_000);
    assert.equal(timers[0]?.cancelled, true, "a response cancels its deadline");
    assert.equal(timers[1]?.ms, 60_000);
    const next = verifier.snapshot("carol", [], []);
    assert.equal(timers[1]?.cancelled, true, "new work cancels the idle stop");
    assert.equal(timers[2]?.ms, 30_000);
    timers[2]!.fire();
    await assert.rejects(next, /verifier stopped/);
    assert.equal(timers[2]?.cancelled, true);
    await assert.rejects(verifier.snapshot("carol", [], []));
    const idle = timers.at(-1)!;
    assert.equal(idle.ms, 60_000);
    idle.fire();
    await assert.rejects(verifier.snapshot("carol", [], []), /./, "a later request can start a fresh worker");
  } finally {
    verifier.close();
    wall.after = original;
  }
});
