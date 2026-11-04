import assert from "node:assert/strict";
import { test } from "node:test";
import { knownThreads } from "../src/connects/known-threads.ts";
import { Store } from "../src/store/store.ts";

test("a connect learns people of the 200 recent threads without reading older people's rows", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const ids: number[] = [];
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person',?,'hi',?)");
    db.exec("BEGIN");
    for (let n = 0; n < 250; n++) {
      const id = store.openThread("slack:T", "C", String(n), null, null).id;
      store.joinThread(id, "agent", "team");
      put.run(id, `U${n}`, n + 1);
      ids.push(id);
    }
    db.exec("COMMIT");
    let visited = 0;
    db.function("visit_known_person", (author) => { visited++; return author; });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.replace("SELECT author FROM thread_people", "SELECT visit_known_person(author) AS author FROM thread_people"));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    try {
      const known = knownThreads(store, "team");
      assert.deepEqual(known.map((row) => row.thread), ids.slice(-200).reverse());
      assert.deepEqual(known[0]?.people, ["U249"]);
      assert.equal(visited, 200, `the connect read ${visited} authors`);
    } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); }
  } finally { store.close(); }
});

test("the recent limit is across all connects, before choosing one connect", () => {
  const store = Store.open(":memory:");
  try {
    const put = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person',?,'hi',?)");
    const ids: number[] = [];
    for (let n = 0; n < 205; n++) {
      const id = store.openThread("slack:T", "C", String(n), null, null).id;
      store.joinThread(id, "agent", n === 204 ? "other" : "team");
      put.run(id, `U${n}`, n + 1);
      ids.push(id);
    }
    const known = knownThreads(store, "team");
    assert.deepEqual(known.map((row) => row.thread), ids.slice(5, 204).reverse());
    assert.equal(known.length, 199);
  } finally { store.close(); }
});
