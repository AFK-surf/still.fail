import assert from "node:assert/strict";
import { test } from "node:test";
import { autoArchive } from "../src/sessions/lifecycle.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function session(store: Store, key: string) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
    token: key, createdAt: 1, lastActiveAt: 1 });
}

function observe(store: Store) {
  const db = store.db;
  let visits = 0;
  const plans: string[][] = [];
  db.function("visit_binding_use", () => { visits++; return 1; });
  Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (source: string) => {
        let sql = source;
        sql = sql.replace("SELECT connect, session_key FROM bindings", "SELECT visit_binding_use() AS visit, connect, session_key FROM bindings")
          .replace("SELECT i.session, i.connect", "SELECT visit_binding_use() AS visit, i.session, i.connect")
          .replace("DELETE FROM bindings WHERE session_key = ?", "DELETE FROM bindings WHERE visit_binding_use() AND session_key = ?")
          .replace("SELECT binding_rowid FROM session_binding_rows WHERE", "SELECT binding_rowid FROM session_binding_rows WHERE visit_binding_use() AND");
        const statement = target.prepare(sql);
        if (!source.includes("FROM bindings") && !source.includes("session_binding_rows")) return statement;
        return new Proxy(statement, { get(t, p) {
          if (p === "all" || p === "run") return (...args: unknown[]) => {
            plans.push((target.prepare(`EXPLAIN QUERY PLAN ${source}`).all(...args as any[]) as { detail: string }[]).map((row) => row.detail));
            return (t[p] as any)(...args);
          };
          const value = Reflect.get(t, p, t);
          return typeof value === "function" ? value.bind(t) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) });
  return { reset: () => { visits = 0; plans.length = 0; }, visits: () => visits, plans: () => plans,
    restore: () => Object.defineProperty(store, "db", { configurable: true, value: db }) };
}

test("auto-archive checks bindings only for active sessions", async () => {
  const r = new Rig(), db = r.store.db;
  try {
    session(r.store, "mine");
    const put = db.prepare("INSERT INTO bindings(connect,session_key) VALUES(?,?)");
    put.run("mine-connect", "mine");
    const extra = (from: number, to: number) => { for (let i = from; i < to; i++) put.run(`other-${i}`, `old-${i}`); };
    const observed = observe(r.store);
    try {
      extra(0, 40); observed.reset(); autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      const before = observed.visits();
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      extra(40, 400); observed.reset(); autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      assert.equal(observed.visits(), before, `binding visits grew from ${before} to ${observed.visits()}`);
      assert.ok(observed.plans().some((plan) => plan.some((line) => line.startsWith("SEARCH i ") && line.includes("session=?")));
    } finally { observed.restore(); }
  } finally { await r.close(); }
});

test("deleting a session does not scan unrelated bindings", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    session(store, "first"); session(store, "second");
    const put = db.prepare("INSERT INTO bindings(connect,session_key) VALUES(?,?)");
    put.run("first-connect", "first"); put.run("second-connect", "second");
    const extra = (from: number, to: number) => { for (let i = from; i < to; i++) put.run(`other-${i}`, `old-${i}`); };
    const observed = observe(store);
    try {
      extra(0, 40); observed.reset(); store.deleteSession("first");
      const before = observed.visits();
      assert.equal(store.binding("first-connect"), null);
      extra(40, 400); observed.reset(); store.deleteSession("second");
      assert.equal(store.binding("second-connect"), null);
      assert.equal(observed.visits(), before, `binding visits grew from ${before} to ${observed.visits()}`);
      assert.ok(observed.plans().some((plan) => plan.some((line) => line.includes("session_binding_rows") && line.includes("session=?"))));
    } finally { observed.restore(); }
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM bindings").get()?.n, 400);
  } finally { store.close(); }
});
