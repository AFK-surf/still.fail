// How a station is asked for its two kinds of channel, and what its answers hold (src/station/channel-kinds.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { ENTRIES, TRANSCRIPT } from "../src/station/channel-kinds.ts";

test("a_read_as_the_station_takes_it", () => {
  assert.equal(ENTRIES.path("7", { latest: true }), "/threads/7/entries?limit=50");
  assert.equal(ENTRIES.path("7", { after: 12 }), "/threads/7/entries?after=12");
  assert.equal(ENTRIES.path("7", { from: 11, to: 12 }), "/threads/7/entries?from=11&to=12");
  assert.equal(ENTRIES.path("7", { before: 51 }), "/threads/7/entries?before=51&limit=50");
  assert.equal(TRANSCRIPT.path("k 1", { latest: true }), "/sessions/k%201/timeline?before=1000000000000000&limit=200&brief=1");
  assert.equal(TRANSCRIPT.path("k1", { before: 400 }), "/sessions/k1/timeline?before=400&limit=200&brief=1");
  // A stretch in brief, but for a step opened (whole); what came after an item, with the latest page for a station that
  // takes no `after`.
  assert.equal(TRANSCRIPT.path("k1", { from: 3, to: 9 }), "/sessions/k1/timeline?from=3&to=9&brief=1");
  assert.equal(TRANSCRIPT.path("k1", { from: 3, to: 9, whole: true }), "/sessions/k1/timeline?from=3&to=9");
  assert.equal(TRANSCRIPT.path("k1", { after: 12 }), "/sessions/k1/timeline?after=12&before=1000000000000000&limit=200&brief=1");
});

test("what_an_answer_holds_by_number", () => {
  // A thread's entries say their numbers, and the answer how far the thread goes.
  const page = { last: 9, entries: [{ n: 7, text: "a" }, { text: "no number" }, { n: 8, text: "b" }] };
  assert.deepEqual(ENTRIES.items(page, { after: 6 }).map(([n]) => n), [7, 8]);
  assert.equal(ENTRIES.last(page), 9);
  // A transcript's page says where it starts (one that does not starts where it was asked from), and how many entries
  // the transcript has (`end`; a station from before does not say).
  assert.deepEqual(TRANSCRIPT.items({ start: 40, entries: ["x", "y"] }, { latest: true }), [[40, "x"], [41, "y"]]);
  assert.deepEqual(TRANSCRIPT.items({ entries: ["x"] }, { from: 3, to: 3 }), [[3, "x"]]);
  assert.equal(TRANSCRIPT.last({ start: 40, entries: [] }), null);
  assert.equal(TRANSCRIPT.last({ start: 40, entries: ["x"], end: 45 }), 44);
  assert.equal(TRANSCRIPT.last({ start: 0, entries: [], end: 0 }), null);
});
