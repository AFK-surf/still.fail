// The Rust core's store.rs tests, ported (same names, same checks): time on a TestClock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { apply as applyOps, type Op } from "../src/delta.ts";
import { applyKeyed, type AnyOp } from "../src/collections.ts";
import { CoreError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import { Output } from "../src/output.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { COALESCE_MS, EVICT_AFTER_MS, KEPT_PER_CLIENT, Store, type Source, type Value } from "../src/store.ts";
import { FakeHost, flush } from "../src/testing.ts";
import { token, version } from "../src/digest.ts";
import { work } from "../src/work.ts";
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

test("a_topic_only_watched_inside_the_core_is_formatted_when_a_page_asks_for_it", async () => {
  const { host, store, pass } = setup();
  const stations: Topic = { topic: "stations", scope: "ws" };
  const heard: unknown[] = [];
  const shape = Output.prototype.shape;
  let formatted = 0;
  Output.prototype.shape = function (topic, ...args) {
    if (topic.topic === "stations") formatted++;
    return shape.call(this, topic, ...args);
  };
  const watch = store.watch(stations, () => heard.push(store.get(stations)));
  try {
    store.set(stations, { ok: [{ id: "a", name: "first" }] });
    await pass(COALESCE_MS * 2);
    assert.deepEqual(heard, [[{ id: "a", name: "first" }]]);
    assert.equal(formatted, 0, "a value read only by another page needs no client output");
    assert.deepEqual(host.takeEmitted(), []);

    store.subscribe(1, 1, stations);
    await pass(COALESCE_MS * 2);
    assert.deepEqual(host.takeEmitted(), [[1, value(1, [{ id: "a", name: "first" }])]]);
    assert.equal(formatted, 1);

    store.unsubscribe(1, 1);
    store.set(stations, { ok: [{ id: "a", name: "second" }] });
    await pass(COALESCE_MS * 2);
    assert.deepEqual(heard.at(-1), [{ id: "a", name: "second" }]);
    assert.equal(formatted, 1, "a closed page is not formatted while its cache is kept");

    store.subscribe(1, 2, stations);
    const messages = host.takeEmitted();
    await pass(COALESCE_MS * 2);
    messages.push(...host.takeEmitted());
    let shown: unknown;
    for (const [, message] of messages) {
      const m = message as { value?: unknown; delta?: Op[] };
      if ("value" in m) shown = m.value;
      else if (m.delta) shown = applyOps(shown, m.delta);
    }
    assert.deepEqual(shown, [{ id: "a", name: "second" }]);
  } finally {
    watch.drop();
    Output.prototype.shape = shape;
  }
});

test("a_closed_page_is_not_formatted_until_it_is_opened_again", async () => {
  const { host, store, pass } = setup();
  const page: Topic = { topic: "page" };
  const shape = Output.prototype.shape;
  let formatted = 0;
  Output.prototype.shape = function (topic, ...args) {
    if (topic.topic === "page") formatted++;
    return shape.call(this, topic, ...args);
  };
  try {
    store.subscribe(1, 1, page);
    store.set(page, { ok: { name: "first" } });
    await pass(COALESCE_MS * 2);
    assert.deepEqual(host.takeEmitted(), [[1, value(1, { name: "first" })]]);
    assert.equal(formatted, 1);

    store.unsubscribe(1, 1);
    store.set(page, { ok: { name: "second" } });
    await pass(COALESCE_MS * 2);
    assert.equal(formatted, 1, "nothing is formatting a page that nobody is viewing");
    assert.deepEqual(host.takeEmitted(), []);

    store.subscribe(1, 2, page);
    let shown: unknown;
    const messages = host.takeEmitted();
    assert.equal(messages.length, 0, "a reopened page is not sent a stale value while its current one is prepared");
    await pass(COALESCE_MS * 2);
    messages.push(...host.takeEmitted());
    for (const [, message] of messages) {
      const m = message as { value?: unknown; delta?: Op[] };
      if ("value" in m) shown = m.value;
      else if (m.delta) shown = applyOps(shown, m.delta);
    }
    assert.deepEqual(shown, { name: "second" }, "reopening shows the latest value");
  } finally {
    Output.prototype.shape = shape;
  }
});

test("a_reopened_held_page_catches_up_with_changes_while_closed", async () => {
  const { host, store, pass } = setup();
  let held: unknown = { name: "first" };
  store.setHeld((topic) => topic.topic === "overview" ? held : undefined);
  store.subscribe(1, 1, overview());
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(1, { name: "first" })]]);
  store.unsubscribe(1, 1);

  held = { name: "second" };
  store.changed(overview());
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 2, overview());
  const messages = host.takeEmitted();
  assert.equal(messages.length, 0, "a reopened held value is not sent an outdated snapshot");
  await pass(COALESCE_MS * 2);
  messages.push(...host.takeEmitted());
  let shown: unknown;
  for (const [, message] of messages) {
    const m = message as { value?: unknown; delta?: Op[] };
    if ("value" in m) shown = m.value;
    else if (m.delta) shown = applyOps(shown, m.delta);
  }
  assert.deepEqual(shown, { name: "second" }, "a held value changed while the page was closed");
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

test("a_subscriber_from_another_of_its_subscriptions_gets_its_first_value_as_what_changed_from_that_ones", async () => {
  const { host, store, pass } = setup();
  const rows = (limit: number): Topic => ({ topic: "chatRows", station: "ws/st", limit });
  const list = Array.from({ length: 100 }, (_, i) => ({ id: `t${i}`, title: `chat ${i}` }));
  store.subscribe(1, 10, rows(50), true);
  store.set(rows(50), { ok: list.slice(0, 50) });
  await pass(COALESCE_MS * 2);
  const [[, first]] = host.takeEmitted() as [number, { value: unknown }][];
  // (more of them asked: a new subscription from the first, which the client holds till it answers)
  store.subscribe(1, 11, rows(100), true, 10);
  store.set(rows(100), { ok: list });
  await pass(COALESCE_MS * 2);
  const [[c, more]] = host.takeEmitted() as [number, { id: number; delta: AnyOp[]; from: number }][];
  assert.equal(c, 1);
  assert.equal(more.id, 11);
  assert.equal(more.from, 10);
  assert.deepEqual(applyKeyed(first.value, more.delta), list);
  // (one not keyed, or from one it does not have: whole)
  store.subscribe(1, 12, rows(100), true, 99);
  assert.deepEqual(host.takeEmitted(), [[1, value(12, list)]]);
});

/// A token as the store gives a value object (digest.ts `token`): `<run>:<count>`, base 36.
const TOKEN = /^[0-9a-z]+:[0-9a-z]+$/;

test("an_unsubscribe_that_keeps_is_answered_with_the_version_of_what_its_subscriber_holds_its_last_message", async () => {
  const { host, store, pass } = setup();
  store.subscribe(1, 10, overview());
  store.set(overview(), { ok: { n: 1 } });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  // (a difference on its way as the unsubscribe comes: gone out before it, so what is held by the answer has it)
  store.set(overview(), { ok: { n: 2 } });
  await pass(COALESCE_MS * 2);
  store.unsubscribe(1, 10, true);
  const out = host.takeEmitted() as [number, Record<string, unknown>][];
  assert.equal(out.length, 2);
  assert.deepEqual(out[0], [1, value(10, { n: 2 })]);
  const said = out[1]![1] as { id: number; v: string };
  assert.equal(said.id, 10);
  assert.match(said.v, TOKEN);
  // (none further for it)
  store.set(overview(), { ok: { n: 3 } });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), []);
  // Not kept: no answer, nothing hashed.
  store.subscribe(1, 11, overview());
  host.takeEmitted();
  store.unsubscribe(1, 11);
  assert.deepEqual(host.takeEmitted(), []);
  // Kept of one that never had a value, or of an id unknown: answered still, with none.
  store.subscribe(1, 12, { topic: "overview", station: "ws/other" });
  store.unsubscribe(1, 12, true);
  store.unsubscribe(1, 99, true);
  assert.deepEqual(host.takeEmitted(), [
    [1, { id: 12, v: null }],
    [1, { id: 99, v: null }],
  ]);
});

test("a_change_not_gone_out_as_an_unsubscribe_that_keeps_comes_is_not_in_its_version_and_follows_a_same", async () => {
  const { host, store, pass } = setup();
  store.subscribe(1, 10, overview());
  store.set(overview(), { ok: { n: 1 } });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.set(overview(), { ok: { n: 2 } });
  // (not gone out yet: the client holds n 1)
  store.unsubscribe(1, 10, true);
  const [[, { v: held }]] = host.takeEmitted() as [number, { id: number; v: string }][];
  // Asked again with it before the change goes out: what it holds is still what went last, so `same`, and then the
  // change as to any subscriber.
  store.subscribe(1, 11, overview(), false, undefined, held);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [
    [1, { id: 11, same: true }],
    [1, value(11, { n: 2 })],
  ]);
});

test("a_subscription_asked_with_the_version_it_holds_is_answered_same_where_the_value_is_that_one", async () => {
  const { host, store, pass } = setup();
  const rows: Topic = { topic: "chatRows", station: "ws/st" };
  const list = [{ id: "a", title: "A" }, { id: "b", title: "B" }];
  store.subscribe(1, 10, rows, true);
  store.set(rows, { ok: list });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.unsubscribe(1, 10, true);
  const [[, { v }]] = host.takeEmitted() as [number, { v: string }][];
  // Still held (idle): answered at once.
  store.subscribe(1, 11, rows, true, undefined, v);
  assert.deepEqual(host.takeEmitted(), [[1, { id: 11, same: true }]]);
  // Then on as any subscriber: what changes goes as keyed ops to what it holds.
  store.set(rows, { ok: [...list, { id: "c", title: "C" }] });
  await pass(COALESCE_MS * 2);
  const [[, next]] = host.takeEmitted() as [number, { id: number; delta: AnyOp[] }][];
  assert.equal(next.id, 11);
  assert.deepEqual(applyKeyed(list, next.delta), [...list, { id: "c", title: "C" }]);
  // A version of another value: whole.
  store.unsubscribe(1, 11);
  store.subscribe(1, 12, rows, true, undefined, v);
  assert.deepEqual(host.takeEmitted(), [[1, value(12, [...list, { id: "c", title: "C" }])]]);
  store.unsubscribe(1, 12);
  // Let go of and dropped from the store, nothing of it remembered for the client (its `same` above took it): made
  // again equal, it is another object, so another token: whole (a token names the value object, never its content).
  await pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4);
  assert.deepEqual(store.liveTopics(), []);
  store.subscribe(1, 13, rows, true, undefined, v);
  store.set(rows, { ok: list.map((r) => ({ ...r })) });
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(13, list)]]);
});

/// Subscribes `client`'s `id` to `topic`, lets its value `v` go out, and lets go of it keeping it: the version said.
async function keptAt(t: ReturnType<typeof setup>, client: number, id: number, topic: Topic, v: unknown, keyed: boolean): Promise<string> {
  t.store.subscribe(client, id, topic, keyed);
  t.store.set(topic, { ok: v });
  await t.pass(COALESCE_MS * 2);
  t.host.takeEmitted();
  t.store.unsubscribe(client, id, true);
  const out = t.host.takeEmitted() as [number, { id: number; v: string }][];
  assert.equal(out.length, 1);
  assert.deepEqual([out[0]![0], out[0]![1].id], [client, id]);
  assert.match(out[0]![1].v, TOKEN);
  return out[0]![1].v;
}

test("a_subscription_asked_again_with_a_version_the_core_remembers_gets_what_changed_from_it_keyed", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const rows: Topic = { topic: "chatRows", station: "ws/st" };
  const list = Array.from({ length: 40 }, (_, i) => ({ id: `r${i}`, title: `Row ${i} ${"words ".repeat(8)}` }));
  const v = await keptAt(t, 1, 10, rows, list, true);
  assert.equal(store.keptOf(1), 1);
  // One row changed and one added while nobody held it: what changed from the rows kept, keyed, not the 40 again.
  const next = [...list.slice(0, 5), { ...list[5]!, title: "Renamed" }, ...list.slice(6), { id: "new", title: "New" }];
  store.set(rows, { ok: next });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 11, rows, true, undefined, v);
  await pass(COALESCE_MS * 2);
  const [[, first]] = host.takeEmitted() as [number, { id: number; delta: AnyOp[]; kept: true }][];
  assert.equal(first.id, 11);
  assert.equal(first.kept, true);
  assert.deepEqual(applyKeyed(list, first.delta), next);
  // The same result as the value whole would give, and far lighter.
  assert.ok(JSON.stringify(first).length * 4 < JSON.stringify(value(11, next)).length);
  // Its first message gone, the core remembers none of it: asked with that version again, whole.
  assert.equal(store.keptOf(1), 0);
  store.unsubscribe(1, 11);
  store.subscribe(1, 12, rows, true, undefined, v);
  assert.deepEqual(host.takeEmitted(), [[1, value(12, next)]]);
});

test("a_subscription_asked_again_not_keyed_gets_plain_ops_from_what_the_core_remembers", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const was = { text: "x".repeat(400), n: 1 };
  const v = await keptAt(t, 1, 10, overview(), was, false);
  store.set(overview(), { ok: { ...was, n: 2 } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 11, overview(), false, undefined, v);
  await pass(COALESCE_MS * 2);
  const [[, first]] = host.takeEmitted() as [number, { id: number; delta: Op[]; kept: true }][];
  assert.deepEqual({ id: first.id, kept: first.kept }, { id: 11, kept: true });
  assert.deepEqual(applyOps(structuredClone(was), first.delta), { ...was, n: 2 });
  // Then on as any subscriber.
  store.set(overview(), { ok: { ...was, n: 3 } });
  await pass(COALESCE_MS * 2);
  const [[, then]] = host.takeEmitted() as [number, { id: number; delta: Op[] }][];
  assert.deepEqual(applyOps(structuredClone({ ...was, n: 2 }), then.delta), { ...was, n: 3 });
});

test("a_subscription_asked_again_goes_whole_where_what_changed_is_heavier_or_nothing_of_that_version_is_remembered", async () => {
  const t = setup();
  const { host, store, pass } = t;
  // What changed weighs more than the value: whole.
  const v = await keptAt(t, 1, 10, overview(), { n: 1 }, false);
  store.set(overview(), { ok: { n: 2 } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 11, overview(), false, undefined, v);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(11, { n: 2 })]]);
  assert.equal(store.keptOf(1), 0);
  store.unsubscribe(1, 11);
  // Another version than the one remembered: whole, and the remembered one forgotten all the same.
  const big = { text: "x".repeat(400), n: 1 };
  await keptAt(t, 1, 12, overview(), big, false);
  store.set(overview(), { ok: { ...big, n: 2 } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 13, overview(), false, undefined, version({ other: true }));
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(13, { ...big, n: 2 })]]);
  assert.equal(store.keptOf(1), 0);
  store.unsubscribe(1, 13);
  // Another client's: nothing remembered for this one.
  const w = await keptAt(t, 2, 20, overview(), big, false);
  store.set(overview(), { ok: { ...big, n: 3 } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 14, overview(), false, undefined, w);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(14, { ...big, n: 3 })]]);
  assert.equal(store.keptOf(2), 1);
  // An error now: the error, nothing else.
  store.set(overview(), { err: new CoreError("x", "gone") });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.subscribe(2, 21, overview(), false, undefined, w);
  const out = host.takeEmitted() as [number, Record<string, unknown>][];
  assert.equal(out.length, 1);
  assert.ok("error" in out[0]![1]);
  assert.equal(store.keptOf(2), 0);
});

test("a_subscription_asked_again_from_another_takes_that_ones_rows_before_what_was_kept", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const chats = (limit: number): Topic => ({ topic: "chatRows", station: "ws/st", limit });
  const list = Array.from({ length: 30 }, (_, i) => ({ id: `r${i}`, title: `Row ${i} ${"words ".repeat(8)}` }));
  const v = await keptAt(t, 1, 10, chats(50), list, true);
  // The first rows held; more of them asked from those, with the version kept as well: from the rows held.
  store.subscribe(1, 11, chats(20), true);
  store.set(chats(20), { ok: list.slice(0, 20) });
  store.set(chats(50), { ok: list });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.subscribe(1, 12, chats(50), true, 11, v);
  await pass(COALESCE_MS * 2);
  const [[, first]] = host.takeEmitted() as [number, Record<string, unknown>][];
  // (the value is that version still: `same` before either)
  assert.deepEqual(first, { id: 12, same: true });
  store.unsubscribe(1, 12, true);
  host.takeEmitted();
  const more = [...list, { id: "r30", title: "Row 30" }];
  store.set(chats(50), { ok: more });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 13, chats(50), true, 11, v);
  await pass(COALESCE_MS * 2);
  const [[, from]] = host.takeEmitted() as [number, { id: number; delta: AnyOp[]; from?: number; kept?: true }][];
  assert.equal(from.from, 11);
  assert.equal(from.kept, undefined);
  assert.deepEqual(applyKeyed(list.slice(0, 20), from.delta), more);
  assert.equal(store.keptOf(1), 0);
});

test("the_values_remembered_for_a_client_are_bounded_the_least_recently_let_go_of_forgotten_and_dropped_with_it", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const topic = (i: number): Topic => ({ topic: "overview", station: `ws/s${i}` });
  const big = (i: number) => ({ text: "x".repeat(400), n: i });
  const versions: string[] = [];
  for (let i = 0; i < KEPT_PER_CLIENT + 2; i++) versions.push(await keptAt(t, 1, 100 + i, topic(i), big(i), false));
  assert.equal(store.keptOf(1), KEPT_PER_CLIENT);
  for (let i = 0; i < KEPT_PER_CLIENT + 2; i++) store.set(topic(i), { ok: { ...big(i), m: true } });
  await pass(COALESCE_MS * 2);
  // The first two let go of are forgotten: whole. The third is remembered: what changed.
  store.subscribe(1, 200, topic(0), false, undefined, versions[0]);
  store.subscribe(1, 201, topic(1), false, undefined, versions[1]);
  store.subscribe(1, 202, topic(2), false, undefined, versions[2]);
  await pass(COALESCE_MS * 2);
  const out = (host.takeEmitted() as [number, { id: number }][]).sort((a, b) => a[1].id - b[1].id);
  assert.deepEqual(out.map(([, m]) => ("kept" in m ? "kept" : "value" in m ? "value" : "?")), ["value", "value", "kept"]);
  // A client gone: all of it forgotten.
  assert.equal(store.keptOf(1), KEPT_PER_CLIENT - 1);
  store.dropClient(1);
  assert.equal(store.keptOf(1), 0);
});

test("a_value_let_go_of_keeping_it_and_asked_again_unchanged_is_answered_same_nothing_of_it_hashed", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const rows: Topic = { topic: "chatRows", station: "ws/st" };
  const list = Array.from({ length: 40 }, (_, i) => ({ id: `r${i}`, title: `Row ${i}` }));
  const hashed = work.versions;
  const v = await keptAt(t, 1, 10, rows, list, true);
  store.subscribe(1, 11, rows, true, undefined, v);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, { id: 11, same: true }]]);
  // (a token is the value object's: nothing of it made canonical, nothing hashed, at either end)
  assert.equal(work.versions - hashed, 0);
});

test("a_value_evicted_and_made_again_equal_goes_as_what_changed_from_what_was_kept_which_is_nothing", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const rows: Topic = { topic: "chatRows", station: "ws/st" };
  const list = Array.from({ length: 40 }, (_, i) => ({ id: `r${i}`, title: `Row ${i} ${"words ".repeat(8)}` }));
  const hashed = work.versions;
  const v = await keptAt(t, 1, 10, rows, list, true);
  // Dropped from the store, the value it held remembered for the client (#kept): made again equal, another object.
  await pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4);
  assert.deepEqual(store.liveTopics(), []);
  assert.equal(store.keptOf(1), 1);
  store.subscribe(1, 11, rows, true, undefined, v);
  store.set(rows, { ok: list.map((r) => ({ ...r })) });
  await pass(COALESCE_MS * 2);
  // What changed from what it kept is nothing: `same`, the value not sent again (21 bytes on the wire).
  const out = host.takeEmitted();
  assert.deepEqual(out, [[1, { id: 11, same: true }]]);
  assert.equal(JSON.stringify(out[0]![1]).length, 21);
  assert.equal(work.versions - hashed, 0);
  assert.equal(store.keptOf(1), 0);
});

test("a_value_asked_again_with_a_token_of_another_run_goes_whole", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const rows: Topic = { topic: "chatRows", station: "ws/st" };
  const list = [{ id: "a", title: "A" }];
  const v = await keptAt(t, 1, 10, rows, list, true);
  // (the same count, another run: as a token a client kept across a restart of its core says)
  const other = `zzzzzzzzzzzz:${v.split(":")[1]}`;
  assert.notEqual(other, v);
  store.subscribe(1, 11, rows, true, undefined, other);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(11, list)]]);
});

test("a_token_is_the_value_objects_and_a_value_that_is_no_object_goes_by_its_content", () => {
  const a = { n: 1 };
  assert.equal(token(a), token(a));
  assert.notEqual(token(a), token({ n: 1 }));
  assert.match(token(a), TOKEN);
  assert.equal(token("x"), version("x"));
  assert.equal(token(null), version(null));
});

test("a_version_is_its_values_canonical_json_length_and_hash", () => {
  assert.equal(version({ b: 1, a: [2] }), version({ a: [2], b: 1 }));
  assert.notEqual(version({ a: 1 }), version({ a: 2 }));
  assert.equal(version("x").split(":")[0], (3).toString(36));
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

test("a_topic_nobody_subscribes_to_waits_behind_what_pages_wait_for", async () => {
  // A workspace's marks let go of at a switch of workspace (kept for its page coming back) were made again, 8 ms in
  // Hermes, ahead of the chat list and the jobs of the workspace switched to (2026-11-11).
  const { host, store, pass } = setup();
  const idle: Topic = { topic: "idle" };
  const background: Topic = { topic: "background" };
  const pages: Topic[] = [{ topic: "page1" }, { topic: "page2" }];
  const order: string[] = [];
  let made = 0;
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      order.push(topic.topic);
      made++;
      // (the first page opens the next as it is made, as a page's view asks for another)
      if (topic.topic === "page1") {
        store.subscribe(1, 5, pages[1]!);
        store.invalidate(pages[1]!);
      }
      return { ok: `${topic.topic} ${made}` };
    },
  });
  store.subscribe(1, 1, idle);
  store.subscribe(1, 2, background);
  store.invalidate(idle);
  store.invalidate(background);
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.unsubscribe(1, 1);
  order.length = 0;
  // Let go of, then changed: queued first; then background work, then a page.
  store.invalidate(idle);
  store.invalidate(background);
  store.subscribe(1, 4, pages[0]!);
  store.invalidate(pages[0]!);
  await pass(COALESCE_MS * 4);
  // The pages and the background work take turns as before; the topic let go of after them all.
  assert.deepEqual(order, ["page1", "background", "page2", "idle"]);
  assert.deepEqual(host.takeEmitted().map(([, m]) => (m as { id: number }).id), [4, 2, 5]);
  // Made for what reads it in the core all the same, and sent to a page that comes back for it.
  assert.deepEqual(store.get(idle), "idle 6");
  store.subscribe(1, 6, idle);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(6, "idle 6")]]);
});

/// What the store sent, in order: `<topic>` for each message.
function sentOrder(host: FakeHost, names: Map<number, string>): string[] {
  return host.takeEmitted().map(([, m]) => names.get((m as { id: number }).id) ?? `?${(m as { id: number }).id}`);
}

test("background_work_waits_till_every_first_answer_of_a_burst_has_gone_out", async () => {
  // A switch of workspace subscribes its first screen in one go; the pump yields between topics, and work no page
  // waits for (a list's rows loaded behind its first screen, the sync's slices) took those turns: a station's rows,
  // 2.3-3.5 ms in Hermes, ahead of each answer after the list's (2026-11-11).
  const { host, store } = setup();
  const runner = store.runner;
  const order: string[] = [];
  const burst = ["chats", "marks", "stations", "profiles", "status"];
  const names = new Map(burst.map((name, i) => [i + 1, name]));
  store.setSource({
    start(topic) {
      store.invalidate(topic);
    },
    stop() {},
    compute(topic) {
      order.push(topic.topic);
      // The list's first value sets going its rows' load, a station a turn, as views.ts #head does.
      if (topic.topic === "chats") {
        runner.fork(
          Effect.gen(function* () {
            for (const station of ["a", "b", "c"]) {
              yield* store.turn();
              order.push(`load ${station}`);
            }
          }),
        );
      }
      return { ok: topic.topic };
    },
  });
  burst.forEach((name, i) => store.subscribe(1, i + 1, { topic: name }));
  await flush(20);
  // No time passed: all of it on the loop's turns.
  assert.deepEqual(order, [...burst, "load a", "load b", "load c"]);
  assert.deepEqual(sentOrder(host, names), burst, "in the order subscribed");
});

test("background_work_waits_for_what_pages_wait_for_not_for_a_topic_let_go_of", async () => {
  const { store, pass } = setup();
  const runner = store.runner;
  const order: string[] = [];
  store.setSource({ start() {}, stop() {}, compute: (topic) => (order.push(topic.topic), { ok: order.length }) });
  // Kept a while after it was let go of, and changed: made again last (#nextUpdate), after background work.
  const idle: Topic = { topic: "idle" };
  store.subscribe(1, 1, idle);
  store.invalidate(idle);
  await pass(COALESCE_MS * 2);
  store.unsubscribe(1, 1);
  // Shown: its change, and a page opening.
  const shown: Topic = { topic: "shown" };
  store.subscribe(1, 2, shown);
  store.invalidate(shown);
  await pass(COALESCE_MS * 2);
  order.length = 0;
  store.invalidate(idle);
  store.invalidate(shown);
  await pass(COALESCE_MS - 10);
  // Nothing due yet (the window is open): background work goes on at once.
  runner.fork(Effect.andThen(store.answered(), Effect.sync(() => order.push("background in the window"))));
  await flush();
  assert.deepEqual(order, ["background in the window"]);
  order.length = 0;
  const page: Topic = { topic: "page" };
  store.subscribe(1, 3, page);
  store.invalidate(page);
  runner.fork(Effect.andThen(store.turn(), Effect.sync(() => order.push("background"))));
  await pass(COALESCE_MS * 2);
  assert.deepEqual(order, ["page", "shown", "background", "idle"]);
});

test("a_subscribe_arriving_while_the_pump_answers_a_burst_is_answered_in_that_run", async () => {
  const { host, store } = setup();
  const burst = ["one", "two", "three"];
  const names = new Map([...burst.map((name, i): [number, string] => [i + 1, name]), [9, "late"]]);
  store.setSource({
    start(topic) {
      store.invalidate(topic);
    },
    stop() {},
    compute(topic) {
      // A UI's message coming in as the first is made: taken at the pump's next yield, as a host's message is.
      if (topic.topic === "one") setImmediate(() => store.subscribe(1, 9, { topic: "late" }));
      return { ok: topic.topic };
    },
  });
  burst.forEach((name, i) => store.subscribe(1, i + 1, { topic: name }));
  await flush();
  // No time passed (none of COALESCE_MS): answered with the burst, after those subscribed before it.
  assert.deepEqual(sentOrder(host, names), [...burst, "late"]);
});

test("a_pump_that_goes_on_and_on_lets_what_comes_in_in_between_its_topics", async () => {
  // What the pump's yield between topics is for: a run of changes that keeps making more (here a topic that changes
  // itself as it is made, 100 times) keeps nothing that comes in waiting till it is over. Without it, the subscribe
  // below was taken after the 100th.
  const { host, store } = setup();
  let made = 0;
  let cameAt = -1;
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      if (topic.topic !== "busy") return { ok: topic.topic };
      made++;
      if (made === 1) setImmediate(() => ((cameAt = made), store.subscribe(1, 2, { topic: "page" }), store.invalidate({ topic: "page" })));
      if (made < 100) store.invalidate(topic);
      return { ok: made };
    },
  });
  store.subscribe(1, 1, { topic: "busy" });
  store.invalidate({ topic: "busy" });
  const background = { at: -1 };
  store.runner.fork(Effect.andThen(store.turn(), Effect.sync(() => void (background.at = made))));
  // (the loop's turns, no time passed: one a topic made)
  await flush(250);
  assert.equal(made, 100);
  assert.ok(cameAt > 0 && cameAt < 5, `the subscribe came in after ${cameAt} of them`);
  const page = host.takeEmitted().findIndex(([, m]) => (m as { id: number }).id === 2);
  assert.ok(page >= 0 && page < 5, `its page answered as the ${page}th message`);
  // Background work waits for what pages wait for: the topic's changes went to its page first.
  assert.equal(background.at, 100);
});

/// A page made from a dependency, kept live by a watch as a view would: what its source made of it, as many times.
function madeFrom(t: ReturnType<typeof setup>, make: (dependency: Record<string, unknown>) => unknown) {
  const { store } = t;
  const dependency: Topic = { topic: "dependency" };
  const page: Topic = { topic: "page" };
  const made = { n: 0 };
  store.setSource({
    start(topic) {
      if (topic.topic === "page") store.invalidate(page);
    },
    stop() {},
    compute(topic) {
      if (topic.topic !== "page") return undefined;
      made.n++;
      const d = store.get(dependency) as Record<string, unknown> | undefined;
      return d === undefined ? undefined : { ok: make(d) };
    },
  });
  store.watch(dependency, () => {});
  return { dependency, page, made };
}

/// What `messages` make of a value, in order.
function shownOf(messages: [number, unknown][]): unknown {
  let shown: unknown;
  for (const [, message] of messages) {
    const m = message as { value?: unknown; delta?: Op[] };
    if ("value" in m) shown = m.value;
    else if (m.delta) shown = applyOps(shown, m.delta);
  }
  return shown;
}

test("a_page_let_go_of_whose_value_is_made_again_the_same_is_answered_at_once_with_what_went_out", async () => {
  // A pref written at every switch of workspace, read whole by several views, made their topics again the same while
  // their pages were away: each came back sent whole and shaped again (a chat list's 69 KB, 2026-11-11).
  const t = setup();
  const { host, store, pass } = t;
  const { dependency, page, made } = madeFrom(t, (d) => ({ title: d.title }));
  store.set(dependency, { ok: { title: "A", seen: 1 } });
  store.subscribe(1, 1, page);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(1, { title: "A" })]]);
  store.unsubscribe(1, 1, true);
  const [[, { v }]] = host.takeEmitted() as [number, { v: string }][];

  store.set(dependency, { ok: { title: "A", seen: 2 } });
  const before = made.n;
  await pass(COALESCE_MS * 2);
  assert.equal(made.n, before + 1, "made again while let go of");
  const shapes = work.shapes;
  store.subscribe(1, 2, page);
  assert.deepEqual(host.takeEmitted(), [[1, value(2, { title: "A" })]], "at once: what went out");
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [], "and nothing after");
  assert.equal(made.n, before + 1, "not made again for it");
  assert.equal(work.shapes, shapes, "nor shaped again");

  // One that says it holds that version: `same`, at once.
  store.unsubscribe(1, 2);
  store.set(dependency, { ok: { title: "A", seen: 3 } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 3, page, false, undefined, v);
  assert.deepEqual(host.takeEmitted(), [[1, { id: 3, same: true }]]);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), []);
  assert.equal(work.shapes, shapes);
});

test("a_page_let_go_of_whose_value_is_made_again_otherwise_is_sent_its_new_value_whole", async () => {
  const t = setup();
  const { host, store, pass } = t;
  const { dependency, page } = madeFrom(t, (d) => ({ title: d.title }));
  store.set(dependency, { ok: { title: "A" } });
  store.subscribe(1, 1, page);
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.unsubscribe(1, 1);
  store.set(dependency, { ok: { title: "B" } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 2, page);
  assert.deepEqual(host.takeEmitted(), [], "not what went out before");
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(2, { title: "B" })]], "the new value, whole");
});

test("a_page_let_go_of_whose_value_is_set_is_sent_its_new_value_whole", async () => {
  const { host, store, pass } = setup();
  const page: Topic = { topic: "page" };
  store.watch(page, () => {});
  store.subscribe(1, 1, page);
  store.set(page, { ok: { n: 1 } });
  await pass(COALESCE_MS * 2);
  host.takeEmitted();
  store.unsubscribe(1, 1);
  store.set(page, { ok: { n: 2 } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 2, page);
  assert.deepEqual(host.takeEmitted(), []);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, value(2, { n: 2 })]]);
  // an error set: that, whole
  store.unsubscribe(1, 2);
  store.set(page, { err: new CoreError("offline", "连不上") });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 3, page);
  assert.deepEqual(host.takeEmitted(), []);
  await pass(COALESCE_MS * 2);
  assert.deepEqual(host.takeEmitted(), [[1, { id: 3, error: { code: "offline", message: "连不上" } }]]);
});

test("a_page_let_go_of_whose_words_about_time_moved_on_is_sent_them_fresh", async () => {
  type Said = { time: { lastActiveAt: { ago: string } } };
  const ago = (messages: [number, unknown][]) => (shownOf(messages) as Said).time.lastActiveAt.ago;
  const t = setup();
  const { host, store, pass } = t;
  const at = host.nowMs() - 2 * 60_000;
  const { dependency, page } = madeFrom(t, (d) => ({ title: d.title, lastActiveAt: at }));
  store.watch(page, () => {});
  store.set(dependency, { ok: { title: "A", seen: 1 } });
  store.subscribe(1, 1, page);
  await pass(COALESCE_MS * 2);
  const first = ago(host.takeEmitted());
  store.unsubscribe(1, 1);

  // Told out of date as the minute's clock moves on (another page shows times in words meanwhile).
  const other: Topic = { topic: "other" };
  store.subscribe(2, 1, other);
  store.set(other, { ok: { n: 1 } });
  store.setClock();
  await pass(61_000 + COALESCE_MS * 2);
  host.takeEmitted();
  store.subscribe(1, 2, page);
  assert.deepEqual(host.takeEmitted(), [], "not the words that went out");
  await pass(COALESCE_MS * 2);
  const second = ago(host.takeEmitted());
  assert.notEqual(second, first);

  // And with no clock moved on: made again the same in another minute than its words were said in.
  store.unsubscribe(1, 2);
  store.unsubscribe(2, 1);
  await pass(61_000);
  store.set(dependency, { ok: { title: "A", seen: 2 } });
  await pass(COALESCE_MS * 2);
  store.subscribe(1, 3, page);
  assert.deepEqual(host.takeEmitted(), []);
  await pass(COALESCE_MS * 2);
  assert.notEqual(ago(host.takeEmitted()), second);
});
