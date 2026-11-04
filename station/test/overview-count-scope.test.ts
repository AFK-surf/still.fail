import assert from "node:assert/strict";
import { test } from "node:test";
import { overview } from "../src/api/overview.ts";
import { Store } from "../src/store/store.ts";

test("the overview counts only sessions visible in the viewer's workspace", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const names = ["", "a", "å", "中"];
    db.exec("BEGIN");
    for (let n = 0; n < 4003; n++) {
      const key = `session-${n}`;
      store.insertSession({ key, connect: names[n % names.length]!, runtime: "claude", profile: "cc",
        workspace: "/work", token: `token-${n}`, createdAt: n, lastActiveAt: n,
        ws: n < 2 ? "mine" : n === 2 ? null : "elsewhere" });
    }
    db.prepare("UPDATE sessions SET archived_at = 1 WHERE key = 'session-1'").run();
    db.exec("COMMIT");
    let visited = 0;
    let query = "";
    let params: unknown[] = [];
    db.function("visit_session_count", () => { visited++; return 1; });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const counting = sql.includes("COUNT(*) AS n") && sql.includes("sessions");
          const statement = target.prepare(counting ? sql.replaceAll("COUNT(*) AS n", "SUM(visit_session_count()) AS n") : sql);
          if (!counting) return statement;
          query = sql;
          return new Proxy(statement, { get(t, p) {
            if (p === "all") return (...args: unknown[]) => { params = args; return (t.all as any)(...args); };
            const v = Reflect.get(t, p, t);
            return typeof v === "function" ? v.bind(t) : v;
          } });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    const hub: any = { processes: () => [], config: () => ({ dataDir: "/" }) };
    const cloud: any = { state: null };
    const config = () => ({ connects: names.map((id) => ({ id, workspace: "mine" })) });
    const viewer = { sub: "s", email: "person@example.test", name: "P", role: "member", workspace: "mine", device: "d", home: false };
    const get = async (who: typeof viewer) => await overview({ store, hub, cloud, config }, who, "en") as any;
    const joined = await get(viewer);
    assert.equal(joined.counts.sessions, 2);
    assert.deepEqual(joined.connects.map((c: any) => c.sessions), [1, 1, 0, 0]);
    assert.equal(visited, 2, `the overview counted ${visited} sessions for a workspace with two`);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${query}`).all(...params as any[]).map((r: any) => r.detail).join("\n");
    assert.match(plan, /SEARCH .* USING COVERING INDEX sessions_by_connect \(connect=\? AND ws=\?\)/);
    visited = 0;
    const home = await get({ ...viewer, home: true });
    assert.equal(home.counts.sessions, 3);
    assert.deepEqual(home.connects.map((c: any) => c.sessions), [1, 1, 1, 0]);
    assert.equal(visited, 3);
    visited = 0;
    const empty = await get({ ...viewer, workspace: "absent" });
    assert.equal(empty.counts.sessions, 0);
    assert.equal(visited, 0);
  } finally { store.close(); }
});
