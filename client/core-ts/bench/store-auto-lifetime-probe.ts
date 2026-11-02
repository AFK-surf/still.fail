// Isolated Store lifecycle probe on Hermes. The prelude supplies the engine's timer interface and a controllable clock.
import "../src/hosts/hermes-globals.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { Workspaces } from "../src/workspace.ts";

const g = globalThis as any;
const native = g.__native;
let computations = 0;
let emissions = 0;
let baseEmitted: unknown;
const host = {
  nowMs: () => native.now(),
  monotonicMs: () => native.monotonic(),
  utcOffsetMin: () => 0,
  emit(_client: number, message: { id: number; value?: unknown }) {
    if (message.id === 1 && "value" in message) baseEmitted = message.value;
    if (message.id > 1 && "value" in message) emissions++;
  },
};
async function drain(until: number, finished: () => boolean, label: string) {
  for (let step = 0; step < 100_000; step++) {
    // The native engine drains promise jobs after each callback. Give the runtime the same opportunity here.
    await Promise.resolve();
    if (finished()) { g.__probeClock = until; return; }
    let id = 0;
    let due = Infinity;
    for (const [key, at] of g.__probeTimers as Map<number, number>) {
      if (at < due) { id = key; due = at; }
    }
    if (due > until) continue;
    g.__probeClock = due;
    g.__probeTimers.delete(id);
    g.__stillfail_timer(id);
  }
  throw Error(label + ": the harness did not reach its completion condition; computed=" + computations + ", emitted=" + emissions + ", timers=" + g.__probeTimers.size);
}
function size() {
  g.gc();
  return g.HermesInternal.getInstrumentedStats().js_allocatedBytes as number;
}
async function run() {
const runner = new Runner();
const store = new Store(host as any, runner);
const workspaces = new Workspaces(host as any, runner);
const base = { topic: "base" };
store.setSource({
  start(topic) {
    if (topic.topic !== "page") return;
    store.invalidate(topic);
  },
  stop() {},
  compute(topic) {
    if (topic.topic === "page") {
      computations++;
      const value = store.get(base);
      const owner = workspaces.owner(`unknown-${topic.n}`);
      return { ok: { n: topic.n, base: value, owner, payload: "x".repeat(1000) } };
    }
    return undefined;
  },
});
store.subscribe(1, 1, base);
store.set(base, { ok: 1 });
await drain(0, () => baseEmitted === 1, "base");
const before = size();
const count = 2000;
for (let i = 0; i < count; i++) store.subscribe(1, i + 2, { topic: "page", n: i });
await drain(0, () => computations === count && emissions === count, "pages");
if (computations !== count || emissions !== count) throw Error("pages were not evaluated: computed=" + computations + ", emitted=" + emissions + ", timers=" + g.__probeTimers.size);
const live = size();
for (let i = 0; i < count; i++) store.unsubscribe(1, i + 2);
await drain(60_001, () => store.liveTopics().length === 1, "eviction");
if (store.liveTopics().length !== 1) throw Error("pages were not evicted: " + store.liveTopics().length + ", timers=" + g.__probeTimers.size);
if (workspaces.all().length !== 0) throw Error("reading an unknown owner created a workspace");
const after = size();
store.set(base, { ok: 2 });
await drain(60_101, () => baseEmitted === 2, "base after eviction");
if (computations !== count || emissions !== count) throw Error("evicted pages still received the update");
g.print("pages=" + count + " computed=" + computations + " emitted=" + emissions + " baseline=" + before + " live=" + live + " after=" + after + " retained=" + (after - before) + " evicted_update=ignored");
runner.shutdown();
}
void run().catch((error) => g.print("probe_error=" + String(error)));
