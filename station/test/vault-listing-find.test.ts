import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";
import type { Request } from "../src/vault/crypto.ts";

function fixture(path = ":memory:", count = 120) {
  const db = new DatabaseSync(path);
  if (path !== ":memory:") db.exec("PRAGMA journal_mode=WAL");
  let inspected = 0;
  let onRead: (() => void) | undefined;
  db.function("listing_seen", (_id: unknown) => {
    inspected++;
    const run = onRead; onRead = undefined; run?.();
    return 0;
  });
  const observed = new Proxy(db, { get(target, key) {
    if (key === "prepare") return (sql: string) => target.prepare(sql.replace(
      /SELECT (id, )?body FROM vault_plain WHERE ws = \? AND owner = \?/,
      "SELECT $1body, listing_seen(id) AS seen FROM vault_plain WHERE ws = ? AND owner = ?"));
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const plain = new PlainStore(observed), vaults = new VaultStore(db);
  for (let n = 0; n < count; n++) {
    const id = `i${String(n).padStart(3, "0")}`;
    const name = n === 1 || n === 3 ? "TÄRGET" : n === 2 ? "i100" : `key-${n}`;
    plain.put({ ws: "w", id, owner: "p@example.test", version: 0, kind: "token", name, fields: { value: "test-only" }, notes: "", at: 1000,
      ...(n === 0 ? {} : { listing: { name, kind: "token", modes: ["env"], hosts: [] } }) });
  }
  plain.put({ ws: "w", id: "i000-deleted", owner: "p@example.test", version: 1, kind: "token", name: "target", fields: {}, notes: "", at: 1000, deleted: true });
  plain.put({ ws: "w", id: "i000-other", owner: "other@example.test", version: 0, kind: "token", name: "target", fields: { value: "test-only" }, notes: "", at: 1000,
    listing: { name: "target", kind: "token", modes: ["env"], hosts: [] } });
  const prior = Promise.withResolvers<void>();
  const secrets = new Secrets({ db: observed, plain, vaults, data: ".", proxy: {} as never, now: () => 1_000_000, home: () => "w", lock: () => null,
    hub: { store: { getSession: () => ({ ws: "w", archivedAt: null }), starter: () => "p@example.test", latestThread: () => null, subscribe: () => {} } } as never,
    backfill: { previousGone: prior.promise } });
  const requested: Request[] = [];
  secrets.listen((request) => requested.push(request));
  return { db, secrets, requested, count: () => inspected, reset: () => { inspected = 0; },
    onRead: (run: () => void) => { onRead = run; }, prior };
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

for (const count of [31, 32, 33]) test(`a plain listing remains findable with ${count} entries around the prefix boundary`, async () => {
  const f = fixture(":memory:", count - 1);
  try {
    await f.secrets.ask("s", { item: `key-${count - 2}`, reason: "test" });
    assert.equal(f.requested.at(-1)?.item, `i${String(count - 2).padStart(3, "0")}`);
    await assert.rejects(f.secrets.ask("s", { item: "absent", reason: "test" }), /No secret named/);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("asking for a later or absent plain listing retains the full lookup result", async () => {
  const f = fixture();
  try {
    // The stored key, not a possibly old body's id, is the boundary of the ordered query.
    const raw = f.db.prepare("SELECT body FROM vault_plain WHERE ws=? AND id=?").get("w", "i030") as { body: string };
    const body = JSON.parse(raw.body); body.id = "z-old-body-id";
    f.db.prepare("UPDATE vault_plain SET body=? WHERE ws=? AND id=?").run(JSON.stringify(body), "w", "i030");
    await f.secrets.ask("s", { item: "key-119", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i119");
    await assert.rejects(f.secrets.ask("s", { item: "absent", reason: "test" }), /No secret named/);
    assert.equal(f.requested.length, 1);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("a prefix and its remaining items share a snapshot when another connection changes an earlier item", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-listing-find-")), path = join(dir, "db");
  const f = fixture(path), other = new DatabaseSync(path);
  try {
    const row = other.prepare("SELECT body FROM vault_plain WHERE ws=? AND id=?").get("w", "i004") as { body: string };
    const item = JSON.parse(row.body);
    item.listing.name = "fresh name";
    const later = other.prepare("SELECT body FROM vault_plain WHERE ws=? AND id=?").get("w", "i050") as { body: string };
    const laterItem = JSON.parse(later.body); laterItem.listing.name = "fresh name";
    other.prepare("UPDATE vault_plain SET body=? WHERE ws=? AND id=?").run(JSON.stringify(laterItem), "w", "i050");
    f.onRead(() => { other.prepare("UPDATE vault_plain SET body=? WHERE ws=? AND id=?").run(JSON.stringify(item), "w", "i004"); });
    await f.secrets.ask("s", { item: "fresh name", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i050");
    await f.secrets.ask("s", { item: "fresh name", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i004");
  } finally {
    f.prior.resolve(); await f.secrets.close(); other.close(); f.db.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a listing search releases its snapshot on success and on an unreadable prefix", async () => {
  const f = fixture();
  try {
    f.db.exec("BEGIN");
    await f.secrets.ask("s", { item: "tärget", reason: "test" });
    assert.equal(f.db.isTransaction, true);
    f.db.prepare("UPDATE vault_plain SET body=? WHERE ws=? AND id=?").run("{broken", "w", "i000");
    await assert.rejects(f.secrets.ask("s", { item: "tärget", reason: "test" }), SyntaxError);
    assert.equal(f.db.isTransaction, true);
    f.db.exec("ROLLBACK");
    assert.equal(f.db.prepare("SELECT count(*) AS n FROM vault_requests").get()?.n, 0);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});

test("an unreadable later item does not prevent asking for an earlier listed item", async () => {
  const f = fixture();
  try {
    f.db.prepare("UPDATE vault_plain SET body=? WHERE ws=? AND id=?").run("{broken", "w", "i119");
    await f.secrets.ask("s", { item: "tärget", reason: "test" });
    assert.equal(f.requested.at(-1)?.item, "i001");
    assert.throws(() => f.secrets.listings("s"), SyntaxError);
  } finally { f.prior.resolve(); await f.secrets.close(); f.db.close(); }
});
