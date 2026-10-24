// A chat's own find (src/chat-find.ts, `chat.find.go`): where the reader starts among what was found, how they go along
// it, and which of how many times they are at.
import assert from "node:assert/strict";
import { test } from "node:test";
import { findGo, findPlace, findStart, findStep } from "../src/chat-find.ts";
import { parseCall } from "../src/core/calls.ts";
import { answers, call, cloudCore } from "./helpers.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const HITS = [{ seq: 3, count: 1 }, { seq: 7, count: 2 }, { seq: 12, count: 1 }];

test("the_reader_starts_at_what_is_showing_else_the_nearest_before_else_the_first", () => {
  assert.deepEqual(findStart(HITS, 6, 9), { seq: 7, k: 0 });
  assert.deepEqual(findStart(HITS, 8, 11), { seq: 7, k: 0 }, "none showing: the nearest before");
  assert.deepEqual(findStart(HITS, 1, 2), { seq: 3, k: 0 }, "none before: the first");
  assert.deepEqual(findStart(HITS, null, null), { seq: 3, k: 0 });
  assert.equal(findStart([], 1, 9), null);
});

test("the_next_and_the_one_before_go_along_every_time_round_from_an_end_to_the_other", () => {
  assert.deepEqual(findStep(HITS, { seq: 3, k: 0 }, 1), { seq: 7, k: 0 });
  assert.deepEqual(findStep(HITS, { seq: 7, k: 0 }, 1), { seq: 7, k: 1 }, "the second time in the same message");
  assert.deepEqual(findStep(HITS, { seq: 7, k: 1 }, 1), { seq: 12, k: 0 });
  assert.deepEqual(findStep(HITS, { seq: 12, k: 0 }, 1), { seq: 3, k: 0 }, "round from the last to the first");
  assert.deepEqual(findStep(HITS, { seq: 3, k: 0 }, -1), { seq: 12, k: 0 }, "and back");
  assert.deepEqual(findStep(HITS, { seq: 12, k: 0 }, -1), { seq: 7, k: 1 }, "back into a message: its last time");
  assert.deepEqual(findStep(HITS, null, -1), { seq: 12, k: 0 }, "from nowhere: an end");
  // Its row draws the words once (a link's address held the other): gone along once.
  assert.deepEqual(findStep(HITS, { seq: 7, k: 0 }, 1, { "7": 1 }), { seq: 12, k: 0 });
  assert.deepEqual(findStep(HITS, { seq: 12, k: 0 }, -1, { "7": 1 }), { seq: 7, k: 0 });
});

test("which_of_how_many_times_the_reader_is_at", () => {
  assert.deepEqual(findPlace(HITS, { seq: 7, k: 1 }), { at: { seq: 7, k: 1 }, position: 3, total: 4 });
  assert.deepEqual(findPlace(HITS, null), { at: null, position: 0, total: 4 });
  assert.deepEqual(findPlace(HITS, { seq: 5, k: 0 }), { at: null, position: 0, total: 4 });
  assert.deepEqual(findGo(HITS, null, 0, 10, 20), { at: { seq: 12, k: 0 }, position: 4, total: 4 });
  assert.deepEqual(findGo(HITS, { seq: 12, k: 0 }, 1, null, null), { at: { seq: 3, k: 0 }, position: 1, total: 4 });
  // More of the chat read: where the reader is kept while what was found still has it, else where they start.
  assert.deepEqual(findGo(HITS, { seq: 7, k: 1 }, 0, 10, 20), { at: { seq: 7, k: 1 }, position: 3, total: 4 });
  assert.deepEqual(findGo(HITS, { seq: 5, k: 0 }, 0, 10, 20), { at: { seq: 12, k: 0 }, position: 4, total: 4 });
});

test("a_client_asks_the_core_where_the_reader_goes", async () => {
  assert.deepEqual(parseCall("chat.find.go", { hits: HITS, at: { seq: 7, k: 0 }, by: 1 }), {
    kind: "chatFindGo", hits: HITS, at: { seq: 7, k: 0 }, by: 1, from: null, to: null, drawn: {},
  });
  const { host, core } = await cloudCore();
  const ui = core.connect();
  call(core, ui, 1, "chat.find.go", { hits: HITS, by: 0, from: 6, to: 9 });
  await host.settle();
  assert.deepEqual((answers(host.takeEmitted(), 1) as J).ok, { at: { seq: 7, k: 0 }, position: 2, total: 4 });
  call(core, ui, 2, "chat.find.go", { hits: HITS, at: { seq: 7, k: 1 }, by: -1, drawn: { "7": 2 } });
  await host.settle();
  assert.deepEqual((answers(host.takeEmitted(), 2) as J).ok, { at: { seq: 7, k: 0 }, position: 2, total: 4 });
  // Its params read as the other calls' are: a step is one of -1, 0, 1.
  call(core, ui, 3, "chat.find.go", { hits: HITS, by: 2 });
  await host.settle();
  assert.ok("error" in (answers(host.takeEmitted(), 3) as J));
  core.close();
});
