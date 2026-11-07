import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Request } from "../src/api/request.ts";
import { routes } from "../src/api/routes/vault.ts";
import { VaultStore } from "../src/vault/store.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  let inspected = 0;
  db.function("vault_seen", (_id: unknown) => { inspected++; return 0; });
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => target.prepare(sql.replace(
      "SELECT body FROM vaults WHERE ws = ?", "SELECT body, vault_seen(id) AS seen FROM vaults WHERE ws = ?"));
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const vaults = new VaultStore(observed);
  for (let i = 0; i < 120; i++) vaults.putVault({ ws: "w", id: `other-${i}`, seq: 0, owner: "other", members: ["other"], epoch: 0 } as never);
  vaults.putVault({ ws: "w", id: "target", seq: 0, owner: "alice", members: ["alice"], epoch: 0 } as never);
  vaults.putVault({ ws: "another", id: "target", seq: 0, owner: "bob", members: ["bob"], epoch: 0 } as never);
  const item = { ws: "w", vault: "target", id: "one", version: 0, epoch: 0 };
  vaults.putItem(item as never);
  const route = routes({ vaults, lock: (ws) => ws === "w" ? { ws: "w" } as never : null })
    .find((r) => r.method === "GET" && r.pattern.test("/vault/items"))!;
  const read = async (sub: string, vault?: string) => {
    inspected = 0;
    const request: Request = { method: "GET", path: "/vault/items", query: vault === undefined ? [] : [["vault", vault]],
      headers: {}, body: Buffer.alloc(0), viewer: { sub, workspace: "w", email: `${sub}@example.test`, name: sub, role: "member", device: "device" }, lang: "en" };
    const answer = await route.handle(request, []);
    return { status: answer.status, body: JSON.parse((answer.body as Buffer).toString()), inspected };
  };
  return { db, vaults, read, item };
}

test("requesting a specific vault's items does not read other vaults", async () => {
  const f = fixture();
  try {
    const answer = await f.read("alice", "target");
    assert.equal(answer.status, 200);
    assert.deepEqual(answer.body.items, [f.item]);
    assert.ok(answer.inspected <= 1, `read ${answer.inspected} vaults`);
  } finally { f.db.close(); }
});

test("a specific vault is still checked for membership, existence and deletion", async () => {
  const f = fixture();
  try {
    const denied = await f.read("bob", "target"), missing = await f.read("alice", "missing");
    assert.equal(denied.body.code, "vault_unknown");
    assert.equal(missing.body.code, "vault_unknown");
    assert.ok(denied.inspected <= 1);
    assert.ok(missing.inspected <= 1);
    assert.deepEqual((await f.read("alice")).body.items, [f.item]);
    f.vaults.putVault({ ws: "w", id: "target", seq: 1, owner: "alice", members: ["alice"], epoch: 1, deleted: true } as never);
    const deleted = await f.read("alice", "target");
    assert.equal(deleted.status, 200);
    assert.deepEqual(deleted.body.items, []);
    assert.deepEqual((await f.read("alice")).body.items, []);
  } finally { f.db.close(); }
});

test("an unrelated unreadable vault does not prevent reading a specified vault", async () => {
  const f = fixture();
  try {
    f.db.prepare("UPDATE vaults SET body=? WHERE ws=? AND id=?").run("{broken", "w", "other-0");
    assert.deepEqual((await f.read("alice", "target")).body.items, [f.item]);
    await assert.rejects(f.read("alice"), SyntaxError);
  } finally { f.db.close(); }
});

test("a stored vault with a different body id or workspace is not returned for its database key", async () => {
  const f = fixture();
  try {
    const update = f.db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='target'");
    update.run(JSON.stringify({ ws: "w", id: "other-id", members: ["alice"] }));
    assert.equal((await f.read("alice", "target")).body.code, "vault_unknown");
    update.run(JSON.stringify({ ws: "another", id: "target", members: ["alice"] }));
    assert.equal((await f.read("alice", "target")).body.code, "vault_unknown");
  } finally { f.db.close(); }
});
