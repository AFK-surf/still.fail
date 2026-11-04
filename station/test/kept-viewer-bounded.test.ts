import assert from "node:assert/strict";
import { test } from "node:test";
import { keptChats, makeStore } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("a viewer's kept chats use its index instead of reading everyone else's", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const keep = db.prepare("INSERT INTO kept_chats(viewer, thread) VALUES (?, ?)");
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) keep.run("other", n);
    keep.run("mine", 1);
    keep.run("mine", 3);
    db.exec("COMMIT");
    let visited = 0;
    let query = "";
    db.function("visit_kept", (_viewer) => { visited++; return 1; });
    const observed = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql.includes("FROM kept_chats") && sql.includes("?1")) {
            query = sql;
            sql = sql.replace("WHERE ?1 IS NULL OR viewer = ?1", "WHERE visit_kept(viewer) AND (?1 IS NULL OR viewer = ?1)")
              .replace("WHERE viewer = ?1", "WHERE visit_kept(viewer) AND viewer = ?1");
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const read = makeStore(observed, "/no-station-config");
    assert.deepEqual([...keptChats(read, "mine")], [1, 3]);
    assert.equal(visited, 2, `reading two kept chats visited ${visited} marks`);
    assert.match((db.prepare(`EXPLAIN QUERY PLAN ${query}`).all("mine") as { detail: string }[]).map(r => r.detail).join(" | "),
      /SEARCH kept_chats USING COVERING INDEX .* \(viewer=\?\)/);
    visited = 0;
    assert.deepEqual([...keptChats(read, "absent")], []);
    assert.equal(visited, 0);
    assert.deepEqual([...keptChats(read, "mine", [1, 2, 3, 3])], [1, 3]);
    assert.equal(keptChats(read, null).size, 5_000);
    assert.equal(keptChats(read, null, [1]).size, 5_000, "null viewer continues to select all viewers");

    Object.defineProperty(store, "db", { configurable: true, value: observed });
    visited = 0;
    assert.deepEqual([...store.keptChats("mine")], [1, 3]);
    assert.equal(visited, 2);
    assert.equal(store.keptChats(null).size, 5_000);
  } finally { store.close(); }
});
