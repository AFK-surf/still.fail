import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import * as schema from "../src/store/schema.ts";

test("installing first deliveries seeks each session's threads without reading their whole history", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE entries (thread INTEGER, n INTEGER, kind TEXT, author_kind TEXT, author TEXT, letter TEXT);
      CREATE TABLE deliveries (thread INTEGER NOT NULL, n INTEGER NOT NULL, session TEXT NOT NULL, delivered_at INTEGER,
        PRIMARY KEY (thread, n, session));
      CREATE INDEX deliveries_session ON deliveries (session, thread)`);
    const put = db.prepare("INSERT INTO deliveries(rowid,thread,n,session) VALUES (?,?,?,?)");
    db.exec("BEGIN");
    for (let n = 0; n < 10_000; n++) put.run(n - 5_000, n % 3, n, n % 2 === 0 ? "" : "中");
    put.run(20_000, 100, 1, "orphan");
    db.exec("COMMIT");
    const expected = db.prepare(`SELECT session, thread, n FROM
      (SELECT session, thread, n, MIN(rowid) FROM deliveries GROUP BY session) ORDER BY session`).all();
    let visited = 0;
    db.function("visit_first_delivery", () => { visited++; return 1; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "exec") return (sql: string) => target.exec(sql
          .replace("FROM deliveries GROUP BY session", "FROM deliveries WHERE visit_first_delivery() GROUP BY session")
          .replaceAll("AND thread = first_threads.thread ORDER BY rowid LIMIT 1", "AND thread = first_threads.thread AND visit_first_delivery() ORDER BY rowid LIMIT 1"));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    schema.addListState(traced);
    assert.deepEqual(db.prepare("SELECT session, thread, n FROM session_first ORDER BY session").all(), expected);
    assert.ok(visited <= 12, `installing first deliveries examined ${visited} historical rows`);
    const seed = (schema as any).SESSION_FIRST_INITIAL as string;
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${seed}`).all().map((r: any) => r.detail).join("\n");
    assert.match(plan, /SEARCH deliveries USING COVERING INDEX deliveries_session \(session=\? AND thread=\?\)/);

    // The installed writers continue to maintain the same first delivery, including REPLACE.
    put.run(30_000, 8, 7, "");
    db.prepare("INSERT OR REPLACE INTO deliveries(thread,n,session) VALUES (0,0,'')").run();
    assert.deepEqual(db.prepare("SELECT session, thread, n FROM session_first ORDER BY session").all(),
      db.prepare(`SELECT session, thread, n FROM
        (SELECT session, thread, n, MIN(rowid) FROM deliveries GROUP BY session) ORDER BY session`).all());
  } finally { db.close(); }
});
