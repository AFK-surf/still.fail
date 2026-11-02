import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("removing one usage total does not examine every other total in that quarter", () => {
  const store = Store.open(":memory:");
  try {
    const insert = store.db.prepare("INSERT INTO usage_quarters VALUES (1, ?, 0, '', '', 'claude', 'm', 0, ?, 0, 0, 0, 0, 0)");
    store.db.exec("BEGIN");
    insert.run("mine", 0);
    for (let n = 0; n < 2_000; n++) insert.run(`other-${n}`, 1);
    store.db.exec("COMMIT");

    const trigger = store.db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_quarters_drop'").get() as { sql: string };
    const deletion = trigger.sql.match(/DELETE FROM usage_quarters WHERE [^;]+/i)?.[0];
    assert.ok(deletion, "the installed trigger has its cleanup statement");
    const values: Record<string, string | number | null> = { at: 900_001, session: "mine", thread: null, person: null, profile: null, runtime: "claude", model: "m", fast: 0 };
    const args: (string | number | null)[] = [];
    const sql = deletion.replace(/\bOLD\.(\w+)/g, (_match, key: string) => {
      assert.ok(key in values, `unexpected old value ${key}`);
      args.push(values[key]!);
      // OLD.at is an INTEGER column; node:sqlite binds JavaScript numbers as REAL.
      return key === "at" ? "CAST(? AS INTEGER)" : "?";
    });
    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[];
    assert.match(plan.map((r) => r.detail).join(" | "), /PRIMARY KEY \(quarter=\? AND session=\? AND thread=\? AND person=\? AND profile=\? AND runtime=\? AND model=\? AND fast=\?\)/);
    let visited = 0;
    store.db.function("visited_total", (value) => { visited++; return value; });
    store.db.prepare(sql.replace("WHERE ", "WHERE visited_total(session) IS NOT NULL AND ")).run(...args);
    assert.equal(visited, 1, "other totals in the same quarter add no examined rows");
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage_quarters").get() as { n: number }).n, 2_000);
  } finally {
    store.close();
  }
});

test("an older database replaces only the cleanup trigger when opened", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-quarter-cleanup-"));
  const path = join(dir, "stillfail.db");
  try {
    let store = Store.open(path);
    store.db.exec(`DROP TRIGGER usage_quarters_drop;
      CREATE TRIGGER usage_quarters_drop AFTER DELETE ON usage BEGIN
        DELETE FROM usage_quarters WHERE quarter = OLD.at / 900000 AND calls <= 0;
      END;`);
    store.close();
    store = Store.open(path);
    try {
      const trigger = store.db.prepare("SELECT sql FROM sqlite_master WHERE name = 'usage_quarters_drop'").get() as { sql: string };
      assert.match(trigger.sql, /DELETE FROM usage_quarters WHERE quarter = OLD\.at \/ 900000 AND session = OLD\.session/);
      assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'usage_quarters_add'").get());
      assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'usage_quarters_grow'").get());
    } finally {
      store.close();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
