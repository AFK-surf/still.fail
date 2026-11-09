// The MoonBit builder of the overview's session counts (station/mb, src/counts) brings old sessions across as
// `sessionCountsStep` does: the same answers and tables, batch by batch, with sessions written meanwhile and rowids
// beyond 2^53; the station's backfill permit taken for each batch (read/mb-reader.ts `MbBackfill`).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbBackfill, MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { installSessionCounts, sessionCountsReady, sessionCountsStep } from "../src/store/session-counts.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A store of 700 sessions (two beyond 2^53 by rowid) from before the counts, the index made over them, none counted.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-session-counts-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_count_%'").all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_count_seen; DROP TABLE session_count_replaced; DROP TABLE session_count_groups; DROP TABLE session_count_totals; DROP TABLE session_count_meta");
  const put = db.prepare("INSERT INTO sessions (rowid,key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES (?,?,?,'thread','claude','cc','/w',?,1,1,?)");
  db.exec("BEGIN");
  put.run(-9007199254740993n, "negative", "x", "negative", "mine");
  for (let i = 1; i <= 700; i++) put.run(i, `s${i}`, ["x", "y", "z"][i % 3], `t${i}`, i % 4 === 0 ? null : `w${i % 5}`);
  put.run(9007199254740993n, "positive", "y", "positive", null);
  db.exec("COMMIT");
  installSessionCounts(db);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, step: number) {
  const db = f.store.db;
  if (step === 1) {
    db.exec("UPDATE sessions SET ws = 'moved', connect = 'q' WHERE key IN ('s3', 's600')");
    db.exec("DELETE FROM sessions WHERE key IN ('s4', 's650')");
    db.exec("INSERT INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES ('late','x','thread','claude','cc','/w','late',1,1,'w1')");
    db.exec("INSERT OR REPLACE INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES ('replacer','z','thread','claude','cc','/w','t5',1,1,NULL)");
  }
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT session, connect, ws FROM session_count_seen ORDER BY session"),
    all("SELECT kind, ws, connect, n FROM session_count_groups ORDER BY kind, ws, connect"),
    all("SELECT kind, ws, n FROM session_count_totals ORDER BY kind, ws"),
    all("SELECT version, CAST(last_rowid AS TEXT) AS last, CAST(end_rowid AS TEXT) AS end, complete FROM session_count_meta"),
  ].join("\n");
}

test("the MoonBit builder counts old sessions batch by batch as sessionCountsStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "session-counts", "--db", mb.path]);
  try {
    let step = 0, done = false;
    for (; step < 20 && !done; step++) {
      writes(ts, step); writes(mb, step);
      const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
      builder.postMessage({});
      const ours = await answered;
      assert.equal(ours.error, undefined);
      done = sessionCountsStep(ts.store.db).done;
      assert.equal(ours.done, done, `step ${step}`);
      assert.equal(tables(mb.store), tables(ts.store), `step ${step}`);
    }
    assert.ok(done && step >= 3, `${step} steps`);
    assert.equal(sessionCountsReady(mb.store.db), true);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("a MoonBit backfill batch waits for the permit, and gives it back", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const priority = new SharedArrayBuffer(8), flags = new Int32Array(priority);
  const backfill = new MbBackfill(binary!, ["--builder", "session-counts", "--db", f.path], priority, 20);
  try {
    const answer = () => new Promise<{ done: boolean }>((resolve) => backfill.once("message", resolve));
    // a foreground write announced: the batch is answered not done, nothing counted
    Atomics.add(flags, 0, 1);
    let answered = answer();
    backfill.postMessage({});
    assert.deepEqual(await answered, { done: false });
    assert.equal((f.store.db.prepare("SELECT COUNT(*) AS n FROM session_count_seen").get() as { n: number }).n, 0);
    Atomics.sub(flags, 0, 1);
    let done = false;
    for (let i = 0; i < 20 && !done; i++) {
      answered = answer();
      backfill.postMessage({});
      done = (await answered).done;
      assert.equal(Atomics.load(flags, 1), 0, "the permit given back after each batch");
    }
    assert.equal(done, true);
    assert.equal(sessionCountsReady(f.store.db), true);
  } finally {
    await backfill.terminate();
    f.close();
  }
});
