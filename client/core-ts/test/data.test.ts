// data.rs's tests, ported (same names, same checks), and kept.rs's: the TS core keeps threads' entries and sessions'
// transcripts as records (rule 3), so kept.rs's chunk store is gone; its tests are ported as what the records do in
// its place (kept.ts reads the Rust core's chunks once, kept.test.ts). Where they deliberately differ, it says why.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Data, SEP } from "../src/data.ts";
import { CHUNK, readKept } from "../src/kept.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";
import { run } from "./run.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const rows = (station: string): Topic => ({ topic: "chatRows", station });
const overview = (station: string): Topic => ({ topic: "overview", station });

function fresh() {
  const host = new FakeHost();
  const runner = new Runner();
  return { host, runner, data: new Data(host, runner) };
}

test("model_selection_survives_old_events_and_finishes_without_reverting", async () => {
  const { host, runner, data } = fresh();
  const topic = overview("w/s");
  data.set(topic, { profiles: [{ id: "p", models: ["a"] }] });
  assert.ok(data.beginModels("w/s", "p", ["a", "b"]));
  assert.ok(!data.beginModels("w/s", "p", []));
  data.update(topic, (o) => ({ ...(o as J), name: "event while saving" }));
  assert.deepEqual((data.get(topic) as J).profiles[0].models, ["a"]);
  assert.deepEqual((data.shown(topic) as J).profiles[0].models, ["a", "b"]);
  assert.deepEqual((data.shown(topic) as J).profiles[0].modelsSaving, ["b"]);
  await run(data.written);
  const restart = new Data(host, runner);
  await run(restart.load);
  assert.deepEqual((restart.shown(topic) as J).profiles[0].models, ["a"]);
  data.set(topic, { profiles: [{ id: "p", models: ["a", "b"] }] });
  assert.deepEqual((data.shown(topic) as J).profiles[0].modelsSaving, ["b"]);
  data.endModels("w/s", "p");
  assert.deepEqual((data.shown(topic) as J).profiles[0].models, ["a", "b"]);
  assert.equal((data.shown(topic) as J).profiles[0].modelsSaving, undefined);
  assert.ok(data.beginModels("w/s", "p", []));
  data.endModels("w/s", "p"); // refused: reveal the confirmed selection
  assert.deepEqual((data.shown(topic) as J).profiles[0].models, ["a", "b"]);
  runner.shutdown();
});

test("what_it_holds_is_there_after_a_restart", async () => {
  const { host, runner, data } = fresh();
  data.set(rows("w/s"), [{ id: "b", title: "二" }, { id: "a", title: "一" }]);
  data.set(overview("w/s"), { connects: [] });
  await run(data.written);
  const again = new Data(host, runner);
  assert.equal(again.get(rows("w/s")), undefined, "nothing before it loads");
  await run(again.load);
  // The order the station gave is kept.
  assert.deepEqual(again.get(rows("w/s")), [{ id: "b", title: "二" }, { id: "a", title: "一" }]);
  assert.deepEqual(again.get(overview("w/s")), { connects: [] });
  runner.shutdown();
});

test("a_list_writes_what_changed_and_forgets_what_left", async () => {
  const { host, runner, data } = fresh();
  const told: Topic[] = [];
  data.onChange((t) => told.push(t));
  data.set(rows("w/s"), [{ id: "a", n: 1 }, { id: "b", n: 1 }]);
  data.set(rows("w/s"), [{ id: "a", n: 1 }, { id: "b", n: 1 }]);
  assert.equal(told.length, 1, "the same value again changes nothing");
  data.set(rows("w/s"), [{ id: "a", n: 2 }]);
  await run(data.written);
  assert.deepEqual(host.dbKeys("row"), [`w/s${SEP}a`]);
  assert.deepEqual(data.get(rows("w/s")), [{ id: "a", n: 2 }]);
  // Read and empty is known; never read is not.
  data.set(rows("w/s"), []);
  assert.deepEqual(data.get(rows("w/s")), []);
  assert.equal(data.get(rows("w/t")), undefined);
  runner.shutdown();
});

test("an_update_changes_what_is_known_only", () => {
  const { runner, data } = fresh();
  const topic = overview("w/s");
  data.update(topic, (v) => ({ ...(v as J), x: 1 }));
  assert.equal(data.get(topic), undefined);
  data.set(topic, { x: 0 });
  data.update(topic, (v) => ({ ...(v as J), x: 1 }));
  assert.deepEqual(data.get(topic), { x: 1 });
  runner.shutdown();
});

test("retain_forgets_the_stations_no_one_reaches", async () => {
  const { host, runner, data } = fresh();
  data.set(rows("w1/s"), [{ id: "a" }]);
  data.set(rows("w2/s"), [{ id: "a" }]);
  data.set({ topic: "workspace", workspace: "w2" }, { id: "w2" });
  await run(data.putItems("entry", "w2/s", "7", [[1, { n: 1 }]]));
  await run(data.putItems("entry", "w1/s", "7", [[1, { n: 1 }]]));
  await run(data.written);
  data.retain((station) => station.startsWith("w1/"), new Set(["w1"]));
  await host.time.pass(50);
  await run(data.written);
  assert.notEqual(data.get(rows("w1/s")), undefined);
  assert.equal(data.get(rows("w2/s")), undefined);
  assert.equal(data.get({ topic: "workspace", workspace: "w2" }), undefined);
  assert.ok([...host.db.keys()].every((k) => !k.split("\u0000")[1].startsWith("w2")), JSON.stringify([...host.db.keys()]));
  assert.equal((await run(data.log("entry", "w1/s", "7"))).size, 1);
  runner.shutdown();
});

// ── kept.rs ──

const entries = (from: number, to: number): [number, unknown][] => Array.from({ length: to - from + 1 }, (_, i) => [from + i, { n: from + i, kind: "message", text: `m${from + i}` }]);
const numbers = (items: Map<number, unknown>) => [...items.keys()].sort((a, b) => a - b);
const range = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => from + i);

test("a_thread_is_kept_in_chunks_of_256_and_read_back", async () => {
  // Records in place of chunks: each entry its own record, read back whole after a restart. Entries already held
  // change nothing (nothing is written for them).
  const { host, runner, data } = fresh();
  await run(data.putItems("entry", "ws/st", "7", entries(201, 250)));
  await run(data.putItems("entry", "ws/st", "7", entries(251, 300)));
  await run(data.putItems("entry", "ws/st", "7", entries(1, 200)));
  await run(data.written);
  const writes = host.db.size;
  const before = [...host.db.entries()].map(([k, v]) => k + v.length).join();
  await run(data.putItems("entry", "ws/st", "7", entries(290, 300)));
  await run(data.written);
  assert.equal([...host.db.entries()].map(([k, v]) => k + v.length).join(), before);
  assert.equal(writes, 300);
  const again = new Data(host, runner);
  assert.deepEqual(numbers(await run(again.log("entry", "ws/st", "7"))), range(1, 300));
  // Deliberately otherwise (rule 3): entries that do not touch what is held are kept beside it, not in its place (the
  // sync fills the gap between).
  await run(again.putItems("entry", "ws/st", "7", entries(400, 401)));
  assert.equal((await run(again.log("entry", "ws/st", "7"))).size, 302);
  runner.shutdown();
});

test("extend_only_carries_on_what_is_kept", async () => {
  // Deliberately otherwise (rule 3): the Rust core kept one unbroken run per thread and dropped what came past a gap;
  // the TS core keeps every entry it is told of, and the sync reads the gap (station-flows.test.ts,
  // a_gap_is_read_once_and_what_came_meanwhile_waits_for_it). What is told twice changes nothing.
  const { runner, data } = fresh();
  await run(data.putItems("entry", "ws/st", "7", entries(1, 10)));
  await run(data.putItems("entry", "ws/st", "7", entries(11, 12)));
  await run(data.putItems("entry", "ws/st", "7", entries(12, 13)));
  await run(data.putItems("entry", "ws/st", "7", entries(20, 21)));
  await run(data.putItems("entry", "ws/st", "7", entries(5, 6)));
  assert.deepEqual(numbers(await run(data.log("entry", "ws/st", "7"))), [...range(1, 13), 20, 21]);
  runner.shutdown();
});

test("a_chunk_that_does_not_match_its_meta_forgets_the_log", async () => {
  // What the Rust core kept, read once: a chunk not as its meta says is not read.
  const host = new FakeHost();
  const put = (k: string, v: unknown) => host.storage.set(k, new TextEncoder().encode(JSON.stringify(v)));
  put("kept", { "thread/ws/st/7": { station: "ws/st", opened: 1, chunks: { 0: 10 } } });
  put("thread/ws/st/7/meta", { first: 1, last: 10 });
  put("thread/ws/st/7/0", entries(2, 11).map(([, e]) => e));
  const runner = new Runner();
  const data = new Data(host, runner);
  await run(readKept(host, data));
  assert.equal((await run(data.log("entry", "ws/st", "7"))).size, 0);
  assert.equal(CHUNK, 256);
  runner.shutdown();
});

test("a_transcript_counts_from_0_and_can_be_cut_short", async () => {
  const { host, runner, data } = fresh();
  const lines = (from: number, to: number): [number, unknown][] => range(from, to).map((i) => [i, `e${i}`]);
  await run(data.putItems("transcript", "ws/st", "ember:c-1", lines(0, 299), 299));
  // Written anew from 100: what came after is gone.
  await run(data.putItems("transcript", "ws/st", "ember:c-1", lines(100, 101), 101));
  let all = await run(data.log("transcript", "ws/st", "ember:c-1"));
  assert.deepEqual([Math.min(...all.keys()), Math.max(...all.keys()), all.size, all.get(101)], [0, 101, 102, "e101"]);
  await run(data.written);
  assert.equal(host.dbKeys("transcript").length, 102);
  await run(data.putItems("transcript", "ws/st", "ember:c-1", [], 49));
  assert.equal((await run(data.log("transcript", "ws/st", "ember:c-1"))).size, 50);
  await run(data.putItems("transcript", "ws/st", "ember:c-1", [], -1));
  all = await run(data.log("transcript", "ws/st", "ember:c-1"));
  assert.equal(all.size, 0);
  runner.shutdown();
});

test("past_the_limit_the_least_recently_opened_go", async () => {
  // Deliberately otherwise (rules 3 and 6): the Rust core kept 50 MB of chunks and let the least recently opened go;
  // the TS core keeps everything the stations it reaches hold (the sync brings it all), and lets go of a station's
  // only once no signed-in account reaches it (retain, above). Here: nothing goes for being opened less.
  const { host, runner, data } = fresh();
  for (const id of ["1", "2", "3"]) await run(data.putItems("entry", "ws/st", id, entries(1, 100)));
  await run(data.written);
  const again = new Data(host, runner);
  for (const id of ["1", "2", "3"]) assert.equal((await run(again.log("entry", "ws/st", id))).size, 100);
  runner.shutdown();
});

test("a_station_out_of_reach_is_forgotten", async () => {
  const { host, runner, data } = fresh();
  await run(data.putItems("entry", "ws/st", "1", entries(1, 2)));
  await run(data.putItems("transcript", "ws/st", "k", [[0, "x"]]));
  await run(data.putItems("entry", "other/st", "1", entries(1, 2)));
  await run(data.putItems("entry", "third/st", "1", entries(1, 2)));
  await run(data.written);
  data.retain((station) => station !== "ws/st", null);
  await host.time.pass(50);
  await run(data.written);
  const again = new Data(host, runner);
  assert.equal((await run(again.log("entry", "ws/st", "1"))).size, 0);
  assert.equal((await run(again.log("transcript", "ws/st", "k"))).size, 0);
  assert.equal((await run(again.log("entry", "other/st", "1"))).size, 2);
  await run(again.forgetLog("entry", "other/st", "1"));
  await run(again.written);
  const third = new Data(host, runner);
  assert.equal((await run(third.log("entry", "other/st", "1"))).size, 0);
  assert.equal((await run(third.log("entry", "third/st", "1"))).size, 2);
  runner.shutdown();
});

test("operations_run_in_the_order_they_were_asked_for", async () => {
  const { host, runner, data } = fresh();
  // Asked for in order, awaited the other way round: written in the order asked (one writer).
  const first = run(data.putItems("entry", "ws/st", "7", entries(1, 10)));
  const second = run(data.putItems("entry", "ws/st", "7", entries(11, 20)));
  await Promise.all([second, first]);
  await run(data.forgetLog("entry", "ws/st", "7"));
  await run(data.putItems("entry", "ws/st", "7", entries(1, 3)));
  await run(data.written);
  assert.deepEqual(host.dbKeys("entry").length, 3);
  const again = new Data(host, runner);
  assert.deepEqual(numbers(await run(again.log("entry", "ws/st", "7"))), range(1, 3));
  runner.shutdown();
});
