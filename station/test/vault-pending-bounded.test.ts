import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PLAIN } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";

test("pending requests do not traverse decided history or another person's pending requests", async () => {
  const counts: Record<string, number[]> = { history: [], pending: [] };
  for (const kind of ["history", "pending"] as const) for (const others of [40, 400]) {
    const db = new DatabaseSync(":memory:");
    let visited = 0, traced = false;
    db.function("pending_seen", (_id) => { visited++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === "SELECT body FROM vault_requests WHERE ws = ? AND status = 'pending'") {
          traced = true;
          return target.prepare(sql.replace("WHERE ws = ?", "WHERE pending_seen(id) AND ws = ?"));
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
      const rows = await secrets.pending("w", null, { sub: "alice", email: "alice@example.test" });
      assert.deepEqual(rows.map((r) => r.id), ["mine"]);
      assert.equal(traced, true);
      counts[kind].push(visited);
    } finally { db.close(); }
  }
  assert.deepEqual(counts, { history: [1, 1], pending: [1, 1] });
});
