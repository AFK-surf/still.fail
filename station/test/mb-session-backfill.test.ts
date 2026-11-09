// The MoonBit builder of what the station prepares for its sessions after a handover (station/mb, src/activity) brings
// an older store across as `workspaceActivityStep`, `recoverWaitsStep` and `awakeWaitsStep` do: the same answers and
// tables, batch by batch, with sessions and turns written meanwhile; a kind it has not taken over is left to the worker.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { MbBackfill, MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { awakeWaitsStep } from "../src/store/awake-waits.ts";
import { recoverWaitsStep } from "../src/store/recover-waits.ts";
import { Store } from "../src/store/store.ts";
import { workspaceActivityStep } from "../src/store/workspace-activity.ts";

const binary = mbReaderBinary();

/// A store of 600 sessions in a few workspaces: some running, some with pending deliveries or letters, most with a
/// last turn (waiting with a wait, failed on a rate limit, done); the three lookups emptied as an older store has them.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-session-backfill-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  db.exec("BEGIN");
  const turn = db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds,detail) VALUES (?,?,'user',?,?,?,?,?,?)");
  for (let i = 0; i < 600; i++) {
    const key = `s${String(i).padStart(3, "0")}`;
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws: i % 5 === 0 ? null : `W${i % 3}` });
    if (i % 3 === 0) db.prepare("UPDATE sessions SET running = 1 WHERE key = ?").run(key);
    if (i % 11 === 0) db.prepare("INSERT INTO deliveries (thread,n,session,delivered_at) VALUES (1,?,?,NULL)").run(i, key);
    if (i % 13 === 0) db.prepare("INSERT INTO letter_deliveries (thread,n,session,delivered_at) VALUES (1,?,?,NULL)").run(i, key);
    if (i % 4 !== 3) turn.run(`t${i}`, key, i, i + 1, i % 4 === 1 ? "failed" : "completed", i % 4 === 0 ? "waiting" : null,
      i % 8 === 0 ? 600 : null, i % 4 === 1 ? "rate_limit: soon" : null);
  }
  db.exec("COMMIT");
  db.exec(`DELETE FROM workspace_activity; UPDATE workspace_activity_meta SET cursor = NULL, complete = 0 WHERE id = 1;
    DELETE FROM session_recover_waits; UPDATE session_recover_wait_meta SET cursor = NULL, complete = 0 WHERE id = 1;
    UPDATE session_awake_wait_meta SET cursor = NULL, complete = 0 WHERE id = 1`);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, step: number) {
  const db = f.store.db;
  if (step === 1) {
    db.exec("UPDATE sessions SET running = 1 WHERE key = 's599'");
    db.exec("UPDATE sessions SET running = 0 WHERE key = 's003'");
    db.exec("INSERT INTO deliveries (thread,n,session,delivered_at) VALUES (2,1,'s150',NULL)");
    db.exec("UPDATE sessions SET archived_at = 5 WHERE key = 's004'");
    db.exec("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES ('late','s590','user',900,901,'completed','waiting',60)");
  }
  if (step === 3) db.exec("DELETE FROM sessions WHERE key IN ('s008', 's580')");
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT ws, session FROM workspace_activity ORDER BY ws, session"),
    all("SELECT cursor, complete FROM workspace_activity_meta"),
    all("SELECT session, awake_deadline FROM session_recover_waits ORDER BY session"),
    all("SELECT cursor, complete FROM session_recover_wait_meta"),
    all("SELECT deadline, session FROM session_awake_deadlines ORDER BY deadline, session"),
    all("SELECT cursor, complete FROM session_awake_wait_meta"),
  ].join("\n");
}

for (const [kind, step] of [["activity", workspaceActivityStep], ["recovery", recoverWaitsStep], ["awake", awakeWaitsStep]] as const) {
  test(`the MoonBit builder brings the ${kind} lookup across as the TypeScript does`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(), mb = old();
    const builder = new MbProcess(binary!, ["--builder", "session-backfill", "--db", mb.path]);
    try {
      // (the awake deadlines wait for the recovery lookup: brought across first on both)
      if (kind === "awake") for (const f of [ts, mb]) while (!recoverWaitsStep(f.store.db).done);
      let n = 0, done = false;
      for (; n < 30 && !done; n++) {
        writes(ts, n); writes(mb, n);
        const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ kind });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        done = step(ts.store.db).done;
        assert.equal(ours.done, done, `batch ${n}`);
        assert.equal(tables(mb.store), tables(ts.store), `batch ${n}`);
      }
      assert.ok(done && n >= 3, `${n} batches`);
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}

test("a kind the MoonBit builder leaves to the worker is asked of the worker, which answers from then on", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const file = new URL("../src/sessions/workspace-activity-worker.ts", import.meta.url);
  const priority = new SharedArrayBuffer(8);
  const backfill = new MbBackfill(binary!, ["--builder", "session-backfill", "--db", f.path], priority, 20,
    () => new Worker(file, { workerData: { path: f.path, priority } }));
  try {
    const ask = (message: object) => {
      const answered = new Promise<{ done: boolean; error?: string; kind?: string }>((resolve) => backfill.once("message", resolve));
      backfill.postMessage(message);
      return answered;
    };
    // the program's own kind, then one only the worker has (its answers say their kind)
    assert.equal((await ask({ kind: "activity" })).kind, undefined);
    const theirs = await ask({ kind: "not-moved-yet" });
    assert.equal(theirs.error, undefined);
    assert.equal(theirs.kind, "not-moved-yet");
    assert.equal((await ask({ kind: "activity" })).kind, "activity", "the worker answers from then on");
    assert.equal(new Int32Array(priority)[1], 0, "no permit left held");
  } finally {
    await backfill.terminate();
    f.close();
  }
});
