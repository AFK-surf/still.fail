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

test("update_replaces_the_value_and_skips_topics_without_a_value", async () => {
  const { host, store, pass } = setup();
  const session: Topic = { topic: "session", station: "ws/st", key: "k" };
  store.subscribe(1, 1, session);
  store.update(session, () => assert.fail("no value yet"));
  store.set(session, { err: new CoreError("x", "出错") });
  store.update(session, () => assert.fail("an error is not a value"));
  store.set(session, { ok: { timeline: [1] } });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.update(session, (v) => ({ timeline: [...(v as { timeline: number[] }).timeline, 2] }));
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
    return { ...x, timeline: [...x.timeline, "message 50"], usage: { ...x.usage, n: 51 } };
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
    [1, value(2, "s")],
    [1, value(1, "o")],
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

test("what_the_store_keeps_is_frozen_all_through_in_tests", async () => {
  const { store, source, pass } = setup();
  const sessions: Topic = { topic: "sessions", station: "ws/st" };
  store.subscribe(1, 1, overview());
  store.subscribe(1, 2, sessions);
  store.set(overview(), { ok: { n: { m: [1] } } });
  source.computed = { ok: { rows: [{ id: "a" }] } };
  store.invalidate(sessions);
  await pass(COALESCE_MS * 2);
  const kept = store.get(overview()) as { n: { m: number[] } };
  const made = store.get(sessions) as { rows: { id: string }[] };
  assert.ok(Object.isFrozen(kept.n.m) && Object.isFrozen(made.rows[0]));
  // Changed only by a new value.
  assert.throws(() => kept.n.m.push(2), TypeError);
  store.update(overview(), (v) => ({ n: { m: [...(v as typeof kept).n.m, 2] } }));
  assert.deepEqual(store.get(overview()), { n: { m: [1, 2] } });
});

test("a_value_its_source_fails_to_make_fails_its_topic_not_the_core", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const defects: unknown[] = [];
  runner.onDefect = (e) => defects.push(e);
  const store = new Store(host, runner);
  const sessions: Topic = { topic: "sessions", station: "ws/st" };
  const kept = Object.freeze({ attachments: Object.freeze([Object.freeze({ path: "/a.png" })]) });
  let broken = true;
  store.setSource({
    start() {},
    stop() {},
    // As #265's chat view did: a write on what the core keeps frozen.
    compute: () => {
      if (broken) (kept.attachments[0] as { owner?: string }).owner = "k";
      return { ok: { rows: 1 } };
    },
  });
  store.subscribe(1, 1, sessions);
  store.subscribe(1, 2, overview());
  store.invalidate(sessions);
  store.set(overview(), { ok: 1 });
  const error = console.error;
  console.error = () => {};
  await host.time.pass(COALESCE_MS * 2, 10);
  console.error = error;
  const sent = host.takeEmitted() as [number, { id: number; error?: { code: string; message: string }; value?: unknown }][];
  const bad = sent.find(([, m]) => m.id === 1)?.[1];
  assert.equal(bad?.error?.code, "internal");
  assert.match(bad?.error?.message ?? "", /not extensible/);
  assert.deepEqual(sent.find(([, m]) => m.id === 2)?.[1], value(2, 1));
  assert.deepEqual(defects, []);
  // Made again once it can be.
  broken = false;
  store.invalidate(sessions);
  await host.time.pass(COALESCE_MS * 2, 10);
  assert.deepEqual(host.takeEmitted(), [[1, value(1, { rows: 1 })]]);
});

test("rounds_that_held_the_core_are_told_at_most_once_a_minute_with_how_many_and_the_worst", async () => {
  // One a round was 1375 spans a phone sent in two hours, more than all else it sent (2026-10-31).
  const host = new FakeHost();
  const told: Record<string, unknown>[] = [];
  const tracer = {
    root: () => {
      const attrs: Record<string, unknown> = {};
      return { set: (k: string, v: unknown) => void (attrs[k] = v), end: () => void told.push(attrs) };
    },
  };
  const store = new Store(host, new Runner(host.time.clock), tracer as never);
  // The first topic holds the core for 60 ms; the second runs in a separate turn.
  let extra = 0;
  const mono = host.monotonicMs.bind(host);
  host.monotonicMs = () => mono() + extra;
  store.setSource({ start() {}, stop() {}, compute: (topic) => ((extra += topic.topic === "a" ? 60 : 0), { ok: extra }) });
  const topics = [{ topic: "a" }, { topic: "b" }];
  topics.forEach((t, i) => store.subscribe(1, i + 1, t));
  for (const t of topics) store.invalidate(t);
  await host.time.pass(COALESCE_MS * 2, 10);
  assert.equal(told.length, 1, "the first at once");
  for (let i = 0; i < 20; i++) {
    for (const t of topics) store.invalidate(t);
    await host.time.pass(COALESCE_MS * 2, 10);
  }
  assert.equal(told.length, 1, "not each round");
  await host.time.pass(60_000, 1000);
  for (const t of topics) store.invalidate(t);
  await host.time.pass(COALESCE_MS * 2, 10);
  assert.equal(told.length, 2);
  assert.equal(told[1]!["stillfail.rounds"], 21);
  assert.equal(told[1]!["stillfail.held_ms"], 60);
});

test("a_change_during_computation_is_eventually_shown", async () => {
  const { host, store, pass } = setup();
  const page: Topic = { topic: "page" };
  let computations = 0;
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      if (topic.topic !== "page") return undefined;
      computations++;
      if (computations === 1) store.invalidate(page);
      return { ok: computations };
    },
  });
  store.subscribe(1, 1, page);
  store.invalidate(page);
  await pass(COALESCE_MS * 4);
  const shown = host.takeEmitted().filter(([, message]) => message.id === 1);
  assert.deepEqual(shown.at(-1), [1, value(1, 2)]);
  assert.equal(store.get(page), 2);
  assert.equal(computations, 2);
});

test("a_new_page_gets_its_first_value_before_unrelated_updates_waiting_to_go_out", async () => {
  const { host, store, pass } = setup();
  const chat: Topic = { topic: "chat", station: "ws/st", thread: 7 };
  store.subscribe(1, 1, overview());
  store.set(overview(), { ok: "before" });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.set(overview(), { ok: "changed" });
  store.subscribe(1, 2, chat);
  store.set(chat, { ok: "opened" });
  await pass(COALESCE_MS * 2);
  const sent = host.takeEmitted();
  assert.deepEqual(sent[0], [1, value(2, "opened")], "the new page is not held behind a background update");
  assert.deepEqual(sent[1], [1, value(1, "changed")], "the update still goes out");
});

test("a_new_page_reads_its_pending_dependency_before_giving_its_first_value", async () => {
  const { host, store, pass } = setup();
  const dependency: Topic = { topic: "dependency" };
  const page: Topic = { topic: "page" };
  let current = "before";
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      if (topic.topic === "dependency") return { ok: current };
      if (topic.topic === "page") return { ok: store.get(dependency) };
      return undefined;
    },
  });
  store.subscribe(1, 1, dependency);
  store.invalidate(dependency);
  await pass(COALESCE_MS * 2);
  host.takeEmitted();

  // The dependency is due for recomputation but has not gone out when the page opens. Giving the page priority must
  // not make its first value from the dependency's previous value.
  current = "after";
  store.invalidate(dependency);
  store.subscribe(1, 2, page);
  store.invalidate(page);
  await pass(COALESCE_MS * 2);
  const messages = host.takeEmitted();
  assert.deepEqual(messages.find(([, message]) => message.id === 2), [1, value(2, "after")]);
});

test("a_new_page_reads_through_pending_dependencies_before_giving_its_first_value", async () => {
  const { host, store, pass } = setup();
  const base: Topic = { topic: "base" };
  const middle: Topic = { topic: "middle" };
  const page: Topic = { topic: "page" };
  let current = "before";
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      if (topic.topic === "base") return { ok: current };
      if (topic.topic === "middle") return { ok: store.get(base) };
      if (topic.topic === "page") return { ok: store.get(middle) };
      return undefined;
    },
  });
  store.subscribe(1, 1, base);
  store.subscribe(1, 2, middle);
  const baseWatch = store.watch(base, () => store.invalidate(middle));
  const middleWatch = store.watch(middle, () => store.invalidate(page));
  store.invalidate(base);
  store.invalidate(middle);
  await pass(COALESCE_MS * 3);
  host.takeEmitted();

  current = "after";
  store.invalidate(base);
  store.subscribe(1, 3, page);
  store.invalidate(page);
  await pass(COALESCE_MS * 4);
  const firstPage = host.takeEmitted().find(([, message]) => message.id === 3);
  assert.deepEqual(firstPage, [1, value(3, "after")]);
  baseWatch.drop();
  middleWatch.drop();
});

test("a_dependency_read_for_a_new_page_still_reaches_its_other_watchers", async () => {
  const { host, store, pass } = setup();
  const dependency: Topic = { topic: "dependency" };
  const page: Topic = { topic: "page" };
  const heard: unknown[] = [];
  let current = "before";
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      if (topic.topic === "dependency") return { ok: current };
      if (topic.topic === "page") return { ok: store.get(dependency) };
      return undefined;
    },
  });
  store.subscribe(1, 1, dependency);
  const watcher = store.watch(dependency, () => heard.push(store.get(dependency)));
  store.invalidate(dependency);
  await pass(COALESCE_MS * 2);
  heard.length = 0;
  host.takeEmitted();

  current = "after";
  store.invalidate(dependency);
  store.subscribe(1, 2, page);
  store.invalidate(page);
  await pass(COALESCE_MS * 3);
  const messages = host.takeEmitted();
  assert.deepEqual(messages.find(([, message]) => message.id === 2), [1, value(2, "after")]);
  assert.deepEqual(messages.find(([, message]) => message.id === 1), [1, value(1, "after")]);
  assert.deepEqual(heard, ["after"]);
  watcher.drop();
});

test("a_reopened_page_shows_its_cache_then_the_pending_dependency_update", async () => {
  const { host, store, pass } = setup();
  const dependency: Topic = { topic: "dependency" };
  const page: Topic = { topic: "page" };
  let current = "before";
  store.setSource({
    start(topic) {
      if (topic.topic === "page") {
        store.watch(dependency, () => store.invalidate(page));
        store.invalidate(page);
      }
    },
    stop() {},
    compute(topic) {
      if (topic.topic === "dependency") return { ok: current };
      if (topic.topic === "page") return { ok: store.get(dependency) };
      return undefined;
    },
  });
  store.subscribe(1, 1, dependency);
  store.invalidate(dependency);
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 2, page);
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.unsubscribe(1, 2);

  current = "after";
  store.invalidate(dependency);
  store.subscribe(1, 3, page);
  const reopened = host.takeEmitted().find(([, message]) => message.id === 3);
  assert.deepEqual(reopened, [1, value(3, "before")], "the previously shown value is available at once");
  await pass(COALESCE_MS * 3);
  const changed = host.takeEmitted().find(([, message]) => message.id === 3);
  assert.deepEqual(changed, [1, value(3, "after")], "the pending dependency reaches it too");
});

test("a_nested_computation_can_fail_and_recover_without_stopping_other_topics", async () => {
  const { host, store, pass } = setup();
  const base: Topic = { topic: "base" };
  const middle: Topic = { topic: "middle" };
  const page: Topic = { topic: "page" };
  const other: Topic = { topic: "other" };
  let broken = false;
  store.setSource({
    start() {}, stop() {},
    compute(topic) {
      if (topic.topic === "base") {
        if (broken) throw Error("base failed");
        return { ok: 1 };
      }
      if (topic.topic === "middle") return store.value(base);
      if (topic.topic === "page") return store.value(middle);
      return undefined;
    },
  });
  const baseWatch = store.watch(base, () => store.invalidate(middle));
  const middleWatch = store.watch(middle, () => store.invalidate(page));
  store.subscribe(1, 1, page);
  store.subscribe(1, 2, other);
  store.invalidate(base);
  store.invalidate(middle);
  store.invalidate(page);
  store.set(other, { ok: 0 });
  await pass(COALESCE_MS * 4);
  host.takeEmitted();
  const error = console.error;
  console.error = () => {};
  try {
    broken = true;
    store.invalidate(base);
    store.set(other, { ok: 1 });
    await pass(COALESCE_MS * 4);
    const failed = host.takeEmitted();
    const message = failed.find(([, m]) => m.id === 1)?.[1];
    assert.ok(message && "error" in message && message.error.code === "internal");
    assert.deepEqual(failed.find(([, m]) => m.id === 2), [1, value(2, 1)]);
    broken = false;
    store.invalidate(base);
    await pass(COALESCE_MS * 4);
    assert.deepEqual(host.takeEmitted().find(([, m]) => m.id === 1), [1, value(1, 1)]);
  } finally {
    console.error = error;
    baseWatch.drop();
    middleWatch.drop();
  }
});

test("new_pages_and_background_updates_both_get_a_turn", async () => {
  const { store, pass } = setup();
  const first: Topic = { topic: "first" };
  const background: Topic = { topic: "background" };
  const pages: Topic[] = [{ topic: "page1" }, { topic: "page2" }, { topic: "page3" }];
  const order: string[] = [];
  const open = (index: number) => {
    store.subscribe(1, index + 3, pages[index]!);
    store.invalidate(pages[index]!);
  };
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      order.push(topic.topic);
      if (topic.topic === "first") open(0);
      const index = pages.findIndex((page) => page.topic === topic.topic);
      if (index >= 0 && index < pages.length - 1) open(index + 1);
      return { ok: topic.topic };
    },
  });
  store.subscribe(1, 1, first);
  store.subscribe(1, 2, background);
  store.set(first, { ok: "old first" });
  store.set(background, { ok: "old background" });
  await pass(COALESCE_MS * 2);
  store.invalidate(first);
  store.invalidate(background);
  await pass(COALESCE_MS * 4);
  assert.deepEqual(order, ["first", "page1", "background", "page2", "page3"]);
});
