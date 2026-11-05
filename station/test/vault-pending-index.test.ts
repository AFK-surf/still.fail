import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillPendingIndex, initializePendingIndex, pendingIndexComplete, PENDING_BODIES } from "../src/vault/pending-index.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE vault_requests (
    ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL, body TEXT NOT NULL,
    thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id)
  )`);
  const put = (id: string, status: string, body: Record<string, unknown> = {}) => db.prepare("INSERT INTO vault_requests (ws,id,session,status,body) VALUES ('w',?,'s',?,?)")
    .run(id, status, JSON.stringify({ ws: "w", id, status, vault: "plain", owner: "alice", at: 100, ...body }));
  const rows = () => db.prepare("SELECT id, owner, vault, owner_decides, at FROM vault_pending_lookup WHERE ws='w' ORDER BY id").all();
  return { db, put, rows };
}

test("the pending index resumes in bounded batches and follows requests changed on either side of its cursor", () => {
  const { db, put, rows } = fixture();
  try {
    for (let i = 0; i < 6; i++) put(`r${i}`, i % 2 ? "granted" : "pending");
    initializePendingIndex(db);
    assert.equal(backfillPendingIndex(db, "w", 2), false);
    db.prepare("UPDATE vault_requests SET status='denied' WHERE ws='w' AND id='r0'").run();
    db.prepare("UPDATE vault_requests SET status='pending', body=json_set(body,'$.vault','v','$.owner','bob') WHERE ws='w' AND id='r1'").run();
    db.prepare("UPDATE vault_requests SET status='pending' WHERE ws='w' AND id='r5'").run();
    while (!backfillPendingIndex(db, "w", 2)) {}
    assert.equal(pendingIndexComplete(db, "w"), true);
    assert.deepEqual(rows().map((row) => [row.id, row.owner, row.vault, row.owner_decides]), [
      ["r1", "bob", "v", 0], ["r2", "alice", "plain", 1], ["r4", "alice", "plain", 1], ["r5", "alice", "plain", 1],
    ]);
    const bodies = db.prepare(PENDING_BODIES).all("w") as { body: string }[];
    assert.deepEqual(bodies.map((row) => JSON.parse(row.body).id), ["r1", "r2", "r4", "r5"]);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${PENDING_BODIES}`).all("w") as { detail: string }[]).map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH p USING PRIMARY KEY/);
    assert.match(plan, /SEARCH r USING INDEX/);
    db.prepare("DELETE FROM vault_requests WHERE ws='w' AND id='r2'").run();
    assert.deepEqual(rows().map((row) => row.id), ["r1", "r4", "r5"]);
  } finally { db.close(); }
});

test("changing only a waiting request's box does not write its lookup again", () => {
  const { db, put } = fixture();
  try {
    initializePendingIndex(db);
    put("r", "pending");
    const count = () => (db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    const before = count();
    db.prepare("UPDATE vault_requests SET body=json_set(body,'$.box','new') WHERE ws='w' AND id='r'").run();
    assert.equal(count() - before, 1);
    put("old", "denied");
    const afterInsert = count();
    db.prepare("UPDATE vault_requests SET body=json_set(body,'$.box','new') WHERE ws='w' AND id='old'").run();
    assert.equal(count() - afterInsert, 1);
  } finally { db.close(); }
});

test("a failed pending-index batch rolls its cursor and entries back together", () => {
  const { db, put, rows } = fixture();
  try {
    put("r", "pending");
    initializePendingIndex(db);
    db.exec("CREATE TRIGGER fail_pending BEFORE INSERT ON vault_pending_lookup BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    assert.throws(() => backfillPendingIndex(db, "w"), /test failure/);
    assert.equal(pendingIndexComplete(db, "w"), false);
    assert.deepEqual(rows(), []);
    db.exec("DROP TRIGGER fail_pending");
    assert.equal(backfillPendingIndex(db, "w"), true);
    assert.deepEqual(rows().map((row) => row.id), ["r"]);
  } finally { db.close(); }
});

test("only a truthy save or the plain library is decided by its owner", () => {
  const { db, put, rows } = fixture();
  try {
    initializePendingIndex(db);
    const saves: unknown[] = [null, false, 0, "", true, 1, "yes", {}, []];
    for (const [i, save] of saves.entries()) put(String(i), "pending", { vault: "v", save });
    assert.deepEqual(rows().map((row) => row.owner_decides), saves.map((save) => save ? 1 : 0));
  } finally { db.close(); }
});
