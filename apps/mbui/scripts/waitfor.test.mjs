import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { closeSync, constants, lstatSync, mkdtempSync, openSync, readSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

test("tee delivers a named event through an existing FIFO", { skip: process.platform === "win32" }, async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "waitfor-fifo-"));
  const fifo = join(dir, "ready");
  assert.equal(spawnSync("mkfifo", [fifo]).status, 0);
  // Opening both ends lets the reader start before the writer without waiting for a filesystem notification.
  const fd = openSync(fifo, constants.O_RDWR | constants.O_NONBLOCK);
  const script = fileURLToPath(new URL("./waitfor.mjs", import.meta.url));
  const child = spawn(process.execPath, [
    script, "--tee", join(dir, "cloud.log"), "--line", "^READY", "--mark", fifo, "--",
    process.execPath, "-e", 'process.stdout.write("READY\\n")',
  ], { stdio: "ignore" });
  t.after(() => {
    child.kill("SIGKILL");
    closeSync(fd);
    rmSync(dir, { recursive: true, force: true });
  });
  const [code] = await once(child, "exit");
  assert.equal(code, 0);
  assert.equal(lstatSync(fifo).isFIFO(), true);
  const message = Buffer.alloc(64);
  const read = readSync(fd, message, 0, message.length, null);
  assert.equal(message.subarray(0, read).toString(), "READY\n");
});
