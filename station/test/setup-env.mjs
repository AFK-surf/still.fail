import { afterEach, beforeEach } from "node:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// A test that needs a custom CA sets it itself. Host trust overrides must not leak into the fake agents' environments.
for (const key of ["SSL_CERT_FILE", "SSL_CERT_DIR", "CODEX_CA_CERTIFICATE"]) delete process.env[key];

// Each run its own temporary directory, named to every test file's process (they inherit it from the runner, which
// makes it) and removed when the run ends: leftover files in a shared directory slow tests that list its parent. Short,
// under /tmp, for the sockets made in it (104 bytes on macOS).
if (!process.env.STILLFAIL_TEST_TMP) {
  const own = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "sft-") : "/tmp/sft-");
  process.env.STILLFAIL_TEST_TMP = own;
  process.env.TMPDIR = process.env.TMP = process.env.TEMP = own;
  process.on("exit", () => rmSync(own, { recursive: true, force: true, maxRetries: 3 }));
}

// What a test file started is gone when it ends. The runner waits for the end of each file's output, and a process
// that file started with its output (a far side in a sandbox, a fake's helper, a `tail -f`) holds it while it lives:
// the whole run waits on it, past CI's time, every test passed. Each such process carries the file's mark in its
// environment; one still running as the file's process ends is ended, and named, and the file fails: what leaves it
// running is to be fixed (esbuild's service, say).
if (process.env.NODE_TEST_CONTEXT === "child-v8" && process.platform !== "win32") {
  const mark = `${process.pid}-${Date.now()}`;
  process.env.STILLFAIL_TEST_FILE = mark;
  process.on("exit", () => {
    let listed = "";
    try {
      // Each process of this user with its environment (macOS: -E; Linux: e).
      listed = execFileSync("ps", process.platform === "darwin" ? ["-E", "-ww", "-x", "-o", "pid=,command="] : ["-x", "-ww", "e", "-o", "pid=,args="], { encoding: "utf8", maxBuffer: 64 << 20, env: { ...process.env, STILLFAIL_TEST_FILE: "" } });
    } catch {
      return;
    }
    const left = listed.split("\n").filter((l) => l.includes(`STILLFAIL_TEST_FILE=${mark}`)).map((l) => l.trim()).filter((l) => Number(l.split(" ")[0]) !== process.pid);
    if (left.length === 0) return;
    for (const l of left) {
      try {
        process.kill(Number(l.split(" ")[0]), "SIGKILL");
      } catch {}
    }
    const file = process.argv.find((a) => /\.test\.(ts|mjs)$/.test(a)) ?? "?";
    process.stderr.write(`${file}: left running after its tests (ended now):\n${left.map((l) => `  ${l.replace(/ [A-Za-z_][A-Za-z0-9_]*=.*$/, "").slice(0, 200)}`).join("\n")}\n`);
    process.exitCode = 1;
  });
}

// A test that hangs says where (scripts/check.sh, stopped at CI's time, sends SIGUSR2 to each test file still running):
// the tests running and since when, else what keeps the process open after its tests (a hook, a leftover process or
// server), to $STILLFAIL_TEST_HUNG/<pid> or stderr. Waits on real processes have no deadline here: without this a hang
// said nothing but its file (41597210040: test/sandbox.test.ts).

const running = new Map();
beforeEach((t) => void running.set(t, Date.now()));
afterEach((t) => void running.delete(t));
// Node writes a diagnostic report on this signal in a test file's process otherwise.
process.report.reportOnSignal = false;
process.on("SIGUSR2", () => {
  const now = Date.now();
  const lines = [...running].map(([t, at]) => `test "${t.fullName}" running ${Math.round((now - at) / 1000)} s`);
  if (lines.length === 0) lines.push("no test running: a hook, or what its tests left open");
  for (const h of process._getActiveHandles()) {
    if (h?.constructor?.name === "ChildProcess") lines.push(`  child process ${h.pid}: ${h.spawnargs.join(" ").slice(0, 160)}`);
    else if (h?.constructor?.name === "Server" && h.address?.()) lines.push(`  server listening at ${JSON.stringify(h.address())}`);
  }
  lines.push(`  resources: ${process.getActiveResourcesInfo().join(", ")}`);
  const text = `${process.argv.find((a) => /\.test\.(ts|mjs)$/.test(a)) ?? "?"}\n${lines.map((l) => `  ${l}`).join("\n")}\n`;
  const dir = process.env.STILLFAIL_TEST_HUNG;
  if (dir) writeFileSync(`${dir}/${process.pid}`, text);
  else process.stderr.write(text);
});
