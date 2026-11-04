import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { historyHits } from "../src/search/sources.ts";
import { Store } from "../src/store/store.ts";

test("a history search brings out only sessions visible to its workspace", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec("BEGIN");
    for (let n = 0; n < 5002; n++) {
      store.insertSession({ key: `s-${n}`, connect: n % 2 ? "ember" : "slack", runtime: "claude", profile: "cc",
        workspace: "/w", token: `token-${n}`, createdAt: n, lastActiveAt: n, ws: n < 2 ? "mine" : "other" });
    }
    db.exec("COMMIT");
    let visited = 0;
    let query = "";
    db.function("visit_history_session", () => { visited++; return 1; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql === "SELECT * FROM sessions ORDER BY last_active_at DESC") {
            query = sql;
            sql = sql.replace("SELECT *", "SELECT *, visit_history_session() AS visited");
          } else if (sql.includes("FROM connects c CROSS JOIN workspaces w")) {
            query = sql;
            sql = sql.replace("SELECT s.*", "SELECT s.*, visit_history_session() AS visited");
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    let clock = 0;
    const found = await historyHits(makeStore(traced, "/no-station-config"), [], ["needle"],
      { workspace: "mine", home: false, scopes: [] }, { limit: 5, offset: 0, ms: 1, now: () => clock++ ? 2 : 0 });
    assert.deepEqual(found, { hits: [], more: true, left: 2 });
    assert.equal(visited, 2, `the search brought out ${visited} session rows for a workspace with two`);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${query}`).all("mine", 0).map((r: any) => r.detail).join("\n");
    assert.match(plan, /SEARCH s USING INDEX sessions_by_connect \(connect=\? AND ws=\?\)/);
  } finally { store.close(); }
});

test("history search keeps visible sessions in activity and insertion order, including archived and old sessions", async () => {
  const data = mkdtempSync(join(tmpdir(), "history-scope-"));
  const store = Store.open(":memory:");
  try {
    const home = join(data, "profile");
    const dir = join(home, "projects", "w");
    mkdirSync(dir, { recursive: true });
    const sessions = [
      { key: "mine-a", connect: "ember", ws: "mine", at: 20 },
      { key: "other", connect: "ember", ws: "other", at: 100 },
      { key: "public", connect: "slack", ws: "*", at: 30 },
      { key: "old", connect: "slack", ws: null, at: 20 },
      { key: "mine-b", connect: "slack", ws: "mine", at: 20 },
    ];
    for (const row of sessions) {
      store.insertSession({ key: row.key, connect: row.connect, runtime: "claude", profile: "cc", workspace: "/w",
        token: `token-${row.key}`, createdAt: row.at, lastActiveAt: row.at, ws: row.ws });
      store.setRuntimeSessionId(row.key, row.key);
      writeFileSync(join(dir, `${row.key}.jsonl`), `${JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text: `needle ${row.key}` }] } })}\n`);
    }
    store.db.prepare("UPDATE sessions SET archived_at=1 WHERE key='mine-b'").run();
    const read = makeStore(store.db, data);
    const profiles = [{ id: "cc", home, runtime: "claude" }];
    const look = async (workspace: string, isHome: boolean, limit = 10, offset = 0) =>
      historyHits(read, profiles, ["needle"], { workspace, home: isHome, scopes: [] }, { limit, offset, ms: 10_000, now: () => 0 });
    assert.deepEqual((await look("mine", true)).hits.map((h) => h.session), ["public", "mine-a", "old", "mine-b"]);
    assert.deepEqual((await look("mine", false)).hits.map((h) => h.session), ["public", "mine-a", "mine-b"]);
    assert.deepEqual((await look("*", false)).hits.map((h) => h.session), ["public"]);
    const page = await look("mine", true, 2, 1);
    assert.deepEqual(page.hits.map((h) => h.session), ["mine-a", "old"]);
    assert.equal(page.more, true);
  } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
});
