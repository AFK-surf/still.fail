import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

function world() {
  const db = new DatabaseSync(":memory:");
  const vaults = new VaultStore(db);
  vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["bob"] } as never);
  const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults, plain: {} as never });
  db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','pending',?)")
    .run(JSON.stringify({ ws: "w", id: "r", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
  const duplicate = () => db.prepare("UPDATE vaults SET body=? WHERE ws='w' AND id='v'")
    .run('{"ws":"w","id":"v","members":["bob"],"members":["alice"]}');
  const pending = (sub: string) => secrets.pending("w", { ws: "w" } as never, { sub, email: `${sub}@example.test` }).map((r) => r.id);
  return { db, secrets, duplicate, pending };
}

test("preparing a member lookup keeps the last members field of an old vault", async () => {
  const f = world();
  try {
    f.duplicate();
    assert.deepEqual(f.pending("alice"), ["r"]);
    await f.secrets.preparePending("w", true);
    assert.deepEqual(f.pending("alice"), ["r"]);
    assert.deepEqual(f.pending("bob"), []);
  } finally { await f.secrets.close(); f.db.close(); }
});

test("a duplicate members field written after preparation is checked from its last value", async () => {
  const f = world();
  try {
    await f.secrets.preparePending("w", true);
    assert.deepEqual(f.pending("alice"), []);
    f.duplicate();
    assert.deepEqual(f.pending("alice"), ["r"]);
    assert.deepEqual(f.pending("bob"), []);
  } finally { await f.secrets.close(); f.db.close(); }
});
