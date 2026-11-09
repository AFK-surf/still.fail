import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { newBoxPair, openSeal, saveContext, type BoxCert } from "../src/vault/crypto.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

test("a newly published device reads only its owner's waiting secrets", () => {
  const visits: number[] = [];
  for (const others of [40, 400]) {
    const db = new DatabaseSync(":memory:");
    let visited = 0, tracing = false;
    db.function("boxed_seen", (_id) => { if (tracing) visited++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (/^SELECT\b.*\bFROM vault_requests\b/is.test(sql) && /\bWHERE\b/i.test(sql)) {
          return target.prepare(sql.replace(/\bWHERE\b/i, "WHERE boxed_seen(id) AND"));
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const vaults = new VaultStore(observed);
      const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => null,
        hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
        proxy: {} as never, vaults, plain: {} as never });
      const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s',?,?)");
      const put = (id: string, owner: string, status: string) => insert.run(id, status, JSON.stringify({
        ws: "w", id, session: "s", vault: "v", owner, at: 0, item: "i", mode: "env", status,
        box: "", save: { kind: "token", name: id, modes: ["env"], hosts: [] }, sealed: [],
      }));
      put("mine", "alice@example.test", "pending");
      const unsaved: [string, Record<string, string>][] = [["mine", { value: "test-secret" }]];
      for (let i = 0; i < others; i++) {
        const id = `other-${i}`;
        put(id, "bob@example.test", "pending");
        unsaved.push([id, { value: "other-secret" }]);
      }
      secrets.carry({ keeper: { boxes: [], held: [] }, unsaved });
      secrets.reboxed();
      const box = newBoxPair();
      const cert = { device: "alice-device", box: box.pub } as BoxCert;
      db.prepare("INSERT INTO vault_boxes(ws,device,body) VALUES('w',?,?)").run(cert.device, JSON.stringify(cert));
      const lock = { ws: "w", devices: new Map([[cert.device, { sub: "alice" }]]),
        members: new Map([["alice", { email: "alice@example.test" }]]) };
      tracing = true;
      secrets.boxed(lock as never, cert);
      tracing = false;
      const saved = JSON.parse((db.prepare("SELECT body FROM vault_requests WHERE ws = 'w' AND id = 'mine'").get() as { body: string }).body);
      assert.deepEqual(JSON.parse(Buffer.from(openSeal(box.priv, saved.sealed[0].secret, saveContext("w", "mine"))).toString()), { value: "test-secret" });
      visits.push(visited);
    } finally { db.close(); }
  }
  assert.equal(visits[0], visits[1]);
  assert.ok(visits[0]! <= 1);
});

test("an older handover can write its pending save after reboxing", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const vaults = new VaultStore(db);
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults, plain: {} as never });
    secrets.carry({ keeper: { boxes: [], held: [] }, unsaved: [["mine", { value: "test-secret" }]] });
    secrets.reboxed();
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','mine','s','pending',?)").run(JSON.stringify({
      ws: "w", id: "mine", session: "s", vault: "v", owner: "alice@example.test", at: 0, item: "i", mode: "env", status: "pending",
      box: "", save: { kind: "token", name: "mine", modes: ["env"], hosts: [] }, sealed: [],
    }));
    const box = newBoxPair();
    const cert = { device: "alice-device", box: box.pub } as BoxCert;
    db.prepare("INSERT INTO vault_boxes(ws,device,body) VALUES('w',?,?)").run(cert.device, JSON.stringify(cert));
    const lock = { ws: "w", devices: new Map([[cert.device, { sub: "alice" }]]),
      members: new Map([["alice", { email: "alice@example.test" }]]) };
    secrets.boxed(lock as never, cert);
    const saved = JSON.parse((db.prepare("SELECT body FROM vault_requests WHERE ws = 'w' AND id = 'mine'").get() as { body: string }).body);
    assert.deepEqual(JSON.parse(Buffer.from(openSeal(box.priv, saved.sealed[0].secret, saveContext("w", "mine"))).toString()), { value: "test-secret" });
  } finally { db.close(); }
});

test("a newly registered device looks up only the older handover's save ids", async () => {
  const visits: number[] = [];
  for (const others of [40, 400]) {
    const db = new DatabaseSync(":memory:");
    let exited!: () => void;
    const previousGone = new Promise<void>((resolve) => { exited = resolve; });
    let visited = 0, tracing = false;
    db.function("boxed_seen", (_id) => { if (tracing) visited++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (/^SELECT\b.*\bFROM vault_requests\b/is.test(sql) && /\bWHERE\b/i.test(sql)) {
          return target.prepare(sql.replace(/\bWHERE\b/i, "WHERE boxed_seen(id) AND"));
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const vaults = new VaultStore(observed);
      const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => null,
        hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
        proxy: {} as never, vaults, plain: {} as never, backfill: { previousGone } });
      const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s',?,?)");
      const put = (id: string, status: string, owner: string) => insert.run(id, status, JSON.stringify({
        ws: "w", id, session: "s", vault: "v", owner, at: 0, item: "i", mode: "env", status,
        box: "", save: { kind: "token", name: id, modes: ["env"], hosts: [] }, sealed: [],
      }));
      put("mine", "pending", "alice@example.test");
      for (let i = 0; i < others; i++) put(`other-${i}`, i % 2 ? "denied" : "pending", "bob@example.test");
      secrets.carry({ keeper: { boxes: [], held: [] }, unsaved: [["mine", { value: "test-secret" }]] });
      const box = newBoxPair();
      const cert = { device: "alice-device", box: box.pub } as BoxCert;
      db.prepare("INSERT INTO vault_boxes(ws,device,body) VALUES('w',?,?)").run(cert.device, JSON.stringify(cert));
      const lock = { ws: "w", devices: new Map([[cert.device, { sub: "alice" }]]),
        members: new Map([["alice", { email: "alice@example.test" }]]) };
      tracing = true;
      secrets.boxed(lock as never, cert);
      tracing = false;
      const saved = JSON.parse((db.prepare("SELECT body FROM vault_requests WHERE ws='w' AND id='mine'").get() as { body: string }).body);
      assert.deepEqual(JSON.parse(Buffer.from(openSeal(box.priv, saved.sealed[0].secret, saveContext("w", "mine"))).toString()), { value: "test-secret" });
      visits.push(visited);
    } finally { exited(); await new Promise<void>((resolve) => setImmediate(resolve)); db.close(); }
  }
  assert.deepEqual(visits, [2, 2]);
});

test("a device tells its owner's waiting requests in their existing order", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const vaults = new VaultStore(db);
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults, plain: {} as never });
    const unsaved: [string, Record<string, string>, { ws: string; owner: string }[]][] = [];
    for (const id of ["z", "a"]) {
      db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)").run(id, JSON.stringify({
        ws: "w", id, session: "s", vault: "v", owner: "alice@example.test", at: 0, item: "i", mode: "env", status: "pending",
        box: "", save: { kind: "token", name: id, modes: ["env"], hosts: [] }, sealed: [],
      }));
      unsaved.push([id, { value: "test-secret" }, [{ ws: "w", owner: "alice@example.test" }]]);
    }
    secrets.carry({ keeper: { boxes: [], held: [] }, unsaved });
    const told: string[] = [];
    secrets.listen((r) => told.push(r.id));
    const box = newBoxPair();
    const cert = { device: "alice-device", box: box.pub } as BoxCert;
    db.prepare("INSERT INTO vault_boxes(ws,device,body) VALUES('w',?,?)").run(cert.device, JSON.stringify(cert));
    const lock = { ws: "w", devices: new Map([[cert.device, { sub: "alice" }]]),
      members: new Map([["alice", { email: "alice@example.test" }]]) };
    secrets.boxed(lock as never, cert);
    assert.deepEqual(told, ["a", "z"]);
    const before = db.prepare("SELECT total_changes() AS n").get() as { n: number };
    secrets.boxed(lock as never, cert);
    const after = db.prepare("SELECT total_changes() AS n").get() as { n: number };
    assert.equal(after.n, before.n, "the same device does not write the requests again");
    assert.deepEqual(told, ["a", "z"]);
  } finally { db.close(); }
});
