import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { sender } from "../src/sessions/messages.ts";
import { prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";
import { Secrets } from "../src/vault/secrets.ts";

test("a page of secret uses prepares only the names it shows without sorting their old chats", async () => {
  for (const older of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db, gate = Promise.withResolvers<void>();
    let reading: Promise<unknown> | undefined;
    try {
      store.insertSession({ key: "s", connect: "slack", runtime: "claude", profile: "cc", workspace: "/w/s",
        token: "s", createdAt: 1, lastActiveAt: 1 });
      const first = store.openThread("slack", "C", "first", "first", null);
      store.joinThread(first.id, "s", "slack");
      db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',1)").run(first.id);
      db.exec("BEGIN");
      let later = first;
      for (let n = 0; n < older; n++) {
        const old = store.openThread("slack", "C", `old-${n}`, `old-${n}`, null);
        store.joinThread(old.id, "s", "slack");
        if (n === 0) later = old;
      }
      db.exec("COMMIT");
      let slowReads = 0;
      const traced = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            if (sql.includes("ORDER BY (SELECT d.rowid FROM deliveries")) slowReads++;
            return target.prepare(sql);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });
      Object.defineProperty(store, "db", { value: traced, configurable: true });
      const requested: string[][] = [];
      const hub = {
        store, link: () => null,
        prepareLatestThreads: async (sessions: readonly string[]) => {
          requested.push([...sessions]);
          await gate.promise;
          while (!prepareLatestThreadStep(db, "s", 64, { existingSession: true }).done) { /* bounded worker batches */ }
        },
      } as any;
      const secrets = new Secrets({ db, hub, data: ".", now: () => 0, home: () => "w",
        lock: () => ({} as never), proxy: {} as never,
        vaults: { vault: () => ({ members: ["p"] }) } as never, plain: {} as never,
        title: (session) => sender(hub, session)[0] });
      const body = JSON.stringify({ ws: "w", id: "r", vault: "v", owner: "p@example.test", at: 1,
        item: "item", session: "s", mode: "env", status: "granted" });
      db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','granted',?)").run(body);
      reading = secrets.uses("w", {} as never, "v", { sub: "p", email: "p@example.test" });
      await new Promise((resolve) => setImmediate(resolve));
      assert.equal(slowReads, 0, `${older} older memberships must not reach the original sort`);
      assert.deepEqual(requested, [["s"]]);
      db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',2)").run(later.id);
      gate.resolve();
      assert.equal((await reading as { chatTitle: string | null }[])[0]?.chatTitle, "old-0");
    } finally {
      gate.resolve();
      await reading?.catch(() => undefined);
      Object.defineProperty(store, "db", { value: db, configurable: true });
      store.close();
    }
  }
});

function waitingUses() {
  const db = new DatabaseSync(":memory:"), gate = Promise.withResolvers<void>();
  let permitted = true, present = true, ready = false, prepares = 0, titles = 0;
  const hub = {
    store: {
      subscribe: () => {}, getSession: () => present ? { ws: "w" } : null,
      sessionHomeThread: () => null, latestThreadIfReady: () => ready ? null : undefined,
    },
    prepareLatestThreads: async () => { prepares++; await gate.promise; },
  } as any;
  const secrets = new Secrets({ db, hub, data: ".", now: () => 0, home: () => "w",
    lock: () => ({} as never), proxy: {} as never,
    vaults: { vault: () => ({ members: permitted ? ["p"] : [] }) } as never, plain: {} as never,
    title: () => { titles++; return "shown"; } });
  const body = JSON.stringify({ ws: "w", id: "r", vault: "v", owner: "p@example.test", at: 1,
    item: "item", session: "s", mode: "env", status: "granted" });
  db.prepare("INSERT INTO vault_requests(ws,id,session,status,body) VALUES('w','r','s','granted',?)").run(body);
  return { db, gate, secrets, prepares: () => prepares, titles: () => titles,
    ready: () => { ready = true; }, remove: () => { present = false; }, revoke: () => { permitted = false; } };
}

test("a vault membership removed while use titles are prepared reveals no results", async () => {
  const w = waitingUses();
  try {
    const reading = w.secrets.uses("w", {} as never, "v", { sub: "p", email: "p@example.test" });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(w.prepares(), 1);
    w.revoke(); w.ready(); w.gate.resolve();
    assert.deepEqual(await reading, []);
    assert.equal(w.titles(), 0);
  } finally { w.gate.resolve(); w.db.close(); }
});

test("a session removed while use titles are prepared does not keep the page waiting", async () => {
  const w = waitingUses();
  try {
    const reading = w.secrets.uses("w", {} as never, "v", { sub: "p", email: "p@example.test" });
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(w.prepares(), 1);
    w.remove(); w.gate.resolve();
    assert.equal((await reading)[0]?.chatTitle, null);
    assert.equal(w.titles(), 0);
  } finally { w.gate.resolve(); w.db.close(); }
});
