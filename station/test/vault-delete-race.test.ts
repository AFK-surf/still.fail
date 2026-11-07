import assert from "node:assert/strict";
import { createPrivateKey, sign } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Events } from "../src/api/events.ts";
import type { Request } from "../src/api/request.ts";
import type { LockState } from "../src/cloud/lock.ts";
import { routes } from "../src/api/routes/vault.ts";
import { itemOk, signedBytes, TAG, vaultOk, type Item, type Vault } from "../src/vault/crypto.ts";
import { VaultStore } from "../src/vault/store.ts";

test("an item validated before another connection deletes its vault is not written afterwards", async () => {
  const v = JSON.parse(readFileSync(new URL("./fixtures/vault-vectors.json", import.meta.url), "utf8")) as {
    ws: string; signer: { key: string; seed: string }; device: { id: string }; vault: Vault; item: Item;
  };
  const dir = mkdtempSync(join(process.cwd(), "vault-delete-race-"));
  const db = new DatabaseSync(join(dir, "data.sqlite"));
  const other = new DatabaseSync(join(dir, "data.sqlite"));
  try {
    db.exec("PRAGMA journal_mode=WAL");
    const vaults = new VaultStore(db), fromOther = new VaultStore(other);
    const device = { id: v.device.id, sub: "alice", kind: "app", label: "Alice", own: true, sign_key: v.signer.key };
    const lock = { ws: v.ws, devices: new Map([[device.id, device]]), members: new Map([["alice", { sub: "alice", email: "a@example.test", role: "owner" }]]),
      signKeys: new Map([[device.id, [v.signer.key]]]) } as LockState;
    const { sig: _, recovery: _recovery, ...held } = v.vault;
    const unsigned = { ...held, seq: 1, epoch: 1, keys: [], deleted: true as const, at: 1002 };
    const key = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), Buffer.from(v.signer.seed, "hex")]), format: "der", type: "pkcs8" });
    const deleted: Vault = { ...unsigned, sig: { key: v.signer.key, alg: "Ed25519", sig: sign(null, signedBytes(unsigned, TAG.vault), key).toString("hex") } };
    assert.equal(vaultOk(lock, v.vault, deleted), null);
    assert.equal(itemOk(lock, v.vault, null, v.item), null);
    vaults.putVault(v.vault);
    let raced = false;
    const interleaved = new Proxy(vaults, { get(target, property) {
      if (property === "putItem") return (item: Item) => {
        raced = true;
        fromOther.putVault(deleted);
        return target.putItem(item);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const told: unknown[] = [];
    const events = { tell: (...args: unknown[]) => told.push(args) } as unknown as Events;
    const request: Request = { method: "PUT", path: "/vault/items", query: [], headers: {}, body: Buffer.from(JSON.stringify(v.item)),
      viewer: { sub: "alice", workspace: v.ws, email: "a@example.test", name: "Alice", role: "owner", device: v.device.id }, lang: "en" };
    // A different database failure is still reported as a failure, not mistaken for the deletion race.
    db.exec("CREATE TRIGGER reject_item BEFORE INSERT ON vault_items BEGIN SELECT RAISE(ABORT, 'injected write failure'); END");
    const normal = routes({ vaults, lock: () => lock, events }).find((r) => r.method === "PUT" && r.pattern.test("/vault/items"))!;
    await assert.rejects(normal.handle(request, []), /injected write failure/);
    db.exec("DROP TRIGGER reject_item");
    const route = routes({ vaults: interleaved, lock: () => lock, events }).find((r) => r.method === "PUT" && r.pattern.test("/vault/items"))!;
    const answer = await route.handle(request, []);
    assert.equal(raced, true);
    assert.equal(vaults.vault(v.ws, v.vault.id)?.deleted, true);
    assert.deepEqual(vaults.items(v.ws, v.vault.id), []);
    assert.equal(answer.status, 404);
    assert.deepEqual(told, []);
  } finally {
    other.close(); db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a vault update validated before another connection deletes it cannot undo the deletion", async () => {
  const v = JSON.parse(readFileSync(new URL("./fixtures/vault-vectors.json", import.meta.url), "utf8")) as {
    ws: string; signer: { key: string; seed: string }; device: { id: string }; vault: Vault;
  };
  const dir = mkdtempSync(join(process.cwd(), "vault-delete-race-"));
  const db = new DatabaseSync(join(dir, "data.sqlite"));
  const other = new DatabaseSync(join(dir, "data.sqlite"));
  try {
    db.exec("PRAGMA journal_mode=WAL");
    const vaults = new VaultStore(db), fromOther = new VaultStore(other);
    const device = { id: v.device.id, sub: "alice", kind: "app", label: "Alice", own: true, sign_key: v.signer.key };
    const lock = { ws: v.ws, devices: new Map([[device.id, device]]), members: new Map([["alice", { sub: "alice", email: "a@example.test", role: "owner" }]]),
      signKeys: new Map([[device.id, [v.signer.key]]]) } as LockState;
    const key = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), Buffer.from(v.signer.seed, "hex")]), format: "der", type: "pkcs8" });
    const signed = (unsigned: Omit<Vault, "sig">): Vault => ({ ...unsigned, sig: { key: v.signer.key, alg: "Ed25519", sig: sign(null, signedBytes(unsigned, TAG.vault), key).toString("hex") } });
    const { sig: _, ...held } = v.vault;
    const { recovery: _recovery, ...withoutRecovery } = held;
    const deleted = signed({ ...withoutRecovery, seq: 1, epoch: 1, keys: [], deleted: true, at: 1002 });
    const updated = signed({ ...held, seq: 1, name: "Renamed", at: 1002 });
    assert.equal(vaultOk(lock, v.vault, deleted), null);
    assert.equal(vaultOk(lock, v.vault, updated), null);
    vaults.putVault(v.vault);
    let raced = false;
    const interleaved = new Proxy(vaults, { get(target, property) {
      if (property === "putVault") return (vault: Vault) => {
        raced = true;
        fromOther.putVault(deleted);
        return target.putVault(vault);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const told: unknown[] = [];
    const events = { tell: (...args: unknown[]) => told.push(args) } as unknown as Events;
    const route = routes({ vaults: interleaved, lock: () => lock, events }).find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    const request: Request = { method: "PUT", path: "/vault/vaults", query: [], headers: {}, body: Buffer.from(JSON.stringify(updated)),
      viewer: { sub: "alice", workspace: v.ws, email: "a@example.test", name: "Alice", role: "owner", device: v.device.id }, lang: "en" };
    const answer = await route.handle(request, []);
    assert.equal(raced, true);
    assert.equal(vaults.vault(v.ws, v.vault.id)?.deleted, true);
    assert.equal(answer.status, 409);
    assert.deepEqual(told, []);
    assert.ok(Buffer.isBuffer(answer.body));
    assert.deepEqual(JSON.parse(answer.body.toString("utf8")).vault, deleted);
  } finally {
    other.close(); db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

for (const recursive of [false, true]) test(`old prepared writes cannot restore a deleted vault (recursive triggers ${recursive})`, () => {
  const dir = mkdtempSync(join(process.cwd(), "vault-delete-old-writer-"));
  const path = join(dir, "data.sqlite");
  const old = new DatabaseSync(path);
  const latest = new DatabaseSync(path);
  try {
    old.exec(`PRAGMA journal_mode=WAL; PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"};
      CREATE TABLE vaults (ws TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(ws,id));
      CREATE TABLE vault_items (ws TEXT NOT NULL, vault TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(ws,vault,id));
      CREATE TABLE vault_boxes (ws TEXT NOT NULL, device TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(ws,device));`);
    const saveVault = old.prepare("INSERT INTO vaults (ws, id, seq, body) VALUES (?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET seq = excluded.seq, body = excluded.body");
    const saveItem = old.prepare("INSERT INTO vault_items (ws, vault, id, version, body) VALUES (?, ?, ?, ?, ?) ON CONFLICT (ws, vault, id) DO UPDATE SET version = excluded.version, body = excluded.body");
    const vault = { ws: "w", id: "v", seq: 0, members: ["alice"] };
    const deleted = { ...vault, seq: 1, deleted: true };
    const item = { ws: "w", vault: "v", id: "i", version: 0 };
    saveVault.run("w", "v", 0, JSON.stringify(vault));
    saveItem.run("w", "v", "i", 0, JSON.stringify(item));
    // The older connection prepared both statements before the new station installed its guards.
    const current = new VaultStore(latest);
    old.exec("CREATE TRIGGER reject_old_item_deletion BEFORE DELETE ON vault_items BEGIN SELECT RAISE(ABORT, 'cannot delete'); END");
    assert.throws(() => saveVault.run("w", "v", 1, JSON.stringify(deleted)), /cannot delete/);
    assert.equal(current.vault("w", "v")?.deleted, undefined);
    assert.deepEqual(current.items("w", "v"), [item]);
    old.exec("DROP TRIGGER reject_old_item_deletion");
    // The old station has not yet run its separate DELETE; its version write removed the items atomically.
    saveVault.run("w", "v", 1, JSON.stringify(deleted));
    assert.deepEqual(current.items("w", "v"), []);
    assert.throws(() => saveItem.run("w", "v", "i", 0, JSON.stringify(item)), /vault was deleted/);
    assert.throws(() => saveVault.run("w", "v", 0, JSON.stringify(vault)), /vault was deleted/);
    assert.throws(() => old.prepare("INSERT OR REPLACE INTO vaults (ws,id,seq,body) VALUES (?,?,?,?)")
      .run("w", "v", 0, JSON.stringify(vault)), /vault was deleted/);
    assert.equal(current.vault("w", "v")?.deleted, true);
    assert.deepEqual(current.items("w", "v"), []);
  } finally {
    latest.close(); old.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a stale item already left by a failed old deletion cannot be updated", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE vaults (ws TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(ws,id));
      CREATE TABLE vault_items (ws TEXT NOT NULL, vault TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL, body TEXT NOT NULL, PRIMARY KEY(ws,vault,id));
      INSERT INTO vaults VALUES ('w','v',1,'{"ws":"w","id":"v","deleted":true}');
      INSERT INTO vault_items VALUES ('w','v','i',0,'{}');`);
    const oldUpdate = db.prepare("UPDATE vault_items SET body=? WHERE ws=? AND vault=? AND id=?");
    const vaults = new VaultStore(db);
    assert.throws(() => oldUpdate.run("{}", "w", "v", "i"), /vault was deleted/);
    // A retry of the deleted version can still remove such leftovers.
    vaults.putVault({ ws: "w", id: "v", seq: 1, deleted: true } as never);
    assert.deepEqual(vaults.items("w", "v"), []);
  } finally { db.close(); }
});
