import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";
import { initializeUseIndex } from "../src/vault/use-index.ts";
import { UnaccountedSchema, installSchema } from "../src/vault/schema-install.ts";
import { withoutUseReader } from "./vault-no-reader.ts";

// A new station process makes its vault on the database the one serving writes to (a handover). Its connections here
// wait for no one (SQLite's default busy timeout, 0): what the new one does must not need the write the old one holds.

const common = (dir: string) => ({ proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
  hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never });

function vault(db: DatabaseSync, dir: string) {
  return new Secrets({ ...common(dir), db: withoutUseReader(db), plain: new PlainStore(db), vaults: new VaultStore(db) });
}

function serving() {
  const dir = mkdtempSync(join(tmpdir(), "vault-schema-handover-")), path = join(dir, "stillfail.db");
  const old = new DatabaseSync(path);
  old.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  vault(old, dir);
  return { dir, path, old };
}

test("a new process makes its vault while the one serving holds the write: nothing of it waits for that write", () => {
  const { dir, path, old } = serving();
  // (the one serving in the middle of a write: before, the new one's use index read its schema in a deferred
  // transaction and then wrote, refused at once, "database is locked", and the station stopped by itself)
  old.exec("BEGIN IMMEDIATE");
  old.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES('w','g','s','{}')").run();
  const next = new DatabaseSync(path);
  try {
    assert.doesNotThrow(() => vault(next, dir));
    assert.equal(next.isTransaction, false, "no transaction left open");
    old.exec("COMMIT");
    assert.equal((next.prepare("SELECT count(*) AS n FROM vault_grants").get() as { n: number }).n, 1, "the old one's write went in");
  } finally { next.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("what a vault index lacks is put in with the write taken first, all of it at once", () => {
  const { dir, path, old } = serving();
  // (a station of before: a trigger and a backfill's first row not there yet)
  old.exec("DROP TRIGGER vault_use_lookup_add; DELETE FROM vault_use_backfill_all; DELETE FROM vault_rebox_backfill");
  // While another holds the write it is not begun at all (here, waiting for no one, refused at its start)...
  old.exec("BEGIN IMMEDIATE");
  const next = new DatabaseSync(path);
  try {
    assert.throws(() => vault(next, dir), /database is locked/);
    assert.equal(next.isTransaction, false, "refused before it began");
    assert.equal(next.prepare("SELECT 1 FROM sqlite_master WHERE name = 'vault_use_lookup_add'").get(), undefined);
    // ...and taken once it is free.
    old.exec("COMMIT");
    vault(next, dir);
    assert.equal(next.isTransaction, false);
    assert.ok(next.prepare("SELECT 1 FROM sqlite_master WHERE name = 'vault_use_lookup_add'").get(), "the trigger made");
    assert.ok(next.prepare("SELECT 1 FROM vault_use_backfill_all WHERE id = 1").get(), "the use index's backfill begun again");
    assert.ok(next.prepare("SELECT 1 FROM vault_rebox_backfill WHERE id = 1").get(), "the rebox index's too");
  } finally { next.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("inside a transaction of its caller's, a vault index's schema goes in that transaction", () => {
  const { dir, old } = serving();
  try {
    old.exec("DROP TRIGGER vault_use_lookup_add; BEGIN IMMEDIATE");
    initializeUseIndex(old);
    assert.ok(old.prepare("SELECT 1 FROM sqlite_master WHERE name = 'vault_use_lookup_add'").get());
    assert.equal(old.isTransaction, true, "the caller's transaction is still its own");
    old.exec("ROLLBACK");
    assert.equal(old.prepare("SELECT 1 FROM sqlite_master WHERE name = 'vault_use_lookup_add'").get(), undefined, "rolled back with it");
  } finally { old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a vault schema with a statement installSchema cannot tell is done is refused at once, saying which", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const base = `CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY) WITHOUT ROWID;
      -- a comment; with a semicolon
      CREATE TRIGGER IF NOT EXISTS t_add AFTER INSERT ON t BEGIN DELETE FROM t WHERE id < 0; END;
      INSERT OR IGNORE INTO t (id) VALUES (1);`;
    installSchema(db, "fine", base, ["SELECT 1 FROM t WHERE id = 1"]);
    for (const [what, extra, rows] of [
      ["a trigger from before dropped", "DROP TRIGGER IF EXISTS t_old;", ["SELECT 1 FROM t WHERE id = 1"]],
      ["a column added", "ALTER TABLE t ADD COLUMN x TEXT;", ["SELECT 1 FROM t WHERE id = 1"]],
      ["a row changed", "UPDATE t SET id = 2 WHERE id = 1;", ["SELECT 1 FROM t WHERE id = 1"]],
      ["a trigger made without IF NOT EXISTS", "CREATE TRIGGER t_new AFTER DELETE ON t BEGIN SELECT 1; END;", ["SELECT 1 FROM t WHERE id = 1"]],
      ["an insert no row query looks for", "", []],
    ] as const) {
      assert.throws(() => installSchema(db, "bad", `${base}\n${extra}`, [...rows]), UnaccountedSchema, what);
    }
    assert.equal(db.isTransaction, false, "refused before anything began");
  } finally { db.close(); }
});
