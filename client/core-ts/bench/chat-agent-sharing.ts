// The chat's agent over a large, already-read session detail, as the database keeps it: frozen all through. Run in
// Hermes (the app's engine), once against each version with the same number of reads. No device data is used.
import "../src/hosts/hermes-globals.ts";
import { Views } from "../src/views/views.ts";
import { Output } from "../src/output.ts";
import { chatJobs } from "../src/jobs.ts";
import { deepFreeze } from "../src/util.ts";

const g = globalThis as any;
const detail = {
  session: { key: "k", runtime: "claude", process: "cold", pending: 0, lastTurn: null },
  turns: Array.from({ length: 2000 }, (_, i) => ({ id: `t${i}`, kind: "chat", detail: "A turn's result".repeat(8), startedAt: 1, endedAt: 2 })),
  threads: Array.from({ length: 100 }, (_, i) => ({ id: i, title: `Chat ${i}`, lastMessage: { text: "A message".repeat(20) } })),
  jobs: Array.from({ length: 1000 }, (_, i) => ({ id: `j${i}`, name: `Job ${i}`, state: "exited", startedAt: 1, notices: [{ at: 1, text: "A notice".repeat(12) }] })),
};
deepFreeze(detail);
const data = { dbs: () => [], onLogChange: () => {} };
const store = { value: (topic: { topic: string }) => topic.topic === "session" ? { ok: detail } : undefined };
const views = new Views({ data, store, host: { nowMs: () => 1_700_000_000_000 } } as any);
let checksum = 0;
function run(count: number): number {
  const before = Date.now();
  for (let i = 0; i < count; i++) {
    const agent = views.agent("w/s", "k");
    checksum += agent.turns.length + agent.threads.length + agent.jobs.length;
  }
  return Date.now() - before;
}
run(1);
let count = Number(g.__benchCount ?? 0);
if (count === 0) {
  count = 1;
  while (run(count) < 250) count *= 2;
}
checksum = 0;
const ms = [run(count), run(count), run(count)];
g.print(`reads=${count} input_bytes=${JSON.stringify(detail).length} ms=${ms.join(",")} checksum=${checksum}`);

// The rest of the opening: decorate and serialize the same agent in a chat. This isolates that work (without shape
// validation) and compares what a full and a compact subscriber receive, not the whole app's opening time.
const raw = { title: "Chat", messages: [], outbox: [], agents: [{ ...detail }] };
const output = new Output();
const clock = { now: 1_700_000_000_000, offsetMin: 0 };
function frame(compact: boolean): string {
  return JSON.stringify(output.shape({ topic: "chat", compact }, raw, clock, false));
}
function frames(n: number, compact: boolean): number {
  const before = Date.now();
  for (let i = 0; i < n; i++) checksum += frame(compact).length;
  return Date.now() - before;
}
const fullBytes = frame(false).length;
const compactBytes = frame(true).length;
let frameCount = 1;
while (frames(frameCount, false) < 250) frameCount *= 2;
const fullMs = [frames(frameCount, false), frames(frameCount, false), frames(frameCount, false)];
const compactMs = [frames(frameCount, true), frames(frameCount, true), frames(frameCount, true)];
g.print(`frames=${frameCount} full_bytes=${fullBytes} compact_bytes=${compactBytes} full_ms=${fullMs.join(",")} compact_ms=${compactMs.join(",")}`);

// The bar's job indicator versus the jobs sheet; both use the same synthetic jobs.
const chat = { agents: [{ jobs: detail.jobs }] };
function jobFrames(n: number, summary: boolean): number {
  const before = Date.now();
  for (let i = 0; i < n; i++) checksum += JSON.stringify(chatJobs(chat, clock, summary)[0]).length;
  return Date.now() - before;
}
const [jobsFull] = chatJobs(chat, clock);
const [jobsSummary] = chatJobs(chat, clock, true);
if (jobsSummary.hasJobs !== (jobsFull.jobs.length > 0) || jobsSummary.alarm !== jobsFull.alarm) throw Error("different button state");
let jobCount = 1;
while (jobFrames(jobCount, false) < 250) jobCount *= 2;
const jobsFullMs = [jobFrames(jobCount, false), jobFrames(jobCount, false), jobFrames(jobCount, false)];
const jobsSummaryMs = [jobFrames(jobCount, true), jobFrames(jobCount, true), jobFrames(jobCount, true)];
g.print(`jobs_frames=${jobCount} full_bytes=${JSON.stringify(jobsFull).length} summary_bytes=${JSON.stringify(jobsSummary).length} full_ms=${jobsFullMs.join(",")} summary_ms=${jobsSummaryMs.join(",")}`);
