// The main thread's waits on files put down (src/ops/file-waits.ts).
import assert from "node:assert/strict";
import fs, { existsSync, mkdtempSync, readdirSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { timeFiles } from "../src/ops/file-waits.ts";
import { WAITED_MS, longestWaits } from "../src/ops/waits.ts";

test("every synchronous call of node:fs is timed, named imports' too; those waiting WAITED_MS or more by the call and who made it, never its path", () => {
  const dir = mkdtempSync(join(tmpdir(), "file-waits-"));
  writeFileSync(join(dir, "someone's notes"), "x");
  // Each call takes as long as the test says, on the clock it gives.
  let takes = 0;
  let at = 0;
  const files = timeFiles(() => (at += takes));
  try {
    takes = 1;
    assert.equal(existsSync(join(dir, "someone's notes")), true);
    takes = WAITED_MS;
    const lookAround = () => readdirSync(dir).map((name) => fs.statSync(join(dir, name)).size);
    assert.deepEqual(lookAround(), [1]);
    assert.equal(existsSync(join(dir, "none")), false);
    // What hangs off a call is there still, and answers as it did.
    assert.equal(realpathSync.native(dir), realpathSync(dir));
    const waits = files.take();
    // (The call hanging off one is not timed.)
    assert.equal(waits.calls, 5);
    assert.equal(waits.ms, 1 + 4 * WAITED_MS);
    const by = [...waits.by.keys()];
    assert.ok(by.some((k) => k.startsWith("readdirSync lookAround")), by.join(" | "));
    assert.ok(by.some((k) => k.startsWith("statSync") && k.includes("lookAround")), by.join(" | "));
    assert.ok(!JSON.stringify(by).includes("notes") && !longestWaits(waits).includes(dir), "never the paths");
    assert.match(longestWaits(waits, 1), /^\S+ .* \d+ms×\d+$/);
    // Taken: from nothing again.
    assert.deepEqual(files.take(), { ms: 0, calls: 0, by: new Map() });
  } finally {
    files.stop();
  }
  // Stopped: as they were.
  takes = WAITED_MS;
  existsSync(dir);
  assert.deepEqual(files.take(), { ms: 0, calls: 0, by: new Map() });
});
