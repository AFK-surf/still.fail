import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { SessionUpJobsBuilder } from "../src/read/session-up-jobs-builder.ts";
import { Readers } from "../src/read/pool.ts";
import { installSessionUpJobs, sessionUpJobsReady } from "../src/store/session-up-jobs.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "session-up-jobs-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'workspace_up_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE workspace_up_session_replaced; DROP TABLE workspace_up_sessions; DROP TABLE workspace_up_meta");
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_up_job_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_up_job_rows; DROP TABLE session_up_job_replaced; DROP TABLE session_up_job_scopes; DROP TABLE session_up_job_meta");
  const put = db.prepare(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log)
    VALUES(?,?,?,'running','','','',?, '')`);
  for (let i = 0; i < 1024; i++) put.run(`long-${i}`, `long-${i}`, "long", i);
  put.run("short", "short", "short", 1);
  installSessionUpJobs(db);
  return { dir, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("a short requested session is prepared before a long one, after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>();
  const builder = new SessionUpJobsBuilder(join(f.dir, "stillfail.db"), { previousGone: previous.promise });
  try {
    let longReady = false;
    const long = builder.ready(["long"]).then(() => { longReady = true; });
    const short = builder.ready(["short"]);
    assert.equal(sessionUpJobsReady(f.store.db, "short"), false);
    assert.equal(f.store.db.prepare("SELECT count(*) AS n FROM session_up_job_scopes").get()!.n, 0);
    previous.resolve();
    await short;
    assert.equal(sessionUpJobsReady(f.store.db, "short"), true);
    assert.equal(longReady, false);
    await long;
    assert.equal(sessionUpJobsReady(f.store.db, "long"), true);
  } finally { previous.resolve(); await builder.close(); f.close(); }
});

test("one cancelled archive check leaves another waiting for the same session", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const builder = new SessionUpJobsBuilder(join(f.dir, "stillfail.db"), { previousGone: previous.promise });
  try {
    const abandoned = builder.ready(["short"], controller.signal);
    const kept = builder.ready(["short"]);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    await kept;
    assert.equal(sessionUpJobsReady(f.store.db, "short"), true);
  } finally { controller.abort(); previous.resolve(); await builder.close(); f.close(); }
});

test("abandoned old-job preparation does not start after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), controller = new AbortController();
  const builder = new SessionUpJobsBuilder(join(f.dir, "stillfail.db"), { previousGone: previous.promise });
  try {
    const abandoned = builder.ready(["long"], controller.signal);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    const kept = builder.ready(["short"]);
    previous.resolve();
    await kept;
    assert.equal(sessionUpJobsReady(f.store.db, "long"), false);
    assert.equal(f.store.db.prepare("SELECT 1 FROM session_up_job_scopes WHERE session='long'").get(), undefined);
  } finally { controller.abort(); previous.resolve(); await builder.close(); f.close(); }
});

test("a stopped old-job worker resumes its pending session", async () => {
  const f = fixture(), file = join(f.dir, "worker.mjs"), marker = join(f.dir, "exited");
  try {
    const real = new URL("../src/read/session-up-jobs-worker.ts", import.meta.url).href;
    writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
    const builder = new SessionUpJobsBuilder(join(f.dir, "stillfail.db"), {}, pathToFileURL(file));
    try {
      await builder.ready(["short"]);
      assert.ok(existsSync(marker));
      assert.equal(sessionUpJobsReady(f.store.db, "short"), true);
      assert.deepEqual(f.store.upJobIds("short"), ["short"]);
    } finally { await builder.close(); }
  } finally { f.close(); }
});

test("a session detail answers during handover, then prepares its old jobs in the background", async () => {
  const dir = mkdtempSync(join(tmpdir(), "session-up-detail-"));
  const store = Store.open(join(dir, "stillfail.db"));
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const preparing = Promise.withResolvers<void>(), prepared = Promise.withResolvers<void>();
  void prepared.promise.catch(() => {});
  const prepare = readers.prepareSessionUpJobs.bind(readers);
  let calls = 0;
  readers.prepareSessionUpJobs = (sessions, signal) => {
    calls++;
    preparing.resolve();
    const pending = prepare(sessions, signal);
    void pending.then(() => prepared.resolve(), prepared.reject);
    return pending;
  };
  try {
    store.insertSession({ key: "mine", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "mine", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    store.db.exec(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log)
      VALUES('old','old','mine','running','','','',1,''); UPDATE session_up_job_meta SET fresh=0`);
    const ended = store.db.prepare(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log)
      VALUES(?,?,'mine','exited','','','',?, '')`);
    for (let i = 0; i < 60; i++) ended.run(`ended-${i}`, `ended-${i}`, i + 10);
    const viewer = { sub: "u", email: "u@example.com", name: "U", role: "owner", workspace: "mine", device: "d", home: false };
    const args = { key: "mine", viewer, lang: "en", jobs: "now", turns: "0" };
    const answer = JSON.parse(await readers.read("session", args, "en"));
    assert.equal(answer.jobs.length, 51);
    assert.ok(answer.jobs.some((job: { id: string }) => job.id === "old"));
    await preparing.promise;
    assert.equal(sessionUpJobsReady(store.db, "mine"), false);
    const whileWaiting = JSON.parse(await readers.read("session", args, "en"));
    assert.deepEqual(whileWaiting.jobs.map((job: { id: string }) => job.id), answer.jobs.map((job: { id: string }) => job.id));
    assert.equal(calls, 1, "repeated reads share one background preparation during handover");
    await readers.read("summary", { key: "mine" }, "en");
    assert.equal(calls, 1, "a later read does not repeat the previous reader's request");
    await assert.rejects(readers.read("session", { ...args, viewer: { ...viewer, workspace: "other" } }, "en"));
    assert.equal(calls, 1, "a refused read does not request preparation");
    previous.resolve();
    await prepared.promise;
    assert.equal(sessionUpJobsReady(store.db, "mine"), true);
    const again = JSON.parse(await readers.read("session", args, "en"));
    assert.deepEqual(again.jobs.map((job: { id: string }) => job.id), answer.jobs.map((job: { id: string }) => job.id));
    assert.equal(calls, 1);

    store.db.exec("UPDATE session_up_job_meta SET fresh=0; DELETE FROM session_up_job_scopes WHERE session='mine'");
    let attempts = 0;
    const retried = Promise.withResolvers<void>();
    void retried.promise.catch(() => {});
    readers.prepareSessionUpJobs = (sessions, signal) => {
      if (++attempts === 1) return Promise.reject(new Error("injected preparation failure"));
      const pending = prepare(sessions, signal);
      void pending.then(retried.resolve, retried.reject);
      return pending;
    };
    await readers.read("session", args, "en");
    await new Promise<void>((resolve) => setImmediate(resolve));
    await readers.read("session", args, "en");
    await retried.promise;
    assert.equal(attempts, 2, "a later read retries a failed background preparation");
    assert.equal(sessionUpJobsReady(store.db, "mine"), true);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
