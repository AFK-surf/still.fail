import assert from "node:assert/strict";
import { test } from "node:test";
import { sessions, summary } from "../src/read/sessions.ts";
import { listSessions, makeStore } from "../src/read/store.ts";
import { sees, type InWorkspace } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

test("the session list reads active or archived rows by the matching index", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const state = db.prepare("UPDATE sessions SET archived_at = ?, ws = ? WHERE key = ?");
    for (let n = 0; n < 202; n++) {
      const key = `session-${n}`;
      store.insertSession({ key, connect: n % 2 === 0 ? "ember" : "other", runtime: "claude", profile: "cc",
        workspace: "/work", token: `token-${n}`, createdAt: n, lastActiveAt: n < 4 ? 999 : n });
      state.run(n < 2 ? null : n, n % 3 === 0 ? null : n % 3 === 1 ? "mine" : "elsewhere", key);
    }
    const read = makeStore(db, "/no-station-config");
    let visited = 0;
    let query = "";
    let params: unknown[] = [];
    db.function("visit_session_row", () => { visited++; return 1; });
    const observed = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const rows = sql.startsWith("SELECT * FROM sessions") && sql.includes("ORDER BY last_active_at DESC");
          const statement = target.prepare(rows ? sql.replace("SELECT *", "SELECT *, visit_session_row() AS visited") : sql);
          if (!rows) return statement;
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
    });
    const result = sessions(makeStore(observed, "/no-station-config"), null, false, "en");
    assert.deepEqual(result.map((r: any) => r.key), ["session-0", "session-1"]);
    assert.equal(visited, 2, `the active list read ${visited} session rows`);
    assert.match(db.prepare(`EXPLAIN QUERY PLAN ${query}`).all(...params as any[]).map((r: any) => r.detail).join("\n"), /USING INDEX sessions_live/);

    visited = 0;
    sessions(makeStore(observed, "/no-station-config"), null, true, "en");
    assert.equal(visited, 200);
    assert.match(db.prepare(`EXPLAIN QUERY PLAN ${query}`).all(...params as any[]).map((r: any) => r.detail).join("\n"), /USING INDEX sessions_put_away/);

    const home: InWorkspace = { workspace: "mine", home: true };
    const other: InWorkspace = { workspace: "mine", home: false };
    for (const viewer of [null, home, other]) for (const connect of [null, "ember", "other"]) for (const archived of [false, true]) {
      const before = listSessions(read)
        .filter((s) => (connect === null || s.connect === connect) && (s.archivedAt !== null) === archived && (viewer === null || sees(viewer, s.ws)))
        .map((s) => summary(read, s.key));
      assert.deepEqual(sessions(read, connect, archived, "en", viewer), before);
    }
  } finally { store.close(); }
});
