import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";
import { PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

for (const operation of ["ask", "save"] as const) {
  test(`a secret ${operation} waits for an old session's latest chat without sorting its memberships`, async () => {
    for (const older of [40, 400]) {
      const store = Store.open(":memory:"), db = store.db;
      const dir = mkdtempSync(join(tmpdir(), "vault-latest-"));
      const gate = Promise.withResolvers<void>();
      let asking: Promise<unknown> | undefined;
      try {
        store.insertSession({ key: "s", connect: "slack", runtime: "claude", profile: "cc", workspace: "/w/s",
          token: "s", createdAt: 1, lastActiveAt: 1 });
        const first = store.openThread("slack", "C", "first", null, null);
        store.joinThread(first.id, "s", "slack");
        db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',1)").run(first.id);
        db.exec("BEGIN");
        let later = first;
        for (let n = 0; n < older; n++) {
          const old = store.openThread("slack", "C", `old-${n}`, null, null);
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
        const plain = new PlainStore(db), vaults = new VaultStore(db);
        plain.put({ ws: "w", id: "i_00000000000000000000000001", owner: "p@example.test", version: 0,
          kind: "token", name: "test key", fields: { value: "fake" }, notes: "",
          listing: { name: "test key", kind: "token", modes: ["env"], hosts: [] }, at: 1 });
        const requested: string[][] = [], posted: string[] = [];
        const hub = {
          store: {
            getSession: store.getSession.bind(store), starter: () => "p@example.test",
            latestThread: store.latestThread.bind(store), latestThreadIfReady: store.latestThreadIfReady.bind(store),
            sessionThreadById: store.sessionThreadById.bind(store), pendingCard: () => null,
            insertMessage: () => [1], withdrawCard: () => true, restateCard: () => true, subscribe: () => {},
          },
          prepareLatestThreads: async (sessions: readonly string[]) => {
            requested.push([...sessions]);
            await gate.promise;
            while (!prepareLatestThreadStep(db, "s", 64, { existingSession: true }).done) { /* bounded worker batches */ }
          },
          chat: () => ({ post: async (where: { threadTs: string }) => { posted.push(where.threadTs); return "posted"; } }),
          shared: () => {}, notify: () => {},
        } as any;
        const secrets = new Secrets({ db, vaults, plain, hub, data: dir, home: () => "w", lock: () => null, now: () => 1_800_000_000_000 });
        asking = operation === "ask"
          ? secrets.ask("s", { item: "test key", reason: "test" })
          : secrets.save("s", { name: "new key", kind: "token", reason: "test", value: "fake", cwd: dir });
        await Promise.resolve();
        assert.equal(slowReads, 0, `${older} older memberships must not reach the original sort`);
        assert.deepEqual(requested, [["s"]]);
        assert.deepEqual(posted, []);
        db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',2)").run(later.id);
        gate.resolve();
        await asking;
        assert.deepEqual(posted, ["old-0"]);
      } finally {
        gate.resolve();
        await asking?.catch(() => undefined);
        Object.defineProperty(store, "db", { value: db, configurable: true });
        store.close();
        rmSync(dir, { recursive: true, force: true });
      }
    }
  });
}
