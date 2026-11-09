import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CARD_BEFORE_LATEST_PERSON, Store } from "../src/store/store.ts";

for (const column of ["card", "options"] as const) for (const event of ["answer", "replacement"] as const) {
  test(`an old ${column} ended before the latest person is skipped for a later ${event}`, () => {
    const visited: number[] = [];
    for (const size of [40, 400]) {
      const store = Store.open(":memory:"), db = store.db;
      try {
        const thread = store.openThread("slack:T", "C", `old-${column}-${event}-${size}`, null, null).id;
        db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread);
        const value = column === "card" ? '{"type":"text"}' : '["yes"]';
        const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,${column})
          VALUES(?,?,?,?,?,?,?,?,?)`);
        db.exec("BEGIN");
        put.run(thread, 1, "message", null, "agent", "a", "old question", 1, value);
        for (let n = 2; n <= size + 1; n++) put.run(thread, n, "edit", 1, "agent", "a", "edit", n, value);
        put.run(thread, size + 2, "message", null, "person", "p", "answer", size + 2, null);
        if (event === "answer") put.run(thread, size + 3, "message", null, "person", "p", "later", size + 3, null);
        else put.run(thread, size + 3, "message", null, "agent", "a", "new card", size + 3, value);
        db.exec("COMMIT");

        let count = 0, instrumented = 0;
        db.function("visited_card_candidate", (_n) => { count++; return 1; });
        const traced = new Proxy(db, {
          get(target, property) {
            if (property === "prepare") return (sql: string) => {
              const observed = sql.replace(/kind\s*=\s*'message'\s+AND\s+(card|options)\s+IS\s+NOT\s+NULL/gi,
                (match) => `visited_card_candidate(n) AND ${match}`);
              if (observed !== sql) instrumented++;
              return target.prepare(observed);
            };
            const value = Reflect.get(target, property, target);
            return typeof value === "function" ? value.bind(target) : value;
          },
        });
        (store as any).db = traced;
        const ended = event === "answer" ? store.cardEndedByMessage(thread, size + 3) : store.cardReplacedBy(thread, size + 3);
        assert.equal(ended, null);
        assert.ok(instrumented > 0, "instrument the event's source-card lookup");
        visited.push(count);
      } finally { (store as any).db = db; store.close(); }
    }
    assert.ok(visited[1]! <= visited[0]! + 2 && visited[1]! <= 8,
      `old ${column} candidates visited before a later ${event}: ${visited.join(" / ")}`);
  });
}

for (const column of ["card", "options"] as const) for (const missingIndexes of [false, true]) {
  test(`an unprepared ${column} keeps event order${missingIndexes ? " without the old indexes" : ""}`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("slack:T", "C", `order-${column}-${missingIndexes}`, null, null).id;
      db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread);
      const card = column === "card" ? '{"type":"text"}' : '["yes"]';
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,${column})
        VALUES(?,?,'message',?,?,?,?,?)`);
      put.run(thread, 1, "person", "p", "first", 1, null);
      put.run(thread, 2, "agent", "a", "A", 2, card);
      put.run(thread, 3, "person", "p", "answer", 3, null);
      put.run(thread, 4, "agent", "a", "B", 4, card);
      put.run(thread, 5, "person", "p", "person's card", 5, card);
      put.run(thread, 6, "person", "p", "answer it", 6, null);
      put.run(thread, 7, "agent", "a", "D", 7, card);
      put.run(thread, 8, "agent", "a", "E", 8, card);
      if (missingIndexes) db.exec("DROP INDEX entries_cards; DROP INDEX entries_options");
      assert.equal(store.cardEndedByMessage(thread, 3)?.[0].n, 2);
      assert.equal(store.cardReplacedBy(thread, 4), null);
      assert.equal(store.cardEndedByMessage(thread, 5)?.[0].n, 4);
      assert.equal(store.cardEndedByMessage(thread, 6)?.[0].n, 5, "a person's own card is included at the boundary");
      assert.equal(store.cardReplacedBy(thread, 7), null);
      assert.equal(store.cardReplacedBy(thread, 8)?.[0].n, 7);
    } finally { store.close(); }
  });
}

test("an old card event seeks the person and both card formats by number", () => {
  const store = Store.open(":memory:");
  try {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${CARD_BEFORE_LATEST_PERSON}`).all(1, 10) as { detail: string }[])
      .map((row) => row.detail).join(" | ");
    for (const index of ["entries_people_by_n", "entries_cards", "entries_options"]) assert.ok(plan.includes(index), plan);
  } finally { store.close(); }
});

test("the last person and older card are read from one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-before-snapshot-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  try {
    const thread = store.openThread("slack:T", "C", "snapshot", null, null).id;
    db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread);
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,?,'message',?,?,?,?,?)");
    put.run(thread, 1, "person", "p", "first", 1, null);
    put.run(thread, 2, "agent", "a", "question", 2, '{"type":"text"}');
    put.run(thread, 5, "person", "p", "answer", 5, null);
    const other = new DatabaseSync(path);
    try {
      let wrote = false;
      db.function("after_person_boundary", (n) => {
        if (!wrote) {
          wrote = true;
          other.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,4,'message','person','p','concurrent',4)").run(thread);
        }
        return n;
      });
      const traced = CARD_BEFORE_LATEST_PERSON.replace("SELECT n FROM entries WHERE thread = ?1",
        "SELECT after_person_boundary(n) FROM entries WHERE thread = ?1");
      assert.notEqual(traced, CARD_BEFORE_LATEST_PERSON);
      assert.equal(db.prepare(traced).get(thread, 5)?.n, 2, "the in-flight read keeps the earlier snapshot");
      assert.ok(wrote);
      assert.equal(db.prepare(CARD_BEFORE_LATEST_PERSON).get(thread, 5)?.n, null, "the next read sees the new answer");
    } finally { other.close(); }
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
