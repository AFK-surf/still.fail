// Spike 1: memory of one `claude -p` stream-json process tree across idle and
// active phases. Usage: node spike/claude-memory.ts [cwd]
import { randomUUID } from "node:crypto";
import { claudeEnv, MODEL, peakSampler, report, sampleTree, sleep, spawnLines } from "./lib.ts";

const cwd = process.argv[2] ?? process.cwd();
const sessionId = randomUUID();
const proc = spawnLines("claude", [
  "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
  "--dangerously-skip-permissions", "--session-id", sessionId, "--model", MODEL,
], { cwd, env: claudeEnv(`ember-spike-${sessionId}`) });

const iterator = proc.lines[Symbol.asyncIterator]();
async function turn(text: string): Promise<{ result: Record<string, unknown>; tools: number }> {
  proc.send({ type: "user", message: { role: "user", content: [{ type: "text", text }] } });
  let tools = 0;
  for (;;) {
    const next = await iterator.next();
    if (next.done) throw new Error("claude exited before the turn ended");
    const frame = JSON.parse(next.value) as Record<string, any>;
    if (frame.type === "assistant") {
      tools += (frame.message?.content ?? []).filter((block: any) => block.type === "tool_use").length;
    }
    if (frame.type === "result") return { result: frame, tools };
  }
}

const rows: Record<string, unknown>[] = [];
const record = (phase: string, sample = sampleTree(proc.child.pid!), extra: Record<string, unknown> = {}) =>
  rows.push({ phase, procs: sample.pids.length, rssMb: sample.rssMb, footprintMb: sample.footprintMb, ...extra });

try {
  await sleep(8000);
  record("spawned, before first input");

  let sampler = peakSampler(proc.child.pid!);
  let run = await turn("Reply with exactly: hi");
  record("turn 1 (no tools) peak", sampler.stop(), { outcome: run.result.is_error ? `ERROR: ${String(run.result.result).slice(0, 60)}` : "ok", tools: run.tools });
  await sleep(10_000);
  record("idle 10s after turn 1");

  sampler = peakSampler(proc.child.pid!);
  run = await turn(
    "Read package.json and docs/design.md, run `ls -la` and `git log --oneline -5`, " +
    "then reply with a three-line summary of this repository. Do not modify anything.",
  );
  record("turn 2 (tools) peak", sampler.stop(), { outcome: run.result.is_error ? `ERROR: ${String(run.result.result).slice(0, 60)}` : "ok", tools: run.tools });
  await sleep(30_000);
  record("idle 30s after turn 2");
  await sleep(90_000);
  record("idle 2min after turn 2");
} finally {
  proc.killTree();
}

report(`claude ${process.env.EMBER_SPIKE_CLAUDE_VERSION ?? ""} memory (model ${MODEL}, session ${sessionId})`, rows);
