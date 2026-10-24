// The log of what a station tells everyone (src/api/event-log.ts): each event its number, a stream the log from where
// it was asked on, a thing said whole kept as it was last said, and what cannot be gone on from said so.
import assert from "node:assert/strict";
import { test } from "node:test";
import { EventLog, KEPT_BYTES, KEPT_MOST, KEPT_MS } from "../src/api/event-log.ts";

const ids = (log: EventLog<string>, since: string) => log.after(since).map((e) => Number(/^id: [0-9a-f]+\.(\d+)\n/.exec(e.text)![1]));

test("an event has its number in the log, and a stream goes on from any of them", () => {
  const log = new EventLog<string>("1f2e3d4c");
  const said = [1, 2, 3, 4].map((i) => log.append("thread", { id: i }, "all", 0));
  assert.deepEqual(said.map((e) => e.n), [1, 2, 3, 4]);
  assert.equal(said[0]!.text, 'id: 1f2e3d4c.1\nevent: thread\ndata: {"id":1}\n\n');
  // From before the first, from the middle, from the last: what came after, in order.
  assert.deepEqual(ids(log, "1f2e3d4c.0"), [1, 2, 3, 4]);
  assert.deepEqual(ids(log, "1f2e3d4c.2"), [3, 4]);
  assert.deepEqual(ids(log, "1f2e3d4c.4"), []);
  assert.ok(log.has("1f2e3d4c.4"));
  // Whom each was for is the teller's to say; it comes back as it was given.
  assert.deepEqual(log.after("1f2e3d4c.3").map((e) => e.to), ["all"]);
  // Another run's, or no id at all: not gone on from.
  for (const since of ["0a0a0a0a.2", "2", "1f2e3d4c", "1f2e3d4c.x", ""]) {
    assert.equal(log.has(since), false, since);
    assert.deepEqual(log.after(since), []);
  }
});

test("a thing said whole is kept as it was last said, what adds to a thing every time", () => {
  const log = new EventLog<string>("1f2e3d4c");
  log.append("thread", { id: 7, n: 1 }, "all", 0);
  log.append("overview", { running: 1 }, "a", 0, "overview\0a");
  log.append("overview", { running: 1 }, "b", 0, "overview\0b");
  log.append("thread", { id: 7, n: 2 }, "all", 0);
  log.append("overview", { running: 2 }, "a", 0, "overview\0a");
  log.append("session", { key: "s" }, "all", 0, "session\0s");
  log.append("session-removed", { key: "s" }, "all", 0, "session\0s");
  // One who heard none of it: both things said in the thread, each viewer's overview and the session as last said,
  // where they were last said.
  assert.deepEqual(ids(log, "1f2e3d4c.0"), [1, 3, 4, 5, 7]);
  assert.deepEqual(log.after("1f2e3d4c.0").map((e) => e.text.split("\n")[1]), ["event: thread", "event: overview", "event: thread", "event: overview", "event: session-removed"]);
  // One who heard the overview before it was said again hears it as it is now.
  assert.deepEqual(ids(log, "1f2e3d4c.2"), [3, 4, 5, 7]);
  // What is kept is counted as it is kept.
  assert.equal(log.state().bytes, log.after("1f2e3d4c.0").reduce((sum, e) => sum + e.text.length, 0));
});

test("what is kept is bounded by age, number and size, and what is let go cannot be gone on from", () => {
  // By age.
  const old = new EventLog<string>("1f2e3d4c");
  old.append("thread", { id: 1 }, "all", 0);
  old.append("thread", { id: 2 }, "all", 1_000);
  old.append("thread", { id: 3 }, "all", KEPT_MS + 500);
  assert.equal(old.has("1f2e3d4c.0"), false, "1 came after it, and is let go");
  assert.deepEqual(ids(old, "1f2e3d4c.1"), [2, 3]);
  // By number.
  const many = new EventLog<string>("1f2e3d4c");
  for (let i = 0; i < KEPT_MOST + 10; i++) many.append("thread", { id: i }, "all", 0);
  assert.equal(many.state().kept, KEPT_MOST);
  assert.equal(many.has("1f2e3d4c.9"), false);
  assert.equal(many.after("1f2e3d4c.10").length, KEPT_MOST);
  // By size; a thing said whole again and again takes the room of one.
  const big = new EventLog<string>("1f2e3d4c");
  const text = "x".repeat(1024 * 1024);
  for (let i = 0; i < 20; i++) big.append("overview", { text }, "a", 0, "overview\0a");
  assert.deepEqual(ids(big, "1f2e3d4c.0"), [20]);
  for (let i = 0; i < 20; i++) big.append("thread", { text }, "all", 0);
  assert.ok(big.state().bytes <= KEPT_BYTES);
  assert.equal(big.has("1f2e3d4c.20"), false);
  assert.ok(big.has(`1f2e3d4c.${big.state().forgotten}`));
  assert.deepEqual(ids(big, `1f2e3d4c.${big.state().forgotten}`), Array.from({ length: 40 - big.state().forgotten }, (_, i) => big.state().forgotten + 1 + i));
});

test("let go of whole, nothing before can be gone on from, and it goes on numbering", () => {
  const log = new EventLog<string>("1f2e3d4c");
  log.append("thread", { id: 1 }, "all", 0);
  log.append("overview", {}, "a", 0, "overview\0a");
  log.clear();
  assert.equal(log.has("1f2e3d4c.2"), false);
  const next = log.append("overview", {}, "a", 0, "overview\0a");
  assert.equal(next.n, 4);
  assert.deepEqual(ids(log, "1f2e3d4c.3"), [4]);
  assert.equal(log.state().bytes, next.text.length);
});

test("what a log keeps goes on in the next process: the same run, numbered on, a thing said whole said again in its place", () => {
  const log = new EventLog<string>("1f2e3d4c");
  log.append("thread", { id: 1 }, "all", 0);
  log.append("overview", { running: 1 }, "a", 0, "overview\0a");
  log.append("overview", { running: 2 }, "a", 0, "overview\0a");
  log.append("thread", { id: 2 }, "all", 0);
  // As it is written and read back: what was said again since is left out.
  const kept = JSON.parse(JSON.stringify(log.kept()));
  assert.deepEqual(kept.events.map((e: { n: number }) => e.n), [1, 3, 4]);
  const next = EventLog.from<string>(kept, 1_000);
  assert.equal(next.run, "1f2e3d4c");
  for (const since of ["1f2e3d4c.0", "1f2e3d4c.2", "1f2e3d4c.4"]) assert.deepEqual(ids(next, since), ids(log, since), since);
  assert.deepEqual(next.after("1f2e3d4c.2").map((e) => e.to), ["a", "all"]);
  // Numbered on from where it was; the overview said again takes the place of the one handed over.
  assert.equal(next.append("overview", { running: 3 }, "a", 1_000, "overview\0a").n, 5);
  assert.deepEqual(ids(next, "1f2e3d4c.0"), [1, 4, 5]);
  assert.equal(next.state().bytes, next.after("1f2e3d4c.0").reduce((sum, e) => sum + e.text.length, 0));
});

test("what is handed over is kept as what is appended is, and what is no log is not taken up", () => {
  // By age, at the time it is taken up.
  const log = new EventLog<string>("1f2e3d4c");
  log.append("thread", { id: 1 }, "all", 0);
  log.append("thread", { id: 2 }, "all", 1_000);
  const next = EventLog.from<string>(log.kept(), KEPT_MS + 500);
  assert.equal(next.has("1f2e3d4c.0"), false);
  assert.deepEqual(ids(next, "1f2e3d4c.1"), [2]);
  // By number.
  const events = Array.from({ length: KEPT_MOST + 10 }, (_, i) => ({ n: i + 1, to: "all", text: "x", at: 0 }));
  const many = EventLog.from<string>({ run: "1f2e3d4c", seq: KEPT_MOST + 10, forgotten: 0, events }, 0);
  assert.equal(many.state().kept, KEPT_MOST);
  assert.equal(many.has("1f2e3d4c.9"), false);
  assert.ok(many.has("1f2e3d4c.10"));
  // Let go of whole before: nothing before can be gone on from there either.
  log.clear();
  const cleared = EventLog.from<string>(log.kept(), 0);
  assert.equal(cleared.has("1f2e3d4c.2"), false);
  assert.equal(cleared.append("thread", {}, "all", 0).n, 4);
  const bad = [{}, { ...log.kept(), run: "../x" }, { ...log.kept(), seq: 1 }, { run: "1f", seq: 2, forgotten: 0, events: [{ n: 3, to: "all", text: "", at: 0 }] }];
  for (const kept of bad) assert.throws(() => EventLog.from(kept as never, 0), /not a log/, JSON.stringify(kept));
});
