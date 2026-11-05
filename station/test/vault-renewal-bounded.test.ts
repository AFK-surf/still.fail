import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PLAIN, PlainStore, type PlainItem } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";

test("a sign-in returns to its original workspace without reading unrelated requests", () => {
  const visits: number[] = [];
  for (const others of [40, 400]) {
    const db = new DatabaseSync(":memory:");
    let visited = 0, tracing = false, lookup = "";
    db.function("renewal_seen", (_ws, _id) => { if (tracing) visited++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (/^SELECT\b.*\bFROM vault_requests\b/is.test(sql) && /\bWHERE\b/i.test(sql)) {
          if (tracing) lookup = sql;
          return target.prepare(sql.replace(/\bWHERE\b/i, "WHERE renewal_seen(ws, id) AND"));
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const plain = new PlainStore(db);
      const secrets = new Secrets({ db: observed, data: ".", now: () => 1000, home: () => "current", lock: () => null,
        hub: { store: { subscribe() {}, getSession() { return { ws: "current" }; } } } as never,
        proxy: {} as never, vaults: {} as never, plain });
      const item: PlainItem = { ws: "z-origin", id: `i_${"0".repeat(26)}`, owner: "alice@example.test", version: 0,
        kind: "browser", name: "Test", fields: { cookies: "[]" }, notes: "", at: 0 };
      plain.put(item);
      const insert = db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,?,?,?,?)");
      for (let i = 0; i < others; i++) insert.run(`a${String(i).padStart(4, "0")}`, `other-${i}`, "other", "denied", "{}");
      insert.run("a-collision", "request", "session", "granted", JSON.stringify({
        ws: "a-collision", id: "request", session: "session", vault: PLAIN, item: item.id, owner: item.owner, mode: "browser", status: "granted",
      }));
      insert.run(item.ws, "request", "session", "granted", JSON.stringify({
        ws: item.ws, id: "request", session: "session", vault: PLAIN, item: item.id, owner: item.owner, mode: "browser", status: "granted",
      }));
      const cookies = JSON.stringify([{ name: "session", value: "new", domain: "example.test", path: "/" }]);
      const returned = secrets.renewed as (session: string, request: string, cookies: string, workspace?: string) => void;
      tracing = true;
      returned.call(secrets, "session", "request", cookies, item.ws);
      tracing = false;
      assert.equal(plain.item(item.ws, item.id)?.fields.cookies, cookies);
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${lookup}`).all(item.ws, "request", "session").map((row) => String(row.detail)).join(" | ");
      assert.match(plan, /SEARCH vault_requests USING INDEX sqlite_autoindex_vault_requests_1 \(ws=\? AND id=\?\)/);
      visits.push(visited);
      returned.call(secrets, "another-session", "request", "[]", item.ws);
      assert.equal(plain.item(item.ws, item.id)?.fields.cookies, cookies, "a different session cannot renew the request");
      returned.call(secrets, "session", "request", "[]", "missing");
      assert.equal(plain.item(item.ws, item.id)?.fields.cookies, cookies, "a missing workspace cannot fall back to another one");
    } finally { db.close(); }
  }
  assert.equal(visits[0], visits[1]);
  assert.ok(visits[0]! <= 1);
});

test("a sign-in from an older kept browser context still returns its cookies", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const plain = new PlainStore(db);
    const secrets = new Secrets({ db, data: ".", now: () => 1000, home: () => "current", lock: () => null,
      hub: { store: { subscribe() {}, getSession() { return { ws: "current" }; } } } as never,
      proxy: {} as never, vaults: {} as never, plain });
    const item: PlainItem = { ws: "old", id: `i_${"0".repeat(26)}`, owner: "alice@example.test", version: 0,
      kind: "browser", name: "Test", fields: { cookies: "[]" }, notes: "", at: 0 };
    plain.put(item);
    db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES(?,?,?,?,?)").run(item.ws, "request", "session", "granted", JSON.stringify({
      ws: item.ws, id: "request", session: "session", vault: PLAIN, item: item.id, owner: item.owner, mode: "browser", status: "granted",
    }));
    const cookies = JSON.stringify([{ name: "session", value: "legacy", domain: "example.test", path: "/" }]);
    secrets.renewed("session", "request", cookies);
    assert.equal(plain.item(item.ws, item.id)?.fields.cookies, cookies);
  } finally { db.close(); }
});
