import assert from "node:assert/strict";
import { test } from "node:test";
import { autoArchive, startAutoArchiveTimer } from "../src/sessions/lifecycle.ts";
import { installSessionUpJobs, sessionUpJobsReady, sessionUpJobsStep } from "../src/store/session-up-jobs.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function job(store: Store, id: string, session: string, state: "running" | "exited", port: number | null) {
  store.insertJob({ id, sessionKey: session, name: id, command: "true", cwd: "/", port, token: id,
    state, pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
}

function session(store: Store, key: string) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
    token: key, createdAt: 1, lastActiveAt: 1 });
}

function observe(store: Store) {
  const db = store.db;
  let visits = 0;
  const plans: string[][] = [];
  db.function("visit_archive_job", () => { visits++; return 1; });
  Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (source: string) => {
        if (source.includes("session_up_job_rows")) {
          plans.push((target.prepare(`EXPLAIN QUERY PLAN ${source}`).all("mine") as { detail: string }[]).map((r) => r.detail));
        }
        const sql = source
          .replace("SELECT * FROM jobs WHERE state = 'running'", "SELECT *, visit_archive_job() AS visited FROM jobs WHERE state = 'running'")
          .replace("SELECT * FROM jobs WHERE state = 'exited' AND port IS NOT NULL", "SELECT *, visit_archive_job() AS visited FROM jobs WHERE state = 'exited' AND port IS NOT NULL")
          .replace("state = 'exited' AND port IS NOT NULL AND session_key = ?1", "state = 'exited' AND port IS NOT NULL AND visit_archive_job() AND session_key = ?1")
          .replace("SELECT 1 FROM session_up_job_rows", "SELECT visit_archive_job() FROM session_up_job_rows")
          .replace("SELECT j.id FROM session_up_job_rows", "SELECT j.id, visit_archive_job() AS visited FROM session_up_job_rows");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) });
  return { reset: () => { visits = 0; }, visits: () => visits, plans: () => plans,
    restore: () => Object.defineProperty(store, "db", { configurable: true, value: db }) };
}

test("automatic archive does not read other sessions' running jobs", async () => {
  const r = new Rig();
  try {
    session(r.store, "mine"); job(r.store, "mine-job", "mine", "running", null);
    const extra = (from: number, to: number) => { for (let i = from; i < to; i++) job(r.store, `other-${i}`, `s-${i}`, "running", null); };
    const observed = observe(r.store);
    try {
      extra(0, 40); observed.reset(); autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      const before = observed.visits();
      assert.equal(before, 1, "only the session's first job is read");
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      extra(40, 400); observed.reset(); autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      assert.equal(observed.visits(), before, `running jobs visited grew from ${before} to ${observed.visits()}`);
      assert.ok(observed.plans().some((p) => p.some((line) => line.includes("session_up_job_rows") && line.includes("session=?"))));
    } finally { observed.restore(); }
  } finally { await r.close(); }
});

test("a session's up jobs do not read other sessions' exited services", () => {
  const store = Store.open(":memory:");
  try {
    job(store, "mine", "mine", "exited", 9000);
    const extra = (from: number, to: number) => { for (let i = from; i < to; i++) job(store, `other-${i}`, `s-${i}`, "exited", 10_000 + i); };
    const observed = observe(store);
    try {
      extra(0, 40); observed.reset(); assert.deepEqual(store.upJobIds("mine"), ["mine"]);
      const before = observed.visits();
      assert.equal(before, 1, "only the session's own service is read");
      extra(40, 400);
      for (let i = 0; i < 400; i++) job(store, `old-mine-${i}`, "mine", "exited", null);
      observed.reset(); assert.deepEqual(store.upJobIds("mine"), ["mine"]);
      assert.equal(observed.visits(), before, `exited services visited grew from ${before} to ${observed.visits()}`);
      assert.ok(observed.plans().some((p) => p.some((line) => line.startsWith("SEARCH i ") && line.includes("session=?"))));
    } finally { observed.restore(); }
  } finally { store.close(); }
});

test("automatic archive checks only the first up job of one session", async () => {
  const r = new Rig();
  try {
    session(r.store, "mine");
    for (let i = 0; i < 400; i++) job(r.store, `mine-${i}`, "mine", "running", null);
    const observed = observe(r.store);
    try {
      observed.reset();
      autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      assert.equal(observed.visits(), 1);
    } finally { observed.restore(); }
  } finally { await r.close(); }
});

function makeOld(store: Store) {
  const db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_up_job_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_up_job_rows; DROP TABLE session_up_job_replaced; DROP TABLE session_up_job_scopes; DROP TABLE session_up_job_meta");
  installSessionUpJobs(db);
}

test("archive waits for a session's old jobs without guessing it is idle", async () => {
  const r = new Rig();
  try {
    session(r.store, "mine"); job(r.store, "mine-job", "mine", "exited", 9000);
    makeOld(r.store);
    const requested: string[] = [];
    autoArchive(r.hub, Date.now() + 3 * 86_400_000, undefined, undefined, (key) => requested.push(key));
    assert.deepEqual(requested, ["mine"]);
    assert.equal(r.store.getSession("mine")?.archivedAt, null);
    assert.deepEqual(r.store.upJobIds("mine"), ["mine-job"], "manual archiving still sees the old service");
    while (!sessionUpJobsReady(r.store.db, "mine")) sessionUpJobsStep(r.store.db, "mine", 1);
    autoArchive(r.hub, Date.now() + 3 * 86_400_000);
    assert.equal(r.store.getSession("mine")?.archivedAt, null);
  } finally { await r.close(); }
});

test("a manually archived session prepares its own old jobs before stopping them", async () => {
  const r = new Rig(), requested = Promise.withResolvers<string>(), ready = Promise.withResolvers<void>();
  const stopped: string[] = [];
  try {
    session(r.store, "mine"); job(r.store, "mine-job", "mine", "exited", 9000);
    for (let i = 0; i < 40; i++) job(r.store, `other-${i}`, `other-${i}`, "exited", 10_000 + i);
    makeOld(r.store);
    r.hub.prepareSessionUpJobs = async (key) => { requested.resolve(key); await ready.promise; };
    r.hub.jobs = { stop: async (id: string) => { stopped.push(id); } } as never;
    const actor = r.hub.actor(r.store.getSession("mine")!);
    const putAway = actor.putAway();
    assert.equal(await requested.promise, "mine");
    assert.deepEqual(stopped, []);
    while (!sessionUpJobsReady(r.store.db, "mine")) sessionUpJobsStep(r.store.db, "mine", 1);
    const observed = observe(r.store);
    try {
      ready.resolve();
      await putAway;
      assert.deepEqual(stopped, ["mine-job"]);
      assert.equal(observed.visits(), 1);
    } finally { observed.restore(); }
  } finally { ready.resolve(); r.hub.jobs = null; await r.close(); }
});

test("a failed old-job preparation still stops an archived session's jobs", async () => {
  const r = new Rig(), stopped: string[] = [];
  try {
    session(r.store, "mine"); job(r.store, "mine-job", "mine", "exited", 9000);
    makeOld(r.store);
    r.hub.prepareSessionUpJobs = async () => { throw new Error("preparation failed"); };
    r.hub.jobs = { stop: async (id: string) => { stopped.push(id); } } as never;
    await r.hub.actor(r.store.getSession("mine")!).putAway();
    assert.deepEqual(stopped, ["mine-job"]);
  } finally { r.hub.jobs = null; await r.close(); }
});

test("the archive timer shares old-job preparation and checks finished sessions on its regular pass", async () => {
  const r = new Rig(), ready = Promise.withResolvers<void>();
  let timer: { ms: number; run: () => void } | null = null, signal: AbortSignal | undefined;
  const calls: string[][] = [];
  const time = { after(ms: number, run: () => void) {
    const next = { ms, run }; timer = next;
    return () => { if (timer === next) timer = null; };
  } };
  const fire = (ms: number) => { const task = timer; assert.ok(task); assert.equal(task.ms, ms); timer = null; task.run(); };
  let stop = () => {};
  try {
    session(r.store, "short"); session(r.store, "long"); job(r.store, "long-job", "long", "running", null);
    makeOld(r.store);
    stop = startAutoArchiveTimer(r.hub, time, {
      prepareSaid: async () => {}, prepareSessionBindings: async () => {},
      prepareSessionUpJobs: (sessions, s) => { signal = s; calls.push([...sessions].sort()); return ready.promise; },
    });
    fire(60_000);
    assert.deepEqual(calls, [["long", "short"]]);
    assert.equal(r.store.getSession("short")?.archivedAt, null);
    assert.equal(r.store.getSession("long")?.archivedAt, null);
    assert.deepEqual(sessionUpJobsStep(r.store.db, "short", 1), { done: true, visited: 0 });
    fire(600_000);
    assert.notEqual(r.store.getSession("short")?.archivedAt, null);
    assert.equal(r.store.getSession("long")?.archivedAt, null);
    assert.deepEqual(calls, [["long", "short"]], "the ongoing preparation is shared");
    while (!sessionUpJobsReady(r.store.db, "long")) sessionUpJobsStep(r.store.db, "long", 1);
    ready.resolve(); await ready.promise; await Promise.resolve();
    fire(0);
    assert.equal(r.store.getSession("long")?.archivedAt, null);
    stop();
    assert.equal(signal?.aborted, true);
  } finally { stop(); ready.resolve(); await r.close(); }
});
