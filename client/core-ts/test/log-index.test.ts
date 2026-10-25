import assert from "node:assert/strict";
import { test } from "node:test";
import { LogIndex, LogIndices } from "../src/db/log-index.ts";
import { missing } from "../src/channels/fill.ts";

test("log_indices_are_bounded_by_numbers_and_log_count_and_evict_the_least_recently_used", () => {
  const cache = new LogIndices(6, 2);
  const a = new LogIndex([1, 2]), b = new LogIndex([3, 4]), c = new LogIndex([5, 6]);
  cache.set("a", a); cache.set("b", b);
  assert.equal(cache.get("a"), a);
  cache.set("c", c);
  assert.equal(cache.get("b"), undefined);
  a.put([3, 4, 5], null);
  cache.set("a", a);
  assert.equal(cache.get("c"), undefined, "growing one log also respects the total numbers budget");
  cache.set("oversized", new LogIndex([0, 1, 2, 3, 4, 5, 6]));
  assert.equal(cache.get("oversized"), undefined);
  assert.equal(cache.get("a"), a);
  cache.clear();
  assert.equal(cache.get("a"), undefined);
});

test("incremental_numbers_and_binary_hole_search_match_a_set_after_arbitrary_changes", () => {
  let state = 193731;
  const random = (n: number) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state % n; };
  const held = new Set<number>();
  const index = new LogIndex([]);
  for (let i = 0; i < 2000; i++) {
    const added = Array.from({ length: random(12) }, () => random(300));
    const cut = random(4) === 0 ? random(300) : null;
    for (const n of added) held.add(n);
    if (cut !== null) for (const n of held) if (n > cut) held.delete(n);
    index.put(added, cut);
    const expected = [...held].sort((a, b) => a - b);
    assert.deepEqual(index.numbers, expected);
    const last = random(350);
    let hole = Math.max(last, expected.at(-1) ?? 0);
    while (hole >= 1 && held.has(hole)) hole--;
    assert.equal(missing(index.numbers, last), hole >= 1 ? hole : null);
    const from = random(300), to = random(300);
    assert.equal(index.count(from, to), expected.filter(n => n >= from && n <= to).length);
  }
});
