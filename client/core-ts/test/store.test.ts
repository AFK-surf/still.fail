// The Rust core's store.rs tests, ported (same names, same checks): time on a TestClock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { CoreError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { COALESCE_MS, EVICT_AFTER_MS, Store, type Source, type Value } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { topicDebug } from "../src/protocol.ts";

holdLanguage();

class Recorder implements Source {
  calls: string[] = [];
  computed: Value | undefined = undefined;
  start(topic: Topic) {
    this.calls.push(`start ${topicDebug(topic)}`);
  }
  stop(topic: Topic) {
    this.calls.push(`stop ${topicDebug(topic)}`);
  }
  compute(topic: Topic) {
    this.calls.push(`compute ${topicDebug(topic)}`);
    return this.computed;
  }
  take() {
    const c = this.calls;
    this.calls = [];
    return c;
  }
}

function setup() {
  const host = new FakeHost();
  const store = new Store(host, new Runner(host.time.clock));
  const source = new Recorder();
  store.setSource(source);
  const pass = (ms: number) => host.time.pass(ms, ms > 1000 ? 100 : 10);
  return { host, store, source, pass };
}

const overview = (): Topic => ({ topic: "overview", station: "ws/st" });
const value = (id: number, v: unknown) => ({ id, value: v });

test("starts_once_and_emits_to_every_subscriber", async () => {
  const { host, store, source, pass } = setup();
  store.subscribe(1, 10, overview());
  store.subscribe(2, 20, overview());
  assert.deepEqual(source.take(), [`start ${topicDebug(overview())}`]);
  assert.deepEqual(host.takeEmitted(), []);
  store.set(overview(), { ok: { n: 1 } });
  assert.deepEqual(host.takeEmitted(), [], "emission waits for the coalescing window");
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [
    [1, value(10, { n: 1 })],
    [2, value(20, { n: 1 })],
  ]);
  assert.deepEqual(store.get(overview()), { n: 1 });
  assert.deepEqual(store.liveTopics(), [overview()]);
});

test("coalesces_changes_into_one_emission", async () => {
  const { host, store, pass } = setup();
  store.subscribe(1, 10, overview());
  for (let n = 0; n < 5; n++) store.set(overview(), { ok: n });
  store.update(overview(), (v) => (v as number) * 10);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(10, 40)]]);
  store.set(overview(), { ok: "again" });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(10, "again")]]);
});

test("sends_the_cached_value_or_error_at_once", async () => {
  const { host, store, source, pass } = setup();
  store.subscribe(1, 10, overview());
  store.set(overview(), { ok: { cached: true } });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.subscribe(2, 5, overview());
  assert.deepEqual(host.takeEmitted(), [[2, value(5, { cached: true })]]);
  const error = new CoreError("offline", "连不上");
  store.set(overview(), { err: error });
  await pass(COALESCE_MS * 2);
  assert.equal(host.takeEmitted().length, 2);
  assert.equal(store.get(overview()), undefined);
  store.subscribe(3, 7, overview());
  assert.deepEqual(host.takeEmitted(), [[3, { id: 7, error: { code: "offline", message: "连不上" } }]]);
  assert.equal(source.take().length, 1, "only the first subscriber starts the topic");
});

test("evicts_a_minute_after_the_last_subscriber_leaves", async () => {
  const { host, store, source, pass } = setup();
  store.subscribe(1, 10, overview());
  store.set(overview(), { ok: 1 });
  await pass(COALESCE_MS * 2);
  source.take();
  host.takeEmitted();
  store.unsubscribe(1, 10);
  await pass(EVICT_AFTER_MS / 2);
  assert.deepEqual(source.take(), []);
  assert.equal(store.get(overview()), 1, "cached through the grace period");
  store.subscribe(1, 11, overview());
  assert.deepEqual(host.takeEmitted(), [[1, value(11, 1)]]);
  await pass((EVICT_AFTER_MS * 3) / 4);
  assert.deepEqual(source.take(), []);
  store.unsubscribe(1, 11);
  await pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4);
  assert.deepEqual(source.take(), [`stop ${topicDebug(overview())}`]);
  assert.equal(store.get(overview()), undefined);
  assert.deepEqual(store.liveTopics(), []);
  store.set(overview(), { ok: "late" });
  assert.deepEqual(store.liveTopics(), []);
  store.subscribe(1, 12, overview());
  assert.deepEqual(host.takeEmitted(), []);
  assert.deepEqual(source.take(), [`start ${topicDebug(overview())}`]);
});

test("drop_client_ends_all_its_subscriptions", async () => {
  const { host, store, source, pass } = setup();
  const sessions: Topic = { topic: "sessions", station: "ws/st" };
  store.subscribe(1, 1, overview());
  store.subscribe(1, 2, sessions);
  store.subscribe(2, 1, sessions);
  source.take();
  store.dropClient(1);
  store.set(overview(), { ok: "o" });
  store.set(sessions, { ok: "s" });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[2, value(1, "s")]]);
  await pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4);
  assert.deepEqual(source.take(), [`stop ${topicDebug(overview())}`]);
  assert.deepEqual(store.liveTopics(), [sessions]);
});

test("update_changes_in_place_and_skips_topics_without_a_value", async () => {
  const { host, store, pass } = setup();
  const session: Topic = { topic: "session", station: "ws/st", key: "k" };
  store.subscribe(1, 1, session);
  store.update(session, () => assert.fail("no value yet"));
  store.set(session, { err: new CoreError("x", "出错了") });
  store.update(session, () => assert.fail("an error is not a value"));
  store.set(session, { ok: { timeline: [1] } });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.update(session, (v) => {
    (v as { timeline: number[] }).timeline.push(2);
  });
  assert.deepEqual(store.get(session), { timeline: [1, 2] });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(1, { timeline: [1, 2] })]]);
});

test("reusing_a_request_id_replaces_the_subscription", async () => {
  const { host, store, source, pass } = setup();
  const sessions: Topic = { topic: "sessions", station: "ws/st" };
  store.subscribe(1, 1, overview());
  store.subscribe(1, 1, sessions);
  source.take();
  store.set(overview(), { ok: "o" });
  store.set(sessions, { ok: "s" });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(1, "s")]]);
  store.unsubscribe(1, 1);
  store.unsubscribe(1, 1);
  await pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4);
  const stopped = source.take().sort();
  assert.deepEqual(stopped, [`stop ${topicDebug(overview())}`, `stop ${topicDebug(sessions)}`].sort());
});

const long = (n: number) => ({ timeline: Array.from({ length: n }, (_, i) => `message ${i}`), usage: { n } });

test("sends_what_changed_after_the_first_value", async () => {
  const { host, store, pass } = setup();
  const session: Topic = { topic: "session", station: "ws/st", key: "k" };
  store.subscribe(1, 1, session);
  store.set(session, { ok: long(50) });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(1, long(50))]]);
  store.update(session, (v) => {
    const x = v as { timeline: string[]; usage: { n: number } };
    x.timeline.push("message 50");
    x.usage.n = 51;
  });
  store.subscribe(2, 7, session);
  assert.deepEqual(host.takeEmitted(), [[2, value(7, long(50))]]);
  await pass(COALESCE_MS * 2);
  const ops = [
    { path: ["timeline"], append: ["message 50"] },
    { path: ["usage", "n"], set: 51 },
  ];
  assert.deepEqual(host.takeEmitted(), [
    [1, { id: 1, delta: ops }],
    [2, { id: 7, delta: ops }],
  ]);
  store.subscribe(3, 1, session);
  assert.deepEqual(host.takeEmitted(), [[3, value(1, long(51))]]);
  store.set(session, { ok: long(51) });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), []);
  store.set(session, { err: new CoreError("offline", "连不上") });
  await pass(COALESCE_MS * 2);
  assert.equal(host.takeEmitted().length, 3);
  store.set(session, { ok: long(52) });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [
    [1, value(1, long(52))],
    [2, value(7, long(52))],
    [3, value(1, long(52))],
  ]);
  store.set(session, { ok: { timeline: [] } });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted()[0], [1, value(1, { timeline: [] })]);
});

test("a_watch_keeps_a_topic_live_and_hears_its_changes", async () => {
  const { host, store, source, pass } = setup();
  const heard: unknown[] = [];
  const watch = store.watch(overview(), () => heard.push(store.get(overview())));
  assert.deepEqual(source.take(), [`start ${topicDebug(overview())}`]);
  store.set(overview(), { ok: 1 });
  assert.deepEqual(heard, [1], "at once, not after the coalescing window");
  store.update(overview(), () => 2);
  assert.equal(heard.length, 2);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [], "a watch is not a UI");
  store.subscribe(1, 1, overview());
  store.unsubscribe(1, 1);
  await pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4);
  assert.deepEqual(source.take(), []);
  assert.deepEqual(store.liveTopics(), [overview()]);
  watch.drop();
  await pass(EVICT_AFTER_MS / 2);
  assert.equal(store.get(overview()), 2, "cached through the grace period");
  await pass((EVICT_AFTER_MS * 3) / 4);
  assert.deepEqual(source.take(), [`stop ${topicDebug(overview())}`]);
  assert.deepEqual(store.liveTopics(), []);
  assert.equal(heard.length, 2);
});

test("an_invalidated_topic_is_computed_once_as_it_goes_out", async () => {
  const { host, store, source, pass } = setup();
  const chats: Topic = { topic: "chats", scope: "ws", mine: false };
  store.subscribe(1, 1, chats);
  source.take();
  store.invalidate(chats);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(source.take(), [`compute ${topicDebug(chats)}`]);
  assert.deepEqual(host.takeEmitted(), []);
  source.computed = { ok: { n: 1 } };
  for (let i = 0; i < 5; i++) store.invalidate(chats);
  assert.deepEqual(source.take(), [], "computed when it goes out");
  await pass(COALESCE_MS * 2);
  assert.deepEqual(source.take(), [`compute ${topicDebug(chats)}`]);
  assert.deepEqual(host.takeEmitted(), [[1, value(1, { n: 1 })]]);
  assert.deepEqual(store.get(chats), { n: 1 });
  store.invalidate(chats);
  await pass(COALESCE_MS * 2);
  assert.equal(source.take().length, 1);
  assert.deepEqual(host.takeEmitted(), []);
});

test("topics_changed_together_go_out_together_in_order", async () => {
  const { host, store, pass } = setup();
  const session: Topic = { topic: "session", station: "ws/st", key: "k" };
  const live: Topic = { topic: "live", station: "ws/st", key: "k" };
  store.subscribe(1, 1, overview());
  store.subscribe(1, 2, session);
  store.subscribe(1, 3, live);
  store.set(overview(), { ok: "o0" });
  store.set(session, { ok: "s0" });
  store.set(live, { ok: "l0" });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.set(overview(), { ok: "o" });
  await pass(COALESCE_MS / 2);
  store.set(session, { ok: "s" });
  store.set(live, { ok: "l" });
  await pass((COALESCE_MS * 3) / 4);
  assert.deepEqual(host.takeEmitted(), [
    [1, value(1, "o")],
    [1, value(2, "s")],
    [1, value(3, "l")],
  ]);
});

test("a_first_value_goes_out_without_waiting_the_window", async () => {
  const { host, store, pass } = setup();
  const session: Topic = { topic: "session", station: "ws/st", key: "k" };
  store.subscribe(1, 1, overview());
  store.set(overview(), { ok: "o0" });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.subscribe(1, 2, session);
  store.set(overview(), { ok: "o" });
  store.set(session, { ok: "s" });
  await pass(COALESCE_MS / 5);
  assert.deepEqual(host.takeEmitted(), [
    [1, value(1, "o")],
    [1, value(2, "s")],
  ]);
});

test("a_keyed_subscriber_gets_keyed_ops_and_the_others_the_old_ones", async () => {
  const { host, store, pass } = setup();
  const rows: Topic = { topic: "chatRows", station: "ws/st" };
  store.subscribe(1, 10, rows, true);
  store.subscribe(2, 20, rows);
  const list = Array.from({ length: 50 }, (_, i) => ({ id: `t${i}`, title: `chat ${i}` }));
  store.set(rows, { ok: list });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.set(rows, { ok: [list[30], ...list.filter((_, i) => i !== 30)] });
  await pass(COALESCE_MS * 2);
  const [[c1, keyed], [c2, old]] = host.takeEmitted() as [number, { id: number; delta?: unknown; value?: unknown }][];
  assert.equal(c1, 1);
  assert.deepEqual(keyed, { id: 10, delta: [{ path: [], key: ["id"], move: "t30", before: "t0" }] });
  assert.equal(c2, 2);
  assert.ok(Array.isArray(old.delta) || "value" in old);
});
