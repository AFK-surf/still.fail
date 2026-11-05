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
      let storeVisits = 0;
      db.function("visited_store_card", (n) => { storeVisits++; return n; });
      const traced = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => target.prepare(
            sql === CARD_POST_BEFORE ? sql.replace("n<?", "n<? AND visited_store_card(n)=n") : sql,
          );
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });
      (store as any).db = traced;
      assert.equal(store.cardEndedByMessage(thread, 1000)?.[0].n, 1);
      const beforeStore = storeVisits;
      assert.ok(beforeStore > 0, "the event reads the card-post index");
      add(42, 401);
      visits = 0;
      for (const { query, n } of counted) assert.equal(query.get(thread, n)?.n, 1);
      assert.equal(visits, before, `card post candidates grew from ${before} to ${visits}`);
      assert.deepEqual(read(), [[1, 1000]]);
      storeVisits = 0;
      assert.equal(store.cardEndedByMessage(thread, 1000)?.[0].n, 1);
      assert.equal(storeVisits, beforeStore, "the event does not traverse the added edits");
    } finally { store.close(); }
  });
}

for (const prepared of [false, true]) {
  test(`card events keep their immediate answers when the old index is ${prepared ? "ready" : "not ready"}`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "EMBER", `event-${prepared}`, null, null).id;
      if (!prepared) db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread);
      const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card) VALUES(?,?,?,?,?,?,?,?,?)");
      const card = JSON.stringify({ type: "options", options: [{ label: "yes", action: "close" }] });
      put.run(thread, 1, "message", null, "agent", "a", "first", 1, card);
      for (let n = 2; n <= 41; n++) put.run(thread, n, "edit", 1, "agent", "a", "first", n, card);
      assert.equal(store.pendingCard(thread)?.[0].n, 1);
      put.run(thread, 42, "message", null, "person", "p", "yes", 100, null);
      assert.equal(store.cardEndedByMessage(thread, 42)?.[0].n, 1);
      assert.deepEqual(store.answersSince(100).map((a) => [a.question.n, a.answer?.n]), [[1, 42]]);
      put.run(thread, 43, "message", null, "agent", "a", "second", 101, card);
      assert.equal(store.cardReplacedBy(thread, 43), null, "the previous card was already answered");
      put.run(thread, 44, "message", null, "agent", "a", "third", 102, card);
      assert.equal(store.cardReplacedBy(thread, 44)?.[0].n, 43);
      assert.equal(store.closeCard("p", thread, 44, "yes"), true);
      assert.equal(store.closedCard(thread, 44)?.[0].n, 44);
      assert.equal(store.pendingCard(thread), null);
    } finally { store.close(); }
  });
}
