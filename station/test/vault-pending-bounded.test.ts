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

test("an unlocked pending list does not prepare old vault memberships", async () => {
  async function visits(n: number) {
    const db = new DatabaseSync(":memory:");
    db.exec("CREATE TABLE vaults(ws TEXT NOT NULL,id TEXT NOT NULL,seq INTEGER NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))");
    const insert = db.prepare("INSERT INTO vaults VALUES('w',?,0,?)");
    for (let i = 0; i < n; i++) insert.run(`v-${i}`, JSON.stringify({ members: ["somebody"] }));
    let seen = 0;
    db.function("vault_seen", (_id) => { seen++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql.startsWith("SELECT id FROM vaults WHERE ws = ?")
        ? sql.replace("SELECT id FROM", "SELECT id, vault_seen(id) AS observed FROM") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => null,
        hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
        proxy: {} as never, vaults: new VaultStore(observed), plain: {} as never });
      await secrets.preparePending("w");
      assert.deepEqual(secrets.pending("w", null, { sub: "alice", email: "alice@example.test" }), []);
      return seen;
    } finally { db.close(); }
  }
  assert.deepEqual(await Promise.all([visits(40), visits(400)]), [0, 0]);
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
    assert.match(plan, /SEARCH p USING (?:COVERING )?INDEX vault_pending_decider/);
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

test("a pending list checks each member vault once, however many of its requests wait", async () => {
  async function vaultReads(n: number) {
    const db = new DatabaseSync(":memory:");
    let reads = 0, reading = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (reading && sql === "SELECT body FROM vaults WHERE ws = ? AND id = ?") reads++;
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const vaults = new VaultStore(observed);
      vaults.putVault({ ws: "w", id: "v", seq: 0, members: ["alice"] } as never);
      const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
        hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
        proxy: {} as never, vaults, plain: {} as never });
      const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
      for (let i = 0; i < n; i++) {
        const id = `r-${i}`;
        insert.run(id, JSON.stringify({ ws: "w", id, session: "s", vault: "v", at: 0, item: "i", mode: "env", status: "pending" }));
      }
      await secrets.preparePending("w");
      reading = true;
      assert.equal(secrets.pending("w", { ws: "w" } as never, { sub: "alice", email: "alice@example.test" }).length, n);
      reading = false;
      return reads;
    } finally { db.close(); }
  }
  assert.deepEqual(await Promise.all([vaultReads(40), vaultReads(400)]), [1, 1]);
});

test("an unreadable old vault preserves the original request-list behavior until rewritten", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE vaults(ws TEXT NOT NULL,id TEXT NOT NULL,seq INTEGER NOT NULL,body TEXT NOT NULL,PRIMARY KEY(ws,id))");
    db.prepare("INSERT INTO vaults VALUES('w','broken',0,?)").run("{broken");
    const vaults = new VaultStore(db);
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => ({ ws: "w" } as never),
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults, plain: {} as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w',?,'s','pending',?)");
    const put = (id: string, vault: string) => insert.run(id, JSON.stringify({ ws: "w", id, session: "s", vault,
      owner: "alice@example.test", at: 0, item: "i", mode: "env", status: "pending" }));
    put("mine", PLAIN);
    await secrets.preparePending("w");
    const viewer = { sub: "alice", email: "alice@example.test" }, lock = { ws: "w" } as never;
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["mine"]);
    put("waiting", "broken");
    assert.throws(() => secrets.pending("w", lock, viewer), SyntaxError);
    vaults.putVault({ ws: "w", id: "broken", seq: 1, members: ["alice"] } as never);
    assert.deepEqual(secrets.pending("w", lock, viewer).map((r) => r.id), ["mine", "waiting"]);
  } finally { db.close(); }
});

test("pending lists remain available while the previous process is still writing", async () => {
  const db = new DatabaseSync(":memory:");
  let exited!: () => void;
  const previousGone = new Promise<void>((resolve) => { exited = resolve; });
  let coming = true;
  let preparing: Promise<void> | undefined;
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "w", lock: () => null, backfill: { previousGone }, coming: () => coming,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults: {} as never, plain: {} as never });
    preparing = secrets.preparePending("w");
    assert.equal(await Promise.race([preparing.then(() => true), new Promise<boolean>((resolve) => setImmediate(() => resolve(false)))]), true);
    const request = { ws: "w", id: "lost", session: "s", vault: PLAIN, owner: "bob@example.test", at: 0,
      item: "i", mode: "env", status: "pending", save: { typed: false } };
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','lost','s','pending',?)").run(JSON.stringify(request));
    assert.deepEqual(secrets.pending("w", null, { sub: "bob", email: "bob@example.test" }).map((r) => r.id), ["lost"]);
    coming = false;
    exited();
    await new Promise<void>((resolve) => setImmediate(resolve));
    await secrets.preparePending("w");
    secrets.pending("w", null, { sub: "alice", email: "alice@example.test" });
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='w' AND id='lost'").get() as { status: string }).status, "expired");
  } finally { exited(); await preparing?.catch(() => {}); db.close(); }
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

test("forgetting a carried save rechecks the same request id in its other workspaces", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "a", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } }, notify() {} } as never,
      proxy: {} as never, vaults: {} as never, plain: { item: () => null } as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,'same','s','pending',?)");
    for (const ws of ["a", "b"]) insert.run(ws, JSON.stringify({ ws, id: "same", session: "s", vault: PLAIN,
      owner: "bob@example.test", at: 0, item: "i", mode: "env", status: "pending", save: { typed: false } }));
    secrets.carry({ keeper: { boxes: [], held: [] }, unsaved: [["same", { value: "secret" }, [
      { ws: "a", owner: "bob@example.test" }, { ws: "b", owner: "bob@example.test" },
    ]]] });
    await Promise.all([secrets.preparePending("a"), secrets.preparePending("b")]);
    assert.equal(secrets.denyPlain("a", "bob@example.test", { request: "same" }), null);
    secrets.pending("b", null, { sub: "alice", email: "alice@example.test" });
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='b' AND id='same'").get() as { status: string }).status, "expired");
  } finally { db.close(); }
});

test("an old unscoped handover forgotten immediately restores lost saves in other workspaces", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "a", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } }, notify() {} } as never,
      proxy: {} as never, vaults: {} as never, plain: { item: () => null } as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,'same','s','pending',?)");
    for (const ws of ["a", "b"]) insert.run(ws, JSON.stringify({ ws, id: "same", session: "s", vault: PLAIN,
      owner: "bob@example.test", at: 0, item: "i", mode: "env", status: "pending", save: { typed: false } }));
    await Promise.all([secrets.preparePending("a"), secrets.preparePending("b")]);
    secrets.carry({ keeper: { boxes: [], held: [] }, unsaved: [["same", { value: "secret" }]] });
    assert.equal(secrets.denyPlain("a", "bob@example.test", { request: "same" }), null);
    secrets.pending("b", null, { sub: "alice", email: "alice@example.test" });
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='b' AND id='same'").get() as { status: string }).status, "expired");
    await new Promise<void>((resolve) => setImmediate(resolve));
  } finally { db.close(); }
});

test("a held request discovered in another workspace is reconsidered when its fields are forgotten", async () => {
  const db = new DatabaseSync(":memory:");
  try {
    const secrets = new Secrets({ db, data: ".", now: () => 0, home: () => "a", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } }, notify() {} } as never,
      proxy: {} as never, vaults: {} as never, plain: { item: () => null } as never });
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,'same','s','pending',?)");
    for (const ws of ["a", "b"]) insert.run(ws, JSON.stringify({ ws, id: "same", session: "s", vault: PLAIN,
      owner: "bob@example.test", at: 0, item: "i", mode: "env", status: "pending", save: { typed: false } }));
    secrets.carry({ keeper: { boxes: [], held: [] }, unsaved: [["same", { value: "secret" }, [
      { ws: "a", owner: "bob@example.test" },
    ]]] });
    await Promise.all([secrets.preparePending("a"), secrets.preparePending("b")]);
    assert.equal(secrets.denyPlain("a", "bob@example.test", { request: "same" }), null);
    secrets.pending("b", null, { sub: "alice", email: "alice@example.test" });
    assert.equal((db.prepare("SELECT status FROM vault_requests WHERE ws='b' AND id='same'").get() as { status: string }).status, "expired");
  } finally { db.close(); }
});

test("the prepared list has the same results and expiry events as the original across request kinds", async () => {
  async function world(prepared: boolean) {
    const db = new DatabaseSync(":memory:");
    const vaults = new VaultStore(db);
    const putVault = (id: string, members: string[]) => vaults.putVault({ ws: "w", id, seq: 0, members } as never);
    putVault("a", ["alice"]); putVault("b", ["bob"]); putVault("shared", ["alice", "bob"]);
    let now = 100_000_000;
    const secrets = new Secrets({ db, data: ".", now: () => now, home: () => "w", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
      proxy: {} as never, vaults, plain: {} as never });
    const events: [string, string][] = [];
    secrets.listen((r) => events.push([r.id, r.status]));
    const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,?,'s',?,?)");
    const carries: ReturnType<Secrets["carried"]> = { keeper: { boxes: [], held: [] }, unsaved: [] };
    const saves = [undefined, false, { typed: true }, { typed: false }] as const;
    const times = [0, 13_600, 13_601, 100_000, null, "1", undefined] as const;
    const names = [PLAIN, "a", "b", "shared", "missing"] as const;
    for (let i = 0; i < 120; i++) {
      const ws = i % 11 === 0 ? "other" : "w", id = `r-${String(i).padStart(3, "0")}`;
      const status = i % 9 === 0 ? "denied" : "pending", owner = i % 3 === 0 ? "alice@example.test" : "bob@example.test";
      const request = { ws, id, session: "s", status, owner, vault: names[i % names.length], at: times[i % times.length],
        item: "i", mode: "env", save: saves[i % saves.length], sealed: i % 7 === 0 ? [{}] : [] };
      insert.run(ws, id, status, JSON.stringify(request));
      if (status === "pending" && i % 13 === 0) carries.unsaved.push([id, { value: "held" }, [{ ws, owner }]]);
    }
    secrets.carry(carries);
    await new Promise<void>((resolve) => setImmediate(resolve));
    if (prepared) await secrets.preparePending("w", true);
    const state = () => ({ events: [...events], rows: db.prepare("SELECT ws,id,status FROM vault_requests ORDER BY ws,id").all() });
    return { db, secrets, putVault, state, advance: () => { now = 200_000_000; } };
  }
  const slow = await world(false), fast = await world(true);
  try {
    const lock = { ws: "w" } as never;
    for (const [sub, email] of [["alice", "alice@example.test"], ["bob", "bob@example.test"]] as const) {
      if (sub === "bob") {
        slow.putVault("a", ["bob"]); fast.putVault("a", ["bob"]);
        slow.advance(); fast.advance();
      }
      const viewer = { sub, email };
      assert.deepEqual(fast.secrets.pending("w", lock, viewer), slow.secrets.pending("w", lock, viewer));
      assert.deepEqual(fast.state(), slow.state());
    }
  } finally { slow.db.close(); fast.db.close(); }
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
