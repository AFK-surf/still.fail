// A change to one chat must not read the viewer's marks and answers for every other chat.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { answersSince, dismissed, keptChats, makeStore } from "../src/read/store.ts";

test("a scoped chat update reads marks and answers only for those chats", () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE dismissed (viewer TEXT, thread INTEGER, n INTEGER, at INTEGER, PRIMARY KEY (viewer, thread, n));
    CREATE TABLE kept_chats (viewer TEXT, thread INTEGER, PRIMARY KEY (viewer, thread));
    CREATE TABLE closed_cards (thread INTEGER, n INTEGER, viewer TEXT, at INTEGER, PRIMARY KEY (thread, n));
    CREATE TABLE entries (thread INTEGER, n INTEGER, kind TEXT, author_kind TEXT, at INTEGER);`);
  const mark = db.prepare("INSERT INTO dismissed VALUES ('person', ?, 1, 100)");
  const keep = db.prepare("INSERT INTO kept_chats VALUES ('person', ?)");
  const close = db.prepare("INSERT INTO closed_cards VALUES (?, 1, 'person', 100)");
  for (let i = 1; i <= 2000; i++) { mark.run(i); keep.run(i); close.run(i); }
  const counts: Record<string, number> = {};
  const observed = {
    prepare(sql: string) {
      const statement = db.prepare(sql);
      const table = /\bFROM (dismissed|kept_chats|closed_cards)\b/i.exec(sql)?.[1];
      return {
        all: (...params: any[]) => {
          const rows = statement.all(...params);
          if (table) counts[table] = (counts[table] ?? 0) + rows.length;
          return rows;
        },
        get: (...params: any[]) => statement.get(...params),
      };
    },
  } as unknown as DatabaseSync;
  try {
    const s = makeStore(observed, ".");
    assert.deepEqual([...dismissed(s, "person", [1])], ["1:1"]);
    assert.deepEqual([...keptChats(s, "person", [1])], [1]);
    // The closed card for thread 1 is before the time window; the other 1,999 cannot be relevant.
    db.prepare("UPDATE closed_cards SET at = 0 WHERE thread = 1").run();
    assert.deepEqual(answersSince(s, 50, [1]), []);
    assert.deepEqual(counts, { dismissed: 1, kept_chats: 1, closed_cards: 0 });
  } finally {
    db.close();
  }
});
