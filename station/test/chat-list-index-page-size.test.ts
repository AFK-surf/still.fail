import assert from "node:assert/strict";
import { test } from "node:test";
import { readPreparedDefaultHome } from "../src/store/chat-list-home-index.ts";
import { installRecentHomeOverlap, readPreparedRecentHome } from "../src/store/chat-list-home-overlap.ts";
import { installRecentChatIndex, readGlobalRecentChatIndex } from "../src/store/chat-list-index.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

test("recent index pages reject sizes that could make a bounded read unbounded", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installRecentChatIndex(db);
    installRecentHomeOverlap(db);
    const reads = [
      (limit: number) => readGlobalRecentChatIndex(db, limit),
      (limit: number) => readPreparedRecentWorkspace(db, "here", limit),
      (limit: number) => readPreparedDefaultHome(db, limit),
      (limit: number) => readPreparedRecentHome(db, "here", limit),
    ];
    for (const read of reads) {
      assert.deepEqual(read(0), { ids: [], total: 0 });
      for (const limit of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1])
        assert.throws(() => read(limit), RangeError, `invalid page size ${limit}`);
    }
  } finally { store.close(); }
});
