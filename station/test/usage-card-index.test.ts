import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { decisionCards, makeStore } from "../src/read/store.ts";
import { Store, newMessage } from "../src/store/store.ts";

test("the first human answer after a card is sought among human messages", () => {
  const store = Store.open(":memory:");
  const thread = store.openThread("ember", "EMBER", "1", null, null);
  store.insertMessage({ ...newMessage(thread.id, "1", "agent", "agent", "choose"), card: { type: "options", options: [{ label: "yes" }] } });
  for (let n = 0; n < 100; n++) store.insertMessage(newMessage(thread.id, `a${n}`, "agent", "agent", "working"));
  store.insertMessage(newMessage(thread.id, "answer", "person", "person", "yes"));
  let plan: string[] = [];
  const db = new Proxy(store.db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.startsWith("SELECT text FROM entries WHERE thread = ? AND n > ?")) {
          plan = (target.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(thread.id, 1) as { detail: string }[]).map((r) => r.detail);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) as DatabaseSync;
  try {
    assert.deepEqual(decisionCards(makeStore(db, ".")), [{ home: null, picked: true }]);
    assert.ok(plan.some((line) => line.includes("entries_people_by_n")), plan.join(" | "));
  } finally { store.close(); }
});
