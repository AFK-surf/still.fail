// Which of a channel's items are yet to be brought (src/station/channel-fill.ts), from the numbers held and how far it
// goes; how the two kinds of channel are asked for (src/station/channel-kinds.ts); and where a device is in a station's
// log of events (src/station/cursor.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Cursor } from "../src/station/cursor.ts";
import { behind, latestMissing, missing, next } from "../src/station/channel-fill.ts";
import { ENTRIES, TRANSCRIPT } from "../src/station/channel-kinds.ts";

const run = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => from + i);

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

test("a_read_as_the_station_takes_it", () => {
  assert.equal(ENTRIES.path("7", { latest: true }), "/threads/7/entries?limit=50");
  assert.equal(ENTRIES.path("7", { after: 12 }), "/threads/7/entries?after=12");
  assert.equal(ENTRIES.path("7", { from: 11, to: 12 }), "/threads/7/entries?from=11&to=12");
  assert.equal(ENTRIES.path("7", { before: 51 }), "/threads/7/entries?before=51&limit=50");
  assert.equal(TRANSCRIPT.path("k 1", { latest: true }), "/sessions/k%201/timeline?before=1000000000000000&limit=200&brief=1");
  assert.equal(TRANSCRIPT.path("k1", { before: 400 }), "/sessions/k1/timeline?before=400&limit=200&brief=1");
  assert.equal(TRANSCRIPT.path("k1", { from: 3, to: 9 }), "/sessions/k1/timeline?from=3&to=9");
});

test("what_an_answer_holds_by_number", () => {
  // A thread's entries say their numbers, and the answer how far the thread goes.
  const page = { last: 9, entries: [{ n: 7, text: "a" }, { text: "no number" }, { n: 8, text: "b" }] };
  assert.deepEqual(ENTRIES.items(page, { after: 6 }).map(([n]) => n), [7, 8]);
  assert.equal(ENTRIES.last(page), 9);
  // A transcript's page says where it starts (one that does not starts where it was asked from); it says nothing of
  // how far the transcript goes.
  assert.deepEqual(TRANSCRIPT.items({ start: 40, entries: ["x", "y"] }, { latest: true }), [[40, "x"], [41, "y"]]);
  assert.deepEqual(TRANSCRIPT.items({ entries: ["x"] }, { from: 3, to: 3 }), [[3, "x"]]);
  assert.equal(TRANSCRIPT.last({ start: 40, entries: [] }), null);
});

test("a_cursor_is_the_furthest_id_heard_of_a_run_written_down_as_it_moves", () => {
  const c = new Cursor();
  assert.equal(c.since, null);
  assert.equal(c.toKeep(), null);
  assert.equal(c.restored, false);
  c.heard("1f2e3d4c.9");
  assert.equal(c.since, "1f2e3d4c.9");
  assert.equal(c.toKeep(), "1f2e3d4c.9");
  assert.equal(c.toKeep(), null, "as last written");
  // Streams overlap as one takes over: an id below the furthest heard moves nothing; what is no id either.
  c.heard("1f2e3d4c.4");
  c.heard("not an id");
  assert.equal(c.since, "1f2e3d4c.9");
  assert.equal(c.toKeep(), null);
  // The station started anew: its run's ids, however low.
  c.heard("0a0a0a0a.2");
  assert.equal(c.since, "0a0a0a0a.2");
  assert.equal(c.toKeep(), "0a0a0a0a.2");
});

test("a_cursor_goes_on_from_what_a_core_before_wrote_down", () => {
  const c = new Cursor("1f2e3d4c.9");
  assert.equal(c.since, "1f2e3d4c.9");
  assert.equal(c.restored, true);
  assert.equal(c.toKeep(), null, "written already");
  // Nothing written down, or nothing an id: it starts afresh.
  assert.equal(new Cursor(null).restored, false);
  assert.equal(new Cursor("gibberish").since, null);
});
