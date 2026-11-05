// Catching up or granting a page of messages must not read the entire rest of a long conversation.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { outflowMessages } from "../src/read/outflow.ts";
import { entriesAfter, makeStore } from "../src/read/store.ts";
import { Store, newMessage } from "../src/store/store.ts";

function data() {
  const store = Store.open(":memory:");
  const thread = store.openThread("ember", "CHAT", "1.0", null, null).id;
  for (let i = 1; i <= 1000; i++) store.insertMessage(newMessage(thread, `1.${i}`, "person", "person", `${i}`));
  let rows = 0;
  const db = new Proxy(store.db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        return new Proxy(statement, {
          get(query, method) {
            if (method === "all") return (...args: any[]) => {
              const result = query.all(...args);
              if (/\bFROM entries\b/i.test(sql)) rows += result.length;
              return result;
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
  return { store, thread, read: makeStore(db, "."), rows: () => rows };
}

test("a limited catch-up returns only that page, while the old unlimited form still works", () => {
  const r = data();
  try {
    assert.deepEqual(entriesAfter(r.read, r.thread, 0n, 2).map((e) => e.n), [1, 2]);
    assert.equal(r.rows(), 2);
    assert.equal(entriesAfter(r.read, r.thread, 0n).length, 1000);
  } finally { r.store.close(); }
});

test("a granted page reads at most one extra entry to tell if more exist", () => {
  const r = data();
  try {
    const page = outflowMessages(r.read, r.thread, 0, 2);
    assert.deepEqual([page.messages.map((m: { n: number }) => m.n), page.more, page.last], [[1, 2], true, 1000]);
    assert.ok(r.rows() <= 3, `read ${r.rows()} entries to return two`);
  } finally { r.store.close(); }
});
