// A loaded list keeps its rows in order as they change one at a time (db/account.ts Collection): the same order as
// sorting all of them, for rows put, moved and taken out in any order.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Collection } from "../src/db/account.ts";

test("a_list_kept_in_order_row_by_row_is_the_list_sorted_whole", () => {
  for (const descending of [false, true]) {
    const list = new Collection(descending);
    const sorts = new Map<string, number[]>();
    // (a fixed sequence: the same every run)
    let seed = 7;
    const next = () => (seed = (seed * 1103515245 + 12345) % 2147483648);
    for (let i = 0; i < 40; i++) {
      list.set(`r${i}`, { id: `r${i}` }, [next() % 10]);
      sorts.set(`r${i}`, list.sort.get(`r${i}`)!);
    }
    list.array();
    for (let step = 0; step < 400; step++) {
      const before = list.array();
      const was = before.map((r) => (r as { id: string }).id);
      const id = `r${next() % 50}`;
      if (next() % 5 === 0) {
        list.delete(id);
        sorts.delete(id);
      } else {
        const sort = [next() % 10];
        list.set(id, { id, step }, sort);
        sorts.set(id, sort);
      }
      const d = descending ? -1 : 1;
      const whole = [...sorts.keys()].sort((a, b) => (sorts.get(a)![0]! - sorts.get(b)![0]!) * d || (a < b ? -1 : a > b ? 1 : 0));
      assert.deepEqual(list.array().map((r) => (r as { id: string }).id), whole, `step ${step}`);
      assert.deepEqual(before.map((r) => (r as { id: string }).id), was, "what was given before is as it was");
    }
  }
});
