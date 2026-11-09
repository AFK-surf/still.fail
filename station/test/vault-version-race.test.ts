import assert from "node:assert/strict";
import { createPrivateKey, sign } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Request } from "../src/api/request.ts";
import type { LockState } from "../src/cloud/lock.ts";
import { routes } from "../src/api/routes/vault.ts";
import { previousExited } from "../src/ops/previous.ts";
import { itemOk, itemSupersedes, signedBytes, TAG, vaultOk, vaultSupersedes, type Item, type Vault } from "../src/vault/crypto.ts";
import { VaultStore } from "../src/vault/store.ts";
import { vaultWriteGate } from "../src/vault/write-gate.ts";

function fixture() {
  const v = JSON.parse(readFileSync(new URL("./fixtures/vault-vectors.json", import.meta.url), "utf8")) as {
    ws: string; signer: { key: string; seed: string }; device: { id: string }; vault: Vault; item: Item;
  };
  const dir = mkdtempSync(join(process.cwd(), "vault-version-race-")), path = join(dir, "data.sqlite");
  const db = new DatabaseSync(path), other = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL");
  const vaults = new VaultStore(db), fromOther = new VaultStore(other);
  const device = { id: v.device.id, sub: "alice", kind: "app", label: "Alice", own: true, sign_key: v.signer.key };
  const lock = { ws: v.ws, devices: new Map([[device.id, device]]), members: new Map([["alice", { sub: "alice", email: "a@example.test", role: "owner" }]]),
    signKeys: new Map([[device.id, [v.signer.key]]]) } as LockState;
  const key = createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), Buffer.from(v.signer.seed, "hex")]), format: "der", type: "pkcs8" });
  const signedVault = (unsigned: Omit<Vault, "sig">): Vault => ({ ...unsigned, sig: { key: v.signer.key, alg: "Ed25519", sig: sign(null, signedBytes(unsigned, TAG.vault), key).toString("hex") } });
  const signedItem = (unsigned: Omit<Item, "sig">): Item => ({ ...unsigned, sig: { key: v.signer.key, alg: "Ed25519", sig: sign(null, signedBytes(unsigned, TAG.item), key).toString("hex") } });
  const request = (path: string, body: unknown): Request => ({ method: "PUT", path, query: [], headers: {}, body: Buffer.from(JSON.stringify(body)),
    viewer: { sub: "alice", workspace: v.ws, email: "a@example.test", name: "Alice", role: "owner", device: v.device.id }, lang: "en" });
  let oldClosed = false;
  const closeOther = () => { if (!oldClosed) { oldClosed = true; other.close(); } };
  const close = () => { closeOther(); db.close(); rmSync(dir, { recursive: true, force: true }); };
  return { v, vaults, fromOther, other, lock, signedVault, signedItem, request, closeOther, close };
}

for (const kind of ["vault", "item"] as const) {
  test(`a ${kind} write waits for the previous station and checks its final version`, async () => {
    const f = fixture();
    const previous = Promise.withResolvers<void>();
    const gate = vaultWriteGate(previous.promise);
    try {
      const { sig: _v, ...vbase } = f.v.vault;
      const { sig: _i, ...ibase } = f.v.item;
      const vaultWinner = f.signedVault({ ...vbase, seq: 1, name: "Other", at: 1002 });
      const vaultNext = f.signedVault({ ...vbase, seq: 1, name: "New", at: 1002 });
      const itemWinner = f.signedItem({ ...ibase, version: 1, listing: { ...ibase.listing!, name: "Other" }, at: 1002 });
      const itemNext = f.signedItem({ ...ibase, version: 1, listing: { ...ibase.listing!, name: "New" }, at: 1002 });
      f.vaults.putVault(f.v.vault);
      if (kind === "item") f.vaults.putItem(f.v.item);
      // This is the old process's prepared statement, made before the new request starts.
      const old = kind === "vault"
        ? f.other.prepare("INSERT INTO vaults (ws, id, seq, body) VALUES (?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET seq = excluded.seq, body = excluded.body")
        : f.other.prepare("INSERT INTO vault_items (ws, vault, id, version, body) VALUES (?, ?, ?, ?, ?) ON CONFLICT (ws, vault, id) DO UPDATE SET version = excluded.version, body = excluded.body");
      const path = kind === "vault" ? "/vault/vaults" : "/vault/items";
      const table = routes({ vaults: f.vaults, lock: () => f.lock, beforeWrite: () => gate.wait() });
      const put = table.find((r) => r.method === "PUT" && r.pattern.test(path))!;
      const get = table.find((r) => r.method === "GET" && r.pattern.test(path))!;
      let answered = false;
      const pending = put.handle(f.request(path, kind === "vault" ? vaultNext : itemNext), []).then((answer) => { answered = true; return answer; });
      await new Promise<void>((resolve) => setImmediate(resolve));
      assert.equal(answered, false);
      assert.equal((await get.handle(f.request(path, {}), [])).status, 200);
      if (kind === "vault") old.run(vaultWinner.ws, vaultWinner.id, vaultWinner.seq, JSON.stringify(vaultWinner));
      else old.run(itemWinner.ws, itemWinner.vault, itemWinner.id, itemWinner.version, JSON.stringify(itemWinner));
      f.closeOther(); // Only after the old connection's writes are done does its process exit.
      previous.resolve();
      const answer = await pending;
      assert.equal(answer.status, 409);
      if (kind === "vault") assert.deepEqual(f.vaults.vault(f.v.ws, f.v.vault.id), vaultWinner);
      else assert.deepEqual(f.vaults.item(f.v.ws, f.v.vault.id, f.v.item.id), itemWinner);
    } finally { gate.close(); f.close(); }
  });
}

test("a write waiting for handover checks the workspace lock afterwards", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const gate = vaultWriteGate(previous.promise);
  try {
    let lock: LockState | null = f.lock;
    const put = routes({ vaults: f.vaults, lock: () => lock, beforeWrite: () => gate.wait() })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    const pending = put.handle(f.request("/vault/vaults", f.v.vault), []);
    lock = null;
    f.closeOther(); previous.resolve();
    const answer = await pending;
    assert.equal(answer.status, 409);
    assert.equal(JSON.parse((answer.body as Buffer).toString()).code, "vault_needs_lock");
    assert.equal(f.vaults.vault(f.v.ws, f.v.vault.id), null);
  } finally { gate.close(); f.close(); }
});

test("session takeover timing out does not release a vault write while the old process lives", async () => {
  const f = fixture();
  let alive = true;
  let wake: (() => void) | undefined;
  const exited = previousExited({ pid: 123, gone: Promise.resolve() }, () => alive,
    () => new Promise<void>((resolve) => { wake = resolve; }));
  const gate = vaultWriteGate(exited);
  try {
    const put = routes({ vaults: f.vaults, lock: () => f.lock, beforeWrite: () => gate.wait() })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    let answered = false;
    const pending = put.handle(f.request("/vault/vaults", f.v.vault), []).then((answer) => { answered = true; return answer; });
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(answered, false);
    assert.equal(f.vaults.vault(f.v.ws, f.v.vault.id), null);
    assert.ok(wake);
    f.closeOther(); alive = false; wake();
    assert.equal((await pending).status, 200);
  } finally { gate.close(); f.close(); }
});

test("stopping the station refuses a vault write waiting for handover", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const gate = vaultWriteGate(previous.promise);
  try {
    const put = routes({ vaults: f.vaults, lock: () => f.lock, beforeWrite: () => gate.wait() })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    const pending = put.handle(f.request("/vault/vaults", f.v.vault), []);
    gate.close();
    assert.equal((await pending).status, 503);
    f.closeOther(); previous.resolve();
    await Promise.resolve();
    assert.equal((await put.handle(f.request("/vault/vaults", f.v.vault), [])).status, 503);
    assert.equal(f.vaults.vault(f.v.ws, f.v.vault.id), null);
  } finally { gate.close(); f.close(); }
});

test("a station stopping as its predecessor exits does not resume the waiting write", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const gate = vaultWriteGate(previous.promise);
  try {
    const put = routes({ vaults: f.vaults, lock: () => f.lock, beforeWrite: () => gate.wait() })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    const pending = put.handle(f.request("/vault/vaults", f.v.vault), []);
    f.closeOther(); previous.resolve();
    await Promise.resolve(); // The gate opened, but the request has yet to continue.
    gate.close();
    assert.equal((await pending).status, 503);
    assert.equal(f.vaults.vault(f.v.ws, f.v.vault.id), null);
  } finally { gate.close(); f.close(); }
});

test("a winning copied sibling is still accepted after the old station exits", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const gate = vaultWriteGate(previous.promise);
  try {
    const { sig: _, ...base } = f.v.vault;
    const a = f.signedVault({ ...base, seq: 1, name: "Alpha", at: 1002 });
    const b = f.signedVault({ ...base, seq: 1, name: "Zulu", at: 1002 });
    const [winner, other] = vaultSupersedes(a, b) ? [a, b] : [b, a];
    f.vaults.putVault(f.v.vault);
    const put = routes({ vaults: f.vaults, lock: () => f.lock, beforeWrite: () => gate.wait() })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    const req = f.request("/vault/vaults", winner); req.query = [["copy", "1"]];
    const pending = put.handle(req, []);
    f.fromOther.putVault(other);
    f.closeOther(); previous.resolve();
    const answer = await pending;
    assert.equal(answer.status, 200);
    assert.deepEqual(f.vaults.vault(f.v.ws, f.v.vault.id), winner);
  } finally { gate.close(); f.close(); }
});

test("a long handover refuses a pending write but accepts later writes once it ends", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  let expire = () => {};
  const gate = vaultWriteGate(previous.promise, (_ms, callback) => { expire = callback; return () => {}; });
  try {
    const put = routes({ vaults: f.vaults, lock: () => f.lock, beforeWrite: () => gate.wait() })
      .find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    const pending = put.handle(f.request("/vault/vaults", f.v.vault), []);
    expire();
    assert.equal((await pending).status, 503);
    assert.equal((await put.handle(f.request("/vault/vaults", f.v.vault), [])).status, 503);
    assert.equal(f.vaults.vault(f.v.ws, f.v.vault.id), null);
    f.closeOther(); previous.resolve();
    await Promise.resolve();
    assert.equal((await put.handle(f.request("/vault/vaults", f.v.vault), [])).status, 200);
  } finally { gate.close(); f.close(); }
});

for (const copy of [false, true]) {
  test(`a vault version changed during a write is not returned to a removed member (copy: ${copy})`, async () => {
    const f = fixture();
    try {
      f.lock.members.set("bob", { sub: "bob", email: "b@example.test", role: "member" });
      const { sig: _, ...base } = f.v.vault;
      const held = f.signedVault({ ...base, members: ["alice", "bob"] });
      const next = f.signedVault({ ...base, members: ["alice", "bob"], seq: 1, name: "Changed", at: 1002 });
      const removed = f.signedVault({ ...base, members: ["alice"], seq: 1, epoch: 1, at: 1002 });
      assert.equal(vaultOk(f.lock, held, next), null);
      assert.equal(vaultOk(f.lock, held, removed), null);
      f.vaults.putVault(held);
      let raced = false;
      const interleaved = new Proxy(f.vaults, { get(target, property) {
        if (property === "putVaultIf") return (vault: Vault, previous: string | null) => {
          if (!raced) { raced = true; f.fromOther.putVault(removed); }
          return target.putVaultIf(vault, previous);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
      const req = f.request("/vault/vaults", next);
      req.viewer = { ...req.viewer, sub: "bob", email: "b@example.test", name: "Bob", role: "member" };
      if (copy) req.query = [["copy", "1"]];
      const answer = await route.handle(req, []);
      assert.equal(raced, true);
      assert.equal(answer.status, 404);
      assert.equal(JSON.parse((answer.body as Buffer).toString()).vault, undefined);
      assert.deepEqual(f.vaults.vault(f.v.ws, f.v.vault.id), removed);
    } finally { f.close(); }
  });
}

test("a failed handover wait refuses writes rather than bypassing the previous station", async () => {
  const previous = Promise.withResolvers<void>();
  const gate = vaultWriteGate(previous.promise);
  try {
    const waiting = gate.wait();
    assert.notEqual(waiting, false);
    assert.notEqual(waiting, undefined);
    previous.reject(new Error("previous process unavailable"));
    assert.equal(await waiting, false);
    assert.equal(await gate.wait(), false);
  } finally { gate.close(); }
});

test("a stale vault write cannot replace a sibling which supersedes it", async () => {
  const f = fixture();
  try {
    const { sig: _, ...base } = f.v.vault;
    const a = f.signedVault({ ...base, seq: 1, name: "Alpha", at: 1002 });
    const b = f.signedVault({ ...base, seq: 1, name: "Zulu", at: 1002 });
    assert.equal(vaultOk(f.lock, f.v.vault, a), null);
    assert.equal(vaultOk(f.lock, f.v.vault, b), null);
    const [winner, stale] = vaultSupersedes(a, b) ? [a, b] : [b, a];
    assert.equal(vaultSupersedes(winner, stale), true);
    f.vaults.putVault(f.v.vault);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putVaultIf") return (vault: Vault, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putVault(winner); }
        return target.putVaultIf(vault, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    await route.handle(f.request("/vault/vaults", stale), []);
    assert.equal(raced, true);
    assert.deepEqual(f.vaults.vault(f.v.ws, f.v.vault.id), winner);
  } finally { f.close(); }
});

test("a stale item write cannot replace a sibling which supersedes it", async () => {
  const f = fixture();
  try {
    const { sig: _, ...base } = f.v.item;
    const a = f.signedItem({ ...base, version: 1, listing: { ...base.listing!, name: "Alpha" }, at: 1002 });
    const b = f.signedItem({ ...base, version: 1, listing: { ...base.listing!, name: "Zulu" }, at: 1002 });
    assert.equal(itemOk(f.lock, f.v.vault, f.v.item, a), null);
    assert.equal(itemOk(f.lock, f.v.vault, f.v.item, b), null);
    const [winner, stale] = itemSupersedes(a, b) ? [a, b] : [b, a];
    assert.equal(itemSupersedes(winner, stale), true);
    f.vaults.putVault(f.v.vault); f.vaults.putItem(f.v.item);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putItemIf") return (item: Item, vaultBody: string, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putItem(winner); }
        return target.putItemIf(item, vaultBody, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/items"))!;
    await route.handle(f.request("/vault/items", stale), []);
    assert.equal(raced, true);
    assert.deepEqual(f.vaults.item(f.v.ws, f.v.vault.id, f.v.item.id), winner);
  } finally { f.close(); }
});

test("a concurrent first vault is not replaced by a stale first write", async () => {
  const f = fixture();
  try {
    const { sig: _, ...base } = f.v.vault;
    const other = f.signedVault({ ...base, name: "Other", at: 1002 });
    assert.equal(vaultOk(f.lock, null, f.v.vault), null);
    assert.equal(vaultOk(f.lock, null, other), null);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putVaultIf") return (vault: Vault, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putVault(other); }
        return target.putVaultIf(vault, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    assert.equal((await route.handle(f.request("/vault/vaults", f.v.vault), [])).status, 409);
    assert.equal(raced, true);
    assert.deepEqual(f.vaults.vault(f.v.ws, f.v.vault.id), other);
  } finally { f.close(); }
});

test("a concurrent first item is not replaced by a stale first write", async () => {
  const f = fixture();
  try {
    const { sig: _, ...base } = f.v.item;
    const other = f.signedItem({ ...base, listing: { ...base.listing!, name: "Other" }, at: 1002 });
    assert.equal(itemOk(f.lock, f.v.vault, null, f.v.item), null);
    assert.equal(itemOk(f.lock, f.v.vault, null, other), null);
    f.vaults.putVault(f.v.vault);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putItemIf") return (item: Item, vaultBody: string, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putItem(other); }
        return target.putItemIf(item, vaultBody, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/items"))!;
    assert.equal((await route.handle(f.request("/vault/items", f.v.item), [])).status, 409);
    assert.equal(raced, true);
    assert.deepEqual(f.vaults.item(f.v.ws, f.v.vault.id, f.v.item.id), other);
  } finally { f.close(); }
});

test("a copied winning vault sibling is retried after a concurrent write", async () => {
  const f = fixture();
  try {
    const { sig: _, ...base } = f.v.vault;
    const a = f.signedVault({ ...base, seq: 1, name: "Alpha", at: 1002 });
    const b = f.signedVault({ ...base, seq: 1, name: "Zulu", at: 1002 });
    const [winner, other] = vaultSupersedes(a, b) ? [a, b] : [b, a];
    f.vaults.putVault(f.v.vault);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putVaultIf") return (vault: Vault, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putVault(other); }
        return target.putVaultIf(vault, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/vaults"))!;
    const req = f.request("/vault/vaults", winner); req.query = [["copy", "1"]];
    assert.equal((await route.handle(req, [])).status, 200);
    assert.equal(raced, true);
    assert.deepEqual(f.vaults.vault(f.v.ws, f.v.vault.id), winner);
  } finally { f.close(); }
});

test("a copied winning item sibling is retried after a concurrent write", async () => {
  const f = fixture();
  try {
    const { sig: _, ...base } = f.v.item;
    const a = f.signedItem({ ...base, version: 1, listing: { ...base.listing!, name: "Alpha" }, at: 1002 });
    const b = f.signedItem({ ...base, version: 1, listing: { ...base.listing!, name: "Zulu" }, at: 1002 });
    const [winner, other] = itemSupersedes(a, b) ? [a, b] : [b, a];
    f.vaults.putVault(f.v.vault); f.vaults.putItem(f.v.item);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putItemIf") return (item: Item, vaultBody: string, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putItem(other); }
        return target.putItemIf(item, vaultBody, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/items"))!;
    const req = f.request("/vault/items", winner); req.query = [["copy", "1"]];
    assert.equal((await route.handle(req, [])).status, 200);
    assert.equal(raced, true);
    assert.deepEqual(f.vaults.item(f.v.ws, f.v.vault.id, f.v.item.id), winner);
  } finally { f.close(); }
});

test("an item is checked again when its vault changes after validation", async () => {
  const f = fixture();
  try {
    const { sig: _, ...base } = f.v.vault;
    const rotated = f.signedVault({ ...base, seq: 1, epoch: 1, at: 1002 });
    assert.equal(vaultOk(f.lock, f.v.vault, rotated), null);
    assert.equal(itemOk(f.lock, f.v.vault, null, f.v.item), null);
    f.vaults.putVault(f.v.vault);
    let raced = false;
    const interleaved = new Proxy(f.vaults, { get(target, property) {
      if (property === "putItemIf") return (item: Item, vaultBody: string, previous: string | null) => {
        if (!raced) { raced = true; f.fromOther.putVault(rotated); }
        return target.putItemIf(item, vaultBody, previous);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const route = routes({ vaults: interleaved, lock: () => f.lock }).find((r) => r.method === "PUT" && r.pattern.test("/vault/items"))!;
    const answer = await route.handle(f.request("/vault/items", f.v.item), []);
    assert.equal(raced, true);
    assert.equal(answer.status, 400);
    assert.equal(f.vaults.item(f.v.ws, f.v.vault.id, f.v.item.id), null);
  } finally { f.close(); }
});
