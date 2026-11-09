import assert from "node:assert/strict";
import { test } from "node:test";
import { lastMessage as readLastMessage, makeStore } from "../src/read/store.ts";
import { LAST_MESSAGE, toMessage } from "../src/store/rows.ts";
import { MERGED } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

for (const side of ["station", "reader"] as const) {
  test(`${side} finds a chat's last message without traversing its later edits`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", "last-message", null, null).id;
      const insert = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
        VALUES(?,?,?,?, 'person','viewer',?,?)`);
      insert.run(thread, 1, "message", null, "original", 1);
      const add = (from: number, to: number) => {
        db.exec("BEGIN");
        for (let n = from; n <= to; n++) insert.run(thread, n, "edit", 1, `edit-${n}`, n);
        db.exec("COMMIT");
      };
      add(2, 41);
      let visits = 0;
      db.function("visited_message_kind", (kind) => { visits++; return kind; });
      db.exec("DROP VIEW merged");
      db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_message_kind(m.kind) = 'message'"));
      const read = () => side === "station" ? store.lastMessage(thread) : readLastMessage(makeStore(db, "/no-station-config"), thread);
      assert.equal(read()?.text, "edit-41");
      const before = visits;
      assert.ok(before > 0, "the message lookup was observed");
      add(42, 401);
      visits = 0;
      const last = read();
      assert.equal(last?.n, 1);
      assert.equal(last?.text, "edit-401");
      assert.equal(visits, before, `message candidates grew from ${before} to ${visits}`);
    } finally { store.close(); }
  });
}

test("the last message keeps old letters, edits and the original entry order", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "last-message", null, null).id;
    const other = store.openThread("ember", "CHAT", "other", null, null).id;
    const reader = makeStore(db, "/no-station-config");
    const original = db.prepare("SELECT * FROM merged WHERE thread = ? ORDER BY n DESC LIMIT 1");
    const expected = () => { const row = original.get(thread); return row === undefined ? null : toMessage(row); };
    const check = () => {
      assert.deepEqual(store.lastMessage(thread), expected());
      assert.deepEqual(readLastMessage(reader, thread), expected());
    };
    const insert = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,letter)
      VALUES(?,?,?,?, 'agent','author',?,?,?)`);
    const letter = JSON.stringify({ way: "in", title: "old", link: null });
    check();
    insert.run(other, 100, "message", null, "other", 100, null);
    insert.run(thread, 1, "message", null, "normal", 300, null);
    check();
    insert.run(thread, 2, "message", null, "old letter", 100, letter);
    insert.run(thread, 3, "edit", 2, "edited letter", 400, null);
    check();
    insert.run(thread, 4, "message", null, "later normal", 20, null);
    insert.run(thread, 5, "edit", 4, "edited normal", 500, null);
    insert.run(thread, 6, "edit", 2, "letter edit with metadata", 600, letter);
    check();
    insert.run(thread, 7, "message", null, "latest letter", 10, letter);
    check();
    db.exec("DROP INDEX entries_letters");
    check();
    db.prepare("DELETE FROM entries WHERE thread = ? AND n = 7").run(thread);
    check();
  } finally { store.close(); }
});

test("the last message seeks the message and legacy-letter indexes", () => {
  const store = Store.open(":memory:");
  try {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${LAST_MESSAGE}`).all(1) as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH m USING INDEX sqlite_autoindex_entries_1 \(thread=\? AND n=\?\)/);
    assert.match(plan, /SEARCH entries USING COVERING INDEX entries_said \(thread=\?\)/);
    assert.match(plan, /SEARCH entries USING INDEX entries_letters \(thread=\?\)/);
  } finally { store.close(); }
});
