// Agents under runners (src/agents/runner.ts) with the real runner binary (STILLFAIL_RUNNER or native/runner's build):
// lines in order, taken up again after a detach exactly where acknowledged, stdin, the exit after all output.
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { RunnerConnection, existingRunners, startRunner } from "../src/agents/runner.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test("lines in order; a station that lets go and comes back reads on where it acknowledged", async () => {
  const data = mkdtempSync(join(tmpdir(), "runner-test-"));
  // Says 1..6, a line every 100 ms, then echoes what it is sent, then exits 3.
  const script = "for i in 1 2 3 4 5 6; do echo line$i; sleep 0.1; done; read x; echo got:$x; echo oops >&2; exit 3";
  const info = await startRunner(data, "t1", "/bin/sh", ["-c", script], process.env, data);
  assert.equal(info.id, "t1");

  const first: string[] = [];
  const a = new RunnerConnection(info, (stream, text) => void (stream === "out" && first.push(text)));
  while (first.length < 2) await sleep(20);
  a.detach();
  const seenByA = first.length;

  await sleep(300);
  assert.equal(existingRunners(data).length, 1, "the runner outlives the connection");
  const second: string[] = [];
  const b = new RunnerConnection(info, (stream, text) => void second.push(`${stream}:${text}`));
  while (second.filter((l) => l.startsWith("out:line")).length + seenByA < 6) await sleep(20);
  b.write("hello\n");
  const exit = await b.exited;
  assert.deepEqual(exit, { code: 3, signal: null });
  const all = [...first, ...second.filter((l) => l.startsWith("out:")).map((l) => l.slice(4))];
  assert.deepEqual(all, ["line1", "line2", "line3", "line4", "line5", "line6", "got:hello"], "no line twice, none lost");
  assert.ok(second.includes("err:oops"));
  b.done();
  await sleep(300);
  assert.equal(existingRunners(data).length, 0, "done: the runner is gone");
});
