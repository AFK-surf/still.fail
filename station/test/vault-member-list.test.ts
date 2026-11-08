import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Request } from "../src/api/request.ts";
import { routes } from "../src/api/routes/vault.ts";
import { backfillVaultMembers } from "../src/vault/member-index.ts";
import { VaultStore } from "../src/vault/store.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  let vaultRows = 0;
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!/\b(?:FROM|JOIN)\s+vaults\b/i.test(sql)) return statement;
      return new Proxy(statement, { get(query, method) {
        if (method === "all") return (...args: never[]) => { const rows = query.all(...args); vaultRows += rows.length; return rows; };
        if (method === "get") return (...args: never[]) => { const row = query.get(...args); if (row !== undefined) vaultRows++; return row; };
        const value = Reflect.get(query, method, query);
        return typeof value === "function" ? value.bind(query) : value;
      } });
    };
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const vaults = new VaultStore(observed);
  for (let i = 0; i < 120; i++) vaults.putVault({ ws: "w", id: `other-${String(i).padStart(3, "0")}`, seq: 0, owner: "bob", members: ["bob"], epoch: 0 } as never);
  const visible = ["alice-1", "alice-2"].map((id) => ({ ws: "w", id, seq: 0, owner: "alice", members: ["alice"], epoch: 0 }));
  for (const v of visible) vaults.putVault(v as never);
  const item = { ws: "w", vault: "alice-1", id: "one", version: 0, epoch: 0 };
  vaults.putItem(item as never);
  const handlers = routes({ vaults, lock: (ws) => ws === "w" ? { ws: "w" } as never : null });
  const read = async (path: string) => {
    vaultRows = 0;
    const request: Request = { method: "GET", path, query: [], headers: {}, body: Buffer.alloc(0),
      viewer: { sub: "alice", workspace: "w", email: "alice@example.test", name: "Alice", role: "member", device: "device" }, lang: "en" };
    const route = handlers.find((r) => r.method === "GET" && r.pattern.test(path))!;
    const answer = await route.handle(request, []);
    return { status: answer.status, body: JSON.parse((answer.body as Buffer).toString()), vaultRows };
  };
  return { db, vaults, visible, item, read };
}

for (const path of ["/vault/vaults", "/vault/items"]) test(`${path} avoids other members' vaults when the member index is ready`, async () => {
  const f = fixture();
  try {
    while (!backfillVaultMembers(f.db, "w", 32)) {}
    const result = await f.read(path);
    assert.equal(result.status, 200);
    assert.deepEqual(result.body, path === "/vault/vaults" ? { vaults: f.visible } : { items: [f.item] });
    assert.ok(result.vaultRows <= f.visible.length, `read ${result.vaultRows} vault bodies`);
  } finally { f.db.close(); }
});

test("an incomplete member index falls back to the complete list", async () => {
  const f = fixture();
  try {
    assert.equal(backfillVaultMembers(f.db, "w", 1), false);
    assert.deepEqual((await f.read("/vault/vaults")).body, { vaults: f.visible });
    assert.deepEqual((await f.read("/vault/items")).body, { items: [f.item] });
  } finally { f.db.close(); }
});

test("a ready member index follows changes and does not expose a replaced membership", async () => {
  const f = fixture();
  try {
    while (!backfillVaultMembers(f.db, "w", 32)) {}
    const added = { ws: "w", id: "other-000", seq: 1, owner: "bob", members: ["bob", "alice"], epoch: 0 };
    f.vaults.putVault(added as never);
    assert.deepEqual((await f.read("/vault/vaults")).body, { vaults: [...f.visible, added] });
    // An older connection can replace a row without recursive DELETE triggers; recheck the body, not just the index.
    const replaced = { ...f.visible[0], members: ["bob"], seq: 2 };
    f.db.prepare("INSERT OR REPLACE INTO vaults(ws,id,seq,body) VALUES(?,?,?,?)")
      .run("w", replaced.id, replaced.seq, JSON.stringify(replaced));
    assert.deepEqual((await f.read("/vault/vaults")).body, { vaults: [f.visible[1], added] });
    assert.deepEqual((await f.read("/vault/items")).body, { items: [] });
  } finally { f.db.close(); }
});

test("an unreadable old vault still makes the full list fail", async () => {
  const f = fixture();
  try {
    while (!backfillVaultMembers(f.db, "w", 32)) {}
    f.db.prepare("UPDATE vaults SET body=? WHERE ws=? AND id=?").run("{broken", "w", "other-000");
    await assert.rejects(f.read("/vault/vaults"), SyntaxError);
    await assert.rejects(f.read("/vault/items"), SyntaxError);
  } finally { f.db.close(); }
});

test("a saved vault with duplicate member keys follows the last key", async () => {
  const f = fixture();
  try {
    const body = '{"ws":"w","id":"other-000","members":["bob"],"members":["alice"]}';
    f.db.prepare("UPDATE vaults SET body=? WHERE ws=? AND id=?").run(body, "w", "other-000");
    while (!backfillVaultMembers(f.db, "w", 32)) {}
    assert.deepEqual((await f.read("/vault/vaults")).body, { vaults: [...f.visible, JSON.parse(body)] });
  } finally { f.db.close(); }
});
