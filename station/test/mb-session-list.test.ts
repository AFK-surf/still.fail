// The MoonBit builder of the session list's index (station/mb, src/sessions) copies the old sessions as
// `sessionListStep` does, and visits them again for search as `auditSessionListStep` does: the same sessions, batch by
// batch, give the same answers and the same tables.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { SessionListBuilder } from "../src/read/session-list-builder.ts";
import { auditSessionListStep, installSessionListIndex, sessionListReady, sessionListStep } from "../src/store/session-list-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A station's database whose sessions are from before the list's index: 650 of them in three workspaces and none,
/// some archived, some with a key holding a NUL, some gone again (gaps).
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-session-list-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_list_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_list_rows; DROP TABLE session_list_replaced; DROP TABLE session_list_meta");
  for (let i = 0; i < 650; i++) {
    const key = i % 50 === 0 ? `with\u0000nul-${i}` : `session-${i}`;
    store.insertSession({ key, connect: i % 2 === 0 ? "ember" : "slack", runtime: "claude", profile: "cc", workspace: "/work",
      token: `token-${i}`, createdAt: i, lastActiveAt: i, ws: i % 4 === 3 ? undefined : `ws-${i % 3}` } as Parameters<Store["insertSession"]>[0]);
  }
  db.exec("UPDATE sessions SET archived_at = 5 WHERE rowid % 7 = 0");
  db.exec("DELETE FROM sessions WHERE rowid % 13 = 0");
  installSessionListIndex(db);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  const has = store.db.prepare("SELECT 1 FROM sqlite_master WHERE name='search_job_session_audit'").get() !== undefined;
  return [
    all("SELECT hex(session) AS session, kind, ws, archived, connect FROM session_list_rows ORDER BY session, kind, ws, archived, connect"),
    all("SELECT id, version, last_rowid, end_rowid, complete FROM session_list_meta"),
    has ? all("SELECT id, version, last_rowid, end_rowid, complete FROM search_job_session_audit") : "no audit",
  ].join("\n");
}

test("the MoonBit builder copies the old sessions, then visits them for search, as the TypeScript steps do", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "session-list", "--db", mb.path]);
  try {
    const steps: { scope: string; ts: boolean; mb: boolean }[] = [];
    for (const scope of ["all", "search"]) {
      for (let i = 0; i < 20; i++) {
        const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ scope });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        const list = sessionListStep(ts.store.db);
        steps.push({ scope, ts: list.done && (scope === "all" || auditSessionListStep(ts.store.db).done), mb: ours.done });
        if (ours.done) break;
      }
      // (the list done before the audit begins: the tables agree at the turn as well)
      assert.equal(tables(mb.store), tables(ts.store));
    }
    assert.ok(steps.length >= 6, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(sessionListReady(mb.store.db), true);
    assert.ok((mb.store.db.prepare("SELECT count(*) AS n FROM session_list_rows WHERE instr(session, char(0)) > 0").get() as { n: number }).n > 5);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station's session list builder finishes the list and its search audit", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const builder = new SessionListBuilder(f.path, {});
  try {
    await builder.readySearch();
    assert.equal(sessionListReady(f.store.db), true);
    assert.equal((f.store.db.prepare("SELECT complete FROM search_job_session_audit").get() as { complete: number }).complete, 1);
  } finally {
    await builder.close();
    f.close();
  }
});
