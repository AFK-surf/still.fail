import assert from "node:assert/strict";
import { test } from "node:test";
import { listedSessions, makeStore } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

for (const archived of [false, true]) for (const connect of [null, "client"]) {
  test(`a workspace session list does not traverse another workspace (archived ${archived}, connect ${connect})`, () => {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      const add = (key: string, ws: string, at: number) => {
        store.insertSession({ key, connect: "client", runtime: "claude", profile: "cc", workspace: "/work",
          token: key, createdAt: at, lastActiveAt: at, ws });
        if (archived) db.prepare("UPDATE sessions SET archived_at = 1 WHERE key = ?").run(key);
      };
      add("mine-1", "mine", 1); add("mine-2", "mine", 2);
      const extra = (from: number, to: number) => {
        db.exec("BEGIN");
        for (let i = from; i < to; i++) add(`other-${i}`, "other", i + 10);
        db.exec("COMMIT");
      };
      let visited = 0;
      const plans: string[] = [];
      db.function("visit_session_candidate", () => { visited++; return 1; });
      const observed = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            // Count candidates before the workspace predicate when the existing global partial index is used.
            const global = /^SELECT \* FROM sessions INDEXED BY sessions_(?:live|put_away) WHERE /.test(sql);
            const statement = target.prepare(global ? sql.replace(" WHERE ", " WHERE visit_session_candidate() AND ") : sql);
            if (!/^(SELECT|WITH)\b/i.test(sql)) return statement;
            return new Proxy(statement, { get(t, p) {
              if (p === "all") return (...args: unknown[]) => {
                plans.push(...(target.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args as any[]) as { detail: string }[]).map((row) => row.detail));
                return (t.all as any)(...args);
              };
              const value = Reflect.get(t, p, t);
              return typeof value === "function" ? value.bind(t) : value;
            } });
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });
      const read = () => {
        visited = 0; plans.length = 0;
        const rows = listedSessions(makeStore(observed, "/no-station-config"), connect, archived, { workspace: "mine", home: false });
        assert.deepEqual(rows.map((row) => row.key), ["mine-2", "mine-1"]);
        return { visited, plan: [...plans] };
      };
      extra(0, 40);
      const before = read();
      extra(40, 400);
      const after = read();
      assert.equal(after.visited, before.visited, `candidate visits grew from ${before.visited} to ${after.visited}`);
      assert.ok(!after.plan.some((line) => /^SCAN (sessions|s)\b/.test(line)), after.plan.join("\n"));
      const seek = after.plan.find((line) => line.startsWith("SEARCH i "));
      assert.ok(seek, after.plan.join("\n"));
      for (const column of ["kind", "ws", "archived"]) assert.ok(seek.includes(`${column}=?`), seek);
      if (connect !== null) assert.match(seek, /connect=\?/);
    } finally { store.close(); }
  });
}

for (const archived of [false, true]) test(`a connection's station-wide session list seeks its own rows (archived ${archived})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const add = (key: string, connect: string) => {
      store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
      if (archived) db.prepare("UPDATE sessions SET archived_at=1 WHERE key=?").run(key);
    };
    add("mine-1", "client"); add("mine-2", "client");
    db.exec("BEGIN");
    for (let i = 0; i < 400; i++) add(`other-${i}`, "other");
    db.exec("COMMIT");
    let plan: string[] = [];
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!/^(SELECT|WITH)\b/i.test(sql)) return statement;
        return new Proxy(statement, { get(t, p) {
          if (p === "all") return (...args: unknown[]) => {
            plan = (target.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args as any[]) as { detail: string }[]).map((row) => row.detail);
            return (t.all as any)(...args);
          };
          const value = Reflect.get(t, p, t);
          return typeof value === "function" ? value.bind(t) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const rows = listedSessions(makeStore(observed, "/none"), "client", archived, null);
    assert.deepEqual(rows.map((row) => row.key), ["mine-1", "mine-2"]);
    assert.ok(plan.some((line) => /SEARCH i USING (?:COVERING )?INDEX session_list_connect \(archived=\? AND connect=\?\)/.test(line)), plan.join("\n"));
  } finally { store.close(); }
});
