import assert from "node:assert/strict";
import { test } from "node:test";
import { sessions, summary } from "../src/read/sessions.ts";
import { makeStore } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

for (const what of ["summary", "list"] as const) test(`a session ${what} does not traverse unrelated bindings`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "mine", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "mine", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const bind = db.prepare("INSERT INTO bindings(connect,session_key) VALUES (?,?)");
    bind.run("z-first", "mine"); bind.run("a-second", "mine");
    const extra = (from: number, to: number) => {
      db.exec("BEGIN");
      for (let i = from; i < to; i++) bind.run(`other-${i}`, `other-session-${i}`);
      db.exec("COMMIT");
    };
    let visited = 0;
    let plans: string[] = [];
    db.function("visit_binding_candidate", () => { visited++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const global = sql === "SELECT connect, session_key FROM bindings";
        const statement = target.prepare(global ? sql.replace("SELECT connect", "SELECT visit_binding_candidate() AS visited, connect") : sql);
        if (!global && !sql.includes("session_binding_rows")) return statement;
        return new Proxy(statement, { get(t, p) {
          if (p === "all") return (...args: unknown[]) => {
            plans = (target.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args as any[]) as { detail: string }[]).map((row) => row.detail);
            return (t.all as any)(...args);
          };
          const value = Reflect.get(t, p, t);
          return typeof value === "function" ? value.bind(t) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = () => {
      visited = 0; plans = [];
      const s = makeStore(observed, "/no-station-config");
      const item = what === "summary" ? summary(s, "mine") : sessions(s, null, false, "en", { workspace: "mine", home: false })[0];
      assert.deepEqual(item.boundTo, ["z-first", "a-second"]);
      return { visited, plan: [...plans] };
    };
    extra(0, 40);
    const before = read();
    extra(40, 400);
    const after = read();
    assert.equal(after.visited, before.visited, `binding visits grew from ${before.visited} to ${after.visited}`);
    assert.ok(after.plan.some((line) => line.startsWith("SEARCH i ") && line.includes("session=?")), after.plan.join("\n"));
  } finally { store.close(); }
});
