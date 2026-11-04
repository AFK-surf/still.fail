import assert from "node:assert/strict";
import { test } from "node:test";
import { DELETE_DISMISSED_OF_THREAD, DELETE_KEPT_CHAT, DELETE_PINS_OF_SESSION, DELETE_READS_OF_THREAD, Store } from "../src/store/store.ts";

for (const { viewers, chats, negative } of [
  { viewers: 1, chats: 5_000, negative: false }, { viewers: 40, chats: 1_000, negative: false },
  { viewers: 40, chats: 1_000, negative: true }, { viewers: 300, chats: 150, negative: false },
])
  test(`deleting a session seeks its marks with ${viewers} viewer(s), negative rowids: ${negative}`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      for (const key of ["a", "b"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
        workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
      const own = store.openThread("ember", "EMBER", "own", null, null).id;
      const shared = store.openThread("ember", "EMBER", "shared", null, null).id;
      store.joinThread(own, "a", "ember");
      store.joinThread(shared, "a", "ember");
      store.joinThread(shared, "b", "ember");
      const read = db.prepare("INSERT INTO reads(viewer,thread,n,at) VALUES (?,?,1,1)");
      const dismissed = db.prepare("INSERT INTO dismissed(viewer,thread,n,at) VALUES (?,?,?,1)");
      const kept = db.prepare("INSERT INTO kept_chats(viewer,thread) VALUES (?,?)");
      const pin = db.prepare("INSERT INTO pins(viewer,session,at) VALUES (?,?,1)");
      db.exec("BEGIN");
      for (let i = 0; i < viewers; i++) {
        const viewer = i === 0 ? "" : `person-${i}`;
        for (let j = 0; j < chats; j++) {
          const thread = j + 3;
          read.run(viewer, thread);
          dismissed.run(viewer, thread, 1);
          kept.run(viewer, thread);
          pin.run(viewer, `other-${j}`);
        }
        for (const thread of [own, shared]) {
          read.run(viewer, thread);
          kept.run(viewer, thread);
          for (const n of [1, 2, 3]) dismissed.run(viewer, thread, n);
        }
        pin.run(viewer, "a");
        pin.run(viewer, "b");
      }
      // These viewers disappear from the table entirely during deletion; none may be skipped by the iterator.
      for (const viewer of ["!only", "only-one", "only-two", "~only"]) {
        read.run(viewer, own);
        dismissed.run(viewer, own, 1);
        kept.run(viewer, own);
        pin.run(viewer, "a");
      }
      db.exec("COMMIT");
      if (negative) for (const table of ["reads", "dismissed", "kept_chats", "pins"])
        db.exec(`UPDATE ${table} SET rowid = -rowid`);

      const tables = { reads: "thread", dismissed: "thread", kept_chats: "thread", pins: "session" } as const;
      const visited: Record<string, number> = {};
      for (const name of Object.keys(tables)) {
        visited[name] = 0;
        db.function(`visit_${name}`, (_viewer, _key) => { visited[name]!++; return 1; });
      }
      Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (source: string) => {
            let sql = source;
            for (const [table, key] of Object.entries(tables)) {
              if (!sql.includes(`FROM ${table}`)) continue;
              const check = `visit_${table}(viewer, ${key}) IS NOT NULL`;
              sql = sql.replace(`DELETE FROM ${table} WHERE`, `DELETE FROM ${table} WHERE ${check} AND`)
                .replaceAll(`SELECT MAX(rowid) FROM ${table}`, `SELECT MAX(rowid) FROM ${table} WHERE ${check}`)
                .replaceAll(`SELECT MIN(rowid) FROM ${table}`, `SELECT MIN(rowid) FROM ${table} WHERE ${check}`)
                .replaceAll(`SELECT viewer FROM ${table} ORDER BY viewer LIMIT 1`, `SELECT viewer FROM ${table} WHERE ${check} ORDER BY viewer LIMIT 1`)
                .replaceAll(`SELECT viewer FROM ${table} WHERE viewer >`, `SELECT viewer FROM ${table} WHERE ${check} AND viewer >`);
            }
            return target.prepare(sql);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      }) });
      try {
        store.deleteSession("a");
        assert.ok(Object.values(visited).every((count) => count > 0 && count <= Math.max(1_024, 6 * viewers + 50)),
          `records visited while deleting the session: ${JSON.stringify(visited)}`);
      } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); }
      for (const [table, key] of Object.entries(tables)) {
        const gone = key === "thread" ? own : "a";
        const keptKey = key === "thread" ? shared : "b";
        assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE ${key}=?`).get(gone)?.n, 0, `${table}: deleted`);
        assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE ${key}=?`).get(keptKey)?.n,
          viewers * (table === "dismissed" ? 3 : 1), `${table}: shared`);
        assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()?.n,
          viewers * (chats + (table === "dismissed" ? 3 : 1)), `${table}: unrelated`);
      }
      assert.equal(store.getThread(own), null);
      assert.notEqual(store.getThread(shared), null);
    } finally { store.close(); }
  });

test("deleting a session removes every viewer's last mark, including an empty viewer", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "EMBER", "own", null, null).id;
    store.joinThread(thread, "a", "ember");
    const readers = ["", "A", "a", "é", "🚀", ...Array.from({ length: 260 }, (_, i) => `viewer-${i}`)];
    const putRead = db.prepare("INSERT INTO reads(viewer,thread,n,at) VALUES (?,?,1,1)");
    const putDismissed = db.prepare("INSERT INTO dismissed(viewer,thread,n,at) VALUES (?,?,1,1)");
    const putKept = db.prepare("INSERT INTO kept_chats(viewer,thread) VALUES (?,?)");
    const putPin = db.prepare("INSERT INTO pins(viewer,session,at) VALUES (?,'a',1)");
    for (const viewer of readers) {
      putRead.run(viewer, thread);
      putDismissed.run(viewer, thread);
      putKept.run(viewer, thread);
      putPin.run(viewer);
    }
    store.deleteSession("a");
    for (const table of ["reads", "dismissed", "kept_chats", "pins"])
      assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()?.n, 0, table);
  } finally { store.close(); }
});

test("deleting one chat keeps a second read from each of many viewers", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
    const own = store.openThread("ember", "EMBER", "own", null, null).id;
    const other = store.openThread("ember", "EMBER", "other", null, null).id;
    store.joinThread(own, "a", "ember");
    const put = db.prepare("INSERT INTO reads(viewer,thread,n,at) VALUES (?,?,1,1)");
    db.exec("BEGIN");
    for (let i = 0; i < 10_000; i++) {
      put.run(`viewer-${i}`, own);
      put.run(`viewer-${i}`, other);
    }
    db.exec("COMMIT");
    store.deleteSession("a");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM reads WHERE thread = ?").get(own)?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM reads WHERE thread = ?").get(other)?.n, 10_000);
  } finally { store.close(); }
});

test("a failed mark deletion rolls back the session and earlier mark removals", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "EMBER", "own", null, null).id;
    store.joinThread(thread, "a", "ember");
    db.prepare("INSERT INTO reads(viewer,thread,n,at) VALUES ('person',?,1,1)").run(thread);
    db.prepare("INSERT INTO dismissed(viewer,thread,n,at) VALUES ('person',?,1,1)").run(thread);
    db.prepare("INSERT INTO kept_chats(viewer,thread) VALUES ('person',?)").run(thread);
    db.prepare("INSERT INTO pins(viewer,session,at) VALUES ('person','a',1)").run();
    db.function("fail_delete", () => { throw new Error("mark deletion failed"); });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (source: string) => target.prepare(source.replace(
          "DELETE FROM dismissed WHERE", "DELETE FROM dismissed WHERE fail_delete() AND"));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    try { assert.throws(() => store.deleteSession("a"), /mark deletion failed/); }
    finally { Object.defineProperty(store, "db", { configurable: true, value: db }); }
    assert.notEqual(store.getSession("a"), null);
    assert.notEqual(store.getThread(thread), null);
    for (const table of ["reads", "dismissed", "kept_chats", "pins"])
      assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()?.n, 1, table);
  } finally { store.close(); }
});

test("deleting each kind of mark seeks by viewer and chat", () => {
  const store = Store.open(":memory:");
  try {
    for (const [table, sql, key] of [
      ["reads", DELETE_READS_OF_THREAD, "thread"], ["dismissed", DELETE_DISMISSED_OF_THREAD, "thread"],
      ["kept_chats", DELETE_KEPT_CHAT, "thread"], ["pins", DELETE_PINS_OF_SESSION, "session"],
    ]) {
      const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("x").map((row) => String(row.detail));
      assert.ok(plan.some((detail) => detail.includes(`SEARCH ${table}`) && detail.includes(`viewer=? AND ${key}=?`)),
        `${table}: ${plan.join("; ")}`);
      assert.ok(!plan.some((detail) => detail === `SCAN ${table}`), `${table}: ${plan.join("; ")}`);
    }
  } finally { store.close(); }
});
