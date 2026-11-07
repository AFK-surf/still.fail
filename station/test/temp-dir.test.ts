import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

test("a test directory is removed even if the worker exits while its after hook is waiting", () => {
  const parent = mkdtempSync(join(tmpdir(), "temp-exit-test-"));
  try {
    const child = join(parent, "child.test.mjs");
    const made = join(parent, "made");
    const waiting = join(parent, "waiting");
    const helper = new URL("./temp-dir.ts", import.meta.url).href;
    writeFileSync(child, `
      import { writeFileSync } from "node:fs";
      import { after, test } from "node:test";
      import { tempDir } from ${JSON.stringify(helper)};
      const data = tempDir(${JSON.stringify(join(parent, "data-"))});
      writeFileSync(${JSON.stringify(made)}, data);
      writeFileSync(data + "/input", "test input");
      test("passes", () => {});
      after(async () => { writeFileSync(${JSON.stringify(waiting)}, ""); await new Promise(() => {}); });
    `);
    const env = { ...process.env };
    delete env.NODE_TEST_CONTEXT;
    const run = spawnSync(process.execPath, ["--test", child], { env, encoding: "utf8", timeout: 30000 });
    assert.equal(run.status, 0, run.stderr || run.stdout);
    assert.ok(existsSync(waiting), "the after hook started but did not finish");
    const data = readFileSync(made, "utf8");
    assert.equal(existsSync(data), false, "the temporary data was removed at exit");
  } finally {
    rmSync(parent, { recursive: true, force: true, maxRetries: 3 });
  }
});
