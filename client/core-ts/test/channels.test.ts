// Channels (src/channels): what a station only adds to, kept in sync by number. Driven on its own here: a station that
// holds channels whole and answers reads of them, a device's store and a lane of tasks, all in memory. No core, database
// or stream is in it (station-flows.test.ts has the channels of a core: a thread's entries, a session's transcript).
//
// What is random (what a push drops, doubles or delays) runs on the seeds of sim-seeds.ts: a failure names its seed,
// and SIM_SEED=<seed> runs it again as it was.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { type Channel, Channels, type Held, type Kind, type Reach } from "../src/channels/channels.ts";
import { behind, latestMissing, missing, next } from "../src/channels/fill.ts";
import { CoreError } from "../src/error.ts";
import { Priority } from "../src/sync/scheduler.ts";
import { seeds } from "./sim-seeds.ts";

const run = (from: number, to: number) => Array.from({ length: Math.max(0, to - from + 1) }, (_, i) => from + i);

// ── which read comes next (fill.ts) ──

test("nothing_held_asks_the_latest_page_and_all_held_asks_nothing", () => {
  assert.deepEqual(next([], 0, 50), { latest: true });
  assert.deepEqual(next([], 120, 50), { latest: true });
  assert.equal(next(run(1, 12), 12, 50), null);
  assert.equal(missing(run(1, 12), 12), null);
  // Held past what the summary says (a message just told, the summary on its way): nothing to ask.
  assert.equal(next(run(1, 12), 10, 50), null);
});

test("what_came_after_what_is_held_is_asked_first", () => {
  assert.deepEqual(next(run(1, 12), 15, 50), { after: 12 });
  // Though there is a hole below too: the latest first.
  assert.deepEqual(next([1, 2, 3, 7, 8], 15, 50), { after: 8 });
  assert.equal(latestMissing(8, 15), true);
  assert.equal(latestMissing(15, 15), false);
  assert.equal(latestMissing(null, 0), true);
});

test("a_hole_is_asked_from_just_past_what_is_held_below_it_a_page_at_most", () => {
  // Told 13 while 11 and 12 went missing.
  assert.deepEqual(next([...run(1, 10), 13], 13, 50), { from: 11, to: 12 });
  assert.equal(behind([...run(1, 10), 13], 13), true);
  // Two holes: the higher first, then (it filled) the lower.
  assert.deepEqual(next([1, 2, 5, 6, 9], 9, 50), { from: 7, to: 8 });
  assert.deepEqual(next([1, 2, 5, 6, 7, 8, 9], 9, 50), { from: 3, to: 4 });
  // A hole wider than a page: its top page.
  assert.deepEqual(next([1, 200], 200, 50), { from: 150, to: 199 });
});

test("history_before_what_is_held_is_no_hole_but_is_asked_page_by_page", () => {
  // The latest page alone is held: nothing told went missing…
  assert.equal(behind(run(151, 200), 200), false);
  // …and what is before it comes a page at a time, down to the first.
  assert.deepEqual(next(run(151, 200), 200, 50), { from: 101, to: 150 });
  assert.deepEqual(next(run(3, 200), 200, 50), { from: 1, to: 2 });
  assert.equal(missing(run(151, 200), 200), 150);
});

test("behind_is_going_further_than_what_is_held_or_a_hole_in_it", () => {
  // It goes further than what is held.
  assert.equal(behind(run(1, 12), 15), true);
  assert.equal(behind(run(151, 200), 203), true);
  // All of it held, or held past what is said of it.
  assert.equal(behind(run(1, 12), 12), false);
  assert.equal(behind(run(1, 12), 10), false);
  // None of it held: not behind, it is yet to be brought.
  assert.equal(behind([], 12), false);
});

// ── a channel told, said to go so far, and read (channels.ts) ──

const PAGE = 5;
const ST = "ws/st";

/// A kind as the station of these tests takes its reads: `<id>?latest`, `?after=3`, `?from=4&to=5`, `?before=6`.
const kind = (whole: boolean): Kind => ({
  name: whole ? "log" : "tail",
  first: 1,
  page: PAGE,
  whole,
  cost: whole ? 1 : 3,
  task: (id) => `read/${id}`,
  path: (id, read) => `${id}?${"latest" in read ? "latest" : "after" in read ? `after=${read.after}` : "before" in read ? `before=${read.before}` : `from=${read.from}&to=${read.to}`}`,
  items: (answer) => (answer as { items: [number, unknown][] }).items,
  last: (answer) => (whole ? (answer as { last: number }).last : null),
});
/// One brought whole (as a thread's entries are), and one whose latest page is (as a transcript's).
const LOG = kind(true);
const TAIL = kind(false);
const log = (id: string): Channel => ({ kind: LOG, station: ST, id });
const tail = (id: string): Channel => ({ kind: TAIL, station: ST, id });
const item = (id: string, n: number) => `${id}:${n}`;

/// A station, a device and the lane between them.
function world() {
  // The station: how far each channel goes (its items are 1 to there, item n of `id` being `id:n`).
  const there = new Map<string, number>();
  const asked: string[] = [];
  const state: { failing: CoreError | null; reached: boolean } = { failing: null, reached: true };
  const answer = (path: string) => {
    const [id, query] = path.split("?") as [string, string];
    const last = there.get(id) ?? 0;
    const q = new URLSearchParams(query);
    let [from, to] = [1, last];
    if (query === "latest") from = Math.max(1, last - PAGE + 1);
    else if (q.has("after")) from = Number(q.get("after")) + 1;
    else if (q.has("before")) [from, to] = [Math.max(1, Number(q.get("before")) - PAGE), Number(q.get("before")) - 1];
    else [from, to] = [Number(q.get("from")), Math.min(last, Number(q.get("to")))];
    return { last, items: run(from, to).map((n) => [n, item(id, n)] as [number, unknown]) };
  };

  // The device: the items it holds by number, how far each channel is known to go, and those let go for room.
  const items = new Map<string, Map<number, unknown>>();
  const heads = new Map<string, number>();
  const letGo = new Set<string>();
  const key = (c: Channel) => `${c.kind.name}/${c.id}`;
  const of = (c: Channel) => items.get(key(c)) ?? new Map<number, unknown>();
  const numbers = (c: Channel) => [...of(c).keys()].sort((a, b) => a - b);
  const held: Held = {
    numbers,
    span: (c) => (of(c).size === 0 ? null : { min: numbers(c)[0]!, max: numbers(c).at(-1)! }),
    count: (c, from, to) => numbers(c).filter((n) => n >= from && n <= to).length,
    put: (c, put, cutAfter) => {
      const mine = of(c);
      items.set(key(c), mine);
      for (const [n, v] of put) mine.set(n, v);
      if (cutAfter !== null) for (const n of [...mine.keys()]) if (n > cutAfter) mine.delete(n);
    },
    letGo: (c) => letGo.has(key(c)),
    // Only of one brought whole is it kept how far it goes (a thread's summary says; nothing says of a transcript).
    head: (c) => (c.kind.whole ? (heads.get(key(c)) ?? 0) : 0),
    raise: (c, n) => {
      if (c.kind.whole && n > (heads.get(key(c)) ?? 0)) heads.set(key(c), n);
    },
  };

  // The lane: a task a name (asked for again while it waits, it is the same task), the most urgent first.
  type Task = { name: string; priority: number; work: Effect.Effect<void, CoreError>; done: Deferred.Deferred<void, CoreError> };
  const waiting: Task[] = [];
  const later: (() => void)[] = [];
  const answers: [string, string | null, boolean][] = [];
  const reach: Reach = {
    read: (_station, path) =>
      Effect.suspend(() => {
        asked.push(path);
        return state.failing ? Effect.fail(state.failing) : Effect.succeed(answer(path) as unknown);
      }),
    reached: () => state.reached,
    enqueue: (_station, name, priority, work) => {
      const same = waiting.find((t) => t.name === name);
      if (same) {
        same.priority = Math.max(same.priority, priority);
        return same.done;
      }
      const task: Task = { name, priority, work, done: Deferred.makeUnsafe<void, CoreError>() };
      waiting.push(task);
      return task.done;
    },
    later: (_station, work) => void later.push(work),
    answered: (c, error, nothing) => void answers.push([c.id, error?.code ?? null, nothing]),
  };
  const channels = new Channels(held, reach);

  /// Runs what waits until nothing does (a task may ask for another), and `until` is over if given.
  const work = async (until?: Promise<unknown>) => {
    let over = until === undefined;
    until?.then(() => (over = true), () => (over = true));
    for (let turn = 0; turn < 1000 && (!over || waiting.length > 0); turn++) {
      waiting.sort((a, b) => b.priority - a.priority);
      const task = waiting.shift();
      if (task) Deferred.doneUnsafe(task.done, await Effect.runPromise(Effect.exit(task.work)));
      else await new Promise((resolve) => setImmediate(resolve));
    }
    assert.ok(over && waiting.length === 0, "the lane came to rest");
  };
  /// The burst of what the station is saying is over.
  const burstOver = () => {
    for (const w of later.splice(0)) w();
  };
  /// The station says items of a channel as they are added (the push).
  const tell = (c: Channel, ...ns: number[]) => channels.told(c, ns.map((n) => [n, item(c.id, n)]));
  return { there, asked, state, letGo, heads, held, numbers, of, waiting, answers, channels, work, burstOver, tell };
}

test("what_is_told_in_order_is_held_and_nothing_is_read", async () => {
  const w = world();
  const c = log("c");
  for (const n of run(1, 12)) {
    w.there.set("c", n);
    w.tell(c, n);
    // Its summary says so too, before or after: by the time the burst is over the item is held.
    w.channels.goesTo(c, n);
  }
  w.burstOver();
  await w.work();
  assert.deepEqual(w.numbers(c), run(1, 12));
  assert.equal(w.of(c).get(7), "c:7");
  assert.equal(w.held.head(c), 12);
  assert.deepEqual(w.asked, []);
  assert.equal(w.channels.behind(c), false);
});

test("a_hole_what_was_told_left_is_read_at_once_and_once", async () => {
  const w = world();
  const c = log("c");
  w.there.set("c", 7);
  w.tell(c, 1, 2, 3);
  // 4 and 5 never came: 6 shows the hole, and 7 comes before it is read.
  w.tell(c, 6);
  assert.equal(w.channels.behind(c), true);
  w.tell(c, 7);
  assert.deepEqual(w.waiting.map((t) => `${t.name}@${t.priority}`), [`read/c@${Priority.shown}`], "one task, however often it is found behind");
  await w.work();
  assert.deepEqual(w.asked, ["c?from=4&to=5"]);
  assert.deepEqual(w.numbers(c), run(1, 7));
  assert.equal(w.channels.behind(c), false);
});

test("behind_by_several_holes_it_is_read_until_it_is_not_and_no_further_back", async () => {
  const w = world();
  const c = log("c");
  w.there.set("c", 20);
  // Held from 8 on, with three holes and short of its end: what came after first, then each hole from the highest down.
  w.tell(c, 8, 9, 12, 15, 16, 18);
  w.channels.goesTo(c, 20);
  w.burstOver();
  await w.work();
  assert.deepEqual(w.asked, ["c?after=18", "c?from=17&to=17", "c?from=13&to=14", "c?from=10&to=11"]);
  assert.deepEqual(w.numbers(c), run(8, 20));
  assert.equal(w.channels.behind(c), false);
  // What is before all that is held is not read for that: it is brought whole, in the background.
  assert.deepEqual(w.channels.next(c), { from: 3, to: 7 });
  // A hole the station does not fill (it answers nothing for it) is asked once, not over and over.
  w.there.set("c", 22);
  w.tell(c, 22);
  w.there.set("c", 20);
  const asked = w.asked.length;
  await w.work();
  assert.deepEqual(w.asked.slice(asked), ["c?from=21&to=21"]);
  assert.equal(w.channels.behind(c), true);
});

test("said_to_go_further_it_is_read_once_the_burst_is_over_whoever_said_so", async () => {
  const w = world();
  const c = log("c");
  w.tell(c, 1, 2, 3);
  // Its summary alone says it goes to 5 (the items were never told): not read before the burst is over.
  w.there.set("c", 5);
  w.channels.goesTo(c, 5);
  await w.work();
  assert.deepEqual(w.asked, []);
  w.burstOver();
  await w.work();
  assert.deepEqual(w.asked, ["c?after=3"]);
  assert.deepEqual(w.numbers(c), run(1, 5));
  // The answer to a read says how far it goes as well: the station went on to 8, and only 7 was told. The read of
  // the hole is answered that it goes to 8, and what came after is read with it.
  w.there.set("c", 8);
  w.tell(c, 7);
  await w.work();
  assert.deepEqual(w.asked, ["c?after=3", "c?from=6&to=6", "c?after=7"]);
  assert.deepEqual(w.numbers(c), run(1, 8));
  w.burstOver();
  await w.work();
  assert.equal(w.asked.length, 3);
  // Said to go no further than what is held: nothing.
  w.channels.goesTo(c, 6);
  w.burstOver();
  await w.work();
  assert.equal(w.asked.length, 3);
  assert.equal(w.held.head(c), 8, "how far it goes is never lowered");
});

test("none_of_it_held_it_is_not_behind_and_is_brought_from_its_latest_page_back_to_its_first", async () => {
  const w = world();
  const c = log("c");
  w.there.set("c", 12);
  // Said to go to 12 with nothing held: that is no hole, and nothing is read for it.
  w.channels.goesTo(c, 12);
  w.burstOver();
  await w.work();
  assert.deepEqual(w.asked, []);
  assert.equal(w.channels.latestMissing(c), true);
  // A UI shows it: its latest page alone, at once.
  w.channels.bring(c, Priority.shown, "latest");
  await w.work();
  assert.deepEqual(w.asked, ["c?latest"]);
  assert.deepEqual(w.numbers(c), run(8, 12));
  assert.equal(w.channels.latestMissing(c), false);
  assert.equal(w.channels.behind(c), false, "what is before all that is held is not a hole");
  // In the background: the pages before, down to its first, a page a run.
  w.channels.bring(c, Priority.background);
  await w.work();
  assert.deepEqual(w.asked, ["c?latest", "c?from=3&to=7", "c?from=1&to=2"]);
  assert.deepEqual(w.numbers(c), run(1, 12));
  assert.equal(w.channels.next(c), null);
  w.channels.bring(c, Priority.background);
  await w.work();
  assert.equal(w.asked.length, 3, "all of it held: nothing more is read");
});

test("one_not_brought_whole_has_its_latest_page_and_what_is_before_as_asked", async () => {
  const w = world();
  const t = tail("t");
  w.there.set("t", 12);
  w.channels.bring(t, Priority.background);
  await w.work();
  assert.deepEqual(w.asked, ["t?latest"]);
  assert.deepEqual(w.numbers(t), run(8, 12));
  // Nothing more by itself, and what is told past a hole is put as it is: its hole is not read.
  w.channels.bring(t, Priority.background);
  w.tell(t, 20);
  w.channels.catchUp(t, Priority.shown);
  await w.work();
  assert.deepEqual(w.asked, ["t?latest"]);
  assert.equal(w.channels.behind(t), false);
  // Gone back to: the page before, read where not all of it is held.
  await Effect.runPromise(w.channels.older(t, 8, { quiet: false }));
  assert.deepEqual(w.asked, ["t?latest", "t?before=8"]);
  assert.deepEqual(w.numbers(t), [...run(3, 12), 20]);
  await Effect.runPromise(w.channels.older(t, 8, { quiet: false }));
  await Effect.runPromise(w.channels.older(t, 1, { quiet: false }));
  assert.equal(w.asked.length, 2, "held, or nothing before it: not read");
});

test("a_stream_that_was_away_has_it_asked_what_came_after_what_is_held_whatever_is_said_of_it", async () => {
  const w = world();
  const c = log("c");
  w.tell(c, 1, 2, 3);
  // The station went on to 5 and nothing said so (the stream was away): how far it goes is as old as what is held.
  w.there.set("c", 5);
  assert.equal(w.channels.behind(c), false);
  w.channels.catchUp(c, Priority.shown);
  await w.work();
  assert.deepEqual(w.asked, ["c?after=3"]);
  assert.deepEqual(w.numbers(c), run(1, 5));
  assert.equal(w.held.head(c), 5);
  // Nothing came since: asked all the same, as nothing else would say so.
  w.channels.catchUp(c, Priority.shown);
  await w.work();
  assert.deepEqual(w.asked, ["c?after=3", "c?after=5"]);
  // Asked while a read of it waits: the same task, which asks what came after first.
  w.there.set("c", 6);
  const d = log("d");
  w.there.set("d", 9);
  w.tell(d, 5, 6);
  w.channels.bring(d, Priority.background);
  w.channels.catchUp(d, Priority.shown);
  assert.deepEqual(w.waiting.map((t) => `${t.name}@${t.priority}`), [`read/d@${Priority.shown}`]);
  await w.work();
  assert.deepEqual(w.asked.slice(2), ["d?after=6", "d?from=1&to=4"]);
  assert.deepEqual(w.numbers(d), run(1, 9));
  // One none of which is held is not asked: it is brought when it is to be.
  w.there.set("e", 4);
  w.channels.catchUp(log("e"), Priority.shown);
  await w.work();
  assert.equal(w.asked.length, 4);
});

test("a_message_sent_into_it_is_waited_on_until_it_is_held", async () => {
  const w = world();
  const c = log("c");
  w.tell(c, 1, 2, 3);
  // Sent, and given number 5 (another came in before it): what came after what is held is read before it answers.
  w.there.set("c", 5);
  await w.work(Effect.runPromise(w.channels.sent(c, 5)));
  assert.deepEqual(w.asked, ["c?after=3"]);
  assert.deepEqual(w.numbers(c), run(1, 5));
  // Told before its answer came: held already, nothing is read.
  w.there.set("c", 6);
  w.tell(c, 6);
  await w.work(Effect.runPromise(w.channels.sent(c, 6)));
  assert.equal(w.asked.length, 1);
  // The read failing does not fail the sending: the message went.
  w.there.set("c", 7);
  w.state.failing = new CoreError("network", "连不上");
  await w.work(Effect.runPromise(w.channels.sent(c, 7)));
  assert.equal(w.held.head(c), 7);
  assert.deepEqual(w.numbers(c), run(1, 6));
});

test("a_stretch_and_the_page_before_are_read_for_one_who_waits_and_fail_as_the_read_does", async () => {
  const w = world();
  const c = log("c");
  w.there.set("c", 30);
  w.tell(c, ...run(20, 30));
  await Effect.runPromise(w.channels.range(c, 12, 14, { quiet: false }));
  await Effect.runPromise(w.channels.older(c, 12, { quiet: false }));
  assert.deepEqual(w.asked, ["c?from=12&to=14", "c?before=12"]);
  assert.deepEqual(w.numbers(c), [...run(7, 14), ...run(20, 30)]);
  // All held, or nothing asked: no read.
  await Effect.runPromise(w.channels.range(c, 20, 25, { quiet: false }));
  await Effect.runPromise(w.channels.range(c, 9, 8, { quiet: false }));
  assert.equal(w.asked.length, 2);
  // It fails as the read does, and nothing is put.
  w.state.failing = new CoreError("http_500", "坏了", 500);
  const failed = await Effect.runPromise(Effect.result(w.channels.range(c, 15, 19, { quiet: false })));
  assert.equal(failed._tag === "Failure" && failed.failure.code, "http_500");
  assert.deepEqual(w.numbers(c), [...run(7, 14), ...run(20, 30)]);
  // Only what was asked for is put, whatever the answer holds: a read of items 3 to 4 answered with more.
  w.state.failing = null;
  assert.equal(await Effect.runPromise(w.channels.read(c, { before: 5 }, { quiet: true })), 4);
  assert.deepEqual(w.numbers(c).slice(0, 4), run(1, 4));
});

test("a_read_in_the_background_says_how_it_was_answered_and_a_station_not_reached_is_not_asked", async () => {
  const w = world();
  const c = log("c");
  w.there.set("c", 9);
  // Not reached: nothing is asked.
  w.state.reached = false;
  w.channels.bring(c, Priority.background);
  await w.work();
  assert.deepEqual(w.asked, []);
  // Reached, and answered no: said so, with none of it held; nothing is asked after it.
  w.state.reached = true;
  w.state.failing = new CoreError("http_403", "不是你的", 403);
  w.channels.bring(c, Priority.background);
  await w.work();
  assert.deepEqual(w.asked, ["c?latest"]);
  assert.deepEqual(w.answers, [["c", "http_403", true]]);
  assert.deepEqual(w.numbers(c), []);
  // Answered: said so too (what was said of it before no longer holds).
  w.state.failing = null;
  w.channels.bring(c, Priority.background, "latest");
  await w.work();
  assert.deepEqual(w.answers.at(-1), ["c", null, true]);
  assert.deepEqual(w.numbers(c), run(5, 9));
});

test("one_let_go_for_room_is_left_as_it_is", async () => {
  const w = world();
  const c = log("c");
  w.there.set("c", 9);
  w.tell(c, 1, 2, 3);
  w.letGo.add("log/c");
  // Told: it goes that far, and nothing is put or read.
  w.tell(c, 9);
  w.channels.goesTo(c, 9);
  w.channels.bring(c, Priority.shown);
  w.channels.catchUp(c, Priority.shown);
  w.burstOver();
  await w.work();
  assert.equal(w.held.head(c), 9);
  assert.deepEqual(w.numbers(c), [1, 2, 3]);
  assert.deepEqual(w.asked, []);
  assert.equal(w.channels.next(c), null);
  // Shown again: behind, and read.
  w.letGo.delete("log/c");
  w.channels.settle(c);
  await w.work();
  assert.deepEqual(w.asked, ["c?after=3"]);
  assert.deepEqual(w.numbers(c), run(1, 9));
});

test("written_anew_from_before_its_end_what_was_past_that_goes", () => {
  const w = world();
  const t = tail("t");
  w.tell(t, 1, 2, 3, 4, 5);
  // Items 3 and 4 written anew, and the channel ending there now.
  w.channels.told(t, [[3, "t:3 again"], [4, "t:4 again"]], 4);
  assert.deepEqual(w.numbers(t), [1, 2, 3, 4]);
  assert.equal(w.of(t).get(3), "t:3 again");
  // Written anew as nothing from 2 on.
  w.channels.told(t, [], 1);
  assert.deepEqual(w.numbers(t), [1]);
});

test("a_channels_next_read_as_one_of_a_batch", () => {
  const w = world();
  const c = log("c");
  w.there.set("c", 12);
  // A sweep asks each channel its next read, and gives it the answer; it goes on while items come.
  const paths: string[] = [];
  for (let read = w.channels.batched(c), turn = 0; read !== null && turn < 10; read = w.channels.batched(c), turn++) {
    paths.push(read.path);
    const [id, query] = read.path.split("?");
    const from = query === "latest" ? 8 : Number(new URLSearchParams(query).get("from"));
    const to = query === "latest" ? 12 : Number(new URLSearchParams(query).get("to"));
    assert.equal(read.took({ _tag: "Success", success: { last: 12, items: run(from, to).map((n) => [n, item(id!, n)]) } }), to - from + 1);
  }
  assert.deepEqual(paths, ["c?latest", "c?from=3&to=7", "c?from=1&to=2"]);
  assert.deepEqual(w.numbers(c), run(1, 12));
  // One that fails says so, and brings nothing.
  const d = log("d");
  assert.equal(w.channels.batched(d)!.took({ _tag: "Failure", failure: new CoreError("http_404", "没有", 404) }), 0);
  assert.deepEqual(w.answers.at(-1), ["d", "http_404", true]);
  // One not brought whole: its latest page while none is held, then nothing.
  const t = tail("t");
  assert.equal(w.channels.batched(t)!.path, "t?latest");
  w.tell(t, 4);
  assert.equal(w.channels.batched(t), null);
});

/// A generator of numbers in [0, 1) from a seed (mulberry32).
function random(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

test("whatever_the_push_drops_doubles_or_delays_a_channel_ends_whole_once_anything_says_how_far_it_goes", async () => {
  for (const seed of seeds()) {
    const next = random(seed);
    const w = world();
    const c = log("c");
    const LAST = 80;
    // What happened, for a failure to say.
    const did: string[] = [];
    const delayed: number[] = [];
    const tell = (n: number, how: string) => {
      did.push(`${how} ${n}`);
      w.tell(c, n);
    };
    for (let n = 1; n <= LAST; n++) {
      w.there.set("c", n);
      // The push of item n: lost, late (after others), or as it should be and at times twice.
      const push = next();
      if (push < 0.2) did.push(`lost ${n}`);
      else if (push < 0.35) delayed.push(n);
      else {
        tell(n, "told");
        if (next() < 0.1) tell(n, "again");
      }
      if (delayed.length > 0 && next() < 0.4) tell(delayed.splice(Math.floor(next() * delayed.length), 1)[0]!, "late");
      // And between pushes, in any order: reads run, a summary says how far it goes, a burst ends, a stream comes back.
      const between = next();
      if (between < 0.2) {
        did.push("reads run");
        await w.work();
      } else if (between < 0.3) {
        did.push(`summary ${n}`);
        w.channels.goesTo(c, n);
      } else if (between < 0.4) {
        did.push("burst over");
        w.burstOver();
      } else if (between < 0.45) {
        did.push("stream back");
        w.channels.catchUp(c, Priority.shown);
      }
    }
    const told = `seed ${seed}: ${did.join(", ")}`;
    // The last word: its summary says how far it goes. No push after it, nothing else.
    w.channels.goesTo(c, LAST);
    w.burstOver();
    await w.work();
    w.burstOver();
    await w.work();
    const numbers = w.numbers(c);
    assert.ok(numbers.length > 0, told);
    assert.deepEqual(numbers, run(numbers[0]!, LAST), `nothing is missing from the first item held on. ${told}`);
    assert.equal(w.channels.behind(c), false, told);
    for (const n of numbers) assert.equal(w.of(c).get(n), item("c", n), told);
    // What was lost before anything was held is no hole: it comes with the rest, in the background.
    w.channels.bring(c, Priority.background);
    await w.work();
    assert.deepEqual(w.numbers(c), run(1, LAST), `all of it, brought in the background. ${told}`);
    // And nothing was read that was held: no read asks what came after the last item, or a stretch held whole.
    assert.ok(w.asked.length <= LAST, `${w.asked.length} reads. ${told}`);
  }
});
