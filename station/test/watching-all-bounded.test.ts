import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore, watching } from "../src/read/store.ts";
import { JOBS_RUNNING, Store } from "../src/store/store.ts";

test("the station-wide watching view does not read ordinary running jobs", () => {
  const reads: number[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let seen = 0;
    db.function("ordinary_seen", (id) => { if (String(id).startsWith("ordinary-")) seen++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === JOBS_RUNNING
        ? sql.replace("WHERE state = 'running'", "WHERE state = 'running' AND ordinary_seen(id)") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const insert = db.prepare(`INSERT INTO jobs(id,token,session_key,state,watch,name,command,cwd,started_at,log)
        VALUES(?,?,?,'running',?,?,'','',?,'')`);
      insert.run("watch", "watch", "mine", 1, "watching", 10);
      for (let i = 0; i < unrelated; i++) insert.run(`ordinary-${i}`, `ordinary-${i}`, "other", 0, "job", i);
      assert.deepEqual(watching(makeStore(observed, ".")).get("mine"), { names: ["watching"], since: 10, at: 10 });
      reads.push(seen);
    } finally { store.close(); }
  }
  assert.deepEqual(reads, [0, 0]);
});
