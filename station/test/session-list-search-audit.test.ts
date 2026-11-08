import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { SESSION_LIST_FIRST, SESSION_LIST_NEXT, SESSION_LIST_SEE_POSITION, auditSessionListStep } from "../src/store/session-list-index.ts";
import { Store } from "../src/store/store.ts";

const missing = `SELECT key, CASE WHEN ws IS NULL THEN 0 ELSE 1 END, COALESCE(ws, ''),
  archived_at IS NOT NULL, connect FROM sessions
  EXCEPT SELECT session, kind, ws, archived, connect FROM session_list_rows`;
const extra = `SELECT session, kind, ws, archived, connect FROM session_list_rows
  EXCEPT SELECT key, CASE WHEN ws IS NULL THEN 0 ELSE 1 END, COALESCE(ws, ''),
    archived_at IS NOT NULL, connect FROM sessions`;

test("old session candidates are audited in bounded batches while another connection writes", () => {
  const data = mkdtempSync(join(tmpdir(), "session-list-audit-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const other = new DatabaseSync(join(data, "stillfail.db"));
  const db = writer.db;
  try {
    for (const key of ["a", "b\0suffix", "c"]) writer.insertSession({ key, connect: "ember", runtime: "claude",
      profile: "cc", workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
    db.exec("DELETE FROM session_list_rows");
    assert.deepEqual(auditSessionListStep(db, 1), { done: false, visited: 1 });
    // Both moves are maintained by the installed triggers, including the row that moves behind the cursor.
    other.exec("UPDATE sessions SET rowid=1000, ws='away' WHERE key='a'");
    other.prepare("UPDATE sessions SET rowid=-10, ws='elsewhere' WHERE key=?").run("b\0suffix");
    let batches = 0;
    while (!auditSessionListStep(db, 1).done) assert.ok(++batches < 10);
    assert.deepEqual(db.prepare(missing).all(), []);
    assert.deepEqual(db.prepare(extra).all(), []);
    assert.ok(db.prepare("SELECT 1 FROM session_list_rows WHERE session=? AND ws='elsewhere'").get("b\0suffix"));
  } finally { other.close(); writer.close(); rmSync(data, { recursive: true, force: true }); }
});

test("a failed session audit batch rolls its cursor and repaired candidates back", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    for (const key of ["a", "b", "c"]) writer.insertSession({ key, connect: "ember", runtime: "claude",
      profile: "cc", workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
    db.exec("DELETE FROM session_list_rows");
    assert.deepEqual(auditSessionListStep(db, 1), { done: false, visited: 1 });
    const position = db.prepare("SELECT CAST(last_rowid AS TEXT) AS n FROM search_job_session_audit WHERE id=1").get()!.n;
    db.exec("CREATE TRIGGER fail_search_session_audit BEFORE INSERT ON session_list_rows WHEN NEW.session='c' BEGIN SELECT RAISE(ABORT, 'audit failed'); END");
    assert.throws(() => auditSessionListStep(db, 10), /audit failed/);
    assert.equal(db.prepare("SELECT CAST(last_rowid AS TEXT) AS n FROM search_job_session_audit WHERE id=1").get()!.n, position);
    assert.equal(db.prepare("SELECT 1 FROM session_list_rows WHERE session='b'").get(), undefined);
    db.exec("DROP TRIGGER fail_search_session_audit");
    assert.deepEqual(auditSessionListStep(db, 10), { done: true, visited: 2 });
    assert.deepEqual(db.prepare(missing).all(), []);
  } finally { writer.close(); }
});

test("a file-backed audit resumes exactly across large rowids", () => {
  const data = mkdtempSync(join(tmpdir(), "session-list-audit-restart-"));
  let writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  try {
    for (const key of ["low", "high"]) writer.insertSession({ key, connect: "ember", runtime: "claude",
      profile: "cc", workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
    writer.db.exec(`UPDATE sessions SET rowid=CAST('-9007199254740993' AS INTEGER) WHERE key='low';
      UPDATE sessions SET rowid=CAST('9007199254740993' AS INTEGER) WHERE key='high'; DELETE FROM session_list_rows`);
    assert.deepEqual(auditSessionListStep(writer.db, 1), { done: false, visited: 1 });
    writer.close();
    writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
    assert.deepEqual(auditSessionListStep(writer.db, 1), { done: false, visited: 1 });
    assert.deepEqual(auditSessionListStep(writer.db, 1), { done: true, visited: 0 });
    assert.deepEqual(writer.db.prepare(missing).all(), []);
  } finally { writer.close(); rmSync(data, { recursive: true, force: true }); }
});

test("each session audit batch seeks its rowid bounds and candidate", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    for (const [sql, args] of [
      [SESSION_LIST_FIRST, ["100", 32]], [SESSION_LIST_NEXT, ["10", "100", 32]],
      [SESSION_LIST_SEE_POSITION, ["10"]],
    ] as const) {
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[])
        .map((row) => row.detail).join("\n");
      assert.match(plan, /SEARCH sessions USING INTEGER PRIMARY KEY/);
      assert.doesNotMatch(plan, /SCAN sessions|SCAN s\b|USE TEMP B-TREE/);
    }
  } finally { writer.close(); }
});
