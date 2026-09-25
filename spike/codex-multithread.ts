// Spike 2: memory of one shared `codex app-server` as threads accumulate, then
// with several turns running at once. Usage: node spike/codex-multithread.ts [cwd] [threads]
import { codexEnv, MODEL, peakSampler, report, sampleTree, sleep, startAppServer } from "./lib.ts";

const cwd = process.argv[2] ?? process.cwd();
const threadCount = Number(process.argv[3] ?? 8);
const concurrent = Math.min(4, threadCount);
const app = await startAppServer(cwd, codexEnv("ember-spike-codex"));

const rows: Record<string, unknown>[] = [];
const record = (phase: string, sample = sampleTree(app.pid), extra: Record<string, unknown> = {}) =>
  rows.push({ phase, procs: sample.pids.length, rssMb: sample.rssMb, footprintMb: sample.footprintMb, ...extra });
const commands = (items: any[]) => items.filter((item) => item?.type === "commandExecution").length;

try {
  await sleep(5000);
  record("initialized, no threads");

  const threads: string[] = [];
  for (let i = 1; i <= threadCount; i++) {
    const started = await app.request("thread/start", { cwd, model: MODEL, approvalPolicy: "never" });
    threads.push(started.thread.id);
    const items = await app.runTurn(started.thread.id, "Run `ls` in the current directory and reply with only the number of entries.");
    await sleep(2000);
    record(`${i} thread(s), each after one turn`, sampleTree(app.pid), { commands: commands(items) });
  }

  const sampler = peakSampler(app.pid);
  const results = await Promise.all(threads.slice(0, concurrent).map((id) =>
    app.runTurn(id, "Run `git log --oneline -3` and reply with only the newest commit subject.")));
  record(`${concurrent} turns at once, peak`, sampler.stop(), { commands: results.map(commands).join("+") });
  await sleep(30_000);
  record("idle 30s after concurrent turns");
} finally {
  app.killTree();
}

report(`codex app-server memory (model ${MODEL}, ${threadCount} threads)`, rows);
