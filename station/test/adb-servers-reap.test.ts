// The grants' adb servers a station process before left running (read/adb/servers.ts `reap`): stopped by the next, as
// written down; another process given one's pid since is left alone.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { GrantServers } from "../src/adb/servers.ts";
import { platform } from "../src/platform/index.ts";

test("the grants' adb servers a station before left are stopped by the next; a pid now another's is left", { skip: process.platform === "win32" }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "adb-reap-"));
  const record = join(dir, "adb-servers.json");
  const left = spawn("sleep", ["60"], { stdio: "ignore" });
  const other = spawn("sleep", ["60"], { stdio: "ignore" });
  try {
    await new Promise((r) => setTimeout(r, 200));
    const exited = new Promise<number | null>((resolve) => left.once("exit", (code, signal) => resolve(signal === "SIGTERM" ? 15 : code)));
    writeFileSync(record, JSON.stringify([
      { pid: left.pid, port: 1, started: platform.startTimeOf(left.pid!) },
      // As written down, started long before: not this process.
      { pid: other.pid, port: 2, started: (platform.startTimeOf(other.pid!) ?? 0) - 3_600_000 },
    ]));
    const servers = new GrantServers(() => null, record);
    assert.equal(await servers.reap(), 1);
    assert.equal(await exited, 15, "the one left stopped");
    assert.equal(other.exitCode, null, "the other runs on");
  } finally {
    left.kill("SIGKILL");
    other.kill("SIGKILL");
    rmSync(dir, { recursive: true, force: true });
  }
});
