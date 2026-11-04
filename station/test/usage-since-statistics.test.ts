import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, usageSince as readSince } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("the first usage time is read from a maintained statistic", () => {
  const store = Store.open(":memory:");
  try {
    const put = store.db.prepare(`INSERT OR REPLACE INTO usage
      (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output)
      VALUES (?, ?, 'a', 'claude', 1, 0, 0, 0, 0)`);
    const remove = store.db.prepare("DELETE FROM usage WHERE id = ?");
    let changes = 0;
    store.db.function("usage_span_changed", () => { changes++; return 0; });
    store.db.exec("CREATE TEMP TRIGGER track_usage_span AFTER UPDATE ON usage_span BEGIN SELECT usage_span_changed(); END;");
    const check = (at: number | null) => {
      store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage"
        ? constants.SQLITE_DENY : constants.SQLITE_OK);
      try {
        assert.equal(readSince(makeStore(store.db, ".")), at);
        assert.equal(store.usageSince(), at);
      } finally { store.db.setAuthorizer(null); }
    };
    check(null);
    put.run("a", 100);
    const afterFirst = changes;
    assert.equal(afterFirst, 1);
    put.run("b", 200);
    assert.equal(changes, afterFirst, "a later call does not rewrite an unchanged first time");
    check(100);
    put.run("a", 300); // SQLite REPLACE may not fire a delete trigger for the earlier row.
    check(200);
    put.run("c", 200);
    remove.run("b");
    check(200);
    store.db.prepare("UPDATE usage SET at = ? WHERE id = ?").run(500, "c");
    check(300);
    put.run("d", -10);
    check(-10);
    remove.run("d");
    remove.run("a");
    remove.run("c");
    check(null);
  } finally { store.close(); }
});

test("an older database finds its first usage with one indexed lookup, then follows older writers", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-since-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  try {
    store.db.exec(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output)
      VALUES ('old', 123, 'a', 'claude', 1, 0, 0, 0, 0);`);
    store.db.exec(`DROP TRIGGER IF EXISTS usage_span_add; DROP TRIGGER IF EXISTS usage_span_drop;
      DROP TRIGGER IF EXISTS usage_span_move; DROP TABLE IF EXISTS usage_span;`);
    store.close();
    store = Store.open(path);
    const plan = (store.db.prepare("EXPLAIN QUERY PLAN SELECT MIN(at) FROM usage INDEXED BY usage_at").all() as { detail: string }[])
      .map((row) => row.detail).join(" | ");
    assert.match(plan, /SEARCH usage USING COVERING INDEX usage_at/);
    assert.equal((store.db.prepare("SELECT first_at FROM usage_span WHERE id = 1").get() as { first_at: number }).first_at, 123);
    const older = new DatabaseSync(path);
    try {
      older.exec(`INSERT INTO usage (id, at, session, runtime, input, cache_read, cache_write, cache_write_long, output)
        VALUES ('late', 12, 'a', 'claude', 1, 0, 0, 0, 0);`);
      assert.equal(store.usageSince(), 12);
      older.exec("DELETE FROM usage WHERE id = 'late'");
      assert.equal(store.usageSince(), 123);
    } finally { older.close(); }
  } finally {
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
