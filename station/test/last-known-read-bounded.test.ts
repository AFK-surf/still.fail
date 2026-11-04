import assert from "node:assert/strict";
import { test } from "node:test";
import { newMessage, Store } from "../src/store/store.ts";

test("the first message numbers itself without scanning other chats' reads", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const withRead = store.openThread("ember", "EMBER", "with-read", null, null).id;
    const withDelivery = store.openThread("ember", "EMBER", "with-delivery", null, null).id;
    const empty = store.openThread("ember", "EMBER", "empty", null, null).id;
    const negative = store.openThread("ember", "EMBER", "negative", null, null).id;
    const put = db.prepare("INSERT INTO reads(viewer,thread,n,at) VALUES (?,?,?,?)");
    db.exec("BEGIN");
    for (let viewer = 0; viewer < 40; viewer++) {
      for (let thread = 5; thread <= 1_004; thread++) put.run(`person-${viewer}`, thread, thread, thread);
      put.run(`person-${viewer}`, withRead, 100 + viewer, 1);
    }
    put.run("person-0", negative, -9, 1);
    db.prepare("INSERT INTO deliveries(thread,n,session) VALUES (?,?,'s')").run(withRead, 130);
    db.prepare("INSERT INTO deliveries(thread,n,session) VALUES (?,?,'s')").run(withDelivery, 200);
    db.prepare("INSERT INTO deliveries(thread,n,session) VALUES (?,?,'s')").run(negative, -3);
    db.exec("COMMIT");

    let visited = 0;
    db.function("visit_old_read", (_viewer, _thread) => { visited++; return 1; });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.includes("FROM reads") && sql.includes("MAX(n)")
            ? sql.replaceAll("FROM reads WHERE thread = ?1", "FROM reads WHERE visit_old_read(viewer, thread) AND thread = ?1")
              .replaceAll("SELECT viewer FROM reads ORDER BY viewer LIMIT 1", "SELECT viewer FROM reads WHERE visit_old_read(viewer, thread) ORDER BY viewer LIMIT 1")
              .replaceAll("SELECT viewer FROM reads WHERE viewer >", "SELECT viewer FROM reads WHERE visit_old_read(viewer, thread) AND viewer >")
              .replaceAll("SELECT n FROM reads WHERE viewer =", "SELECT n FROM reads WHERE visit_old_read(viewer, thread) AND viewer =")
            : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    try {
      for (const [thread, expected] of [[withRead, 140], [withDelivery, 201], [empty, 1], [negative, -2]]) {
        visited = 0;
        const [n] = store.insertMessage(newMessage(thread!, `t${thread}`, "person", "me", "hello"));
        assert.equal(n, expected);
        assert.ok(visited > 0 && visited <= 2_048, `the first message examined ${visited} reads`);
      }
    } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); }
  } finally { store.close(); }
});
