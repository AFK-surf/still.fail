// Spike 2: memory of one shared `codex app-server` as threads accumulate, then
// with several turns running at once. Usage: node spike/codex-multithread.ts [cwd] [threads]
import { codexEnv, MODEL, peakSampler, report, sampleTree, sleep, spawnLines } from "./lib.ts";

const cwd = process.argv[2] ?? process.cwd();
const threadCount = Number(process.argv[3] ?? 8);
const concurrent = Math.min(4, threadCount);
const proc = spawnLines("codex", ["app-server", "--listen", "stdio://"], { cwd, env: codexEnv("ember-spike-codex") });

let nextId = 1;
const pending = new Map<number, { resolve(v: any): void; reject(e: Error): void }>();
const turnWaiters = new Map<string, () => void>();
(async () => {
  for await (const line of proc.lines) {
    const msg = JSON.parse(line) as Record<string, any>;
    if (typeof msg.id === "number" && ("result" in msg || "error" in msg) && pending.has(msg.id)) {
      const waiter = pending.get(msg.id)!;
      pending.delete(msg.id);
      if (msg.error) waiter.reject(new Error(JSON.stringify(msg.error)));
      else waiter.resolve(msg.result);
    } else if (msg.id !== undefined && msg.method) {
      // A server->client request (approval etc.): refuse so nothing hangs.
      proc.send({ id: msg.id, error: { code: -32601, message: "not supported in spike" } });
    } else if (msg.method === "turn/completed") {
      turnWaiters.get(msg.params?.threadId)?.();
    } else if (msg.method === "error") {
      console.error("codex error notification:", JSON.stringify(msg.params).slice(0, 400));
    }
  }
})();

function request(method: string, params: unknown): Promise<any> {
  const id = nextId++;
  proc.send({ id, method, params });
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

async function runTurn(threadId: string, text: string): Promise<void> {
  const done = new Promise<void>((resolve) => turnWaiters.set(threadId, resolve));
  await request("turn/start", { threadId, input: [{ type: "text", text }] });
  await Promise.race([done, sleep(180_000).then(() => { throw new Error(`turn on ${threadId} timed out`); })]);
  turnWaiters.delete(threadId);
}

const rows: Record<string, unknown>[] = [];
const record = (phase: string, sample = sampleTree(proc.child.pid!)) =>
  rows.push({ phase, procs: sample.pids.length, rssMb: sample.rssMb, footprintMb: sample.footprintMb });

try {
  await request("initialize", { clientInfo: { name: "ember-spike", version: "0" }, capabilities: { experimentalApi: true } });
  proc.send({ method: "initialized", params: {} });
  await sleep(5000);
  record("initialized, no threads");

  const threads: string[] = [];
  for (let i = 1; i <= threadCount; i++) {
    const started = await request("thread/start", { cwd, model: MODEL, approvalPolicy: "never" });
    threads.push(started.thread.id);
    await runTurn(started.thread.id, "Run `ls` in the current directory and reply with only the number of entries.");
    await sleep(2000);
    record(`${i} thread(s), each after one turn`);
  }

  const sampler = peakSampler(proc.child.pid!);
  await Promise.all(threads.slice(0, concurrent).map((id) =>
    runTurn(id, "Run `git log --oneline -3` and reply with only the newest commit subject.")));
  record(`${concurrent} turns at once, peak`, sampler.stop());
  await sleep(30_000);
  record("idle 30s after concurrent turns");
} finally {
  proc.killTree();
}

report(`codex app-server memory (model ${MODEL}, ${threadCount} threads)`, rows);
