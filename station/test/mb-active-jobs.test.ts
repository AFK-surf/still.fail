// The MoonBit session backfill builds an older store's active-job lookups beside the running queue and publishes them
// (and copies the remote keys of an other-jobs table older than its remote index) as `activeJobUpgradeStep` does: the
// same schema, answers and rows, batch by batch, with jobs written meanwhile and the schema changed between batches.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { activeJobUpgradeStep } from "../src/store/active-jobs-upgrade.ts";

const binary = mbReaderBinary();

/// A jobs table of 400 jobs (watched and not, running and done, some remote); `remote`: the two lookups already there
/// but the other jobs' table from before its remote index.
function old(remote: boolean) {
  const dir = mkdtempSync(join(tmpdir(), "mb-active-jobs-"));
  const path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode = WAL;
    CREATE TABLE jobs(id TEXT PRIMARY KEY, session_key TEXT NOT NULL, state TEXT NOT NULL, watch INTEGER NOT NULL, token TEXT UNIQUE NOT NULL);
    CREATE INDEX jobs_state ON jobs(state);`);
  const add = db.prepare("INSERT INTO jobs VALUES (?, ?, ?, ?, ?)");
  db.exec("BEGIN");
  for (let i = 0; i < 400; i++) add.run(i % 5 === 0 ? `remote_${i}` : `job-${i}`, `s${i % 7}`, i % 4 === 0 ? "exited" : "running", i % 3 === 0 ? 1 : 0, `token-${i}`);
  db.exec("COMMIT");
  if (remote) {
    db.exec(`CREATE TABLE active_watch_jobs (job TEXT PRIMARY KEY, session TEXT NOT NULL, token TEXT NOT NULL UNIQUE) WITHOUT ROWID;
      CREATE TABLE active_other_jobs (session TEXT NOT NULL, job TEXT NOT NULL, PRIMARY KEY (session, job)) WITHOUT ROWID;
      INSERT INTO active_other_jobs SELECT session_key, id FROM jobs WHERE state = 'running' AND watch = 0;`);
  }
  return { dir, path, db, close: () => { db.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number, remote: boolean) {
  const db = f.db;
  if (n === 1) {
    db.exec("INSERT INTO jobs VALUES ('remote_late', 's1', 'running', 0, 'late')");
    db.exec("UPDATE jobs SET state = 'exited' WHERE id = 'job-1'");
    db.exec("UPDATE jobs SET watch = 1 WHERE id = 'job-2'");
    db.exec("DELETE FROM jobs WHERE id = 'job-398'");
    db.exec("INSERT OR REPLACE INTO jobs VALUES ('job-3', 's9', 'running', 0, 'token-397')");
    if (remote) db.exec("INSERT INTO active_other_jobs VALUES ('s1', 'remote_late'); DELETE FROM active_other_jobs WHERE job = 'remote_5'");
  }
  // (a schema change between batches: the walk starts over)
  if (n === 2) db.exec("CREATE INDEX IF NOT EXISTS mb_test_jobs_session ON jobs(session_key)");
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(db: DatabaseSync): string {
  const schema = (db.prepare("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name LIKE 'active_%' ORDER BY type, name").all() as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'active_%' ORDER BY name").all() as { name: string }[]).map((r) => r.name);
  return JSON.stringify([schema, names.map((name) => (db.prepare(`SELECT * FROM ${name}`).all() as object[])
    .map((r) => JSON.stringify(r, (k, v) => k === "schema_version" ? "(the store's own)" : v)).sort())]);
}

for (const remote of [false, true]) {
  test(`the MoonBit session backfill ${remote ? "copies the remote keys" : "builds and publishes the active-job lookups"} as the TypeScript does`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(remote), mb = old(remote);
    const builder = new MbProcess(binary!, ["--builder", "session-backfill", "--db", mb.path]);
    try {
      let n = 0, done = false;
      for (; n < 30 && !done; n++) {
        writes(ts, n, remote); writes(mb, n, remote);
        const answered = new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ kind: "active-jobs" });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        assert.equal(ours.fallback, undefined);
        done = activeJobUpgradeStep(ts.db).done;
        assert.equal(ours.done, done, `batch ${n}`);
        assert.equal(tables(mb.db), tables(ts.db), `batch ${n}`);
      }
      assert.ok(done && n >= 4, `${n} batches`);
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}
