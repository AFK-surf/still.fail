import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillReboxIndex, initializeReboxIndex, reboxIndexComplete, REBOX_READY } from "../src/vault/rebox-index.ts";
import { UseIndex } from "../src/vault/use-index.ts";

function fixture(db = new DatabaseSync(":memory:")) {
  db.exec(`CREATE TABLE vault_requests (
    ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL, body TEXT NOT NULL,
    thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id)
  )`);
  const insert = db.prepare("INSERT INTO vault_requests (ws,id,session,status,body) VALUES (?,?,'s',?,'{}')");
  const put = (ws: string, id: string, status: string) => insert.run(ws, id, status);
  const ready = () => (db.prepare(REBOX_READY).all() as { ws: string; id: string }[]).map(({ ws, id }) => [ws, id]);
  return { db, put, ready };
}

test("old requests are indexed in bounded resumable batches while writes on both sides remain current", () => {
  const { db, put, ready } = fixture();
  try {
    for (let i = 0; i < 6; i++) put("w", `r${i}`, i % 2 ? "granted" : "pending");
    initializeReboxIndex(db);
    assert.equal(reboxIndexComplete(db), false);
    assert.equal(backfillReboxIndex(db, 2), false);
    db.prepare("UPDATE vault_requests SET status='denied' WHERE ws='w' AND id='r0'").run();
    db.prepare("UPDATE vault_requests SET status='pending' WHERE ws='w' AND id='r1'").run();
    db.prepare("UPDATE vault_requests SET ws='a', id='moved' WHERE ws='w' AND id='r4'").run();
    db.prepare("DELETE FROM vault_requests WHERE ws='w' AND id='r2'").run();
    put("z", "new", "pending");
    initializeReboxIndex(db); // Restarting schema preparation must preserve its cursor and entries.
    while (!backfillReboxIndex(db, 2)) {}
    assert.equal(reboxIndexComplete(db), true);
    assert.deepEqual(ready(), [["w", "r1"], ["a", "moved"], ["z", "new"]]);
  } finally { db.close(); }
});

test("a failed recovery-index batch rolls its cursor and entries back together", () => {
  const { db, put, ready } = fixture();
  try {
    put("w", "r1", "pending");
    put("w", "r2", "pending");
    initializeReboxIndex(db);
    db.exec("CREATE TRIGGER fail_rebox BEFORE INSERT ON vault_rebox_lookup WHEN NEW.id='r2' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    assert.throws(() => backfillReboxIndex(db, 2), /test failure/);
    assert.equal(reboxIndexComplete(db), false);
    assert.deepEqual(ready(), []);
    const state = db.prepare("SELECT after_ws, after_id FROM vault_rebox_backfill WHERE id=1").get() as { after_ws: string | null; after_id: string | null };
    assert.deepEqual([state.after_ws, state.after_id], [null, null]);
    db.exec("DROP TRIGGER fail_rebox");
    while (!backfillReboxIndex(db, 2)) {}
    assert.deepEqual(ready(), [["w", "r1"], ["w", "r2"]]);
  } finally { db.close(); }
});

test("new requests keep the recovery lookup current without rewriting it for a changed box", () => {
  const { db, put, ready } = fixture();
  try {
    initializeReboxIndex(db);
    assert.equal(reboxIndexComplete(db), true);
    put("w", "r", "pending");
    const count = () => (db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const before = count();
    db.prepare("UPDATE vault_requests SET body='new box' WHERE ws='w' AND id='r'").run();
    assert.equal(count() - before, 1);
    assert.deepEqual(ready(), [["w", "r"]]);
    db.prepare("UPDATE vault_requests SET status='granted' WHERE ws='w' AND id='r'").run();
    assert.deepEqual(ready(), []);
    db.prepare("UPDATE vault_requests SET status='pending' WHERE ws='w' AND id='r'").run();
    db.prepare("DELETE FROM vault_requests WHERE ws='w' AND id='r'").run();
    assert.deepEqual(ready(), []);
  } finally { db.close(); }
});

for (const recursive of [0, 1]) test(`replacing a pending request with a decision removes it from recovery with recursive triggers ${recursive}`, () => {
  const { db, put, ready } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive}`);
    initializeReboxIndex(db);
    put("w", "r", "pending");
    db.prepare("INSERT OR REPLACE INTO vault_requests (ws,id,session,status,body) VALUES ('w','r','s','denied','{}')").run();
    assert.deepEqual(ready(), []);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_rebox_lookup").get() as { n: number }).n, 0);
  } finally { db.close(); }
});

test("renumbering and vacuuming requests preserve which boxes are recovered and their order", () => {
  const dir = mkdtempSync(join(tmpdir(), "rebox-vacuum-"));
  const { db, put, ready } = fixture(new DatabaseSync(join(dir, "station.db")));
  try {
    initializeReboxIndex(db);
    put("a", "discard", "pending");
    put("b", "first", "pending");
    put("a", "second", "pending");
    db.prepare("DELETE FROM vault_requests WHERE id='discard'").run();
    const before = db.prepare("SELECT rowid FROM vault_requests WHERE id='first'").get() as { rowid: number };
    // Simulate a rowid change even on SQLite builds that happen to preserve rowids during this VACUUM.
    db.exec("UPDATE vault_requests SET rowid=rowid+100");
    db.exec("VACUUM");
    const after = db.prepare("SELECT rowid FROM vault_requests WHERE id='first'").get() as { rowid: number };
    assert.notEqual(after.rowid, before.rowid);
    assert.deepEqual(ready(), [["b", "first"], ["a", "second"]]);
  } finally { db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a previous connection's prepared writes keep the new recovery lookup current", () => {
  const dir = mkdtempSync(join(tmpdir(), "rebox-previous-writer-"));
  const path = join(dir, "station.db");
  const { db, put, ready } = fixture(new DatabaseSync(path));
  db.exec("PRAGMA journal_mode=WAL");
  const previous = new DatabaseSync(path);
  try {
    put("w", "old", "pending");
    // The earlier process prepared these statements before the new process installed its triggers.
    const add = previous.prepare("INSERT INTO vault_requests (ws,id,session,status,body) VALUES ('w','new','s','pending','{}')");
    const decide = previous.prepare("UPDATE vault_requests SET status='denied' WHERE ws='w' AND id='old'");
    initializeReboxIndex(db);
    add.run();
    decide.run();
    while (!backfillReboxIndex(db, 1)) {}
    assert.deepEqual(ready(), [["w", "new"]]);
  } finally { previous.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the worker prepares recovery after handover and includes the previous process's writes", { timeout: 30_000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "rebox-worker-"));
  const { db, put, ready } = fixture(new DatabaseSync(join(dir, "station.db")));
  let finish!: () => void;
  const previousGone = new Promise<void>((resolve) => { finish = resolve; });
  let index: UseIndex | undefined;
  try {
    db.exec("PRAGMA journal_mode=WAL");
    put("w", "old", "pending");
    for (let i = 0; i < 40; i++) put("w", `history-${i}`, "denied");
    index = new UseIndex(db, { previousGone });
    assert.equal(reboxIndexComplete(db), false);
    put("w", "during-handover", "pending");
    assert.equal(reboxIndexComplete(db), false);
    finish();
    while (!reboxIndexComplete(db)) await new Promise<void>((resolve) => setTimeout(resolve, 5));
    assert.deepEqual(ready(), [["w", "old"], ["w", "during-handover"]]);
  } finally {
    finish();
    await index?.close();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
