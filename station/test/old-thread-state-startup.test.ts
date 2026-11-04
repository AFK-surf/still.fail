import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { addListState } from "../src/store/schema.ts";

test("installing old thread state seeks its boundaries instead of reading a long chat", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE entries (thread INTEGER NOT NULL, n INTEGER NOT NULL, kind TEXT NOT NULL,
        author_kind TEXT NOT NULL, author TEXT NOT NULL, letter TEXT, PRIMARY KEY (thread, n));
      CREATE INDEX entries_said ON entries (thread, n, author_kind, author, letter) WHERE kind = 'message' AND letter IS NULL;
      CREATE INDEX entries_people_by_n ON entries (thread, n) WHERE author_kind = 'person' AND kind = 'message';
      CREATE INDEX entries_letters ON entries (thread, n) WHERE letter IS NOT NULL;
      CREATE TABLE deliveries (thread INTEGER NOT NULL, n INTEGER NOT NULL, session TEXT NOT NULL,
        delivered_at INTEGER, PRIMARY KEY (thread, n, session));
      CREATE INDEX deliveries_session ON deliveries (session, thread);`);
    const put = db.prepare("INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?)");
    db.exec("BEGIN");
    for (let n = 0; n < 10_000; n++) put.run(-5, n, "message", "agent", "a", null);
    put.run(77, -2, "edit", "agent", "a", null);
    put.run(77, 1, "edit", "agent", "a", "not a message");
    put.run(78, -4, "message", "person", "p", "letter");
    put.run(78, 8, "message", "agent", "a", "letter");
    put.run(78, 9, "message", "person", "q", null);
    put.run(78, 11, "message", "person", "p", null);
    db.exec("COMMIT");
    const expected = db.prepare(`SELECT thread, MAX(n) AS last_n,
      MAX(CASE WHEN kind = 'message' AND letter IS NULL THEN n END) AS said_n,
      MIN(CASE WHEN kind = 'message' AND author_kind = 'person' THEN n END) AS person_n,
      COUNT(CASE WHEN kind = 'message' AND letter IS NOT NULL THEN 1 END) AS letters
      FROM entries GROUP BY thread ORDER BY thread`).all();
    const people = db.prepare(`SELECT thread, author, MIN(n) AS first_n FROM entries
      WHERE kind = 'message' AND author_kind = 'person' GROUP BY thread, author ORDER BY thread, author`).all();
    let visited = 0;
    db.function("visit_thread_state", () => { visited++; return 1; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "exec") return (sql: string) => target.exec(sql
          .replace("FROM entries GROUP BY thread", "FROM entries WHERE visit_thread_state() GROUP BY thread")
          .replaceAll("FROM entries AS e WHERE e.thread = t.thread", "FROM entries AS e WHERE visit_thread_state() AND e.thread = t.thread")
          .replaceAll("WHERE e.thread = t.thread AND e.kind", "WHERE visit_thread_state() AND e.thread = t.thread AND e.kind")
          .replaceAll("FROM entries WHERE thread > state_threads.thread", "FROM entries WHERE visit_thread_state() AND thread > state_threads.thread")
          .replaceAll("FROM entries ORDER BY thread LIMIT 1", "FROM entries WHERE visit_thread_state() ORDER BY thread LIMIT 1"));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    addListState(traced);
    assert.deepEqual(db.prepare("SELECT * FROM thread_state ORDER BY thread").all(), expected);
    assert.deepEqual(db.prepare("SELECT * FROM thread_people ORDER BY thread, author").all(), people);
    assert.ok(visited <= 50, `installing thread state examined ${visited} historical entries`);
  } finally { db.close(); }
});
