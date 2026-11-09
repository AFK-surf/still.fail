import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { LockState } from "../src/cloud/lock.ts";
import { certOk, type BoxCert, type Request, type Vault } from "../src/vault/crypto.ts";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

function fixture(path = ":memory:") {
  const v = JSON.parse(readFileSync(new URL("./fixtures/vault-vectors.json", import.meta.url), "utf8")) as {
    ws: string; signer: { key: string }; device: { id: string }; cert: BoxCert; vault: Vault;
  };
  const db = new DatabaseSync(path);
  if (path !== ":memory:") db.exec("PRAGMA journal_mode=WAL");
  let vaultRows = 0;
  let onRead: (() => void) | undefined;
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!/\bFROM\s+vaults\b/i.test(sql) || !/\bbody\b/i.test(sql)) return statement;
      return new Proxy(statement, { get(query, method) {
        if (method === "all") return (...args: never[]) => {
          const rows = query.all(...args); vaultRows += rows.length;
          const callback = onRead; onRead = undefined; callback?.();
          return rows;
        };
        const value = Reflect.get(query, method, query);
        return typeof value === "function" ? value.bind(query) : value;
      } });
    };
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const vaults = new VaultStore(observed);
  const device = { id: v.device.id, sub: "alice", kind: "app", own: true, sign_key: v.signer.key };
  const lock = { ws: v.ws, devices: new Map([[device.id, device]]),
    members: new Map([["alice", { sub: "alice", email: "a@example.test", role: "owner" }]]), signKeys: new Map() } as LockState;
  assert.equal(certOk(lock, v.cert), null);
  for (let i = 0; i < 120; i++) vaults.putVault({ ws: v.ws, id: `v${String(i).padStart(3, "0")}`, seq: 0, owner: "bob", members: ["bob"], epoch: 0, keys: [] } as never);
  const previous = Promise.withResolvers<void>();
  const secrets = new Secrets({ db: observed, plain: new PlainStore(db), vaults, data: ".", proxy: {} as never,
    now: () => 1_000_000, home: () => v.ws, lock: () => lock, backfill: { previousGone: previous.promise },
    hub: { store: { getSession: () => ({ ws: v.ws, archivedAt: null }), starter: () => "a@example.test", latestThread: () => null, subscribe: () => {} } } as never });
  const requests: Request[] = [];
  secrets.listen((request) => requests.push(request));
  return { v, db, vaults, secrets, requests, previous, rows: () => vaultRows, reset: () => { vaultRows = 0; }, onRead: (f: () => void) => { onRead = f; } };
}

test("without an admitted box key, choosing a vault need not read the workspace's vaults", async () => {
  const f = fixture();
  try {
    f.db.prepare("UPDATE vaults SET body='{broken' WHERE ws=? AND id='v000'").run(f.v.ws);
    f.reset();
    assert.equal(f.secrets.status("s"), "off");
    assert.equal(f.rows(), 0);
    f.reset();
    await f.secrets.save("s", { name: "key", kind: "token", reason: "test", value: "sample", cwd: "." });
    assert.equal(f.requests.at(-1)?.vault, "");
    assert.equal(f.rows(), 0);
  } finally { f.previous.resolve(); await f.secrets.close(); f.db.close(); }
});

test("an early personal vault does not require reading later vaults", async () => {
  const f = fixture();
  try {
    f.vaults.putBox(f.v.cert);
    f.vaults.putVault({ ...f.v.vault, id: "v000" });
    f.reset();
    assert.equal(f.secrets.status("s"), "on");
    assert.ok(f.rows() <= 32, `read ${f.rows()} vault bodies`);
    f.reset();
    await f.secrets.save("s", { name: "key", kind: "token", reason: "test", value: "sample", cwd: "." });
    assert.equal(f.requests.at(-1)?.vault, "v000");
    assert.ok(f.rows() <= 32, `read ${f.rows()} vault bodies`);
  } finally { f.previous.resolve(); await f.secrets.close(); f.db.close(); }
});

test("a later personal vault is preferred over an earlier shared one", async () => {
  const f = fixture();
  try {
    f.vaults.putBox(f.v.cert);
    f.vaults.putVault({ ...f.v.vault, id: "v000", owner: "bob" });
    f.vaults.putVault({ ...f.v.vault, id: "v080" });
    await f.secrets.save("s", { name: "key", kind: "token", reason: "test", value: "sample", cwd: "." });
    assert.equal(f.requests.at(-1)?.vault, "v080");
  } finally { f.previous.resolve(); await f.secrets.close(); f.db.close(); }
});

test("when there is no personal vault, the first eligible shared vault is chosen", async () => {
  const f = fixture();
  try {
    f.vaults.putBox(f.v.cert);
    f.vaults.putVault({ ...f.v.vault, id: "v001", owner: "bob" });
    f.vaults.putVault({ ...f.v.vault, id: "v080", owner: "bob" });
    await f.secrets.save("s", { name: "key", kind: "token", reason: "test", value: "sample", cwd: "." });
    assert.equal(f.requests.at(-1)?.vault, "v001");
  } finally { f.previous.resolve(); await f.secrets.close(); f.db.close(); }
});

test("selection keeps membership and device-key checks across the prefix boundary", async () => {
  const f = fixture();
  try {
    f.vaults.putBox(f.v.cert);
    f.vaults.putVault({ ...f.v.vault, id: "v000", members: ["bob"] });
    f.vaults.putVault({ ...f.v.vault, id: "v001", keys: [] });
    f.vaults.putVault({ ...f.v.vault, id: "v032" });
    const body = JSON.parse((f.db.prepare("SELECT body FROM vaults WHERE ws=? AND id='v031'").get(f.v.ws) as { body: string }).body);
    body.id = "z-old-body-id";
    f.db.prepare("UPDATE vaults SET body=? WHERE ws=? AND id='v031'").run(JSON.stringify(body), f.v.ws);
    await f.secrets.save("s", { name: "key", kind: "token", reason: "test", value: "sample", cwd: "." });
    assert.equal(f.requests.at(-1)?.vault, "v032");
  } finally { f.previous.resolve(); await f.secrets.close(); f.db.close(); }
});

test("the prefix and fallback choose from one snapshot while another connection changes owners", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-owner-lookup-")), path = join(dir, "data.sqlite");
  const f = fixture(path), other = new DatabaseSync(path);
  try {
    f.vaults.putBox(f.v.cert);
    f.vaults.putVault({ ...f.v.vault, id: "v000", owner: "bob" });
    f.vaults.putVault({ ...f.v.vault, id: "v080" });
    let changed = false;
    f.onRead(() => {
      other.exec("BEGIN IMMEDIATE");
      other.prepare("UPDATE vaults SET body=json_set(body, '$.owner', 'alice') WHERE ws=? AND id='v000'").run(f.v.ws);
      other.prepare("UPDATE vaults SET body=json_set(body, '$.owner', 'bob') WHERE ws=? AND id='v080'").run(f.v.ws);
      other.exec("COMMIT");
      changed = true;
    });
    await f.secrets.save("s", { name: "first", kind: "token", reason: "test", value: "sample", cwd: "." });
    assert.equal(changed, true);
    assert.equal(f.requests.at(-1)?.vault, "v080");
    await f.secrets.save("s", { name: "second", kind: "token", reason: "test", value: "sample", cwd: "." });
    assert.equal(f.requests.at(-1)?.vault, "v000");
  } finally { f.previous.resolve(); await f.secrets.close(); other.close(); f.db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the choice releases its snapshot and an early match does not read later damaged vaults", async () => {
  const f = fixture();
  try {
    f.vaults.putBox(f.v.cert);
    f.vaults.putVault({ ...f.v.vault, id: "v000" });
    f.db.prepare("UPDATE vaults SET body='{broken' WHERE ws=? AND id='v080'").run(f.v.ws);
    f.db.exec("BEGIN");
    assert.equal(f.secrets.status("s"), "on");
    assert.equal(f.db.isTransaction, true);
    f.db.prepare("UPDATE vaults SET body='{broken' WHERE ws=? AND id='v001'").run(f.v.ws);
    assert.throws(() => f.secrets.status("s"), SyntaxError);
    assert.equal(f.db.isTransaction, true);
    f.db.exec("ROLLBACK");
  } finally { f.previous.resolve(); await f.secrets.close(); f.db.close(); }
});
