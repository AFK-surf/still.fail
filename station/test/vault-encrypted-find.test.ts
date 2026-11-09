import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { LockState } from "../src/cloud/lock.ts";
import type { Request } from "../src/vault/crypto.ts";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

function fixture(path = ":memory:") {
  const db = new DatabaseSync(path);
  if (path !== ":memory:") db.exec("PRAGMA journal_mode=WAL");
  let vaultRows = 0, itemRows = 0;
  let onItemRead: (() => void) | undefined;
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      const table = /\bFROM\s+(vaults|vault_items)\b/i.exec(sql)?.[1];
      if (!table || !/\bbody\b/i.test(sql)) return statement;
      return new Proxy(statement, { get(query, method) {
        if (method === "all") return (...args: never[]) => {
          const rows = query.all(...args);
          if (table === "vaults") vaultRows += rows.length; else itemRows += rows.length;
          if (table === "vault_items") { const callback = onItemRead; onItemRead = undefined; callback?.(); }
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
  for (let n = 0; n < 120; n++) {
    const id = `v${String(n).padStart(3, "0")}`;
    vaults.putVault({ ws: "w", id, seq: 0, owner: "alice", members: ["alice"], epoch: 1 } as never);
  }
  for (let n = 0; n < 120; n++) {
    const id = `i${String(n).padStart(3, "0")}`;
    const name = n === 1 || n === 3 ? "TÄRGET" : n === 2 ? "i100" : `key-${n}`;
    vaults.putItem({ ws: "w", vault: "v000", id, version: 0, epoch: 1,
      ...(n === 0 ? {} : { listing: { name, kind: "token", modes: ["env"], hosts: [] } }) } as never);
  }
  const member = { sub: "alice", email: "p@example.test", role: "owner" };
  const lock = { ws: "w", members: new Map([["alice", member]]), devices: new Map(), signKeys: new Map() } as LockState;
  const prior = Promise.withResolvers<void>();
  const secrets = new Secrets({ db: observed, plain: new PlainStore(db), vaults, data: ".", proxy: {} as never, now: () => 1_000_000,
    home: () => "w", lock: () => lock,
    hub: { store: { getSession: () => ({ ws: "w", archivedAt: null }), starter: () => "p@example.test", latestThread: () => null, subscribe: () => {} } } as never,
    backfill: { previousGone: prior.promise } });
  const requested: Request[] = [];
  secrets.listen((request) => requested.push(request));
  return { db, vaults, secrets, requested, counts: () => ({ vaultRows, itemRows }), reset: () => { vaultRows = itemRows = 0; },
    onItemRead: (callback: () => void) => { onItemRead = callback; }, prior };
}

test("asking for an early encrypted listing need not read later vaults or items", async () => {
  const f = fixture();
  try {
    f.reset();
    await f.secrets.ask("s", { item: "  tärget  ", reason: "test" });
    assert.equal(f.requested.at(-1)?.vault, "v000");
    assert.equal(f.requested.at(-1)?.item, "i001");
    const count = f.counts();
    assert.ok(count.vaultRows <= 32, `read ${count.vaultRows} vaults`);
    assert.ok(count.itemRows <= 32, `read ${count.itemRows} items`);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("encrypted listing lookup keeps membership, epoch and deletion checks", async () => {
  const f = fixture();
  try {
    const read = f.db.prepare("SELECT body FROM vault_items WHERE ws=? AND vault=? AND id=?");
    const update = f.db.prepare("UPDATE vault_items SET body=? WHERE ws=? AND vault=? AND id=?");
    const one = JSON.parse((read.get("w", "v000", "i001") as { body: string }).body); one.deleted = true;
    update.run(JSON.stringify(one), "w", "v000", "i001");
    const three = JSON.parse((read.get("w", "v000", "i003") as { body: string }).body); three.epoch = 2;
    update.run(JSON.stringify(three), "w", "v000", "i003");
    f.vaults.putItem({ ws: "w", vault: "v001", id: "later", version: 0, epoch: 1,
      listing: { name: "tärget", kind: "token", modes: ["env"], hosts: [] } } as never);
    f.vaults.putVault({ ws: "w", id: "v001", seq: 1, owner: "alice", members: ["bob"], epoch: 1 } as never);
    f.vaults.putItem({ ws: "w", vault: "v032", id: "later", version: 0, epoch: 1,
      listing: { name: "tärget", kind: "token", modes: ["env"], hosts: [] } } as never);
    await f.secrets.ask("s", { item: "tärget", reason: "test" });
    assert.equal(f.requested.at(-1)?.vault, "v032");
    assert.equal(f.requested.at(-1)?.item, "later");
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("encrypted lookup uses stored keys at the vault and item prefix boundaries", async () => {
  const f = fixture();
  try {
    for (const n of [30, 31, 32]) {
      await f.secrets.ask("s", { item: `key-${n}`, reason: "test" });
      assert.equal(f.requested.at(-1)?.item, `i${String(n).padStart(3, "0")}`);
      const vault = `v${String(n).padStart(3, "0")}`;
      f.vaults.putItem({ ws: "w", vault, id: "boundary", version: 0, epoch: 1,
        listing: { name: `vault-boundary-${n}`, kind: "token", modes: ["env"], hosts: [] } } as never);
      await f.secrets.ask("s", { item: `vault-boundary-${n}`, reason: "test" });
      assert.equal(f.requested.at(-1)?.vault, vault);
    }
    const item = JSON.parse((f.db.prepare("SELECT body FROM vault_items WHERE ws='w' AND vault='v000' AND id='i031'").get() as { body: string }).body);
    item.id = "z-old-item-body";
    f.db.prepare("UPDATE vault_items SET body=? WHERE ws='w' AND vault='v000' AND id='i031'").run(JSON.stringify(item));
    await f.secrets.ask("s", { item: "key-32", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i032");
    const vault = JSON.parse((f.db.prepare("SELECT body FROM vaults WHERE ws='w' AND id='v031'").get() as { body: string }).body);
    vault.id = "z-old-vault-body";
    f.db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v031'").run(JSON.stringify(vault));
    f.vaults.putItem({ ws: "w", vault: "v032", id: "late", version: 0, epoch: 1,
      listing: { name: "after vault boundary", kind: "token", modes: ["env"], hosts: [] } } as never);
    await f.secrets.ask("s", { item: "after vault boundary", reason: "test" });
    assert.equal(f.requested.at(-1)?.vault, "v032");
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("encrypted listing reads release their snapshot within an enclosing transaction", async () => {
  const f = fixture();
  try {
    f.db.exec("BEGIN");
    await f.secrets.ask("s", { item: "tärget", reason: "test" });
    assert.equal(f.db.isTransaction, true);
    f.db.prepare("UPDATE vault_items SET body=? WHERE ws='w' AND vault='v000' AND id='i000'").run("{broken");
    await assert.rejects(f.secrets.ask("s", { item: "tärget", reason: "test" }), SyntaxError);
    assert.equal(f.db.isTransaction, true);
    f.db.exec("ROLLBACK");
    assert.equal(f.db.prepare("SELECT count(*) AS n FROM vault_requests").get()?.n, 0);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("encrypted prefix and fallback share a snapshot with another connection", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-encrypted-find-")), path = join(dir, "db");
  const f = fixture(path), other = new DatabaseSync(path);
  try {
    const read = other.prepare("SELECT body FROM vault_items WHERE ws=? AND vault=? AND id=?");
    const update = other.prepare("UPDATE vault_items SET body=? WHERE ws=? AND vault=? AND id=?");
    const earlier = JSON.parse((read.get("w", "v000", "i004") as { body: string }).body); earlier.listing.name = "fresh";
    const later = JSON.parse((read.get("w", "v000", "i050") as { body: string }).body); later.listing.name = "fresh";
    update.run(JSON.stringify(later), "w", "v000", "i050");
    f.onItemRead(() => { update.run(JSON.stringify(earlier), "w", "v000", "i004"); });
    await f.secrets.ask("s", { item: "fresh", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i050");
    await f.secrets.ask("s", { item: "fresh", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i004");
  } finally { f.prior.resolve(); await f.secrets.close(); other.close(); f.db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an unreadable later encrypted vault does not block an earlier match", async () => {
  const f = fixture();
  try {
    f.db.prepare("UPDATE vaults SET body=? WHERE ws=? AND id=?").run("{broken", "w", "v119");
    await f.secrets.ask("s", { item: "tärget", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i001");
    assert.throws(() => f.secrets.listings("s"), SyntaxError);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("encrypted listing lookup retains the first name-or-id match and full fallback", async () => {
  const f = fixture();
  try {
    await f.secrets.ask("s", { item: "i100", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i002");
    await f.secrets.ask("s", { item: "key-119", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i119");
    await assert.rejects(f.secrets.ask("s", { item: "absent", reason: "test" }), /No secret named/);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});
