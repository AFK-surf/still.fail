import assert from "node:assert/strict";
import { test } from "node:test";
import { Data } from "../src/data.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { COALESCE_MS, EVICT_AFTER_MS, Store, type Value } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { Workspaces } from "../src/workspace.ts";
import { run } from "./run.ts";

test("a_page_follows_what_it_reads_without_synchronous_recomputation", async () => {
  const host = new FakeHost();
  const store = new Store(host, new Runner(host.time.clock));
  const gate: Topic = { topic: "gate" };
  const left: Topic = { topic: "left" };
  const right: Topic = { topic: "right" };
  const unrelated: Topic = { topic: "unrelated" };
  const page: Topic = { topic: "page" };
  let made = 0;
  store.setSource({
    start() {},
    stop() {},
    compute(topic) {
      if (topic.topic !== "page") return undefined;
      made++;
      return { ok: store.get(store.get(gate) ? left : right) };
    },
  });
  const pass = () => host.time.pass(COALESCE_MS * 3, 10);
  for (const [id, topic, value] of [[10, gate, true], [11, left, 1], [12, right, 5], [13, unrelated, 0]] as const) {
    store.subscribe(1, id, topic);
    store.set(topic, { ok: value });
  }
  store.subscribe(1, 1, page);
  store.invalidate(page);
  await pass();
  assert.deepEqual(host.takeEmitted().find(([, message]) => message.id === 1), [1, { id: 1, value: 1 }]);
  assert.equal(made, 1);

  store.set(unrelated, { ok: 1 });
  await pass();
  assert.equal(made, 1, "an unread topic does not make the page again");
  host.takeEmitted();

  store.set(left, { ok: 2 });
  assert.equal(made, 1, "a data write only schedules the page's work");
  await pass();
  assert.deepEqual(host.takeEmitted().find(([, message]) => message.id === 1), [1, { id: 1, value: 2 }]);
  assert.equal(made, 2);

  store.set(gate, { ok: false });
  await pass();
  assert.deepEqual(host.takeEmitted().find(([, message]) => message.id === 1), [1, { id: 1, value: 5 }]);
  assert.equal(made, 3);
  store.set(left, { ok: 3 });
  await pass();
  assert.equal(made, 3, "a dependency no longer read is released");
  host.takeEmitted();
  store.set(right, { ok: 6 });
  await pass();
  assert.deepEqual(host.takeEmitted().find(([, message]) => message.id === 1), [1, { id: 1, value: 6 }]);
  assert.equal(made, 4);
});

test("a_selected_value_uses_each_readers_equality_rule", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const source: Topic = { topic: "source" };
  const byParity: Topic = { topic: "byParity" };
  const exact: Topic = { topic: "exact" };
  const pick = (value: Value | undefined) => value && "ok" in value ? Number(value.ok) : 0;
  const sameParity = (a: number, b: number) => a % 2 === b % 2;
  store.setSource({
    start(topic) { if (topic.topic !== "source") store.invalidate(topic); },
    stop() {},
    compute(topic) {
      if (topic.topic === "byParity") return { ok: store.select(source, pick, sameParity) };
      if (topic.topic === "exact") return { ok: store.select(source, pick) };
      return undefined;
    },
  });
  try {
    store.subscribe(1, 9, source);
    store.set(source, { ok: 1 });
    store.subscribe(1, 1, byParity);
    store.subscribe(1, 2, exact);
    await host.time.pass(COALESCE_MS * 3, 10);
    host.takeEmitted();
    store.set(source, { ok: 3 });
    await host.time.pass(COALESCE_MS * 3, 10);
    const sent = host.takeEmitted();
    assert.equal(sent.some(([, message]) => message.id === 1), false, "the parity view did not change");
    assert.deepEqual(sent.find(([, message]) => message.id === 2), [1, { id: 2, value: 3 }]);
  } finally { runner.shutdown(); }
});

test("a_direct_chat_read_follows_only_the_row_it_uses", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  const store = new Store(host, runner);
  const a: Topic = { topic: "page", id: "a" };
  const b: Topic = { topic: "page", id: "b" };
  const made = new Map<string, number>();
  data.set({ topic: "chatRows", station: "w/s" }, [{ id: "a", title: "A" }, { id: "b", title: "B" }]);
  data.set({ topic: "archivedRows", station: "w/s" }, []);
  await run(data.written);
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute(topic) {
      const id = String(topic.id);
      made.set(id, (made.get(id) ?? 0) + 1);
      return { ok: data.chatNamed("w/s", id)?.row ?? null };
    },
  });
  try {
    store.subscribe(1, 1, a);
    store.subscribe(1, 2, b);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(a), { id: "a", title: "A" });
    assert.deepEqual(store.get(b), { id: "b", title: "B" });
    host.takeEmitted();

    data.putChat("w/s", { id: "a", title: "New A" });
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(a), { id: "a", title: "New A" });
    assert.equal(made.get("b"), 1, "another row of the same station does not rebuild this page");

    data.set({ topic: "chatRows", station: "w/s" }, [{ id: "b", title: "B" }]);
    data.set({ topic: "archivedRows", station: "w/s" }, [{ id: "a", title: "Archived A" }]);
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(a), { id: "a", title: "Archived A" });
    assert.equal(made.get("b"), 1, "archiving another row does not rebuild this page");
  } finally { runner.shutdown(); }
});

test("a_page_follows_a_workspaces_account_as_it_is_discovered_or_changes", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const workspaces = new Workspaces(host, runner);
  const store = new Store(host, runner);
  const page: Topic = { topic: "page" };
  let made = 0;
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute() { made++; return { ok: workspaces.owner("w") }; },
  });
  try {
    store.subscribe(1, 1, page);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(store.get(page), null);
    assert.equal(workspaces.get("w"), undefined, "reading an unknown owner did not create a workspace");
    workspaces.setOwners(new Map([["other", "s2"]]));
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(made, 1, "another workspace did not rebuild the page");
    workspaces.setOwners(new Map([["w", "s1"], ["other", "s2"]]));
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(store.get(page), "s1");
    workspaces.setOwners(new Map([["w", "s3"]]));
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(store.get(page), "s3");
    workspaces.setOwners(new Map());
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(store.get(page), null);
  } finally { runner.shutdown(); }
});

test("a_page_follows_a_workspaces_account_read_from_the_workspace", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const workspaces = new Workspaces(host, runner);
  const workspace = workspaces.of("w");
  const store = new Store(host, runner);
  const page: Topic = { topic: "page" };
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute() { return { ok: workspace.owner }; },
  });
  try {
    store.subscribe(1, 1, page);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(store.get(page), null);
    workspaces.setOwners(new Map([["w", "s1"]]));
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(store.get(page), "s1");
  } finally { runner.shutdown(); }
});

test("a_page_follows_a_workspaces_account_set_as_workspaces_appear_or_leave", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const workspaces = new Workspaces(host, runner);
  const store = new Store(host, runner);
  const page: Topic = { topic: "page" };
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute() { return { ok: workspaces.owned() }; },
  });
  try {
    store.subscribe(1, 1, page);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), []);
    workspaces.setOwners(new Map([["w", "s1"], ["other", "s2"]]));
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), [["other", "s2"], ["w", "s1"]]);
    workspaces.setOwners(new Map([["w", "s3"]]));
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), [["w", "s3"]]);
  } finally { runner.shutdown(); }
});

test("a_record_read_follows_its_own_account_workspace_or_device_value", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  const store = new Store(host, runner);
  const records = [
    { table: "me", key: "s1" },
    { table: "choice", key: "ws:w:chat" },
    { table: "choice", key: "device-chat" },
  ];
  const made = [0, 0, 0];
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute(topic) {
      const i = Number(topic.index);
      made[i]++;
      return { ok: data.record(records[i].table, records[i].key) ?? null };
    },
  });
  const topics = records.map((_, index): Topic => ({ topic: "page", index }));
  try {
    topics.forEach((topic, i) => store.subscribe(1, i + 1, topic));
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(topics.map((topic) => store.get(topic)), [null, null, null]);
    for (let i = 0; i < records.length; i++) {
      const { table, key } = records[i];
      data.put(table, key, { selected: i });
      await run(data.written);
      await host.time.pass(COALESCE_MS * 3, 10);
      assert.deepEqual(store.get(topics[i]), { selected: i });
      assert.deepEqual(made, records.map((_, n) => n <= i ? 2 : 1), "other records did not rebuild their pages");
    }
    data.forgetRecord("choice", "ws:w:chat");
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(store.get(topics[1]), null);
    data.device.put("choice", "device-chat", { selected: "direct" });
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(topics[2]), { selected: "direct" });
  } finally { runner.shutdown(); }
});

test("a_slack_read_tracks_the_session_it_reads", async () => {
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
    compute() { made++; return { ok: data.slackSaid("w/s", "k").map((said) => said.text) }; },
  });
  const heard = (text: string) => ({ at: "1970-01-01T00:00:01Z", kind: "user", text: `<message via="slack" thread="C0OPS/1.2" from="Mia (U9)" ts="1.2">${text}</message>` });
  try {
    store.subscribe(1, 1, page);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), []);
    data.putItems("transcript", "w/s", "other", [[1, heard("elsewhere")]]);
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(made, 1, "another session did not rebuild the page");
    data.putItems("transcript", "w/s", "k", [[1, heard("hello")]]);
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), ["hello"]);
    data.putItems("transcript", "w/s", "k", [], 0);
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), []);
  } finally { runner.shutdown(); }
});

test("a_marked_chats_read_ignores_changes_to_unmarked_rows", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const data = new Data(host, runner, {
    owner: () => "s1",
    derive: { tone: (row) => row.unread ? "done" : null, asks: () => false },
  });
  await run(data.open(["s1"]));
  data.set({ topic: "chatRows", station: "w/s" }, [{ id: "a", unread: false, title: "A" }, { id: "b", unread: true, title: "B" }]);
  await run(data.written);
  const store = new Store(host, runner);
  const page: Topic = { topic: "page" };
  let made = 0;
  store.setSource({
    start(topic) { store.invalidate(topic); },
    stop() {},
    compute() { made++; return { ok: data.marked(["w/s"]).map(([, row]) => `${row.id}:${row.title}`).sort() }; },
  });
  try {
    store.subscribe(1, 1, page);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), ["b:B"]);
    data.putChat("w/s", { id: "a", unread: false, title: "New A" });
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(made, 1, "an unmarked chat did not rebuild the marks page");
    data.set({ topic: "archivedRows", station: "w/s" }, [{ id: "old", unread: true, title: "Archived" }]);
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.equal(made, 1, "an archived chat did not rebuild the marks page");
    data.putChat("w/s", { id: "b", unread: true, title: "New B" });
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), ["b:New B"]);
    data.putChat("w/s", { id: "a", unread: true, title: "New A" });
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), ["a:New A", "b:New B"]);
    data.putChat("w/s", { id: "b", unread: false, title: "B" });
    await run(data.written);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(store.get(page), ["a:New A"]);
  } finally { runner.shutdown(); }
});

test("a_page_updates_when_data_it_read_before_it_was_available_arrives", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  const workspace: Topic = { topic: "workspace", workspace: "ws" };
  const page: Topic = { topic: "page" };
  let held: unknown;
  store.setHeld((topic) => topic.topic === "workspace" ? held : undefined);
  store.setSource({
    start(topic) { if (topic.topic === "page") store.invalidate(topic); },
    stop() {},
    compute(topic) {
      if (topic.topic !== "page") return undefined;
      const value = store.get(workspace);
      return value === undefined ? undefined : { ok: value };
    },
  });
  try {
    store.subscribe(1, 1, page);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(host.takeEmitted(), []);

    held = { name: "ready" };
    store.changed(workspace);
    await host.time.pass(COALESCE_MS * 3, 10);
    assert.deepEqual(host.takeEmitted(), [[1, { id: 1, value: { name: "ready" } }]]);
  } finally { runner.shutdown(); }
});

test("reading_a_topic_starts_it_and_releases_it_when_the_dependency_changes", async () => {
  const host = new FakeHost();
  const store = new Store(host, new Runner(host.time.clock));
  const page: Topic = { topic: "page" };
  const gate: Topic = { topic: "gate" };
  const left: Topic = { topic: "left" };
  const right: Topic = { topic: "right" };
  const starts: string[] = [];
  const stops: string[] = [];
  let chooseLeft = true, leftValue = 1, rightValue = 5;
  store.setSource({
    start(topic) { starts.push(topic.topic); store.invalidate(topic); },
    stop(topic) { stops.push(topic.topic); },
    compute(topic) {
      if (topic.topic === "page") return { ok: store.get(store.get(gate) ? left : right) };
      if (topic.topic === "gate") return { ok: chooseLeft };
      if (topic.topic === "left") return { ok: leftValue };
      if (topic.topic === "right") return { ok: rightValue };
      return undefined;
    },
  });
  const pass = (ms = COALESCE_MS * 3) => host.time.pass(ms, ms > 1000 ? 100 : 10);
  store.subscribe(1, 1, page);
  await pass();
  assert.deepEqual(host.takeEmitted(), [[1, { id: 1, value: 1 }]]);
  assert.deepEqual(starts.sort(), ["gate", "left", "page"]);
  assert.equal(store.inUse(gate), true, "a topic read by a live page is in use");
  assert.equal(store.inUse(left), true, "a read dependency stays in use without a manual watch");
  assert.equal(store.inUse(right), false, "an unread topic is not in use");

  leftValue = 2;
  store.changed(left);
  await pass();
  assert.deepEqual(host.takeEmitted(), [[1, { id: 1, value: 2 }]]);
  chooseLeft = false;
  store.changed(gate);
  await pass();
  assert.deepEqual(host.takeEmitted(), [[1, { id: 1, value: 5 }]]);
  assert.deepEqual(starts.sort(), ["gate", "left", "page", "right"]);
  assert.equal(store.inUse(left), false, "the previous dependency is no longer in use during its eviction grace");
  assert.equal(store.inUse(right), true, "the new dependency is in use");

  await pass(EVICT_AFTER_MS * 2);
  assert.deepEqual(stops, ["left"]);
  rightValue = 6;
  store.changed(right);
  await pass();
  assert.deepEqual(host.takeEmitted(), [[1, { id: 1, value: 6 }]]);
  store.unsubscribe(1, 1);
  await pass(EVICT_AFTER_MS * 3);
  assert.deepEqual(stops.sort(), ["gate", "left", "page", "right"]);
  assert.deepEqual(store.liveTopics(), []);
});
