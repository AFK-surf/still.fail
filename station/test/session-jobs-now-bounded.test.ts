import assert from "node:assert/strict";
import { test } from "node:test";
import { jobsNow, makeStore, UP_JOBS_OF } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("a session's current jobs do not inspect other sessions' running or restarting jobs", () => {
  const reads: { running: number; restarting: number }[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let running = 0, restarting = 0;
    db.function("other_running_seen", (id) => { if (String(id).startsWith("other-")) running++; return 1; });
    db.function("other_restarting_seen", (id) => { if (String(id).startsWith("other-")) restarting++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === UP_JOBS_OF
        ? sql.replace("state = 'running' AND session_key", "state = 'running' AND other_running_seen(id) AND session_key")
          .replace("port IS NOT NULL AND session_key", "port IS NOT NULL AND other_restarting_seen(id) AND session_key") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const insert = db.prepare(`INSERT INTO jobs(id,token,session_key,state,port,name,command,cwd,started_at,log)
        VALUES(?,?,?,?,?,'','','',?,'')`);
      insert.run("kept-running", "kept-running", "mine", "running", null, 0);
      insert.run("kept-service", "kept-service", "mine", "exited", 3000, 1);
      for (let i = 0; i < 60; i++) insert.run(`old-${i}`, `old-${i}`, "mine", "exited", null, 10 + i);
      for (let i = 0; i < unrelated; i++) {
        insert.run(`other-running-${i}`, `other-running-${i}`, "other", "running", null, i);
        insert.run(`other-service-${i}`, `other-service-${i}`, "other", "exited", 3001 + i, i);
      }
      const jobs = jobsNow(makeStore(observed, "."), "mine");
      assert.equal(jobs.length, 52);
      assert.ok(jobs.some((job) => job.id === "kept-running"));
      assert.ok(jobs.some((job) => job.id === "kept-service"));
      reads.push({ running, restarting });
    } finally { store.close(); }
  }
  assert.deepEqual(reads, [{ running: 0, restarting: 0 }, { running: 0, restarting: 0 }]);
});
