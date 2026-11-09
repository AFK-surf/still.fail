import assert from "node:assert/strict";
import { test } from "node:test";
import { workspaceSessionsToMeasure, workspaceWorking } from "../src/jobs/workspace-size.ts";
import { RUNNING_JOB_SESSIONS } from "../src/store/active-jobs.ts";
import { JOBS_RUNNING, Store } from "../src/store/store.ts";

for (const matching of [false, true]) test(`a workspace sweep does not read unrelated running jobs (${matching ? "one matching job" : "no matching job"})`, () => {
  const reads: number[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      store.insertSession({ key: "mine", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "mine", createdAt: 1, lastActiveAt: 1 });
      for (let i = 0; i < unrelated; i++) store.insertJob({ id: `remote_${i}`, sessionKey: `other-${i}`,
        name: "queued", command: "true", cwd: "/", port: null, token: `token-${i}`, state: "running", pgid: null,
        exitCode: null, startedAt: i, endedAt: null, restarts: 0, log: "/dev/null", watch: false, queued: true });
      if (matching) store.insertJob({ id: "mine-job", sessionKey: "mine", name: "mine", command: "true", cwd: "/", port: null,
        token: "mine-job", state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
      let seen = 0;
      db.function("workspace_sweep_job_seen", () => { seen++; return 1; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql === JOBS_RUNNING
          ? sql.replace("WHERE state = 'running'", "WHERE state = 'running' AND workspace_sweep_job_seen()")
          : sql === RUNNING_JOB_SESSIONS ? sql.replaceAll("WHERE session = c.value", "WHERE session = c.value AND workspace_sweep_job_seen()") : sql);
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      Object.defineProperty(store, "db", { value: observed });
      assert.deepEqual(workspaceSessionsToMeasure(store, () => "cold").map((s) => s.key), matching ? ["mine"] : []);
      reads.push(seen);
    } finally { store.close(); }
  }
  assert.deepEqual(reads, matching ? [1, 1] : [0, 0]);
});

test("a workspace sweep includes running sessions, processes, jobs and waits only", () => {
  const store = Store.open(":memory:");
  try {
    for (const key of ["idle", "turn", "process", "service", "waiting", "archived"]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
    }
    store.setRunning("turn", true);
    store.insertJob({ id: "service-job", sessionKey: "service", name: "service", command: "true", cwd: "/", port: 9000,
      token: "service-job", state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    store.db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('t','waiting','user',0,1,'completed','waiting')").run();
    store.db.prepare("UPDATE sessions SET archived_at=1 WHERE key='archived'").run();
    const selected = workspaceSessionsToMeasure(store, (key) => key === "process" ? "running" : "cold").map((s) => s.key).sort();
    assert.deepEqual(selected, ["process", "service", "turn", "waiting"]);
  } finally { store.close(); }
});

test("a workspace sweep keeps answering while an old active-job lookup is being prepared", () => {
  const store = Store.open(":memory:");
  try {
    for (const key of ["job", "idle"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
    store.insertJob({ id: "watch", sessionKey: "job", name: "watch", command: "true", cwd: "/", port: null,
      token: "watch", state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: true });
    store.db.exec("DROP TABLE active_watch_jobs; DROP TABLE active_other_jobs");
    assert.deepEqual(workspaceSessionsToMeasure(store, () => "cold").map((s) => s.key), ["job"]);
    assert.deepEqual([...store.runningJobSessions([])], []);
  } finally { store.close(); }
});

test("a workspace sweep follows changing sessions and jobs", () => {
  const store = Store.open(":memory:");
  try {
    for (let i = 0; i < 8; i++) store.insertSession({ key: `s${i}`, connect: "ember", runtime: "claude", profile: "cc",
      workspace: `/w/${i}`, token: `s${i}`, createdAt: 1, lastActiveAt: 1 });
    store.db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('t','s3','user',0,1,'completed','waiting')").run();
    const put = store.db.prepare(`INSERT OR REPLACE INTO jobs (id, session_key, name, command, cwd, token, state, started_at, log, watch)
      VALUES (?, ?, 'job', 'true', '/', ?, ?, 1, '/dev/null', ?)`);
    const session = store.db.prepare("UPDATE sessions SET running = ?, archived_at = ? WHERE key = ?");
    let seed = 0x54821;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    const processState = (key: string) => key === "s5" ? "running" : "cold";
    for (let i = 0; i < 120; i++) {
      const id = `job-${next(16)}`, key = `s${next(8)}`;
      put.run(id, key, id, next(3) === 0 ? "exited" : "running", next(2));
      session.run(next(4) === 0 ? 1 : 0, next(5) === 0 ? 1 : null, `s${next(8)}`);
      const expected = store.liveSessions().filter((s) => workspaceWorking(store, processState, s.key)).map((s) => s.key);
      assert.deepEqual(workspaceSessionsToMeasure(store, processState).map((s) => s.key), expected);
    }
  } finally { store.close(); }
});
