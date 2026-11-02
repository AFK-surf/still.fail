// Exercise a long-lived dependency graph against a direct oracle, including reads during a batch.
import assert from "node:assert/strict";
import { batch, computed, observe, signal } from "../src/reactive.ts";

const queued = new Set<() => void>();
const schedule = (job: () => void) => { queued.add(job); };
const flush = () => {
  while (queued.size) {
    const job = queued.values().next().value!;
    queued.delete(job);
    job();
  }
};

const first = signal(0), second = signal(2), gate = signal(true);
const failure = Error("E");
const chosen = computed(() => gate.get() ? first.get() : second.get());
const inner = computed(() => {
  const value = chosen.get();
  if (value === 13) throw failure;
  if (value === 17) throw undefined;
  return value % 3;
});
const middle = computed(() => inner.get() * 2);
const outer = computed(() => {
  try { return "ok:" + middle.get(); }
  catch (error) { return error === undefined ? "err:undefined" : error === failure ? "err:E" : "err:unexpected"; }
});
let shown = "", shownSecond = -1, runs = 0;
const stop = observe(() => { shown = outer.get(); runs++; }, schedule);
const stopSecond = observe(() => { shownSecond = second.get(); }, schedule);
let useFirst = true, a = 0, b = 2, count = 0, seed = 1862799;
const values = [0, 1, 2, 3, 4, 5, 13, 17];
const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
const expected = () => {
  const value = useFirst ? a : b;
  return value === 13 ? "err:E" : value === 17 ? "err:undefined" : "ok:" + ((value % 3) * 2);
};
function step(nextGate: boolean, nextFirst: number, nextSecond: number, readInside: boolean) {
  batch(() => {
    first.set(a = nextFirst);
    if (readInside) assert.equal(outer.get(), expected(), "read during batch " + count);
    second.set(b = nextSecond);
    gate.set(useFirst = nextGate);
  });
  flush();
  assert.equal(shown, expected(), "page after batch " + count);
  assert.equal(shownSecond, b, "independent observer after batch " + count);
  assert.equal(outer.get(), expected(), "read after batch " + count);
  count++;
}
for (const [g, a, b, read] of [[true, 13, 2, false], [true, 0, 2, false], [false, 0, 17, false], [false, 13, 17, true], [false, 13, 2, false]] as const) step(g, a, b, read);
for (let i = 0; i < 3000; i++) {
  const nextGate = random() % 7 === 0 ? !useFirst : useFirst;
  const nextFirst = random() % 3 === 0 ? values[random() % values.length]! : a;
  const nextSecond = random() % 3 === 0 ? values[random() % values.length]! : b;
  step(nextGate, nextFirst, nextSecond, i % 19 === 0);
}
const stoppedAt = runs;
stop(); stopSecond();
first.set(13); second.set(17); gate.set(!useFirst);
flush();
assert.equal(runs, stoppedAt, "disposed page does not run again");
assert.equal(first.subscriberCount(), 0, "first source released");
assert.equal(second.subscriberCount(), 0, "second source released");
assert.equal(gate.subscriberCount(), 0, "gate released");
console.log("automatic_graph=pass transactions=" + count + " page_runs=" + runs);
