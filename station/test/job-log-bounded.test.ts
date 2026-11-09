import assert from "node:assert/strict";
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { tail } from "../src/read/jobs.ts";

test("a log tail stops at the file end seen before the read even as the job writes more", () => {
  const dir = fs.mkdtempSync(join(tmpdir(), "job-tail-bound-"));
  const path = join(dir, "job.log");
  fs.writeFileSync(path, "old\n".repeat(16_384));
  const read = fs.readSync;
  let appended = false;
  const reading = (...args: any[]) => {
    const n = Reflect.apply(read, fs, args) as number;
    if (n > 0 && !appended) {
      appended = true;
      fs.appendFileSync(path, "new\n");
    }
    return n;
  };
  try {
    Object.defineProperty(fs, "readSync", { value: reading, writable: true, configurable: true });
    syncBuiltinESMExports();
    assert.equal(tail(path, 1), "old");
    assert.ok(appended);
    assert.ok(fs.readFileSync(path, "utf8").endsWith("new\n"), "the later log entry is still available to the next read");
  } finally {
    Object.defineProperty(fs, "readSync", { value: read, writable: true, configurable: true });
    syncBuiltinESMExports();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
