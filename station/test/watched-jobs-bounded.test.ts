import assert from "node:assert/strict";
import { test } from "node:test";
import { watchedJobs } from "../src/jobs/memory.ts";
import { ProcessJobsBuilder } from "../src/jobs/process-jobs-builder.ts";
import { PROCESS_JOBS } from "../src/store/process-jobs.ts";
import { JOBS_RUNNING, Store } from "../src/store/store.ts";

test("memory, resources and the phone gate do not read queued jobs without a process group", async () => {
  const seen: number[] = [];
  for (const queued of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let waiting = 0, observing = false;
    db.function("waiting_job_seen", (id) => { if (observing && String(id).startsWith("waiting-")) waiting++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === JOBS_RUNNING
        ? sql.replace("WHERE state = 'running'", "WHERE state = 'running' AND waiting_job_seen(id)")
        : sql === PROCESS_JOBS ? sql.replace("WHERE j.state = 'running'", "WHERE waiting_job_seen(j.id) AND j.state = 'running'") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const add = db.prepare(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,pgid,port,started_at,log,queued)
        VALUES(?,?,?,'running',?,'','',?,?,?,'',?)`);
      add.run("first", "first", "one", "first", 101, null, 20, 0);
      add.run("second", "second", "two", "second", 202, 8080, 20, 0);
      for (let i = 0; i < queued; i++) add.run(`waiting-${i}`, `waiting-${i}`, "other", "waiting", null, null, i, 1);
      Object.defineProperty(store, "db", { value: observed });
      const builder = new ProcessJobsBuilder(store, Promise.resolve());
      const expected = [
        { id: "first", session: "one", pgid: 101, label: 'Job "first" (first)' },
        { id: "second", session: "two", pgid: 202, label: 'Service "second" (second, port 8080)' },
      ];
      assert.deepEqual(watchedJobs(store, builder), expected);
      await builder.settled();
      observing = true;
      assert.deepEqual(watchedJobs(store, builder), expected);
      add.run("waiting-new", "waiting-new", "other", "waiting", null, null, 21, 1);
      assert.deepEqual(watchedJobs(store, builder), expected);
      observing = false;
      seen.push(waiting);
      await builder.close();
    } finally { store.close(); }
  }
  assert.deepEqual(seen, [0, 0]);
});
