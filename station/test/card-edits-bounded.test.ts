import assert from "node:assert/strict";
import { test } from "node:test";
import { CARD_BEFORE, OPTIONS_BEFORE } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

for (const { column, sql } of [
  { column: "card", sql: CARD_BEFORE },
  { column: "options", sql: OPTIONS_BEFORE },
] as const) {
  test(`finding the previous ${column} does not traverse later edits`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "EMBER", `card-edits-${column}`, null, null).id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,${column})
        VALUES(?,?,?,?, 'agent','a','choose',?,?)`);
      const value = column === "card" ? '{"type":"text"}' : '["yes"]';
      put.run(thread, 1, "message", null, 1, value);
      const add = (from: number, to: number) => {
        db.exec("BEGIN");
        for (let n = from; n <= to; n++) put.run(thread, n, "edit", 1, n, value);
        db.exec("COMMIT");
      };
      add(2, 41);
      let visits = 0;
      db.function("visited_card_kind", (kind) => { visits++; return kind; });
      const counted = sql.replace("kind = 'message'", "visited_card_kind(kind) = 'message'");
      assert.notEqual(counted, sql, "the card candidate lookup is observed");
      const plan = (statement: string) => db.prepare(`EXPLAIN QUERY PLAN ${statement}`).all(thread, 1000)
        .map((row) => String(row.detail)).join("\n");
      assert.match(plan(sql), new RegExp(`entries_${column === "card" ? "cards" : "options"}`));
      assert.match(plan(counted), new RegExp(`entries_${column === "card" ? "cards" : "options"}`));
      const query = db.prepare(counted);
      assert.equal(query.get(thread, 1000)?.n, 1);
      const before = visits;
      assert.ok(before > 0);
      add(42, 401);
      visits = 0;
      assert.equal(query.get(thread, 1000)?.n, 1);
      assert.equal(visits, before, `card candidates grew from ${before} to ${visits}`);
    } finally { store.close(); }
  });
}
