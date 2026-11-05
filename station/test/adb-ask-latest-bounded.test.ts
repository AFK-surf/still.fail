import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants } from "../src/adb/grants.ts";
import { prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";

test("a phone request waits for an old session's latest chat without scanning its memberships", async () => {
  for (const older of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    const gate = Promise.withResolvers<void>();
    let asking: Promise<unknown> | undefined;
    try {
      store.insertSession({ key: "s", connect: "slack", runtime: "claude", profile: "cc", workspace: "/w/s",
        token: "s", createdAt: 1, lastActiveAt: 1 });
      const latest = store.openThread("slack", "C", "latest", null, null);
      store.joinThread(latest.id, "s", "slack");
      db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',1)").run(latest.id);
      db.exec("BEGIN");
      let later = latest;
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
      const requested: string[][] = [], posted: string[] = [];
      const hub = {
        store: {
          getSession: store.getSession.bind(store), starter: () => "p@example.test",
          latestThread: store.latestThread.bind(store),
          latestThreadIfReady: (session: string) => (store as any).latestThreadIfReady(session),
          sessionThreadById: store.sessionThreadById.bind(store), pendingCard: () => null,
          insertMessage: () => [1], withdrawCard: () => true, restateCard: () => true,
          threadSessions: () => [], subscribe: () => {},
        },
        prepareLatestThreads: async (sessions: readonly string[]) => {
          requested.push([...sessions]);
          await gate.promise;
          while (!prepareLatestThreadStep(db, "s", 64, { existingSession: true }).done) { /* bounded worker batches */ }
        },
        chat: () => ({ post: async (where: { threadTs: string }) => { posted.push(where.threadTs); return "posted"; } }),
        shared: () => {}, notify: () => {},
      } as any;
      const grants = new PhoneGrants({ db, hub, home: () => null, title: () => null, now: () => 1_800_000_000_000 });
      asking = grants.ask("s", "debug");
      await Promise.resolve();
      assert.equal(slowReads, 0, `${older} older memberships must not reach the original sort`);
      assert.deepEqual(requested, [["s"]]);
      assert.deepEqual(posted, [], "no request is posted before the correct destination is ready");
      db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',2)").run(later.id);
      gate.resolve();
      const result = await asking as { chat: string };
      assert.equal(result.chat, "C/old-0", "the destination follows a delivery during preparation");
      assert.deepEqual(posted, ["old-0"]);
    } finally {
      gate.resolve();
      await asking?.catch(() => undefined);
      Object.defineProperty(store, "db", { value: db, configurable: true });
      store.close();
    }
  }
});

function waitingRequest() {
  const db = new DatabaseSync(":memory:"), gate = Promise.withResolvers<void>();
  const thread = { connect: "slack", thread: { id: 1, channel: "C", threadTs: "latest", surface: "slack" } };
  let present = true, ready = false, requested = 0, posted = 0, ids = 0;
  const hub = {
    store: {
      getSession: () => present ? { ws: "w", archivedAt: null } : null,
      starter: () => "p@example.test", latestThread: () => { throw new Error("unbounded latest read"); },
      latestThreadIfReady: () => ready ? thread : undefined,
      sessionThreadById: () => thread, pendingCard: () => null, insertMessage: () => [1],
      withdrawCard: () => true, restateCard: () => true, threadSessions: () => [], subscribe: () => {},
    },
    prepareLatestThreads: async () => { requested++; await gate.promise; },
    chat: () => ({ post: async () => { posted++; return "posted"; } }), shared: () => {}, notify: () => {},
  } as any;
  const grants = new PhoneGrants({ db, hub, home: () => "w", title: () => null, now: () => 1_800_000_000_000,
    id: () => `p${++ids}` });
  return { db, grants, gate, requested: () => requested, posted: () => posted,
    ready: () => { ready = true; }, remove: () => { present = false; } };
}

test("concurrent phone requests share the request created after preparation", async () => {
  const w = waitingRequest();
  try {
    const first = w.grants.ask("s", "debug"), second = w.grants.ask("s", "debug too");
    assert.equal(w.requested(), 2);
    assert.equal(w.posted(), 0);
    w.ready(); w.gate.resolve();
    const [a, b] = await Promise.all([first, second]);
    assert.equal(a.id, b.id);
    assert.equal(w.posted(), 1);
    assert.equal(w.db.prepare("SELECT COUNT(*) AS n FROM adb_requests").get()?.n, 1);
  } finally { w.gate.resolve(); w.db.close(); }
});

test("a session removed during preparation does not get a phone request", async () => {
  const w = waitingRequest();
  try {
    const asking = w.grants.ask("s", "debug");
    assert.equal(w.requested(), 1);
    w.remove(); w.gate.resolve();
    await assert.rejects(asking, /archived or gone/);
    assert.equal(w.posted(), 0);
    assert.equal(w.db.prepare("SELECT COUNT(*) AS n FROM adb_requests").get()?.n, 0);
  } finally { w.gate.resolve(); w.db.close(); }
});
