import assert from "node:assert/strict";
import { test } from "node:test";
import { threadHistory } from "../src/sessions/conversations.ts";
import type { Hub } from "../src/sessions/hub.ts";
import { MESSAGE_PAGE_ENTRIES } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

test("message-page entries seek the requested keys in their own chat", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    const other = store.openThread("ember", "CHAT", "2.1", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at)
      VALUES(?,?,'message','agent','worker',?,?)`);
    put.run(thread, 1, "first", 1); put.run(thread, 2, "not on page", 2); put.run(thread, 3, "third", 3);
    put.run(other, 1, "other chat", 1);
    assert.deepEqual(store.messagePageEntries(thread, [3, 1, 99]).map((e) => e.text), ["first", "third"]);
    assert.deepEqual(store.messagePageEntries(thread, [1, 2, 3]).map((e) => e.text), ["first", "not on page", "third"]);
    assert.deepEqual(store.messagePageEntries(thread, []), []);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${MESSAGE_PAGE_ENTRIES}`).all(thread, "[3,1,99]") as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH e USING INDEX sqlite_autoindex_entries_1 \(thread=\? AND n=\?\)/);
  } finally { store.close(); }
});

test("chat history shows its page's cards without reading the entries between its messages", async () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card,options)
      VALUES(?,?,?,?,'agent','worker',?,?,?,?)`);
    db.exec("BEGIN");
    put.run(thread.id, 1, "message", "1.1", "first", 1, null, JSON.stringify([{ label: "First" }]));
    for (let n = 2; n <= 81; n++) put.run(thread.id, n, "edit", null, `other-${n}`, n, null, null);
    put.run(thread.id, 82, "message", "82.1", "second", 82,
      JSON.stringify({ type: "options", options: [{ label: "Second" }] }), null);
    db.exec("COMMIT");

    // Observe rows returned by the existing range read: the intervening entries are not part of this page.
    const entriesBetween = store.entriesBetween.bind(store);
    let largestRange = 0;
    store.entriesBetween = (...args) => {
      const entries = entriesBetween(...args);
      largestRange = Math.max(largestRange, entries.length);
      return entries;
    };
    const hub = { store, chatOf: () => null } as unknown as Hub;
    const read = (args: Record<string, unknown>) => threadHistory(hub, "worker", thread, "internal", "CHAT/1.1", args);
    const parts = (await read({ limit: 2 })).split("</message>");
    assert.match(parts[0]!, /first[\s\S]*Answer card: no longer pending[\s\S]*First/);
    assert.match(parts[1]!, /second[\s\S]*Answer card: pending[\s\S]*Second/);
    const earlier = await read({ before: "82.1", limit: 2 });
    assert.match(earlier, /first[\s\S]*Answer card: no longer pending[\s\S]*First/);
    assert.doesNotMatch(earlier, /second|Second/);
    assert.ok(largestRange <= 2, `the two-message page read ${largestRange} entries between its messages`);
  } finally { store.close(); }
});
