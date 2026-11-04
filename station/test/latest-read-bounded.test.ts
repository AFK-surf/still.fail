import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("the latest read of a chat includes every viewer and ignores other chats", () => {
  const store = Store.open(":memory:");
  try {
    const put = store.db.prepare("INSERT INTO reads (viewer, thread, n, at) VALUES (?, ?, ?, ?)");
    assert.equal(store.lastReadAt(7), null);
    put.run("", 7, 1, -50);
    put.run("a", 7, 4, 42);
    put.run("z", 7, 8, -1);
    put.run("a", 8, 5, 999);
    assert.equal(store.lastReadAt(7), 42);
    assert.equal(store.lastReadAt(8), 999);
    store.db.prepare("DELETE FROM reads WHERE viewer = 'a' AND thread = 7").run();
    assert.equal(store.lastReadAt(7), -1);
    store.db.prepare("DELETE FROM reads WHERE thread = 7").run();
    assert.equal(store.lastReadAt(7), null);
  } finally { store.close(); }
});

test("the latest read still includes everyone when there are many viewers", () => {
  const store = Store.open(":memory:");
  try {
    const put = store.db.prepare("INSERT INTO reads (viewer, thread, n, at) VALUES (?, ?, 1, ?)");
    for (let i = 0; i < 50; i++) put.run(`viewer-${i}`, i % 2 ? 8 : 7, i - 100);
    put.run("last", 7, 42);
    assert.equal(store.lastReadAt(7), 42);
    assert.equal(store.lastReadAt(8), -51);
    assert.equal(store.lastReadAt(9), null);
    store.db.prepare("UPDATE reads SET at = 100 WHERE viewer = 'viewer-4' AND thread = 7").run();
    assert.equal(store.lastReadAt(7), 100);
  } finally { store.close(); }
});

test("small and sparse tables with arbitrary rowids still return the exact latest read", () => {
  for (const rowid of [
    (i: number) => -1_000_000_000n - BigInt(i),
    (i: number) => i === 0 ? -(2n ** 62n) : i === 599 ? 2n ** 62n : BigInt(i) * 100_000n,
  ]) {
    const store = Store.open(":memory:");
    try {
      const put = store.db.prepare("INSERT INTO reads (rowid, viewer, thread, n, at) VALUES (?, ?, ?, 1, ?)");
      for (let i = 0; i < 600; i++) put.run(rowid(i), `viewer-${Math.floor(i / 2)}`, 7 + i % 2, i - 1_000);
      assert.equal(store.lastReadAt(7), -402);
      assert.equal(store.lastReadAt(8), -401);
      assert.equal(store.lastReadAt(9), null);
      store.db.prepare("DELETE FROM reads WHERE viewer = 'viewer-299'").run();
      assert.equal(store.lastReadAt(7), -404);
      assert.equal(store.lastReadAt(8), -403);
    } finally { store.close(); }
  }
});

test("the size bound seeks the ends of the rowid table", () => {
  const store = Store.open(":memory:");
  try {
    for (const edge of ["MIN", "MAX"]) {
      const plan = store.db.prepare(`EXPLAIN QUERY PLAN SELECT ${edge}(rowid) FROM reads`).all() as { detail: string }[];
      assert.ok(plan.some((row) => row.detail.startsWith("SEARCH reads")), JSON.stringify(plan));
      assert.ok(!plan.some((row) => row.detail.startsWith("SCAN reads")), JSON.stringify(plan));
    }
  } finally { store.close(); }
});

test("finding a chat's latest read does not visit that viewer's other chats", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const put = db.prepare("INSERT INTO reads (viewer, thread, n, at) VALUES ('a', ?, 1, ?)");
    db.exec("BEGIN");
    for (let thread = 1; thread <= 5_000; thread++) put.run(thread, thread);
    db.exec("COMMIT");
    let visited = 0;
    db.function("visit_read", (_viewer, _thread) => { visited++; return 1; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.includes("FROM reads") && sql.includes("AS at")
            ? sql.replace("FROM reads WHERE thread = ?", "FROM reads WHERE visit_read(viewer, thread) AND thread = ?")
              .replace("SELECT viewer FROM reads ORDER BY viewer LIMIT 1", "SELECT viewer FROM reads WHERE visit_read(viewer, thread) ORDER BY viewer LIMIT 1")
              .replace("SELECT viewer FROM reads WHERE viewer >", "SELECT viewer FROM reads WHERE visit_read(viewer, thread) AND viewer >")
              .replace("SELECT at FROM reads WHERE viewer =", "SELECT at FROM reads WHERE visit_read(viewer, thread) AND viewer =")
            : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: traced, configurable: true });
    try {
      assert.equal(store.lastReadAt(4_999), 4_999);
      assert.ok(visited > 0 && visited <= 3, `only this viewer and chat are sought (visited ${visited})`);
      visited = 0;
      assert.equal(store.lastReadAt(6_000), null);
      assert.ok(visited > 0 && visited <= 2, `a missing chat does not scan unrelated reads (visited ${visited})`);
    } finally { Object.defineProperty(store, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

for (const { viewers, chats, negative } of [
  { viewers: 40, chats: 1_000, negative: false },
  { viewers: 300, chats: 200, negative: false },
  { viewers: 300, chats: 200, negative: true },
])
  test(`a chat's latest read does not scan other chats with ${viewers} viewers${negative ? " and negative rowids" : ""}`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      const put = db.prepare("INSERT INTO reads(rowid,viewer,thread,n,at) VALUES (?,?,?,?,?)");
      db.exec("BEGIN");
      for (let viewer = 0; viewer < viewers; viewer++)
        for (let thread = 1; thread <= chats; thread++) {
          const id = viewer * chats + thread;
          put.run(negative ? -id : id, `person-${viewer}`, thread, 1, viewer * 1_000 + thread);
        }
      db.exec("COMMIT");
      let visited = 0;
      db.function("visit_read", (_viewer, _thread) => { visited++; return 1; });
      const traced = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => target.prepare(
            sql.includes("FROM reads") && sql.includes("AS at")
              ? sql.replaceAll("FROM reads WHERE thread = ?", "FROM reads WHERE visit_read(viewer, thread) AND thread = ?")
                .replaceAll("SELECT viewer FROM reads ORDER BY viewer LIMIT 1", "SELECT viewer FROM reads WHERE visit_read(viewer, thread) ORDER BY viewer LIMIT 1")
                .replaceAll("SELECT viewer FROM reads WHERE viewer >", "SELECT viewer FROM reads WHERE visit_read(viewer, thread) AND viewer >")
                .replaceAll("SELECT at FROM reads WHERE viewer =", "SELECT at FROM reads WHERE visit_read(viewer, thread) AND viewer =")
                .replaceAll("SELECT 1 FROM reads LIMIT", "SELECT 1 FROM reads WHERE visit_read(viewer, thread) LIMIT")
              : sql,
          );
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });
      Object.defineProperty(store, "db", { value: traced, configurable: true });
      try {
        assert.equal(store.lastReadAt(chats), (viewers - 1) * 1_000 + chats);
        assert.ok(visited > 0 && visited <= 2_048, `unrelated reads must be bounded (visited ${visited})`);
        visited = 0;
        assert.equal(store.lastReadAt(chats + 1), null);
        assert.ok(visited > 0 && visited <= 2_048, `a missing chat must also be bounded (visited ${visited})`);
      } finally { Object.defineProperty(store, "db", { value: db, configurable: true }); }
    } finally { store.close(); }
  });
