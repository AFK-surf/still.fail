import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PENDING_DUE, PENDING_MEMBER, PENDING_NO_TIME, PENDING_OTHER_TIME, PENDING_OWN } from "../src/vault/pending-index.ts";
import { PLAIN } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

async function visited(kind: "history" | "pending", others: number) {
  const db = new DatabaseSync(":memory:");
  let count = 0, traced = false, reading = false;
  db.function("pending_seen", (_id) => { if (reading) count++; return 1; });
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      if ([PENDING_OWN, PENDING_DUE, PENDING_NO_TIME, PENDING_OTHER_TIME].includes(sql)) {
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

test("a pending list reads its member vaults and follows membership changes", async () => {
  const db = new DatabaseSync(":memory:");
  let seen = 0, reading = false;
  db.function("pending_seen", (_id) => { if (reading) seen++; return 1; });
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => target.prepare(sql === PENDING_MEMBER
      ? sql.replace("AND p.ws = m.ws", "AND pending_seen(p.id) AND p.ws = m.ws") : sql);
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  try {
    const vaults = new VaultStore(observed);
    const putVault = (id: string, members: string[]) => vaults.putVault({ ws: "w", id, seq: 0, members } as never);
    putVault("mine", ["alice"]);
    putVault("theirs", ["bob"]);
    const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults, plain: {} as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    const put = (id: string, vault: string) => insert.run(id, JSON.stringify({ ws: "w", id, session: "s", vault, at: 0, item: "i", mode: "env", status: "pending" }));
    put("mine", "mine");
    for (let i = 0; i < 400; i++) put(`other-${i}`, "theirs");
    await secrets.preparePending("w");
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${PENDING_MEMBER}`).all("w", "alice") as { detail: string }[]).map((row) => row.detail).join("\n");
    assert.match(plan, /SEARCH m USING PRIMARY KEY/);
    assert.match(plan, /SEARCH p USING (?:COVERING )?INDEX vault_pending_vault/);
    assert.match(plan, /SEARCH r USING INDEX/);
    const viewer = { sub: "alice", email: "alice@example.test" }, lock = { ws: "w" } as never;
    reading = true;
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["mine"]);
    reading = false;
    assert.equal(seen, 1);
    putVault("mine", ["bob"]);
    assert.deepEqual(secrets.pending("w", lock, viewer), []);
    putVault("mine", ["alice"]);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["mine"]);
  } finally { db.close(); }
});

test("preparing a pending list waits for the previous process to finish writing", async () => {
  const db = new DatabaseSync(":memory:");
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => null, backfill: { previousGone },
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    let ready = false;
    const preparing = secrets.preparePending("w").then(() => { ready = true; });
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(ready, false);
    const request = { ws: "w", id: "lost", session: "s", vault: PLAIN, owner: "bob@example.test", at: 0,
      item: "i", mode: "env", status: "pending", save: { typed: false } };
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','lost','s','pending',?)").run(JSON.stringify(request));
    exited();
    await preparing;
    secrets.pending("w", null, { sub: "alice", email: "alice@example.test" });
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='w' AND id='lost'").get() as { status: string }).status, "expired");
  } finally { exited(); db.close(); }
});

test("a later handover keeps a save even after the pending list was prepared", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    const request = { ws: "w", id: "save", session: "s", vault: PLAIN, owner: "bob@example.test", at: 0,
      item: "i", mode: "env", status: "pending", save: { typed: false } };
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','save','s','pending',?)").run(JSON.stringify(request));
    await secrets.preparePending("w");
    secrets.carry({ keeper: { boxes: [], held: [] }, unsaved: [["save", { value: "secret" }, [{ ws: "w", owner: "bob@example.test" }]]] });
    assert.deepEqual(secrets.pending("w", null, { sub: "bob", email: "bob@example.test" }).map((r) => r.id), ["save"]);
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='w' AND id='save'").get() as { status: string }).status, "pending");
    await new Promise<void>((resolve) => setImmediate(resolve));
  } finally { db.close(); }
});

test("other people's carried saves do not get read on every prepared list", async () => {
  async function visits(n: number) {
    const db = new DatabaseSync(":memory:");
    let reads = 0, reading = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (reading && sql.startsWith("SELECT body, thread, card_ts FROM vault_requests WHERE ws = ? AND id = ?")) reads++;
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => null,
        hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
        proxy: {} as never, vaults: {} as never, plain: {} as never });
      const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
      const carried: ReturnType<Secrets["carried"]> = { keeper: { boxes: [], held: [] }, unsaved: [] };
      for (let i = 0; i < n; i++) {
        const id = `other-${i}`;
        const request = { ws: "w", id, session: "s", vault: PLAIN, owner: "bob@example.test", at: 0,
          item: "i", mode: "env", status: "pending", save: { typed: false } };
        insert.run(id, JSON.stringify(request));
        carried.unsaved.push([id, { value: "secret" }, [{ ws: "w", owner: "bob@example.test" }]]);
      }
      secrets.carry(carried);
      await secrets.preparePending("w");
      reading = true;
      assert.deepEqual(secrets.pending("w", null, { sub: "alice", email: "alice@example.test" }), []);
      reading = false;
      return reads;
    } finally { db.close(); }
  }
  assert.deepEqual(await Promise.all([visits(40), visits(400)]), [0, 0]);
});

test("a prepared list settles other people's lost and overdue saves in request order", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 100_000_000, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    const put = (id: string, fields: Record<string, unknown>) => insert.run(id, JSON.stringify({
      ws: "w", id, session: "s", vault: PLAIN, owner: "bob@example.test", at: 100_000, item: "i", mode: "env", status: "pending", ...fields,
    }));
    put("a-lost", { save: { typed: false } });
    put("b-overdue", { at: 0 });
    put("c-bad-time", { at: null });
    put("d-string-time", { at: "1" }); // JavaScript adds before comparing: '1' + 86400 is 186400.
    put("mine", { owner: "alice@example.test" });
    const told: [string, string][] = [];
    secrets.listen((r) => told.push([r.id, r.status]));
    await secrets.preparePending("w");
    assert.deepEqual(secrets.pending("w", null, { sub: "alice", email: "alice@example.test" }).map((r) => r.id), ["mine"]);
    assert.deepEqual(told, [["a-lost", "expired"], ["b-overdue", "expired"], ["c-bad-time", "expired"]]);
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='w' AND id='d-string-time'").get() as { status: string }).status, "pending");
  } finally { db.close(); }
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
