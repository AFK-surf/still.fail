// The Rust core's attend.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Attend } from "../src/attend.ts";
import { parseAttend, type FocusCall } from "../src/attend-parse.ts";
import { FakeHost } from "../src/testing.ts";
import { run } from "./run.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const focus = (v: J): FocusCall => (parseAttend("client.focus", v) as { focus: FocusCall }).focus;
const chat = (read: number, more: boolean, messages: [number, number, boolean][]): J => ({
  thread: { id: 7, read },
  more,
  messages: messages.map(([seq, at, mine]) => ({ seq, createdAt: at, mine })),
});

test("the_unread_line_holds_for_the_visit_and_is_there_from_the_first_value", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  let v = chat(2, false, [[1, 0, false], [2, 0, false], [3, 0, true], [4, 0, false]]);
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
  assert.equal(v.unreadLine, 4);
  attend.focus(1, focus({ visible: true, focused: true, chat: { station: "ws/st", thread: 7 } }));
  v = attend.chat("ws/st", null, v).value;
  assert.equal(v.unreadLine, 4);
  const later = host.nowMs() + 1;
  v = chat(4, false, [[1, 0, false], [2, 0, false], [3, 0, true], [4, 0, false], [5, later, false]]);
  v = attend.chat("ws/st", null, v).value;
  assert.equal(v.unreadLine, 4);
  attend.focus(1, focus({ left: { station: "ws/st", thread: 7 } }));
  attend.focus(1, focus({ chat: { station: "ws/st", session: "k1", thread: 7 } }));
  await host.time.pass(5);
  v = attend.chat("ws/st", "k1", v).value;
  assert.equal(v.unreadLine, 5);
  attend.focus(1, focus({ left: { station: "ws/st", thread: 8 } }));
  assert.equal(attend.visits.size, 1);
  attend.focus(1, focus({ chat: null }));
  attend.focus(2, focus({ chat: { station: "ws/st", thread: 7 } }));
  v = chat(1, true, [[10, 0, false], [11, 0, false]]);
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
  assert.deepEqual([v.unreadLine, v.unreadAbove], [null, false]);
  v = chat(1, true, [[1, 0, false], [2, 0, false]]);
  v = attend.chat("ws/st", null, v).value;
  assert.equal(v.unreadLine, 2);
});

test("only_what_is_said_while_a_chat_shows_comes_in", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  const said = (v: J) => v.messages.filter((m: J) => m.said === true).map((m: J) => m.seq);
  const started = (v: J) => v.agents.filter((a: J) => a.started === true).map((a: J) => a.session.key);
  const at = (n: number, caught: number, agents: J) => {
    const v = chat(n, false, Array.from({ length: n }, (_, i) => [i + 1, 0, false] as [number, number, boolean]));
    v.caught = caught;
    v.agents = agents;
    return v;
  };
  const agents = (a: string, b: string) => [{ session: { key: "a" }, status: a }, { session: { key: "b" }, status: b }];
  attend.focus(1, focus({ visible: true, chat: { station: "ws/st", thread: 7 } }));
  let v = at(2, 2, agents("running", "idle"));
  v = attend.chat("ws/st", null, v).value;
  assert.ok(said(v).length === 0 && started(v).length === 0);
  v = at(4, 4, agents("running", "idle"));
  v = attend.chat("ws/st", null, v).value;
  assert.deepEqual(said(v), []);
  v = at(6, 4, agents("running", "running"));
  v = attend.chat("ws/st", null, v).value;
  assert.deepEqual([said(v), started(v)], [[5, 6], ["b"]]);
  v = at(7, 7, agents("running", "running"));
  v = attend.chat("ws/st", null, v).value;
  assert.deepEqual(said(v), [5, 6]);
  v = at(7, 7, agents("running", "idle"));
  v = attend.chat("ws/st", null, v).value;
  assert.deepEqual(started(v), []);
  attend.focus(1, focus({ chat: null }));
  attend.focus(1, focus({ chat: { station: "ws/st", thread: 7 } }));
  v = at(7, 7, agents("running", "idle"));
  v = attend.chat("ws/st", null, v).value;
  assert.deepEqual(said(v), []);
  attend.focus(1, focus({ chat: null }));
  v = at(9, 7, agents("running", "idle"));
  v = attend.chat("ws/st", null, v).value;
  assert.deepEqual(said(v), []);
});

test("background_and_delayed_messages_are_history_but_new_live_messages_still_animate", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  const value = (n: number, created: number, status: string) => {
    const v = chat(0, false, Array.from({ length: n }, (_, i) => [i + 1, created, false] as [number, number, boolean]));
    v.caught = 0;
    v.agents = [{ session: { key: "a" }, status, since: created }];
    return v;
  };
  const quiet = (v: J) => {
    assert.ok(v.messages.every((m: J) => m.said !== true));
    assert.ok(v.agents.every((a: J) => a.started !== true));
  };
  attend.focus(1, focus({ visible: true, chat: { station: "ws/st", thread: 7 } }));
  attend.chat("ws/st", null, value(1, 0, "idle"));
  let live = value(2, 0, "running");
  live = attend.chat("ws/st", null, live).value;
  assert.equal(live.messages[1].said, true);
  attend.focus(1, focus({ visible: false }));
  let background = value(1000, 0, "running");
  background = attend.chat("ws/st", null, background).value;
  quiet(background);
  attend.focus(1, focus({ visible: true }));
  let delayed = value(2000, 0, "running");
  delayed = attend.chat("ws/st", null, delayed).value;
  quiet(delayed);
  attend.chat("ws/st", null, value(2000, 0, "idle"));
  let fresh = value(2001, host.nowMs() + 1, "running");
  fresh = attend.chat("ws/st", null, fresh).value;
  assert.equal(fresh.messages.filter((m: J) => m.said === true).length, 1);
  assert.equal(fresh.agents[0].started, true);
});

test("a_hidden_tab_does_not_stop_animation_in_another_visible_tab", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  for (const client of [1, 2]) attend.focus(client, focus({ visible: true, chat: { station: "ws/st", thread: 7 } }));
  attend.chat("ws/st", null, chat(0, false, [[1, 0, false]]));
  attend.focus(1, focus({ visible: false }));
  let v = chat(0, false, [[1, 0, false], [2, 0, false]]);
  v = attend.chat("ws/st", null, v).value;
  assert.equal(v.messages[1].said, true);
});

test("a_message_shown_whole_on_a_page_in_front_is_read_its_end_shown_or_not", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  const v = chat(1, false, [[1, 0, false], [2, 0, false], [3, 0, false], [4, 0, false]]);
  // up to 3 shown whole, the end not: read up to 3
  attend.focus(1, focus({ visible: true, focused: true, chat: { station: "ws/st", thread: 7, end: false, seen: 3 } }));
  assert.deepEqual(attend.chat("ws/st", null, v).due, [{ read: { thread: 7, seq: 3 } }]);
  assert.deepEqual(attend.chat("ws/st", null, v).due, []);
  // not in front: no further
  attend.focus(1, focus({ focused: false, chat: { station: "ws/st", thread: 7, end: false, seen: 4 } }));
  assert.deepEqual(attend.chat("ws/st", null, chat(3, false, [[1, 0, false], [2, 0, false], [3, 0, false], [4, 0, false]])).due, []);
  attend.focus(1, focus({ focused: true }));
  assert.deepEqual(attend.chat("ws/st", null, chat(3, false, [[1, 0, false], [2, 0, false], [3, 0, false], [4, 0, false]])).due, [{ read: { thread: 7, seq: 4 } }]);
  // a seen past what the chat has: up to its newest; one under what is read: nothing
  attend.focus(1, focus({ chat: { station: "ws/st", thread: 7, end: false, seen: 2 } }));
  assert.deepEqual(attend.chat("ws/st", null, chat(4, false, [[1, 0, false], [2, 0, false], [3, 0, false], [4, 0, false]])).due, []);
});

test("a_chat_is_read_while_its_end_shows_on_a_page_in_front", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  let v = chat(1, false, [[1, 0, false], [2, 0, false]]);
  attend.focus(1, focus({ visible: false, chat: { station: "ws/st", thread: 7, end: true } }));
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
  attend.focus(1, focus({ visible: true, chat: { station: "ws/st", thread: 7, end: false } }));
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
  attend.focus(1, focus({ chat: { station: "ws/st", thread: 7, end: true } }));
  {
    // In view but not in front (a window behind others, on another screen): not read.
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
  attend.focus(1, focus({ focused: true }));
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, [{ read: { thread: 7, seq: 2 } }]);
  }
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
  attend.failed("ws/st", { read: { thread: 7, seq: 2 } });
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, [{ read: { thread: 7, seq: 2 } }]);
  }
  v = chat(2, false, [[1, 0, false], [2, 0, false]]);
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
  v = chat(2, false, [[1, 0, false], [2, 0, false], [3, 0, false]]);
  v.newer = true;
  {
    const r = attend.chat("ws/st", null, v);
    v = r.value;
    assert.deepEqual(r.due, []);
  }
});

test("notices_show_unless_off_looked_at_or_left_to_a_push_and_each_once", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  const n = (id: string) => ({ id, station: "ws/st", session: "k1", thread: 7 });
  const shown = (a: Attend) => a.value(null).show.map((x: J) => x.id);
  assert.ok(!attend.noticed([n("n1")], false));
  attend.focus(1, focus({ visible: true, focused: false, chat: { station: "ws/st", thread: 7 } }));
  assert.ok(attend.noticed([n("n2")], true));
  attend.focus(1, focus({ focused: true }));
  assert.ok(!attend.noticed([n("n3")], true));
  assert.deepEqual(shown(attend), ["n2"]);
  assert.ok(attend.claim("n2"));
  assert.ok(!attend.claim("n2"));
  assert.deepEqual(shown(attend), []);
  attend.setPushing(true);
  attend.focus(1, focus({ visible: false, focused: false }));
  assert.ok(!attend.noticed([n("n4")], true));
  assert.ok(attend.pushed(null));
  attend.focus(2, focus({ visible: true }));
  assert.ok(attend.noticed([n("n5")], true));
  assert.ok(!attend.pushed(null));
  await run(attend.set(false, true));
  assert.ok(!attend.noticed([n("n6")], true));
  assert.deepEqual(shown(attend), []);
  const again = await run(Attend.load(host));
  assert.deepEqual(again.value(null), { on: false, asked: true, push: false, kinds: { wait: true, failed: true, done: "away", message: true }, preview: true, permission: "unknown", show: [] });
  attend.gone(2);
  assert.ok(!attend.seen());
});

test("only_the_kinds_turned_on_are_shown_a_turn_done_by_default_only_while_the_app_is_not_in_front", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  const n = (id: string, kind: string) => ({ id, kind, station: "ws/st", session: "k1", thread: 7 });
  const shown = () => attend.value(null).show.map((x: J) => x.id);
  attend.focus(1, focus({ visible: true, focused: true, chat: { station: "ws/st", thread: 9 } }));
  attend.noticed([n("d1", "done"), n("w1", "wait"), n("b1", "block"), n("m1", "message")], true);
  assert.deepEqual(shown(), ["w1", "b1", "m1"], "in front: a turn done is not told");
  for (const id of shown()) attend.claim(id);
  attend.focus(1, focus({ focused: false }));
  attend.noticed([n("d2", "done")], true);
  assert.deepEqual(shown(), ["d2"]);
  attend.claim("d2");
  await run(attend.set(null, null, { done: "off", message: false }));
  attend.noticed([n("d3", "done"), n("m2", "message"), n("f1", "failed")], true);
  assert.deepEqual(shown(), ["f1"]);
  attend.claim("f1");
  await run(attend.set(null, null, { wait: false }));
  assert.deepEqual(attend.value(null).kinds, { wait: false, failed: true, done: "off", message: false }, "each given one changes, the rest stay");
  attend.focus(1, focus({ visible: false }));
  assert.ok(!attend.pushed(null, "block"));
  assert.ok(attend.pushed(null, "failed"));
  assert.ok(attend.pushed(null));
  const again = await run(Attend.load(host));
  assert.deepEqual(again.value(null).kinds, { wait: false, failed: true, done: "off", message: false });
});

test("only_the_workspace_the_viewer_is_in_is_heard_of", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  const n = (id: string, workspace: string) => ({ id, station: `${workspace}/st`, workspace, session: "k1", thread: 7 });
  const shown = (a: Attend, w: string | null) => a.value(w).show.map((x: J) => x.id);
  attend.focus(1, focus({ visible: true }));
  assert.ok(attend.noticed([n("n1", "w1"), n("n2", "w2")], true));
  assert.deepEqual(shown(attend, null), ["n1", "n2"]);
  attend.claim("n1");
  attend.claim("n2");
  attend.focus(1, focus({ workspace: "w1" }));
  assert.ok(!attend.noticed([n("n3", "w2")], true));
  attend.focus(1, focus({ chat: { station: "w1/st", thread: 9 } }));
  assert.ok(attend.noticed([n("n4", "w1"), n("n5", "w2")], true));
  assert.deepEqual(shown(attend, null), ["n4"]);
  attend.focus(2, focus({ visible: true, workspace: "w2" }));
  assert.ok(attend.noticed([n("n6", "w2")], true));
  assert.deepEqual(shown(attend, "w2"), ["n6"]);
  assert.deepEqual(shown(attend, "w1"), ["n4"]);
  attend.focus(1, focus({ visible: false }));
  attend.focus(2, focus({ visible: false }));
  assert.ok(attend.pushed("w2"));
  assert.ok(!attend.pushed("w3"));
  assert.ok(attend.pushed(null));
  attend.gone(1);
  attend.gone(2);
  assert.ok(attend.pushed("w3"));
});

test("what_is_measured_only_to_be_shown_waits_for_a_page_in_view", async () => {
  const host = new FakeHost();
  const attend = await run(Attend.load(host));
  // No UI said where it is: taken as looking.
  assert.equal(attend.shown(), true);
  attend.focus(1, focus({ visible: false }));
  assert.equal(attend.shown(), false);
  let back = false;
  const waiting = run(Effect.map(attend.untilShown(), () => (back = true)));
  await host.time.pass(60_000);
  assert.equal(back, false);
  attend.focus(1, focus({ visible: true }));
  await waiting;
  assert.equal(back, true);
  attend.focus(1, focus({ visible: false }));
  attend.gone(1);
  assert.equal(attend.shown(), true);
});
