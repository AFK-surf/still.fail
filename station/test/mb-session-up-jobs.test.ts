// The MoonBit builder of the sessions' up jobs (station/mb, src/upjobs) prepares a session's old jobs as
// `sessionUpJobsStep` does: the same jobs, batch by batch, give the same answers and the same tables.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { SessionUpJobsBuilder } from "../src/read/session-up-jobs-builder.ts";
import { installSessionUpJobs, sessionUpJobsReady, sessionUpJobsStep } from "../src/store/session-up-jobs.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A station's database whose jobs are from before their index: 900 of one session's, running, exited with a port
/// (a service) or exited, some gone again; a few of another's; the index installed over them, nothing prepared.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-session-up-jobs-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_up_job_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_up_job_rows; DROP TABLE session_up_job_replaced; DROP TABLE session_up_job_scopes; DROP TABLE session_up_job_meta");
  const put = db.prepare(`INSERT INTO jobs(id, token, session_key, state, port, name, command, cwd, started_at, log)
    VALUES (?, ?, ?, ?, ?, '', '', '', ?, '')`);
  for (let i = 0; i < 900; i++) put.run(`long-${i}`, `long-${i}`, "long", i % 3 === 0 ? "exited" : "running", i % 6 === 0 ? 8000 + i : null, i);
  for (let i = 0; i < 5; i++) put.run(`short-${i}`, `short-${i}`, "short", "running", null, i);
  db.exec("DELETE FROM jobs WHERE rowid % 17 = 0");
  installSessionUpJobs(db);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT session, job_rowid FROM session_up_job_rows ORDER BY session, job_rowid"),
    all("SELECT session, last_rowid, end_rowid, complete FROM session_up_job_scopes ORDER BY session"),
  ].join("\n");
}

test("the MoonBit builder prepares a session's old jobs batch by batch as sessionUpJobsStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "session-up-jobs", "--db", mb.path]);
  try {
    const steps: { session: string; ts: boolean; mb: boolean }[] = [];
    for (const session of ["short", "long", "none"]) {
      for (let i = 0; i < 10; i++) {
        const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ session });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        steps.push({ session, ts: sessionUpJobsStep(ts.store.db, session).done, mb: ours.done });
        if (ours.done) break;
      }
    }
    assert.ok(steps.filter((s) => s.session === "long").length >= 4, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(tables(mb.store), tables(ts.store));
    for (const session of ["short", "long", "none"]) assert.equal(sessionUpJobsReady(mb.store.db, session), true);
    const invalid = new Promise((resolve) => builder.once("message", resolve));
    builder.postMessage({ scope: "all" });
    assert.deepEqual(await invalid, { done: false, error: "invalid session up jobs preparation request" });
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station's session up jobs builder finishes what it is asked", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const builder = new SessionUpJobsBuilder(f.path, {});
  try {
    await builder.ready(["long", "short"]);
    assert.equal(sessionUpJobsReady(f.store.db, "long"), true);
    assert.equal(sessionUpJobsReady(f.store.db, "short"), true);
  } finally {
    await builder.close();
    f.close();
  }
});
