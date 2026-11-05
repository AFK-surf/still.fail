import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Held } from "../src/vault/keeper.ts";
import { PLAIN } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  let visited = 0;
  const deletes: string[] = [];
  db.function("grant_seen", (_ws, _id) => { visited++; return 1; });
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      if (sql.startsWith("DELETE FROM vault_grants WHERE ")) {
        deletes.push(sql);
        return target.prepare(sql.replace(" WHERE ", " WHERE grant_seen(ws,id) AND "));
      }
      return target.prepare(sql);
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const secrets = new Secrets({ db: observed, data: ".", now: () => 0, home: () => "w", lock: () => null,
    hub: { store: { subscribe() {}, getSession() { return {}; } } } as never,
    proxy: {} as never, vaults: {} as never, plain: {} as never });
  const insert = db.prepare("INSERT INTO vault_grants(ws,id,session,body) VALUES(?,?,'s','{}')");
  const held = (ws: string, id: string, vault: string): Held => ({
    request: { ws, id, session: "s", vault, item: "i", chat: "", mode: "env", reason: "", box: "", at: 0, status: "granted" },
    grant: { v: 1, ws, request: id, vault, item: "i", mode: "env", hosts: [], scope: "chat", exp: 1000,
      secret: "", at: 0, sig: { key: "", alg: "Ed25519", sig: "" } },
    secret: { kind: "token", name: "token", fields: { value: "x" } }, uses: 0 });
  return { db, secrets, insert, held, deletes, visits: () => visited, reset: () => { visited = 0; deletes.length = 0; } };
}

test("forgetting a plain grant does not traverse grants of other workspaces", () => {
  const visits: number[] = [], plans: string[] = [];
  for (const others of [40, 400]) {
    const f = fixture();
    try {
      for (let i = 0; i < others; i++) f.insert.run(`other-${i}`, `other-${i}`);
      f.insert.run("w", "mine");
      f.secrets.keeper.restore(f.held("w", "mine", PLAIN));
      f.reset();
      f.secrets.keeper.drop("mine");
      visits.push(f.visits());
      assert.equal(f.db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, others);
      plans.push(f.deletes[0]!);
    } finally { f.db.close(); }
  }
  assert.deepEqual(visits, [1, 1], "other workspaces' grants must not be traversed");
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE vault_grants(ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(ws,id))");
    for (const sql of plans) {
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("w", "mine").map((row) => String(row.detail)).join(" | ");
      assert.match(plan, /SEARCH vault_grants USING INDEX sqlite_autoindex_vault_grants_1 \(ws=\? AND id=\?\)/);
    }
  } finally { db.close(); }
});

test("forgetting a plain grant keeps an unrelated workspace's grant with the same id", () => {
  const f = fixture();
  try {
    f.insert.run("w", "mine");
    f.insert.run("other", "mine");
    f.secrets.keeper.restore(f.held("w", "mine", PLAIN));
    f.secrets.keeper.drop("mine");
    assert.deepEqual(f.db.prepare("SELECT ws FROM vault_grants ORDER BY ws").all().map((r) => r.ws), ["other"]);
  } finally { f.db.close(); }
});

test("forgetting a vault grant does not touch the plain-grants table", () => {
  const f = fixture();
  try {
    f.insert.run("another-workspace", "other");
    f.secrets.keeper.restore(f.held("w", "mine", "vault"));
    f.reset();
    f.secrets.keeper.drop("mine");
    assert.deepEqual(f.deletes, []);
    assert.equal(f.db.prepare("SELECT count(*) AS n FROM vault_grants").get()?.n, 1);
  } finally { f.db.close(); }
});
