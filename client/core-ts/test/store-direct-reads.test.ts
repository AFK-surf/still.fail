import assert from "node:assert/strict";
import { test } from "node:test";
import { Data } from "../src/data.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { COALESCE_MS, Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { run } from "./run.ts";

test("a_page_follows_the_thread_it_reads_directly", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  const store = new Store(host, runner);
  const page: Topic = { topic: "page" };
  let made = 0;
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute() { made++; return { ok: data.thread("w/s", 1) ?? null }; },
  });
  const pass = () => host.time.pass(COALESCE_MS * 3, 10);
  try {
    store.subscribe(1, 1, page);
    await pass();
    assert.equal(store.get(page), null);
    data.putThread("w/s", { id: 2, title: "other" });
    await run(data.written);
    await pass();
    assert.equal(made, 1, "another thread did not rebuild the page");
    data.putThread("w/s", { id: 1, title: "first" });
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { id: 1, title: "first" });
    data.putThread("w/s", { id: 1, title: "changed" });
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { id: 1, title: "changed" });
    data.dropThread("w/s", 1);
    await run(data.written);
    await pass();
    assert.equal(store.get(page), null);
    data.putThread("w/s", { id: 1, title: "returned" });
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { id: 1, title: "returned" });
    data.of("w/s")!.forgetStation("w/s");
    await run(data.written);
    await pass();
    assert.equal(store.get(page), null, "forgetting the station releases its thread");
  } finally { runner.shutdown(); }
});

test("a_page_follows_the_log_it_reads_directly", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  const store = new Store(host, runner);
  const page: Topic = { topic: "page" };
  let made = 0;
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute() {
      made++;
      return { ok: {
        numbers: [...data.logNumbers("entry", "w/s", "1")],
        values: [...data.logRange("entry", "w/s", "1", 1, 10).values()],
        span: data.logSpan("entry", "w/s", "1"),
        count: data.logCount("entry", "w/s", "1", 1, 10),
      } };
    },
  });
  const pass = () => host.time.pass(COALESCE_MS * 3, 10);
  try {
    store.subscribe(1, 1, page);
    await pass();
    assert.deepEqual(store.get(page), { numbers: [], values: [], span: null, count: 0 });
    data.putItems("entry", "w/s", "2", [[1, { text: "other" }]]);
    await run(data.written);
    await pass();
    assert.equal(made, 1, "another log did not rebuild the page");
    data.putItems("entry", "w/s", "1", [[1, { text: "first" }]]);
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { numbers: [1], values: [{ text: "first" }], span: { min: 1, max: 1, count: 1 }, count: 1 });
    data.putItems("entry", "w/s", "1", [[2, { text: "next" }]]);
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { numbers: [1, 2], values: [{ text: "first" }, { text: "next" }], span: { min: 1, max: 2, count: 2 }, count: 2 });
    data.forgetLog("entry", "w/s", "1");
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { numbers: [], values: [], span: null, count: 0 });
    data.putItems("entry", "w/s", "1", [[3, { text: "returned" }]]);
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { numbers: [3], values: [{ text: "returned" }], span: { min: 3, max: 3, count: 1 }, count: 1 });
    data.of("w/s")!.forgetStation("w/s");
    await run(data.written);
    await pass();
    assert.deepEqual(store.get(page), { numbers: [], values: [], span: null, count: 0 }, "forgetting the station releases its log");
  } finally { runner.shutdown(); }
});

test("forgetting_a_station_refreshes_its_direct_reads", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  const store = new Store(host, runner);
  const page: Topic = { topic: "page", station: "w/s" };
  const other: Topic = { topic: "page", station: "w/other" };
  const made = new Map<string, number>();
  data.putThread("w/s", { id: 1, title: "first" });
  data.putItems("entry", "w/s", "1", [[1, { text: "message" }]]);
  await run(data.written);
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute(topic) {
      const station = String(topic.station);
      made.set(station, (made.get(station) ?? 0) + 1);
      return { ok: {
        thread: data.thread(station, 1) ?? null,
        messages: [...data.logRange("entry", station, "1", 1, 10).values()],
      } };
    },
  });
  try {
    store.subscribe(1, 1, page);
    store.subscribe(1, 2, other);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), { thread: { id: 1, title: "first" }, messages: [{ text: "message" }] });
    data.of("w/s")!.forgetStation("w/s");
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), { thread: null, messages: [] });
    assert.equal(made.get("w/other"), 1, "another station did not rebuild its page");
  } finally { runner.shutdown(); }
});
