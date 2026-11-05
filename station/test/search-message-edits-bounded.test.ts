import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { threadDocs } from "../src/search/sources.ts";
import { MERGED } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

test("search reads a chat's messages without traversing later edits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "search-edits", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,?,?, 'person','viewer',?,?)`);
    put.run(thread, 1, "message", null, "original", 1);
    const add = (from: number, to: number) => {
      db.exec("BEGIN");
      for (let n = from; n <= to; n++) put.run(thread, n, "edit", 1, `edited-${n}`, n);
      db.exec("COMMIT");
    };
    add(2, 41);
    let visits = 0;
    db.function("visited_search_message_kind", (kind) => { visits++; return kind; });
    db.exec("DROP VIEW merged");
    db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_search_message_kind(m.kind) = 'message'"));
    const reader = makeStore(db, "/no-station-config");
    const read = () => threadDocs(reader, thread).filter((doc) => doc.kind === "message").map((doc) => doc.body);
    assert.deepEqual(read(), ["edited-41"]);
    const before = visits;
    assert.ok(before > 0, "the message lookup was observed");
    add(42, 401);
    visits = 0;
    assert.deepEqual(read(), ["edited-401"]);
    assert.equal(visits, before, `search candidates grew from ${before} to ${visits}`);
  } finally { store.close(); }
});

test("search continues to the next message batch without traversing edits between batches", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "search-edits-batches", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,?,?, 'person','viewer',?,?)`);
    db.exec("BEGIN");
    for (let n = 1; n <= 256; n++) put.run(thread, n, "message", null, `message-${n}`, n);
    for (let n = 257; n <= 296; n++) put.run(thread, n, "edit", 1, `edited-${n}`, n);
    put.run(thread, 297, "message", null, "next batch", 297);
    db.exec("COMMIT");
    let visits = 0;
    db.function("visited_search_batch_kind", (kind) => { visits++; return kind; });
    db.exec("DROP VIEW merged");
    db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_search_batch_kind(m.kind) = 'message'"));
    const reader = makeStore(db, "/no-station-config");
    const read = () => threadDocs(reader, thread).filter((doc) => doc.kind === "message").map((doc) => doc.body);
    const first = read();
    assert.equal(first.length, 257);
    assert.equal(first[0], "edited-296");
    assert.equal(first[256], "next batch");
    const before = visits;
    assert.ok(before > 256, "the message batches were observed");
    db.exec("BEGIN");
    for (let n = 298; n <= 657; n++) put.run(thread, n, "edit", 1, `edited-${n}`, n);
    db.exec("COMMIT");
    visits = 0;
    const next = read();
    assert.equal(next.length, 257);
    assert.equal(next[0], "edited-657");
    assert.equal(next[256], "next batch");
    assert.equal(visits, before, `search candidates grew from ${before} to ${visits}`);
  } finally { store.close(); }
});
