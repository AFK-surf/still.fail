import assert from "node:assert/strict";
import { test } from "node:test";
import { working } from "../src/ops/awake.ts";
import { AWAKE_JOBS } from "../src/store/active-jobs.ts";
import { JOBS_RUNNING, Store } from "../src/store/store.ts";

for (const watchedService of [false, true]) test(`the awake check does not read unrelated running services (${watchedService ? "watched service" : "command"})`, () => {
  const reads: { running: number; candidates: number }[] = [];
  for (const services of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    let visited = 0, candidates = 0, observing = false;
    db.function("awake_job_seen", (_id) => { if (observing) visited++; return 1; });
    db.function("awake_candidate_seen", (_id) => { if (observing) candidates++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === JOBS_RUNNING) return target.prepare(sql.replace("WHERE state = 'running'", "WHERE awake_job_seen(id) AND state = 'running'"));
        if (sql === AWAKE_JOBS) return target.prepare(sql
          .replace("WHERE j.state = 'running'", "WHERE awake_candidate_seen(j.id) AND j.state = 'running'")
          .replace("WHERE state = 'running'", "WHERE awake_candidate_seen(id) AND state = 'running'"));
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const add = (id: string, port: number | null, watch = false) => store.insertJob({ id, sessionKey: "missing", name: id,
        command: "true", cwd: "/", port, token: id, state: "running", pgid: null, exitCode: null,
        startedAt: 100, endedAt: null, restarts: 0, log: "/dev/null", watch });
      for (let i = 0; i < services; i++) add(`service-${i}`, 10_000 + i);
      add("work", watchedService ? 9001 : null, watchedService);
      Object.defineProperty(store, "db", { value: observed });
      observing = true;
      assert.equal(working(store, 1_000), true);
      observing = false;
      reads.push({ running: visited, candidates });
    } finally { store.close(); }
  }
  assert.deepEqual(reads, [{ running: 0, candidates: 1 }, { running: 0, candidates: 1 }]);
});

test("an unexpired wait holds the machine without reading jobs", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "wait", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "wait", createdAt: 1, lastActiveAt: 1 });
    store.db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES ('t','wait','user',0,1,'completed','waiting',600)").run();
    store.awakeJobs = () => { throw new Error("jobs should not be read"); };
    assert.equal(working(store, 100), true);
  } finally { store.close(); }
});

test("the awake job lookup follows running commands, watches and their changes", () => {
  const store = Store.open(":memory:");
  try {
    const add = (id: string, port: number | null, watch: boolean, state: string = "running") => store.insertJob({ id, sessionKey: id,
      name: id, command: "true", cwd: "/", port, token: id, state, pgid: null, exitCode: null, startedAt: 10,
      endedAt: null, restarts: 0, log: "/dev/null", watch });
    add("command", null, false);
    add("watch", null, true);
    add("watch-service", 9001, true);
    add("service", 9002, false);
    add("ended", null, true, "exited");
    const compare = () => {
      const old = store.jobsRunning().filter((job) => job.watch || job.port === null).map((job) => job.sessionKey).sort();
      const current = store.awakeJobs().map((job) => job.sessionKey).sort();
      assert.deepEqual(current, old);
      assert.equal(new Set(current).size, current.length, "a watch without a port appears once");
    };
    compare();
    store.db.prepare("UPDATE jobs SET state='exited' WHERE id='watch-service'").run();
    store.db.prepare("UPDATE jobs SET port=NULL WHERE id='service'").run();
    store.db.prepare("UPDATE jobs SET watch=-1 WHERE id='command'").run();
    compare();
    store.db.prepare("UPDATE jobs SET state='running' WHERE id='ended'").run();
    store.db.prepare("UPDATE jobs SET watch=0, port=9003 WHERE id='watch'").run();
    compare();
  } finally { store.close(); }
});
