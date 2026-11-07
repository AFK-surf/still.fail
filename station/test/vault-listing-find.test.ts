import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";
import type { Request } from "../src/vault/crypto.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  let inspected = 0;
  db.function("listing_seen", (_id: unknown) => { inspected++; return 0; });
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => target.prepare(sql.replace(
      "SELECT body FROM vault_plain WHERE ws = ? AND owner = ?", "SELECT body, listing_seen(id) AS seen FROM vault_plain WHERE ws = ? AND owner = ?"));
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const plain = new PlainStore(observed), vaults = new VaultStore(db);
  for (let n = 0; n < 120; n++) {
    const id = `i${String(n).padStart(3, "0")}`;
    const name = n === 1 ? "TÄRGET" : n === 2 ? "i100" : `key-${n}`;
    plain.put({ ws: "w", id, owner: "p@example.test", version: 0, kind: "token", name, fields: { value: "test-only" }, notes: "", at: 1000,
      ...(n === 0 ? {} : { listing: { name, kind: "token", modes: ["env"], hosts: [] } }) });
  }
  plain.put({ ws: "w", id: "i000-other", owner: "other@example.test", version: 0, kind: "token", name: "target", fields: { value: "test-only" }, notes: "", at: 1000,
    listing: { name: "target", kind: "token", modes: ["env"], hosts: [] } });
  const prior = Promise.withResolvers<void>();
  const secrets = new Secrets({ db: observed, plain, vaults, data: ".", proxy: {} as never, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ ws: "w", archivedAt: null }), starter: () => "p@example.test", latestThread: () => null, subscribe: () => {} } } as never,
    backfill: { previousGone: prior.promise } });
  const requested: Request[] = [];
  secrets.listen((request) => requested.push(request));
  return { db, secrets, requested, count: () => inspected, reset: () => { inspected = 0; }, prior };
}

test("asking for an early plain listing need not read all the owner's later items", async () => {
  const f = fixture();
  try {
    f.reset();
    await f.secrets.ask("s", { item: "  tärget  ", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i001");
    assert.ok(f.count() <= 40, `read ${f.count()} item bodies`);

    // A name before an exact item id wins, just as in the full ordered list.
    f.reset();
    await f.secrets.ask("s", { item: "I100", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i002");
    assert.ok(f.count() <= 40, `read ${f.count()} item bodies`);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("asking for a later or absent plain listing retains the full lookup result", async () => {
  const f = fixture();
  try {
    await f.secrets.ask("s", { item: "key-119", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i119");
    await assert.rejects(f.secrets.ask("s", { item: "absent", reason: "test" }), /No secret named/);
    assert.equal(f.requested.length, 1);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});
