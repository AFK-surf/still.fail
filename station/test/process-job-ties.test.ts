import assert from "node:assert/strict";
import { test } from "node:test";
import { watchedJobs } from "../src/jobs/memory.ts";
import { installProcessJobs, processJobs, processJobsReady, processJobsStep } from "../src/store/process-jobs.ts";
import { Store } from "../src/store/store.ts";

test("prepared process groups keep the previous order when jobs start together with different ports", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const add = db.prepare(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,pgid,port,started_at,log)
      VALUES(?,?,?,'running',?,'','',?,?,10,'')`);
    add.run("high", "high", "high", "high", 1, 8000);
    add.run("none", "none", "none", "none", 2, null);
    add.run("low", "low", "low", "low", 3, 2000);
    add.run("middle", "middle", "middle", "middle", 4, 5000);
    const before = watchedJobs(store);
    assert.deepEqual(before.map((job) => job.id), ["none", "low", "middle", "high"]);
    installProcessJobs(db);
    while (!processJobsReady(db)) processJobsStep(db, 2);
    const after = watchedJobs(store, { read: () => processJobs(db), consider: () => {} });
    assert.deepEqual(after, before);
    db.prepare("UPDATE jobs SET port = ? WHERE id = ?").run(1000, "high");
    assert.deepEqual(watchedJobs(store, { read: () => processJobs(db), consider: () => {} }), watchedJobs(store));
  } finally { store.close(); }
});
