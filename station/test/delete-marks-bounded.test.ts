import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

for (const { viewers, chats } of [{ viewers: 1, chats: 5_000 }, { viewers: 40, chats: 1_000 }])
  test(`deleting a session seeks its marks with ${viewers} viewer(s)`, () => {
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
      db.exec("COMMIT");

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
              if (!sql.includes(`DELETE FROM ${table} WHERE`)) continue;
              const check = `visit_${table}(viewer, ${key}) IS NOT NULL`;
              sql = sql.replace(`DELETE FROM ${table} WHERE`, `DELETE FROM ${table} WHERE ${check} AND`)
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
        assert.ok(Object.values(visited).every((count) => count > 0 && count <= 1_024),
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
