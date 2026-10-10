// Agents under runners (src/agents/runner.ts) with the real runner binary (STILLFAIL_RUNNER or native/runner's build):
// lines in order, taken up again after a detach exactly where acknowledged, stdin, the exit after all output.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { RunnerConnection, existingRunners, startRunner } from "../src/agents/runner.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `f` holds (no deadline: it happens, whatever the machine's speed, or the test hangs).
const until = async (f: () => boolean) => {
  while (!f()) await sleep(20);
};

// On Windows: runner-windows.test.ts (no fifos, no sh).
test("lines in order; a station that lets go and comes back reads on where it acknowledged", { skip: process.platform === "win32" && "runner-windows.test.ts" }, async () => {
  const data = mkdtempSync(join(tmpdir(), "runner-test-"));
  // Says two lines; once let go (the fifo written), four more and marks them said; then echoes what it is sent, then
  // exits 3.
  const go = join(data, "go");
  const said = join(data, "said");
  execFileSync("/usr/bin/mkfifo", [go]);
  const script = `echo line1; echo line2; read g < '${go}'; for i in 3 4 5 6; do echo line$i; done; : > '${said}'; read x; echo got:$x; echo oops >&2; exit 3`;
  const info = await startRunner(data, "t1", "/bin/sh", ["-c", script], process.env, data);
  assert.equal(info.id, "t1");

  const first: string[] = [];
  const a = new RunnerConnection(info, (stream, text) => void (stream === "out" && first.push(text)));
  await until(() => first.length === 2);
  await a.detach();

  // Lines come meanwhile, with nobody to read them.
  writeFileSync(go, "go\n");
  await until(() => existsSync(said));
  assert.equal(existingRunners(data).length, 1, "the runner outlives the connection");
  const second: string[] = [];
  const b = new RunnerConnection(info, (stream, text) => void second.push(`${stream}:${text}`));
  await until(() => second.includes("out:line6"));
  b.write("hello\n");
  const exit = await b.exited;
  assert.deepEqual(exit, { code: 3, signal: null });
  const all = [...first, ...second.filter((l) => l.startsWith("out:")).map((l) => l.slice(4))];
  assert.deepEqual(all, ["line1", "line2", "line3", "line4", "line5", "line6", "got:hello"], "no line twice, none lost");
  assert.ok(second.includes("err:oops"));
  b.done();
  // Done: the runner is gone.
  await until(() => existingRunners(data).length === 0);
});
