import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PENDING_BODIES } from "../src/vault/pending-index.ts";
import { PLAIN } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";

async function visited(kind: "history" | "pending", others: number) {
  const db = new DatabaseSync(":memory:");
  let count = 0, traced = false, reading = false;
  db.function("pending_seen", (_id) => { if (reading) count++; return 1; });
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      if (sql === PENDING_BODIES) {
        traced = true;
        return target.prepare(sql.replace("WHERE p.ws = ?", "WHERE pending_seen(p.id) AND p.ws = ?"));
      }
      return target.prepare(sql);
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  try {
    const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s',?,?)");
    const put = (id: string, owner: string, status: string) => insert.run(id, status, JSON.stringify({
      ws: "w", id, session: "s", vault: PLAIN, owner, at: 0, item: "i", mode: "env", status,
    }));
    put("mine", "alice@example.test", "pending");
    for (let i = 0; i < others; i++) put(`other-${i}`, "bob@example.test", kind === "pending" ? "pending" : "denied");
    await secrets.preparePending("w");
    reading = true;
    const rows = secrets.pending("w", null, { sub: "alice", email: "alice@example.test" });
    reading = false;
    assert.deepEqual(rows.map((r) => r.id), ["mine"]);
    assert.equal(traced, true);
    return count;
  } finally { db.close(); }
}

test("a prepared pending lookup does not traverse decided history", async () => {
  assert.deepEqual(await Promise.all([visited("history", 40), visited("history", 400)]), [1, 1]);
});

test("a prepared pending lookup does not traverse another person's waiting requests", async () => {
  assert.deepEqual(await Promise.all([visited("pending", 40), visited("pending", 400)]), [1, 1]);
});

test("reading a prepared list still expires another person's overdue request", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 100_000_000, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    const put = (id: string, owner: string, at: number) => insert.run(id, JSON.stringify({
      ws: "w", id, session: "s", vault: PLAIN, owner, at, item: "i", mode: "env", status: "pending",
    }));
    put("mine", "alice@example.test", 100_000);
    put("other", "bob@example.test", 0);
    const told: [string, string][] = [];
    secrets.listen((request) => told.push([request.id, request.status]));
    await secrets.preparePending("w");
    assert.deepEqual(secrets.pending("w", null, { sub: "alice", email: "alice@example.test" }).map((r) => r.id), ["mine"]);
    assert.deepEqual(told, [["other", "expired"]]);
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='w' AND id='other'").get() as { status: string }).status, "expired");
  } finally { db.close(); }
});
