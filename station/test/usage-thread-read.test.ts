// Naming a still.fail chat never needs its first message, even when it has no title.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, usageThreads } from "../src/read/store.ts";
import { titleOf } from "../src/read/views.ts";
import { Store, newMessage } from "../src/store/store.ts";

test("usage names still.fail chats without reading their first messages", () => {
  const store = Store.open(":memory:");
  const own = store.openThread("ember", "CHAT", "1", null, null);
  const slack = store.openThread("slack:T1", "C1", "2", null, null);
  store.insertMessage(newMessage(own.id, "1.1", "person", "a", "private first message"));
  store.insertMessage(newMessage(slack.id, "2.1", "person", "a", "Slack title"));
  let firstReads = 0;
  const db = new Proxy(store.db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        return new Proxy(statement, {
          get(query, method) {
            if (method === "get") return (...args: any[]) => {
              if (sql.includes("FROM thread_state t JOIN merged")) firstReads++;
              return query.get(...args);
            };
            const value = Reflect.get(query, method, query);
            return typeof value === "function" ? value.bind(query) : value;
          },
        });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) as DatabaseSync;
  try {
    const rows = usageThreads(makeStore(db, "."), [own.id, slack.id]);
    assert.equal(rows.length, 2);
    assert.equal(titleOf(rows[0]![0], rows[0]![1], null), titleOf(own, null, null));
    assert.equal(titleOf(rows[1]![0], rows[1]![1], null), "Slack title");
    assert.equal(firstReads, 1, "only Slack needs its first message to name the thread");
  } finally { store.close(); }
});
