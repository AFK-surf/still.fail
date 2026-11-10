// The MoonBit session backfill makes the running-process-jobs lookup and brings an older store's running jobs across
// as `installProcessJobs` and `processJobsStep` do: the same schema, answers and rows, batch by batch, with jobs
// written meanwhile, and the walk started over when the schema changes between batches.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { installProcessJobs, processJobsStep } from "../src/store/process-jobs.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const addSql = `INSERT OR REPLACE INTO jobs(rowid,id,token,session_key,state,pgid,name,command,cwd,port,started_at,log)
  VALUES(?,?,?,?,?,?,?,'','',?,?, '')`;

/// A store of 400 jobs from before the lookup (running ones with and without a process group, exited ones), the
/// lookup not made yet.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-process-jobs-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'process_job_%'").all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE IF EXISTS process_job_meta; DROP TABLE IF EXISTS process_job_rows; DROP TABLE IF EXISTS process_job_replaced");
  const put = db.prepare(addSql);
  db.exec("BEGIN");
  for (let i = 1; i <= 400; i++) put.run(i, `j${i}`, `t${i}`, `s${i % 5}`, i % 4 === 0 ? "exited" : "running", i % 3 === 0 ? null : 100 + i, `name${i}`, i % 7 === 0 ? 8000 : null, i);
  db.exec("COMMIT");
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number) {
  const db = f.store.db, put = db.prepare(addSql);
  if (n === 1) {
    put.run(500, "late", "tl", "s1", "running", 900, "late", null, 500);
    db.exec("UPDATE jobs SET state = 'exited' WHERE id = 'j2'");
    db.exec("UPDATE jobs SET pgid = 777 WHERE id = 'j3'");
    db.exec("DELETE FROM jobs WHERE id = 'j399'");
    put.run(5, "j5", "t398", "s1", "running", 55, "replaced", null, 5);
  }
  // (a schema change between batches: the walk starts over)
  if (n === 3) db.exec("CREATE INDEX IF NOT EXISTS mb_test_jobs_name ON jobs(name)");
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(store: Store): string {
  const db = store.db;
  const schema = (db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name LIKE 'process_job%' ORDER BY type, name").all() as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  return JSON.stringify([schema,
    db.prepare("SELECT job FROM process_job_rows ORDER BY job").all(),
    db.prepare("SELECT version, complete, CAST(cursor AS TEXT) AS cursor, CAST(end_rowid AS TEXT) AS end_rowid FROM process_job_meta").all()]);
}

test("the MoonBit session backfill makes and fills the process jobs lookup as the TypeScript does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "session-backfill", "--db", mb.path]);
  try {
    let n = 0, done = false;
    for (; n < 30 && !done; n++) {
      writes(ts, n); writes(mb, n);
      const answered = new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => builder.once("message", resolve));
      builder.postMessage({ kind: "process-jobs" });
      const ours = await answered;
      assert.equal(ours.error, undefined);
      assert.equal(ours.fallback, undefined);
      installProcessJobs(ts.store.db);
      done = processJobsStep(ts.store.db).done;
      assert.equal(ours.done, done, `batch ${n}`);
      assert.equal(tables(mb.store), tables(ts.store), `batch ${n}`);
    }
    assert.ok(done && n >= 6, `${n} batches`);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});
