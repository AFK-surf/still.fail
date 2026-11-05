import assert from "node:assert/strict";
import { test } from "node:test";
import { workspaceWorking } from "../src/jobs/workspace-size.ts";
import { RUNNING_LIMIT } from "../src/store/active-jobs.ts";
import { JOBS_RUNNING, Store } from "../src/store/store.ts";

for (const target of ["idle", "command", "watched service"] as const) test(`rechecking one workspace does not read other sessions' running jobs (${target})`, () => {
  const reads: number[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    let seen = 0;
    db.function("workspace_job_seen", () => { seen++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === JOBS_RUNNING
        ? sql.replace("WHERE state = 'running'", "WHERE state = 'running' AND workspace_job_seen()")
        : sql === RUNNING_LIMIT ? sql.replaceAll("WHERE session = ?1", "WHERE session = ?1 AND workspace_job_seen()") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      store.insertSession({ key: "target", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "target", createdAt: 1, lastActiveAt: 1 });
      for (let i = 0; i < unrelated; i++) store.insertJob({ id: `job-${i}`, sessionKey: `other-${i}`,
        name: "work", command: "true", cwd: "/", port: null, token: `token-${i}`, state: "running", pgid: null,
        exitCode: null, startedAt: i, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
      if (target !== "idle") store.insertJob({ id: "target-job", sessionKey: "target", name: "target", command: "true", cwd: "/",
        port: target === "watched service" ? 9000 : null, token: "target-job", state: "running", pgid: null,
        exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: target === "watched service" });
      Object.defineProperty(store, "db", { value: observed });
      assert.equal(workspaceWorking(store, () => "cold", "target"), target !== "idle");
      reads.push(seen);
    } finally { store.close(); }
  }
  assert.deepEqual(reads, target === "idle" ? [0, 0] : [1, 1]);
});

test("a workspace recheck follows its own session, jobs and waiting turn", () => {
  const store = Store.open(":memory:");
  try {
    const cold = () => "cold";
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    assert.equal(workspaceWorking(store, cold, "missing"), false);
    assert.equal(workspaceWorking(store, cold, "s"), false);
    assert.equal(workspaceWorking(store, () => "running", "s"), true);
    store.insertJob({ id: "service", sessionKey: "s", name: "service", command: "true", cwd: "/", port: 9000,
      token: "service", state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    assert.equal(workspaceWorking(store, cold, "s"), true, "running services also count as workspace work");
    store.db.prepare("UPDATE jobs SET state='exited' WHERE id='service'").run();
    assert.equal(workspaceWorking(store, cold, "s"), false);
    store.db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('t','s','user',0,1,'completed','waiting')").run();
    assert.equal(workspaceWorking(store, cold, "s"), true);
    store.db.prepare("UPDATE sessions SET archived_at=1 WHERE key='s'").run();
    assert.equal(workspaceWorking(store, cold, "s"), false);
  } finally { store.close(); }
});
