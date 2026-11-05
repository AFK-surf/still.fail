import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore, messagesBefore as readMessagesBefore } from "../src/read/store.ts";
import { I64_MAX, MESSAGES_BEFORE, toMessage } from "../src/store/rows.ts";
import { MERGED } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

for (const side of ["station", "reader"] as const) {
  test(`${side} finds a page of messages without traversing their later edits`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "EMBER", "message-page", null, null).id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
        VALUES(?,?,?,?, 'person','viewer',?,?)`);
      for (let n = 1; n <= 3; n++) put.run(thread, n, "message", null, `message-${n}`, n);
      const add = (from: number, to: number) => {
        db.exec("BEGIN");
        for (let n = from; n <= to; n++) put.run(thread, n, "edit", 3, `edit-${n}`, n);
        db.exec("COMMIT");
      };
      add(4, 43);
      let visits = 0;
      db.function("visited_page_kind", (kind) => { visits++; return kind; });
      db.exec("DROP VIEW merged");
      db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_page_kind(m.kind) = 'message'"));
      const read = () => side === "station" ? store.messagesBefore(thread, null, 3)
        : readMessagesBefore(makeStore(db, "/no-station-config"), thread, null, 3);
      assert.deepEqual(read().map((m) => [m.n, m.text]), [[1, "message-1"], [2, "message-2"], [3, "edit-43"]]);
      const before = visits;
      assert.ok(before > 0, "the page lookup was observed");
      add(44, 403);
      visits = 0;
      assert.deepEqual(read().map((m) => [m.n, m.text]), [[1, "message-1"], [2, "message-2"], [3, "edit-403"]]);
      assert.equal(visits, before, `page candidates grew from ${before} to ${visits}`);
    } finally { store.close(); }
  });
}

test("message pages keep the original boundaries, order, letters and latest edits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "message-page", null, null).id;
    const other = store.openThread("ember", "EMBER", "other", null, null).id;
    const reader = makeStore(db, "/no-station-config");
    const insert = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,letter)
      VALUES(?,?,?,?, 'person','viewer',?,?,?)`);
    const letter = JSON.stringify({ way: "in", title: "old", link: null });
    insert.run(other, 9, "message", null, "other", 9, null);
    insert.run(thread, 1, "message", null, "first", 40, null);
    insert.run(thread, 2, "message", null, "old letter", 30, letter);
    insert.run(thread, 3, "edit", 1, "first edited", 50, null);
    insert.run(thread, 4, "message", null, "third", 20, null);
    insert.run(thread, 5, "edit", 2, "letter edited", 60, letter);
    insert.run(thread, 6, "message", null, "fourth letter", 10, letter);
    insert.run(thread, 7, "edit", 4, "third edited after boundary", 70, null);
    const original = db.prepare("SELECT * FROM merged WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?");
    const check = () => {
      for (const before of [null, 1, 2, 3, 4, 5, 6, 7, 8]) for (const limit of [-1, 0, 1, 2, 3, 10]) {
        const expected = original.all(thread, before ?? I64_MAX, limit).map(toMessage).reverse();
        assert.deepEqual(store.messagesBefore(thread, before, limit), expected, `station before=${before} limit=${limit}`);
        assert.deepEqual(readMessagesBefore(reader, thread, before, limit), expected, `reader before=${before} limit=${limit}`);
      }
    };
    check();
    db.exec("DROP INDEX entries_letters");
    check();
    db.prepare("DELETE FROM entries WHERE thread = ? AND n = 6").run(thread);
    check();
  } finally { store.close(); }
});

test("message pages seek both message indexes and fetch only their candidates", () => {
  const store = Store.open(":memory:");
  try {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${MESSAGES_BEFORE}`).all(1, I64_MAX, 3) as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH entries USING COVERING INDEX entries_said \(thread=\? AND n<\?\)/);
    assert.match(plan, /SEARCH entries USING INDEX entries_letters \(thread=\? AND n<\?\)/);
    assert.match(plan, /SEARCH m USING INDEX sqlite_autoindex_entries_1 \(thread=\? AND n=\?\)/);
  } finally { store.close(); }
});

test("message pages take only a page from the two ordered message indexes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const short = store.openThread("ember", "EMBER", "short-page", null, null).id;
    const long = store.openThread("ember", "EMBER", "long-page", null, null).id;
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
    db.function("count_page_message", (n) => { ordinary++; return 1; });
    db.function("count_page_letter", (n) => { letters++; return 1; });
    const counted = MESSAGES_BEFORE.replace("AND letter IS NULL\n", "AND letter IS NULL AND count_page_message(n)\n")
      .replace("AND letter IS NOT NULL\n", "AND letter IS NOT NULL AND count_page_letter(n)\n");
    const query = db.prepare(counted);
    const read = (thread: number) => {
      ordinary = 0; letters = 0;
      const rows = query.all(thread, I64_MAX, 3);
      assert.equal(rows.length, 3);
      return { ordinary, letters };
    };
    const before = read(short), after = read(long);
    assert.deepEqual(after, before, "older messages do not add candidates for the same page");
    assert.ok(before.ordinary > 0 && before.letters > 0, "both indexes were observed");
    assert.ok(before.ordinary + before.letters <= 6, "the merge stopped after the page");
  } finally { store.close(); }
});
