import assert from "node:assert/strict";
import { test } from "node:test";
import { answersSince, makeStore } from "../src/read/store.ts";
import { CARD_POST_BEFORE, CARD_POST_NEXT } from "../src/store/card-post-index.ts";
import { Store } from "../src/store/store.ts";

for (const column of ["card", "options"] as const) {
  test(`a recent answer to a ${column} does not traverse its later edits`, () => {
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
      db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,1000,'message','person','p','yes',100)").run(thread);
      const read = () => answersSince(makeStore(db, "."), 100, [thread]).map((a) => [a.question.n, a.answer?.n]);
      assert.deepEqual(read(), [[1, 1000]]);
      let visits = 0;
      db.function("visited_card_post", (n) => { visits++; return n; });
      const queries = [
        [CARD_POST_BEFORE, CARD_POST_BEFORE.replace("n<?", "n<? AND visited_card_post(n)=n"), 1000],
        [CARD_POST_NEXT, CARD_POST_NEXT.replace("n>=?", "n>=? AND visited_card_post(n)=n"), 1],
      ] as const;
      const counted = queries.map(([sql, observed, n]) => {
        assert.notEqual(observed, sql);
        for (const statement of [sql, observed]) {
          const plan = db.prepare(`EXPLAIN QUERY PLAN ${statement}`).all(thread, n).map((row) => String(row.detail)).join("\n");
          assert.match(plan, /SEARCH card_posts USING PRIMARY KEY/);
        }
        return { query: db.prepare(observed), n };
      });
      for (const { query, n } of counted) assert.equal(query.get(thread, n)?.n, 1);
      const before = visits;
      assert.ok(before > 0);
      add(42, 401);
      visits = 0;
      for (const { query, n } of counted) assert.equal(query.get(thread, n)?.n, 1);
      assert.equal(visits, before, `card post candidates grew from ${before} to ${visits}`);
      assert.deepEqual(read(), [[1, 1000]]);
    } finally { store.close(); }
  });
}
