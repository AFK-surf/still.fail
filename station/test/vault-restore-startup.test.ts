import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

function expiredGrants(db: DatabaseSync, count: number) {
  db.exec("CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))");
  const insert = db.prepare("INSERT INTO vault_grants VALUES(?,?,?,?)");
  for (let i = 0; i < count; i++) {
    const id = `r${String(i).padStart(3, "0")}`;
    const request = { id, ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
      mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
    const grant = { v: 1, ws: "w", request: id, vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 999, at: 900 };
    insert.run("w", id, "s1", JSON.stringify({ request, grant, uses: 0 }));
  }
}

for (const { failAt, remaining } of [{ failAt: 11, remaining: 70 }, { failAt: 41, remaining: 38 }])
test(`an expired-grant batch failing on deletion ${failAt} rolls back and can be retried`, async () => {
  const db = new DatabaseSync(":memory:"), plain = new PlainStore(db), vaults = new VaultStore(db);
  const priority = new Int32Array(new SharedArrayBuffer(8));
  let foregroundSeen = false, deletes = 0;
  try {
    expiredGrants(db, 70);
    db.function("reject_expiry", () => {
      foregroundSeen = Atomics.load(priority, 0) > 0;
      return ++deletes === failAt ? 1 : 0;
    });
    db.exec(`CREATE TRIGGER reject_expiry BEFORE DELETE ON vault_grants WHEN reject_expiry()
      BEGIN SELECT RAISE(ABORT,'test failure'); END`);
    const deps = { db, plain, vaults, proxy: {} as never, data: ".", now: () => 1_000_000, home: () => "w", lock: () => null,
      hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never,
      backfill: { priority: priority.buffer as SharedArrayBuffer } };
    assert.throws(() => new Secrets(deps), /test failure/);
    assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, remaining);
    assert.equal(foregroundSeen, true);
    assert.equal(Atomics.load(priority, 0), 0);
    db.exec("DROP TRIGGER reject_expiry");
    const secrets = new Secrets(deps);
    try { assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 0); }
    finally { await secrets.close(); }
  } finally { db.close(); }
});

test("expired-grant batches stay inside an enclosing transaction", async () => {
  const db = new DatabaseSync(":memory:"), plain = new PlainStore(db), vaults = new VaultStore(db);
  try {
    expiredGrants(db, 70);
    db.exec("BEGIN");
    const secrets = new Secrets({ db, plain, vaults, proxy: {} as never, data: ".", now: () => 1_000_000, home: () => "w", lock: () => null,
      hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never });
    try {
      assert.equal(db.isTransaction, true);
      assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 0);
      db.exec("ROLLBACK");
      assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 70);
    } finally { await secrets.close(); }
  } finally { db.close(); }
});

test("restoring many expired grants keeps a grant renewed after the startup read", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-many-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), other = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec("PRAGMA journal_mode=WAL");
  expiredGrants(db, 70);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const old = (other.prepare("SELECT body FROM vault_grants WHERE id='r019'").get() as { body: string }).body;
  const renewed = JSON.stringify({ ...JSON.parse(old), until: 2000 });
  let changed = false;
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("DELETE FROM vault_grants")) return statement;
      return new Proxy(statement, { get(stmt, method) {
        const value = Reflect.get(stmt, method, stmt);
        if (method === "run" || method === "all") return (...args: unknown[]) => {
          if (!changed) {
            changed = true;
            other.prepare("UPDATE vault_grants SET body=? WHERE id='r019'").run(renewed);
          }
          return value.apply(stmt, args);
        };
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const prior = Promise.withResolvers<void>();
  const secrets = new Secrets({ db: observed, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    assert.equal(changed, true);
    assert.deepEqual(secrets.held("s1").map((h) => h.request.id), ["r019"]);
    assert.equal((db.prepare("SELECT body FROM vault_grants WHERE id='r019'").get() as { body: string }).body, renewed);
    assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 1);
  } finally {
    prior.resolve();
    await secrets.close();
    secrets.keeper.end("s1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a renewal racing an expired-grant batch is either retained or loses to the deletion", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-expiry-writer-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  const signal = new Int32Array(new SharedArrayBuffer(8)), prior = Promise.withResolvers<void>();
  let secrets: Secrets | undefined, worker: Worker | undefined;
  try {
    db.exec("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000");
    expiredGrants(db, 70);
    plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
      listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
    const old = (db.prepare("SELECT body FROM vault_grants WHERE id='r050'").get() as { body: string }).body;
    const renewed = JSON.stringify({ ...JSON.parse(old), until: 2000 });
    worker = new Worker(`
      const { parentPort, workerData } = require('node:worker_threads');
      const { DatabaseSync } = require('node:sqlite');
      const signal = new Int32Array(workerData.signal), db = new DatabaseSync(workerData.path);
      db.exec('PRAGMA busy_timeout=5000');
      parentPort.postMessage('ready');
      Atomics.wait(signal, 0, 0);
      Atomics.store(signal, 1, 1); Atomics.notify(signal, 1);
      try { parentPort.postMessage({ changed: Number(db.prepare("UPDATE vault_grants SET body=? WHERE id='r050'").run(workerData.renewed).changes) }); }
      catch (error) { parentPort.postMessage({ error: error.message }); }
      finally { db.close(); }
    `, { eval: true, workerData: { path, renewed, signal: signal.buffer } });
    await new Promise<void>((resolve, reject) => { worker!.once("message", () => resolve()); worker!.once("error", reject); });
    const result = new Promise<{ changed?: number; error?: string }>((resolve, reject) => {
      worker!.once("message", resolve); worker!.once("error", reject);
    });
    db.function("start_writer", () => {
      Atomics.store(signal, 0, 1); Atomics.notify(signal, 0);
      if (Atomics.wait(signal, 1, 0, 2000) === "timed-out") throw new Error("the competing writer did not start");
      return 0;
    });
    db.exec("CREATE TRIGGER start_competing_writer BEFORE DELETE ON vault_grants WHEN OLD.id='r010' BEGIN SELECT start_writer(); END");
    secrets = new Secrets({ db, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
      hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
    const outcome = await result;
    assert.equal(outcome.error, undefined);
    const row = db.prepare("SELECT body FROM vault_grants WHERE id='r050'").get() as { body: string } | undefined;
    if (outcome.changed === 1) {
      assert.equal(row?.body, renewed);
      assert.deepEqual(secrets.held("s1").map((h) => h.request.id), ["r050"]);
    } else {
      assert.equal(outcome.changed, 0);
      assert.equal(row, undefined);
    }
  } finally {
    Atomics.store(signal, 0, 1); Atomics.notify(signal, 0);
    await worker?.terminate();
    prior.resolve();
    await secrets?.close();
    secrets?.keeper.end("s1");
    db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a renewed grant from another connection survives stale startup cleanup", () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-race-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 999, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), newer = JSON.stringify({ request, grant: { ...grant, exp: 2000 }, uses: 0 });
  let renewed = false;
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("DELETE FROM vault_grants WHERE ws = ? AND id = ?")) return statement;
      return new Proxy(statement, { get(stmt, key) {
        if (key === "run") return (...args: any[]) => {
          if (!renewed) {
            renewed = true;
            other.prepare("UPDATE vault_grants SET body=? WHERE ws=? AND id=?").run(newer, "w", "r1");
          }
          return stmt.run(...args);
        };
        const value = Reflect.get(stmt, key, stmt);
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const prior = Promise.withResolvers<void>();
  const deps = { db: observed, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } };
  try {
    const first = new Secrets(deps);
    assert.equal(renewed, true);
    assert.equal(db.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1")?.body, newer);
    assert.equal(first.held("s1").length, 1);
    const restored = new Secrets({ ...deps, db });
    assert.equal(restored.held("s1").length, 1);
    first.keeper.drop("r1");
    restored.keeper.drop("r1");
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a repeatedly changed grant is recovered after the previous station exits", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-changed-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 990, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>();
  let changes = 0;
  const observed = new Proxy(db, { get(target, property) {
    if (property === "location") return () => null;
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("DELETE FROM vault_grants WHERE ws = ? AND id = ?")) return statement;
      return new Proxy(statement, { get(stmt, key) {
        if (key === "run") return (...args: any[]) => {
          if (changes < 3) {
            changes++;
            const exp = changes === 3 ? 2000 : 990 + changes;
            other.prepare("UPDATE vault_grants SET body=? WHERE ws=? AND id=?")
              .run(JSON.stringify({ request, grant: { ...grant, exp }, uses: 0 }), "w", "r1");
          }
          return stmt.run(...args);
        };
        const value = Reflect.get(stmt, key, stmt);
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db: observed, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    assert.equal(changes, 3);
    assert.equal(secrets.held("s1").length, 0);
    prior.resolve();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(secrets.held("s1").length, 1);
  } finally {
    prior.resolve();
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a grant removed by another connection while it is restored is not held", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-removed-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>();
  let removed = false;
  const observedPlain = new Proxy(plain, { get(target, property) {
    if (property === "itemSnapshot") return (ws: string, id: string) => {
      const item = target.itemSnapshot(ws, id);
      if (!removed) { removed = true; other.prepare("DELETE FROM vault_grants WHERE ws=? AND id=?").run("w", "r1"); }
      return item;
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db, plain: observedPlain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    assert.equal(removed, true);
    assert.equal(secrets.held("s1").length, 0);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

for (const makeValid of [false, true]) test(`a changed item is checked again during grant restoration (becomes valid: ${makeValid})`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-item-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  const item = { ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token" as const, name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token" as const, modes: (makeValid ? ["proxy"] : ["env"]) as ("env" | "proxy")[], hosts: [] }, at: 1000 };
  plain.put(item);
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), otherPlain = new PlainStore(other), prior = Promise.withResolvers<void>();
  let changed = false;
  const observed = new Proxy(plain, { get(target, property) {
    if (property === "itemSnapshot") return (ws: string, id: string) => {
      const snapshot = target.itemSnapshot(ws, id);
      if (!changed) {
        changed = true;
        if (makeValid) otherPlain.put({ ...item, version: 1, listing: { ...item.listing, modes: ["env"] } });
        else otherPlain.put({ ...item, version: 1, deleted: true });
      }
      return snapshot;
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db, plain: observed, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    assert.equal(changed, true);
    assert.equal(secrets.held("s1").length, makeValid ? 1 : 0);
    const count = db.prepare("SELECT COUNT(*) AS n FROM vault_grants").get() as { n: number };
    assert.equal(count.n, makeValid ? 1 : 0);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

for (const makeValid of [false, true]) test(`a changed owner limit is checked again during grant restoration (becomes valid: ${makeValid})`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-limit-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  assert.equal(plain.setLasts("w", "p@example.com", makeValid ? "once" : "hour", 1), null);
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), otherPlain = new PlainStore(other), prior = Promise.withResolvers<void>();
  let changed = false;
  const observed = new Proxy(plain, { get(target, property) {
    if (property === "lasts") return (ws: string, owner: string) => {
      const limit = target.lasts(ws, owner);
      if (!changed) {
        changed = true;
        assert.equal(otherPlain.setLasts(ws, owner, makeValid ? "hour" : "once", 2), null);
      }
      return limit;
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db, plain: observed, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    assert.equal(changed, true);
    assert.equal(secrets.held("s1").length, makeValid ? 1 : 0);
    const count = db.prepare("SELECT COUNT(*) AS n FROM vault_grants").get() as { n: number };
    assert.equal(count.n, makeValid ? 1 : 0);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a grant removed after restoration cannot be used by the new station", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-revoked-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>();
  const secrets = new Secrets({ db, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    assert.equal(secrets.held("s1").length, 1);
    other.prepare("DELETE FROM vault_grants WHERE ws=? AND id=?").run("w", "r1");
    await assert.rejects(secrets.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }));
    assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 0);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("two stations can use the same reusable grant without losing its use count", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restored-uses-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), otherPlain = new PlainStore(other), otherVaults = new VaultStore(other);
  const prior = Promise.withResolvers<void>();
  const common = { proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } };
  const first = new Secrets({ ...common, db, plain, vaults });
  const second = new Secrets({ ...common, db: other, plain: otherPlain, vaults: otherVaults });
  try {
    await Promise.all([
      first.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }),
      second.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }),
    ]);
    const row = db.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1") as { body: string };
    assert.equal((JSON.parse(row.body) as { uses: number }).uses, 2);
  } finally {
    await first.close(); await second.close();
    first.keeper.drop("r1"); second.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a concurrent removal during idle renewal does not recreate the grant", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-renew-removed-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour",
    exp: 2000, at: 900, timeout: { kind: "idle", seconds: 1000 } };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>();
  let removed = false;
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("UPDATE vault_grants SET body = ? WHERE ws = ? AND id = ? AND body = ?")) return statement;
      return new Proxy(statement, { get(stmt, key) {
        if (key === "run") return (...args: any[]) => {
          if (!removed) { removed = true; other.prepare("DELETE FROM vault_grants WHERE ws=? AND id=?").run("w", "r1"); }
          return stmt.run(...args);
        };
        const value = Reflect.get(stmt, key, stmt);
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db: observed, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    secrets.keeper.renew("s1", "r1");
    assert.equal(removed, true);
    assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 0);
    await assert.rejects(secrets.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }));
    assert.equal(db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 0);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a removed browser grant is not listed or put back into the browser", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-browser-removed-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "browser", name: "test", fields: { cookies: "test-only" }, notes: "",
    listing: { name: "test", kind: "browser", modes: ["browser"], hosts: ["example.com"] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "browser", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "browser", hosts: ["example.com"], scope: "hour", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>(), calls: string[] = [];
  const secrets = new Secrets({ db, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise },
    browsers: { signIn: async () => { calls.push("sign-in"); }, passkeysIn: async () => { calls.push("passkeys"); } } as never });
  try {
    other.prepare("DELETE FROM vault_grants WHERE ws=? AND id=?").run("w", "r1");
    secrets.signInAgain("s1");
    secrets.passkeysAgain("s1");
    assert.deepEqual(calls, []);
    assert.equal(secrets.held("s1").length, 0);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a grant renewed just before expiry cleanup stays usable", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-expire-renewed-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour",
    exp: 2000, at: 900, timeout: { kind: "idle", seconds: 1000 } };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0, until: 1001 }));
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>();
  let now = 1_000_000, renewed = false;
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("DELETE FROM vault_grants WHERE ws = ? AND id = ?")) return statement;
      return new Proxy(statement, { get(stmt, key) {
        if (key === "run") return (...args: any[]) => {
          if (!renewed) {
            renewed = true;
            other.prepare("UPDATE vault_grants SET body=? WHERE ws=? AND id=?")
              .run(JSON.stringify({ request, grant, uses: 0, until: 2000 }), "w", "r1");
          }
          return stmt.run(...args);
        };
        const value = Reflect.get(stmt, key, stmt);
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db: observed, plain, vaults, proxy: {} as never, data: dir, now: () => now, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    now = 1_002_000;
    const held = secrets.keeper.usable("s1", "r1");
    assert.equal(renewed, true);
    assert.equal(typeof held, "object");
    if (typeof held !== "string") assert.equal(held.until, 2000);
    const row = db.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1") as { body: string } | undefined;
    assert.equal(row === undefined ? null : (JSON.parse(row.body) as { until: number }).until, 2000);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a reusable grant remains available after repeated competing uses", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-repeated-use-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>();
  let competingUses = 0;
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("UPDATE vault_grants SET body = ? WHERE ws = ? AND id = ? AND body = ?")) return statement;
      return new Proxy(statement, { get(stmt, key) {
        if (key === "run") return (...args: any[]) => {
          if (competingUses < 3) {
            competingUses++;
            other.prepare("UPDATE vault_grants SET body=? WHERE ws=? AND id=?")
              .run(JSON.stringify({ request, grant, uses: competingUses }), "w", "r1");
          }
          return stmt.run(...args);
        };
        const value = Reflect.get(stmt, key, stmt);
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db: observed, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    assert.equal(secrets.keeper.spend("r1"), false);
    assert.equal(competingUses, 3);
    assert.notEqual(typeof secrets.keeper.usable("s1", "r1"), "string");
    assert.equal(secrets.keeper.spend("r1"), true);
    const row = db.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1") as { body: string };
    assert.equal((JSON.parse(row.body) as { uses: number }).uses, 4);
  } finally {
    await secrets.close();
    secrets.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("expiry cleanup does not delete a replacement grant", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-expire-replaced-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "hour", exp: 1001, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const replacement = JSON.stringify({ request, grant: { ...grant, exp: 2000, at: 1000 }, uses: 0 });
  const other = new DatabaseSync(path), prior = Promise.withResolvers<void>();
  let now = 1_000_000, replaced = false;
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("DELETE FROM vault_grants WHERE ws = ? AND id = ?")) return statement;
      return new Proxy(statement, { get(stmt, key) {
        if (key === "run") return (...args: any[]) => {
          if (!replaced) {
            replaced = true;
            other.prepare("UPDATE vault_grants SET body=? WHERE ws=? AND id=?").run(replacement, "w", "r1");
          }
          return stmt.run(...args);
        };
        const value = Reflect.get(stmt, key, stmt);
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const deps = { db: observed, plain, vaults, proxy: {} as never, data: dir, now: () => now, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } };
  const old = new Secrets(deps);
  let next: Secrets | undefined;
  try {
    now = 1_002_000;
    assert.equal(typeof old.keeper.usable("s1", "r1"), "string");
    assert.equal(replaced, true);
    assert.equal(db.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1")?.body, replacement);
    next = new Secrets({ ...deps, db });
    assert.notEqual(typeof next.keeper.usable("s1", "r1"), "string");
  } finally {
    await old.close(); await next?.close();
    old.keeper.drop("r1"); next?.keeper.drop("r1");
    other.close(); db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("closing secrets cancels a history read waiting for handover", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-close-history-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  const prior = Promise.withResolvers<void>();
  const secrets = new Secrets({ db, plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise } });
  try {
    const reading = secrets.uses("w", null, "plain", { sub: "p", email: "p@example.com" })
      .then(() => "completed", (error: Error) => error.message);
    await secrets.close();
    const result = await Promise.race([reading, new Promise<string>((resolve) => setTimeout(() => resolve("still waiting"), 50))]);
    assert.match(result, /station stopping/);
  } finally {
    db.close(); rmSync(dir, { recursive: true, force: true });
  }
});
