import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PLAIN } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { backfillUseIndex, initializeUseIndex, PLAIN_USES, USE_BACKFILL_AFTER, UseIndex, VAULT_USES } from "../src/vault/use-index.ts";

/// Count the JSON fields SQLite actually reads, including those it must examine and then discard. The function has the
/// same results as json_extract for these request fields, and is deterministic so SQLite can use expression indexes.
function fixture(db = new DatabaseSync(":memory:")) {
  let examined = 0;
  const permission = { members: ["alice"], locked: true };
  db.function("json_extract", { deterministic: true }, (body, path) => {
    examined++;
    const value = JSON.parse(String(body))[String(path).slice(2)];
    if (value === undefined || value === null) return null;
    if (typeof value === "boolean") return Number(value);
    return typeof value === "object" ? JSON.stringify(value) : value;
  });
  const service = new Secrets({
    db, data: ".", now: () => 0, home: () => "w", lock: () => (permission.locked ? {} as never : null),
    proxy: {} as never, vaults: { vault: () => ({ members: permission.members }) } as never, plain: {} as never,
    hub: { store: { subscribe() {}, getSession() { return null; } } } as never,
  });
  const insert = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES (?, ?, 's', ?, ?)");
  const put = (id: string, at: number, owner: string, vault = PLAIN, status = "granted", ws = "w", save?: object) => {
    insert.run(ws, id, status, JSON.stringify({ vault, owner, at, item: id, session: "s", mode: "env", status, ...(save ? { save } : {}) }));
  };
  const read = async (vault: string, limit = 1) => {
    examined = 0;
    const rows = await service.uses("w", vault === PLAIN ? null : {} as never, vault, { sub: "alice", email: "Alice@x.com" }, limit);
    return { rows, examined };
  };
  return { db, service, put, read, permission };
}

test("a plain library's limit is applied to its owner's uses, not to everyone else's", async () => {
  const f = fixture();
  try {
    f.put("mine", 1, "alice@x.com");
    f.put("theirs", 2, "bob@x.com");
    assert.deepEqual((await f.read(PLAIN)).rows.map((r) => r.item), ["mine"]);
    assert.deepEqual((await f.service.uses("w", null, PLAIN, { sub: "bob", email: "bob@x.com" }, 1)).map((r) => r.item), ["theirs"]);
  } finally {
    f.db.close();
  }
});

test("a page of uses does not inspect other people's or other vaults' growing history", async () => {
  const f = fixture();
  try {
    f.put("mine", 1, "alice@x.com");
    f.put("shared", 1, "", "v");
    const beforePlain = await f.read(PLAIN);
    const beforeShared = await f.read("v");
    for (let i = 0; i < 2_000; i++) {
      f.put(`other-${i}`, i + 2, "bob@x.com");
      f.put(`vault-${i}`, i + 2, "", "other-vault");
      f.put(`save-${i}`, i + 2, "alice@x.com", PLAIN, "granted", "w", { typed: true });
      f.put(`older-${i}`, -i, "alice@x.com");
    }
    const afterPlain = await f.read(PLAIN);
    const afterShared = await f.read("v");
    assert.equal(afterPlain.examined, beforePlain.examined, "other owners and saves add no JSON examinations");
    assert.equal(afterShared.examined, beforeShared.examined, "other vaults add no JSON examinations");
    assert.deepEqual(afterPlain.rows, beforePlain.rows);
    assert.deepEqual(afterShared.rows, beforeShared.rows);

    // The actual statements must seek to the permitted vault/owner and read in page order; a covering index that
    // still walks all owners, or a temporary sort before LIMIT, would evade the JSON-examination count above.
    const plainPlan = (f.db.prepare(`EXPLAIN QUERY PLAN ${PLAIN_USES}`).all("w", PLAIN, "alice@x.com", 1) as { detail: string }[]).map((r) => r.detail).join(" | ");
    const sharedPlan = (f.db.prepare(`EXPLAIN QUERY PLAN ${VAULT_USES}`).all("w", "v", 1) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plainPlan, /SEARCH u USING COVERING INDEX vault_use_lookup_owner \(ws=\? AND vault=\? AND owner=\?\)/);
    assert.match(sharedPlan, /SEARCH u USING COVERING INDEX vault_use_lookup_vault \(ws=\? AND vault=\?\)/);
    assert.match(plainPlan, /SEARCH r USING INDEX sqlite_autoindex_vault_requests_1 \(ws=\? AND id=\?\)/);
    assert.doesNotMatch(`${plainPlan} ${sharedPlan}`, /TEMP B-TREE/);
  } finally {
    f.db.close();
  }
});

test("a changed request moves in and out of the indexed page", async () => {
  const f = fixture();
  try {
    f.put("a", 1, "alice@x.com");
    f.put("b", 2, "alice@x.com", PLAIN, "pending");
    assert.deepEqual((await f.read(PLAIN)).rows.map((r) => r.item), ["a"]);
    const body = JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: 2, item: "b", session: "s", mode: "env", status: "denied" });
    f.db.prepare("UPDATE vault_requests SET status = 'denied', body = ? WHERE id = 'b'").run(body);
    assert.deepEqual((await f.read(PLAIN)).rows.map((r) => [r.item, r.denied]), [["b", true]]);
    f.db.prepare("DELETE FROM vault_requests WHERE id = 'b'").run();
    assert.deepEqual((await f.read(PLAIN)).rows.map((r) => r.item), ["a"]);
  } finally {
    f.db.close();
  }
});

test("old requests are indexed in bounded resumable batches while new writes keep the index current", async () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
    body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
  const insert = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES ('w', ?, 's', 'granted', ?)");
  for (let i = 0; i < 40; i++) {
    const id = `old-${String(i).padStart(2, "0")}`;
    insert.run(id, JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: i, item: id, session: "s", mode: "env", status: "granted" }));
  }
  const f = fixture(db);
  try {
    assert.equal(backfillUseIndex(db, 7), false);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_use_lookup").get() as { n: number }).n, 7);
    const state = db.prepare("SELECT after_ws, after_id, done FROM vault_use_backfill").get() as { after_ws: string; after_id: string; done: number };
    assert.deepEqual([state.after_ws, state.after_id, state.done], ["w", "old-06", 0]);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${USE_BACKFILL_AFTER}`).all(state.after_ws, state.after_id, 7) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH vault_requests USING COVERING INDEX sqlite_autoindex_vault_requests_1/);
    assert.doesNotMatch(plan, /TEMP B-TREE/);
    // Changes behind the cursor and a new earlier key must survive a restart and the remaining backfill.
    db.prepare("DELETE FROM vault_requests WHERE ws = 'w' AND id = 'old-03'").run();
    f.put("aaa-new", 100, "alice@x.com");
    f.put("zzz-new", 101, "bob@x.com");
    const again = new UseIndex(db);
    const bodies = await again.read("w", PLAIN, "alice@x.com", 100);
    const ids = bodies.map((body) => (JSON.parse(body) as { item: string }).item);
    assert.equal(ids.length, 40);
    assert.equal(ids[0], "aaa-new");
    assert.ok(!ids.includes("old-03"));
    assert.ok(!ids.includes("zzz-new"));
    assert.equal((db.prepare("SELECT done FROM vault_use_backfill").get() as { done: number }).done, 1);
  } finally {
    db.close();
  }
});

test("a disk-backed backfill resumes after reopening and is read by its worker", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-use-index-"));
  const path = join(dir, "station.db");
  let db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode = WAL;
    CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
    body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
  const put = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES ('w', ?, 's', 'granted', ?)");
  for (let i = 0; i < 100; i++) {
    const id = `old-${i}`;
    put.run(id, JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: i, item: id }));
  }
  initializeUseIndex(db);
  assert.equal(backfillUseIndex(db, 7), false);
  assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_use_lookup").get() as { n: number }).n, 7);
  db.close();
  db = new DatabaseSync(path);
  const index = new UseIndex(db);
  try {
    const bodies = await index.read("w", PLAIN, "alice@x.com", 2);
    assert.deepEqual(bodies.map((body) => (JSON.parse(body) as { item: string }).item), ["old-99", "old-98"]);
    assert.equal((db.prepare("SELECT done FROM vault_use_backfill").get() as { done: number }).done, 1);
  } finally {
    await index.close();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("membership is checked again if it changes while the old index is being filled", async () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
    body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
  const put = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES ('w', ?, 's', 'granted', ?)");
  for (let i = 0; i < 40; i++) put.run(`id-${i}`, JSON.stringify({ vault: "v", at: i, item: `id-${i}`, session: "s", mode: "env", status: "granted" }));
  const f = fixture(db);
  try {
    const read = f.service.uses("w", {} as never, "v", { sub: "alice", email: "alice@x.com" });
    f.permission.members = [];
    assert.deepEqual(await read, []);
  } finally {
    db.close();
  }
});
