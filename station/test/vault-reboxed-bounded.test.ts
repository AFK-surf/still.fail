import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { REBOX_LEGACY, REBOX_READY } from "../src/vault/rebox-index.ts";
import { Secrets } from "../src/vault/secrets.ts";

async function visited(others: number) {
  const db = new DatabaseSync(":memory:");
  let visited = 0, observing = false, traced = false;
  db.function("rebox_seen", (_id) => { if (observing) visited++; return 1; });
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      if (sql === REBOX_LEGACY) {
        traced = true;
        return target.prepare(sql.replace("WHERE status = 'pending'", "WHERE rebox_seen(id) AND status = 'pending'"));
      }
      if (sql === REBOX_READY) {
        traced = true;
        return target.prepare(sql.replace("WHERE r.status = 'pending'", "WHERE rebox_seen(p.id) AND r.status = 'pending'"));
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
    const put = (id: string, status: string) => insert.run(id, status, JSON.stringify({
      ws: "w", id, session: "s", vault: "vault", at: 0, item: "i", mode: "env", status, box: "old-box",
    }));
    put("waiting", "pending");
    for (let i = 0; i < others; i++) put(`done-${i}`, "denied");
    await secrets.preparePending("w");
    observing = true;
    secrets.reboxed();
    observing = false;
    const row = db.prepare("SELECT body FROM vault_requests WHERE ws='w' AND id='waiting'").get() as { body: string };
    assert.notEqual(JSON.parse(row.body).box, "old-box");
    assert.equal(traced, true);
    return visited;
  } finally { db.close(); }
}

test("recovering pending boxes does not read decided request history once the recovery index is ready", async () => {
  assert.deepEqual(await Promise.all([visited(40), visited(400)]), [1, 1]);
});

test("an older carried save finds its workspace without reading prepared history", async () => {
  async function visitHistory(others: number) {
    const db = new DatabaseSync(":memory:");
    let count = 0, observing = false, traced = false;
    db.function("rebox_seen", (_id) => { if (observing) count++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === REBOX_LEGACY) {
          traced = true;
          return target.prepare(sql.replace("WHERE status = 'pending'", "WHERE rebox_seen(id) AND status = 'pending'"));
        }
        if (sql === REBOX_READY) {
          traced = true;
          return target.prepare(sql.replace("WHERE r.status = 'pending'", "WHERE rebox_seen(p.id) AND r.status = 'pending'"));
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
      const put = (id: string, status: string) => insert.run(id, status, JSON.stringify({ ws: "w", id, session: "s", vault: "plain",
        owner: "alice@example.test", at: 0, item: "i", mode: "env", status, box: "", save: { typed: false } }));
      put("waiting", "pending");
      for (let i = 0; i < others; i++) put(`done-${i}`, "denied");
      await secrets.preparePending("w");
      observing = true;
      secrets.carry({ keeper: { boxes: [], held: [] }, unsaved: [["waiting", { value: "sample" }]] });
      await new Promise<void>((resolve) => setImmediate(resolve));
      observing = false;
      assert.deepEqual(secrets.carried().unsaved[0]?.[2], [{ ws: "w", owner: "alice@example.test" }]);
      assert.equal(traced, true);
      return count;
    } finally { db.close(); }
  }
  assert.deepEqual(await Promise.all([visitHistory(40), visitHistory(400)]), [1, 1]);
});

test("an old database can still recover a waiting box while its new index is being prepared", () => {
  const db = new DatabaseSync(":memory:");
  let usedLegacy = false;
  db.exec(`CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, status TEXT NOT NULL,
    body TEXT NOT NULL, thread INTEGER, card_ts TEXT, PRIMARY KEY (ws, id));`);
  db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','waiting','s','pending',?)")
    .run(JSON.stringify({ ws: "w", id: "waiting", session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending", box: "old" }));
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      if (sql === REBOX_LEGACY) usedLegacy = true;
      return target.prepare(sql);
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  try {
    const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    secrets.reboxed();
    assert.equal(usedLegacy, true);
    const row = db.prepare("SELECT body FROM vault_requests WHERE ws='w' AND id='waiting'").get() as { body: string };
    assert.notEqual(JSON.parse(row.body).box, "old");
  } finally { db.close(); }
});

test("recovering boxes keeps their existing order across workspaces", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "a", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    const insert = db.prepare("INSERT INTO vault_requests(rowid,ws,id,session,status,body) VALUES(?,?,?,'s','pending',?)");
    for (const [rowid, ws, id] of [[9007199254740993n, "b", "first"], [9007199254740994n, "a", "second"]] as const) {
      insert.run(rowid, ws, id, JSON.stringify({ ws, id, session: "s", vault: "v", item: "i", mode: "env", at: 0, status: "pending", box: "old" }));
    }
    await secrets.preparePending("a");
    const told: string[] = [];
    secrets.listen((request) => told.push(request.id));
    secrets.reboxed();
    assert.deepEqual(told, ["first", "second"]);
  } finally { db.close(); }
});

test("recovering boxes sees one snapshot even while the previous process writes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "rebox-snapshot-"));
  const db = new DatabaseSync(join(dir, "station.db"));
  db.exec("PRAGMA journal_mode=WAL");
  const writer = new DatabaseSync(join(dir, "station.db"));
  let wrote = false, observing = false;
  const request = (ws: string, id: string) => JSON.stringify({ ws, id, session: "s", vault: "v", item: "i", mode: "env", at: 0, status: "pending", box: "old" });
  db.function("rebox_write", () => {
    if (observing && !wrote) {
      wrote = true;
      writer.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('b','later','s','pending',?)").run(request("b", "later"));
    }
    return 1;
  });
  const observed = new Proxy(db, { get(target, property) {
    if (property === "location") return () => null; // Use this connection for preparation; the second connection tests the snapshot.
    if (property === "prepare") return (sql: string) => target.prepare(sql === REBOX_READY
      ? sql.replace("WHERE r.status = 'pending'", "WHERE rebox_write() AND r.status = 'pending'") : sql);
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  try {
    const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "a", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,?,'s','pending',?)");
    insert.run("a", "first", request("a", "first"));
    insert.run("b", "second", request("b", "second"));
    await secrets.preparePending("a");
    const told: string[] = [];
    secrets.listen((r) => told.push(r.id));
    observing = true;
    secrets.reboxed();
    observing = false;
    assert.equal(wrote, true);
    assert.deepEqual(told, ["first", "second"]);
    const row = db.prepare("SELECT body FROM vault_requests WHERE ws='b' AND id='later'").get() as { body: string };
    assert.equal(JSON.parse(row.body).box, "old");
  } finally { writer.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
