import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

for (const [subCode, emailCode] of [[0xd800, 0xdc00], [0xdc00, 0xd800]]) {
  test(`pending requests keep isolated surrogate identities (${subCode.toString(16)}, ${emailCode.toString(16)})`, async () => {
    const db = new DatabaseSync(":memory:"), vaults = new VaultStore(db), sub = String.fromCharCode(subCode);
    const email = `${String.fromCharCode(emailCode)}@example.test`;
    vaults.putVault({ ws: "w", id: "v", seq: 0, members: [sub] } as never);
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults, plain: {} as never });
    try {
      const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
      insert.run("member", JSON.stringify({ ws: "w", id: "member", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
      insert.run("owner", JSON.stringify({ ws: "w", id: "owner", session: "s", vault: "plain", owner: email,
        at: 0, item: "i", mode: "env", status: "pending" }));
      const member = () => secrets.pending("w", { ws: "w" } as never, { sub, email: "alice@example.test" }).map((r) => r.id);
      const owner = (locked: boolean) => secrets.pending("w", locked ? { ws: "w" } as never : null, { sub: "alice", email }).map((r) => r.id);
      assert.deepEqual(member(), ["member"]);
      assert.deepEqual(owner(true), ["owner"]);
      assert.deepEqual(owner(false), ["owner"]);
      await secrets.preparePending("w", true);
      assert.deepEqual(member(), ["member"]);
      assert.deepEqual(owner(true), ["owner"]);
      assert.deepEqual(owner(false), ["owner"]);
    } finally { await secrets.close(); db.close(); }
  });
}
