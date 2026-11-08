import assert from "node:assert/strict";
import { on, once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { PLAIN } from "../src/vault/plain.ts";
import { initializeReboxIndex } from "../src/vault/rebox-index.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { backfillNextWorkspace, backfillUseIndex, initializeUseIndex, PLAIN_USES, USE_BACKFILL_AFTER, UseIndex, VAULT_USES } from "../src/vault/use-index.ts";

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
    await f.read(PLAIN); // Fill this workspace before comparing page reads.
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
    f.db.prepare("INSERT OR REPLACE INTO vault_requests (ws, id, session, status, body) VALUES ('w', 'a', 's', 'pending', ?)").run(body);
    assert.deepEqual((await f.read(PLAIN)).rows, [], "replacing a decided request with a pending one removes it");
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
    assert.equal(backfillUseIndex(db, "w", 7), false);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_use_lookup").get() as { n: number }).n, 7);
    const state = db.prepare("SELECT after_id, done FROM vault_use_backfill WHERE ws = 'w'").get() as { after_id: string; done: number };
    assert.deepEqual([state.after_id, state.done], ["old-06", 0]);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${USE_BACKFILL_AFTER}`).all("w", state.after_id, 7) as { detail: string }[]).map((r) => r.detail).join(" | ");
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
    assert.equal((db.prepare("SELECT done FROM vault_use_backfill WHERE ws = 'w'").get() as { done: number }).done, 1);
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
  assert.equal(backfillUseIndex(db, "w", 7), false);
  assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_use_lookup").get() as { n: number }).n, 7);
  db.close();
  db = new DatabaseSync(path);
  const index = new UseIndex(db);
  try {
    const bodies = await index.read("w", PLAIN, "alice@x.com", 2);
    assert.deepEqual(bodies.map((body) => (JSON.parse(body) as { item: string }).item), ["old-99", "old-98"]);
    assert.equal((db.prepare("SELECT done FROM vault_use_backfill WHERE ws = 'w'").get() as { done: number }).done, 1);
  } finally {
    await index.close();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("vault backfill waits for a foreground writer, then serves the indexed page", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-backfill-priority-"));
  const path = join(dir, "station.db");
  const db = new DatabaseSync(path);
  const priority = new Int32Array(new SharedArrayBuffer(8));
  let worker: Worker | null = null;
  try {
    db.exec(`PRAGMA journal_mode = WAL;
      CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
        body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
    const put = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES ('w', ?, 's', 'granted', ?)");
    const body = (id: string, at: number) => JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at, item: id });
    for (let n = 0; n < 100; n++) put.run(`old-${n}`, body(`old-${n}`, n));
    initializeUseIndex(db);
    Atomics.store(priority, 0, 1);
    initializeReboxIndex(db);
    worker = new Worker(new URL("../src/vault/use-index-worker.ts", import.meta.url), { workerData: { path, priority: priority.buffer } });
    const [notice] = await once(worker, "message") as [{ foreground?: boolean }];
    assert.equal(notice.foreground, true);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_use_lookup").get() as { n: number }).n, 0);
    put.run("new", body("new", 200));
    Atomics.store(priority, 0, 0);
    worker.postMessage({ id: 1, ws: "w", vault: PLAIN, owner: "alice@x.com", limit: 2 });
    const [answer] = await once(worker, "message") as [{ bodies: string[] }];
    assert.deepEqual(answer.bodies.map((b) => JSON.parse(b).item), ["new", "old-99"]);
  } finally {
    if (worker !== null) await worker.terminate();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a ready vault page can be read while a foreground write is pending", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-ready-while-writing-"));
  const path = join(dir, "station.db");
  const db = new DatabaseSync(path);
  const priority = new Int32Array(new SharedArrayBuffer(8));
  let worker: Worker | null = null;
  try {
    db.exec(`PRAGMA journal_mode = WAL;
      CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
        body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
    db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES ('w', 'old', 's', 'granted', ?)")
      .run(JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: 1, item: "old" }));
    db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES ('slow', 'old', 's', 'granted', ?)")
      .run(JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: 1, item: "slow" }));
    initializeUseIndex(db);
    assert.equal(backfillUseIndex(db, "w"), true);
    Atomics.store(priority, 0, 1);
    initializeReboxIndex(db);
    worker = new Worker(new URL("../src/vault/use-index-worker.ts", import.meta.url), { workerData: { path, priority: priority.buffer } });
    const messages = on(worker, "message");
    const next = async () => (await messages.next()).value![0] as { id?: number; foreground?: boolean; request?: number; bodies?: string[] };
    const blocked = async (id: number) => {
      for (;;) {
        const message = await next();
        if (message.foreground && message.request === id) return;
        assert.equal(message.id, undefined, "a different request cannot finish yet");
      }
    };
    const busy = await next();
    assert.equal(busy.foreground, true);
    worker.postMessage({ id: 1, ws: "w", vault: PLAIN, owner: "alice@x.com", limit: 2 });
    const answer = await next();
    assert.equal(answer.id, 1, "a completed page does not wait behind a writer");
    assert.deepEqual(answer.bodies!.map((b) => JSON.parse(b).item), ["old"]);

    worker.postMessage({ id: 2, ws: "slow", vault: PLAIN, owner: "alice@x.com", limit: 2 });
    await blocked(2);
    worker.postMessage({ id: 3, ws: "w", vault: PLAIN, owner: "alice@x.com", limit: 2 });
    const ready = async (id: number) => {
      for (;;) {
        const message = await next();
        if (message.foreground) continue;
        assert.equal(message.id, id, "the unfinished page still waits for the foreground writer");
        return message;
      }
    };
    const first = await ready(3);
    assert.deepEqual(first.bodies!.map((b) => JSON.parse(b).item), ["old"]);
    worker.postMessage({ id: 4, ws: "w", vault: PLAIN, owner: "alice@x.com", limit: 2 });
    const second = await ready(4);
    assert.deepEqual(second.bodies!.map((b) => JSON.parse(b).item), ["old"]);
    await messages.return?.();
  } finally {
    if (worker !== null) await worker.terminate();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a vault history waiting for handover is cancelled when the station closes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-handover-close-"));
  const db = new DatabaseSync(join(dir, "station.db"));
  try {
    db.exec(`CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
      body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
    let finish!: () => void;
    const previousGone = new Promise<void>((resolve) => { finish = resolve; });
    const index = new UseIndex(db, { previousGone });
    const pending = index.read("w", PLAIN, "alice@x.com", 2);
    const stopped = assert.rejects(pending, /station stopping/);
    await index.close();
    await stopped;
    finish();
    await Promise.resolve();
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_use_backfill").get() as { n: number }).n, 0);
  } finally {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a workspace's first read does not backfill other workspaces' old requests", async () => {
  async function readWith(unrelated: number) {
    const db = new DatabaseSync(":memory:");
    db.exec(`CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
      body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
    const put = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES (?, ?, 's', 'granted', ?)");
    const body = (item: string) => JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: 1, item, session: "s", mode: "env", status: "granted" });
    put.run("w", "mine", body("mine"));
    for (let i = 0; i < unrelated; i++) put.run("other", `id-${i}`, body(`id-${i}`));
    const f = fixture(db);
    try {
      return await f.read(PLAIN);
    } finally {
      db.close();
    }
  }
  const small = await readWith(0);
  const large = await readWith(1_000);
  assert.deepEqual(large.rows, small.rows);
  assert.equal(large.examined, small.examined, "another workspace adds no JSON examinations to the first read");
});

test("background backfill can finish the other workspaces in bounded batches", () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
    body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
  const put = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES (?, ?, 's', 'granted', ?)");
  const body = JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: 1 });
  put.run("w", "mine", body);
  for (let i = 0; i < 70; i++) put.run("other", `id-${i}`, body);
  initializeUseIndex(db);
  try {
    assert.equal(backfillUseIndex(db, "w"), true);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM vault_use_lookup WHERE ws = 'other'").get() as { n: number }).n, 0);
    let before = 0;
    let complete = false;
    for (let batch = 0; batch < 10 && !complete; batch++) {
      complete = backfillNextWorkspace(db);
      const after = (db.prepare("SELECT COUNT(*) AS n FROM vault_use_lookup WHERE ws = 'other'").get() as { n: number }).n;
      assert.ok(after - before <= 32, "one transaction indexes at most 32 old requests");
      before = after;
    }
    assert.equal(complete, true);
    assert.equal(before, 70);
  } finally {
    db.close();
  }
});

test("an unreadable old request cannot stop another workspace's page", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-use-corrupt-"));
  const db = new DatabaseSync(join(dir, "station.db"));
  db.exec(`PRAGMA journal_mode = WAL;
    CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
    body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
  const put = db.prepare("INSERT INTO vault_requests (ws, id, session, status, body) VALUES (?, ?, 's', 'granted', ?)");
  put.run("bad", "bad", "not JSON");
  put.run("w", "mine", JSON.stringify({ vault: PLAIN, owner: "alice@x.com", at: 1, item: "mine" }));
  const index = new UseIndex(db);
  try {
    await assert.rejects(index.read("bad", PLAIN, "alice@x.com", 1), /malformed JSON/);
    const bodies = await index.read("w", PLAIN, "alice@x.com", 1);
    assert.equal((JSON.parse(bodies[0]!) as { item: string }).item, "mine");
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
