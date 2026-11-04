import assert from "node:assert/strict";
import { test } from "node:test";
import { answersSince, makeStore } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("a scoped recent-answer read does not enumerate a chat's old cards", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "answer-window", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card,options) VALUES (?,?,?,?,?,?,?,?,?,?)");
    const card = JSON.stringify({ type: "options", options: [{ label: "yes" }] });
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) put.run(thread, n, "message", `old-${n}`, "agent", "a", "choose", 1, card, null);
    db.exec("COMMIT");
    put.run(thread, 5_001, "message", "answer-1", "person", "p", "yes", 100, null, null);
    put.run(thread, 5_002, "message", "more", "person", "p", "more", 110, null, null);
    put.run(thread, 5_003, "message", "legacy", "agent", "a", "again", 2, null, '["yes"]');
    put.run(thread, 5_004, "message", "answer-2", "person", "p", "yes", 120, null, null);
    const expected = store.answersSince(100);
    assert.deepEqual(expected.map((a) => [a.question.n, a.answer?.n]), [[5_000, 5_001], [5_003, 5_004]]);
    let cardsRead = 0;
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          return new Proxy(statement, {
            get(query, method) {
              if (method === "all") return (...args: any[]) => {
                const rows = query.all(...args);
                if (/\bfrom entries\b/i.test(sql) && /\b(?:card|options) IS NOT NULL\b/i.test(sql)) cardsRead += rows.length;
                return rows;
              };
              const value = Reflect.get(query, method, query);
              return typeof value === "function" ? value.bind(query) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const actual = answersSince(makeStore(traced, "."), 100, [thread]);
    assert.deepEqual(actual, expected);
    assert.ok(cardsRead <= 130, `reading recent answers returned ${cardsRead} old card entries`);
  } finally { store.close(); }
});
