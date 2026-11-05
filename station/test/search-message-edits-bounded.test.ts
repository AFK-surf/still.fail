import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { SEARCH_FIRST_MESSAGES, SEARCH_NEXT_MESSAGES, threadDocs } from "../src/search/sources.ts";
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

test("search message batches keep the original bounds, old letters and latest edits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "search-message-bounds", null, null).id;
    const other = store.openThread("ember", "EMBER", "other", null, null).id;
    const insert = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,letter)
      VALUES(?,?,?,?, 'person','viewer',?,?,?)`);
    const letter = JSON.stringify({ way: "in", title: "old", link: null });
    insert.run(other, 2, "message", null, "other", 1, null);
    insert.run(thread, -2, "message", null, "earliest", 60, null);
    insert.run(thread, 1, "message", null, "first", 40, null);
    insert.run(thread, 2, "message", null, "old letter", 30, letter);
    insert.run(thread, 3, "edit", 1, "first edited", 50, null);
    insert.run(thread, 4, "message", null, "third", 20, null);
    insert.run(thread, 5, "edit", 2, "letter edited", 70, letter);
    insert.run(thread, 6, "message", null, "last letter", 10, letter);
    insert.run(thread, 7, "edit", 4, "third edited after bound", 80, null);
    const first = db.prepare(SEARCH_FIRST_MESSAGES), next = db.prepare(SEARCH_NEXT_MESSAGES);
    const oldFirst = db.prepare("SELECT * FROM merged WHERE thread = ? AND n <= ? ORDER BY n LIMIT ?");
    const oldNext = db.prepare("SELECT * FROM merged WHERE thread = ? AND n > ? AND n <= ? ORDER BY n LIMIT ?");
    const check = () => {
      for (const end of [-3, -2, 0, 1, 2, 4, 6, 7, 8]) for (const limit of [0, 1, 3, 10]) {
        assert.deepEqual(first.all(thread, end, limit), oldFirst.all(thread, end, limit), `first end=${end} limit=${limit}`);
        for (const after of [-3, -2, 0, 1, 2, 4, 6, 7, 8]) {
          assert.deepEqual(next.all(thread, after, end, limit), oldNext.all(thread, after, end, limit),
            `after=${after} end=${end} limit=${limit}`);
        }
      }
    };
    check();
    db.exec("DROP INDEX entries_letters");
    check();
    db.prepare("DELETE FROM entries WHERE thread = ? AND n = 6").run(thread);
    check();
  } finally { store.close(); }
});

test("search reads only a batch from the two ordered message indexes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const short = store.openThread("ember", "EMBER", "short-search", null, null).id;
    const long = store.openThread("ember", "EMBER", "long-search", null, null).id;
    const insert = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,letter)
      VALUES(?,?,'message','person','viewer','words',?,?)`);
    const letter = JSON.stringify({ way: "in", title: "old", link: null });
    db.exec("BEGIN");
    for (let n = 1; n <= 400; n++) {
      if (n <= 40) insert.run(short, n, n, n % 9 === 0 ? letter : null);
      insert.run(long, n, n, n % 9 === 0 ? letter : null);
    }
    db.exec("COMMIT");
    let ordinary = 0, letters = 0;
    db.function("count_search_message", (n) => { ordinary++; return 1; });
    db.function("count_search_letter", (n) => { letters++; return 1; });
    const counted = (sql: string) => sql.replace("AND letter IS NULL\n", "AND letter IS NULL AND count_search_message(n)\n")
      .replace("AND letter IS NOT NULL\n", "AND letter IS NOT NULL AND count_search_letter(n)\n");
    const first = db.prepare(counted(SEARCH_FIRST_MESSAGES)), next = db.prepare(counted(SEARCH_NEXT_MESSAGES));
    for (const after of [null, 20]) {
      const read = (thread: number, end: number) => {
        ordinary = 0; letters = 0;
        const rows = after === null ? first.all(thread, end, 3) : next.all(thread, after, end, 3);
        assert.equal(rows.length, 3);
        return { ordinary, letters };
      };
      const before = read(short, 40), later = read(long, 400);
      assert.deepEqual(later, before, "later messages do not add candidates for this batch");
      assert.ok(before.ordinary > 0 && before.letters > 0, "both indexes were observed");
      assert.ok(before.ordinary + before.letters <= 6, "the merge stopped after the batch");
    }
  } finally { store.close(); }
});
