import assert from "node:assert/strict";
import { test } from "node:test";
import { RECENT_CONNECT_THREADS, Store } from "../src/store/store.ts";

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
      const known = store.recentConnectPeople("team", 200);
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
    const known = store.recentConnectPeople("team", 200);
    assert.deepEqual(known.map((row) => row.thread), ids.slice(5, 204).reverse());
    assert.equal(known.length, 199);
  } finally { store.close(); }
});

test("recent connect people agree with the prior list for ties, edits, empty chats and shared connects", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const message = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person',?,'hi',?)");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES (?,2,'edit',1,'person','u','changed',?)");
    db.exec("BEGIN");
    for (let n = 0; n < 240; n++) {
      const surface = n % 7 === 0 ? "ember" : "slack:T";
      const id = store.openThread(surface, "C", String(n), null, null).id;
      db.prepare("UPDATE threads SET created_at=? WHERE id=?").run(n % 7 - 3, id);
      if (n % 11 !== 0) store.joinThread(id, "a", n % 5 === 0 ? "other" : "team");
      if (n % 9 === 0) store.joinThread(id, "b", "other");
      if (n % 13 !== 0) {
        message.run(id, `U${n}`, n % 17 - 8);
        if (n % 4 === 0) edit.run(id, n + 100);
      }
      if (n % 29 === 0) db.prepare("DELETE FROM thread_state WHERE thread=?").run(id);
    }
    db.exec("COMMIT");
    for (const connect of ["team", "other", "missing"]) {
      const prefix = `slack:${connect}:`;
      const before = store.listThreads("", null, null, "none").slice(0, 200)
        .filter((t) => t.sessions.some((m) => m.connect === connect))
        .map((t) => ({ thread: t.thread.id, people: t.people.flatMap((p) => p.startsWith(prefix) ? [p.slice(prefix.length)] : []) }));
      assert.deepEqual(store.recentConnectPeople(connect, 200), before, connect);
    }
  } finally { store.close(); }
});

test("recent thread ordering seeks each thread's latest message", () => {
  const store = Store.open(":memory:");
  try {
    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${RECENT_CONNECT_THREADS}`).all(200, "team").map((r) => String(r.detail));
    assert.ok(plan.some((d) => d.includes("SEARCH e USING INDEX") && d.includes("thread=? AND n=?")), plan.join("; "));
    assert.ok(!plan.some((d) => d === "SCAN e"), plan.join("; "));
  } finally { store.close(); }
});
