import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";
import { withoutUseReader } from "./vault-no-reader.ts";

// These tests hold the actual SQLite file open on two connections; no use-history worker is needed (withoutUseReader).

test("a one-use grant spent during handover stays spent on the new station", () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-restore-spend-")), path = join(dir, "stillfail.db");
  const oldDb = new DatabaseSync(path), oldPlain = new PlainStore(oldDb), oldVaults = new VaultStore(oldDb);
  oldDb.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  oldPlain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "once", exp: 2000, at: 900 };
  oldDb.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const newDb = new DatabaseSync(path), newPlain = new PlainStore(newDb), newVaults = new VaultStore(newDb);
  const common = { proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never };
  const old = new Secrets({ ...common, db: withoutUseReader(oldDb), plain: oldPlain, vaults: oldVaults });
  const next = new Secrets({ ...common, db: withoutUseReader(newDb), plain: newPlain, vaults: newVaults });
  try {
    assert.equal(typeof old.keeper.usable("s1", "r1"), "object");
    assert.equal(typeof next.keeper.usable("s1", "r1"), "object");
    old.keeper.spend("r1");
    next.carry(old.carried());
    const after = next.keeper.usable("s1", "r1");
    assert.equal(typeof after, "string");
    if (typeof after === "string") assert.match(after, /one use/);
  } finally { old.keeper.drop("r1"); next.keeper.drop("r1"); newDb.close(); oldDb.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("two stations cannot both run a one-use plain grant during handover", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-once-run-")), path = join(dir, "stillfail.db");
  const oldDb = new DatabaseSync(path), oldPlain = new PlainStore(oldDb), oldVaults = new VaultStore(oldDb);
  oldDb.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  oldPlain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "once", exp: 2000, at: 900 };
  oldDb.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const newDb = new DatabaseSync(path), newPlain = new PlainStore(newDb), newVaults = new VaultStore(newDb);
  const common = { proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never };
  const old = new Secrets({ ...common, db: withoutUseReader(oldDb), plain: oldPlain, vaults: oldVaults });
  const next = new Secrets({ ...common, db: withoutUseReader(newDb), plain: newPlain, vaults: newVaults });
  try {
    const answers = await Promise.allSettled([
      old.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }),
      next.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }),
    ]);
    assert.equal(answers.filter((answer) => answer.status === "fulfilled").length, 1);
    assert.equal(answers.filter((answer) => answer.status === "rejected").length, 1);
  } finally { old.keeper.drop("r1"); next.keeper.drop("r1"); newDb.close(); oldDb.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const oldUsed of [false, true]) test(`a restored one-use grant waits for a previous station without the claim protocol (old used: ${oldUsed})`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-once-old-")), path = join(dir, "stillfail.db");
  const oldDb = new DatabaseSync(path), oldPlain = new PlainStore(oldDb), oldVaults = new VaultStore(oldDb);
  oldDb.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  oldPlain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "once", exp: 2000, at: 900 };
  oldDb.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const newDb = new DatabaseSync(path), newPlain = new PlainStore(newDb), newVaults = new VaultStore(newDb);
  const prior = Promise.withResolvers<void>();
  const common = { proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never };
  const old = new Secrets({ ...common, db: withoutUseReader(oldDb), plain: oldPlain, vaults: oldVaults });
  const next = new Secrets({ ...common, db: withoutUseReader(newDb), plain: newPlain, vaults: newVaults, backfill: { previousGone: prior.promise } });
  // Before the new claim protocol the old station incremented its in-memory count and unconditionally saved it.
  old.keeper.spend = (id) => {
    const held = old.keeper.usable("s1", id);
    if (typeof held === "string") return false;
    held.uses++;
    oldDb.prepare("UPDATE vault_grants SET body=? WHERE ws=? AND id=?").run(JSON.stringify({ request, grant, uses: held.uses }), "w", id);
    return true;
  };
  const nextRun = next.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" })
    .then(() => "ran", () => "refused");
  try {
    await Promise.resolve();
    const row = newDb.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1") as { body: string };
    assert.equal((JSON.parse(row.body) as { uses: number }).uses, 0);
    if (oldUsed) await old.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" });
    prior.resolve();
    assert.equal(await nextRun, oldUsed ? "refused" : "ran");
  } finally {
    prior.resolve();
    await nextRun;
    old.keeper.drop("r1"); next.keeper.drop("r1");
    newDb.close(); oldDb.close(); rmSync(dir, { recursive: true, force: true });
  }
});

for (const oldUsed of [false, true]) test(`a restored one-use browser grant waits for handover (old used: ${oldUsed})`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-once-browser-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "browser", name: "test", fields: { cookies: "test-only" }, notes: "",
    listing: { name: "test", kind: "browser", modes: ["browser"], hosts: ["example.com"] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "browser", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "browser", hosts: ["example.com"], scope: "once", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const prior = Promise.withResolvers<void>(), calls: string[] = [];
  const next = new Secrets({ db: withoutUseReader(db), plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never, backfill: { previousGone: prior.promise },
    browsers: { signIn: async () => { calls.push("sign-in"); }, passkeysIn: async () => { calls.push("passkeys"); } } as never });
  try {
    next.signInAgain("s1");
    next.passkeysAgain("s1");
    assert.deepEqual(calls, []);
    if (oldUsed) db.prepare("UPDATE vault_grants SET body=? WHERE ws=? AND id=?").run(JSON.stringify({ request, grant, uses: 1 }), "w", "r1");
    prior.resolve();
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(calls, oldUsed ? [] : ["sign-in"]);
    const row = db.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1") as { body: string };
    assert.equal((JSON.parse(row.body) as { uses: number }).uses, 1);
  } finally {
    prior.resolve();
    next.keeper.drop("r1");
    db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a one-use claim detects another connection claiming between its read and write", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-once-between-")), path = join(dir, "stillfail.db");
  const firstDb = new DatabaseSync(path), plain = new PlainStore(firstDb), vaults = new VaultStore(firstDb);
  firstDb.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "once", exp: 2000, at: 900 };
  firstDb.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const secondDb = new DatabaseSync(path), secondPlain = new PlainStore(secondDb), secondVaults = new VaultStore(secondDb);
  const common = { proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never };
  const first = new Secrets({ ...common, db: withoutUseReader(firstDb), plain, vaults });
  let interleaved = false;
  const observed = new Proxy(withoutUseReader(secondDb), { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.startsWith("UPDATE vault_grants SET body = ? WHERE ws = ? AND id = ? AND body = ?")) return statement;
      return new Proxy(statement, { get(stmt, property) {
        if (property === "run") return (...args: any[]) => {
          if (!interleaved) { interleaved = true; assert.equal(first.keeper.spend("r1"), true); }
          return stmt.run(...args);
        };
        const value = Reflect.get(stmt, property, stmt);
        return typeof value === "function" ? value.bind(stmt) : value;
      } });
    };
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const second = new Secrets({ ...common, db: observed, plain: secondPlain, vaults: secondVaults });
  try {
    await assert.rejects(second.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }), /already used or changed/);
    assert.equal(interleaved, true);
    const row = firstDb.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1") as { body: string };
    assert.equal((JSON.parse(row.body) as { uses: number }).uses, 1);
  } finally {
    first.keeper.drop("r1"); second.keeper.drop("r1");
    secondDb.close(); firstDb.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a failed one-use claim leaves the grant available to retry", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-once-fail-")), path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path), plain = new PlainStore(db), vaults = new VaultStore(db);
  db.exec(`CREATE TABLE vault_grants(ws TEXT NOT NULL,id TEXT NOT NULL,session TEXT NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))`);
  plain.put({ ws: "w", id: "i1", owner: "p@example.com", version: 0, kind: "token", name: "test", fields: { value: "test-only" }, notes: "",
    listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: 1000 });
  const request = { id: "r1", ws: "w", vault: "plain", item: "i1", session: "s1", chat: "chat", owner: "p@example.com",
    mode: "env", reason: "test", box: "", at: 1000, status: "granted" };
  const grant = { v: 1, ws: "w", request: "r1", vault: "plain", item: "i1", mode: "env", hosts: [], scope: "once", exp: 2000, at: 900 };
  db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,?,?)").run("w", "r1", "s1", JSON.stringify({ request, grant, uses: 0 }));
  const secrets = new Secrets({ db: withoutUseReader(db), plain, vaults, proxy: {} as never, data: dir, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ archivedAt: null }), subscribe: () => {} } } as never });
  try {
    db.exec("CREATE TRIGGER fail_claim BEFORE UPDATE ON vault_grants BEGIN SELECT RAISE(ABORT,'claim failed'); END");
    await assert.rejects(secrets.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" }), /claim failed/);
    assert.equal(typeof secrets.keeper.usable("s1", "r1"), "object");
    const row = db.prepare("SELECT body FROM vault_grants WHERE ws=? AND id=?").get("w", "r1") as { body: string };
    assert.equal((JSON.parse(row.body) as { uses: number }).uses, 0);
    db.exec("DROP TRIGGER fail_claim");
    await secrets.run("s1", { grant: "r1", command: "printf ok", cwd: dir, env: "TEST_TOKEN" });
    assert.equal(typeof secrets.keeper.usable("s1", "r1"), "string");
  } finally {
    secrets.keeper.drop("r1");
    db.close(); rmSync(dir, { recursive: true, force: true });
  }
});
