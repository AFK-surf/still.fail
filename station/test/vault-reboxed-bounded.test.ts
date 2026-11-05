import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Secrets } from "../src/vault/secrets.ts";

async function visited(others: number) {
  const db = new DatabaseSync(":memory:");
  let visited = 0, observing = false, traced = false;
  db.function("rebox_seen", (_id) => { if (observing) visited++; return 1; });
  const observed = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      if (sql === "SELECT ws, id FROM vault_requests WHERE status = 'pending'") {
        traced = true;
        return target.prepare(sql.replace("WHERE status = 'pending'", "WHERE rebox_seen(id) AND status = 'pending'"));
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

test("recovering pending boxes does not read decided request history once that workspace is prepared", async () => {
  assert.deepEqual(await Promise.all([visited(40), visited(400)]), [1, 1]);
});
