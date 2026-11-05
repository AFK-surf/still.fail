import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { SessionUpJobsBuilder } from "../src/read/session-up-jobs-builder.ts";
import { installSessionUpJobs, sessionUpJobsReady } from "../src/store/session-up-jobs.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "session-up-jobs-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
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
