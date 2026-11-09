import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { Store } from "../src/store/store.ts";
import { SignIns } from "../src/vault/signin.ts";

test("a sign-in waits for an old session's latest chat without scanning its memberships", async () => {
  for (const older of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    const gate = Promise.withResolvers<void>();
    let asking: Promise<unknown> | undefined;
    let signIns: SignIns | undefined;
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
      const requested: string[][] = [], posted: string[] = [];
      const hub = {
        store: {
          getSession: store.getSession.bind(store), starter: () => "p@example.test",
          latestThread: store.latestThread.bind(store), latestThreadIfReady: store.latestThreadIfReady.bind(store),
          sessionThreadById: store.sessionThreadById.bind(store), pendingCardHeader: () => null,
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
      signIns = new SignIns({ db, hub, now: () => 1_800_000_000_000, after: () => () => {},
        workspace: () => "w", screenLink: () => null, id: () => "signin",
        browser: { tabs: () => [{ id: "tab", url: "https://example.com/login" }],
          look: async () => ({ username: true, password: true, code: false, blocked: false }),
          drive: async () => ({ state: "left" }) },
        vault: { listed: () => null, held: () => null, use: async () => "", keep: async () => "" } });
      asking = signIns.ask("s", { site: "example.com", reason: "test" });
      await Promise.resolve();
      assert.equal(slowReads, 0, `${older} older memberships must not reach the original sort`);
      assert.deepEqual(requested, [["s"]]);
      assert.deepEqual(posted, []);
      db.prepare("INSERT INTO deliveries(thread,n,session,delivered_at) VALUES(?,1,'s',2)").run(later.id);
      gate.resolve();
      await asking;
      assert.deepEqual(posted, ["old-0"], "the destination follows a delivery during preparation");
    } finally {
      gate.resolve();
      await asking?.catch(() => undefined);
      await signIns?.close();
      Object.defineProperty(store, "db", { value: db, configurable: true });
      store.close();
    }
  }
});

function waitingSignin() {
  const db = new DatabaseSync(":memory:"), gate = Promise.withResolvers<void>();
  const form = Promise.withResolvers<{ username: boolean; password: boolean; code: boolean; blocked: boolean }>();
  const thread = { connect: "slack", thread: { id: 1, channel: "C", threadTs: "latest", surface: "slack" } };
  let ready = false, present = true, requested = 0, posted = 0, looked = 0, ids = 0;
  const hub = {
    store: {
      getSession: () => present ? { archivedAt: null } : null, starter: () => "p@example.test",
      latestThread: () => { throw new Error("unbounded latest read"); }, latestThreadIfReady: () => ready ? thread : undefined,
      sessionThreadById: () => thread, pendingCardHeader: () => null, insertMessage: () => [1],
      withdrawCard: () => true, restateCard: () => true, subscribe: () => {},
    },
    prepareLatestThreads: async () => { requested++; await gate.promise; },
    chat: () => ({ post: async () => { posted++; return "posted"; } }), shared: () => {}, notify: () => {},
  } as any;
  const signIns = new SignIns({ db, hub, now: () => 1_800_000_000_000, after: () => () => {},
    workspace: () => "w", screenLink: () => null, id: () => `g${++ids}`,
    browser: { tabs: () => [{ id: "tab", url: "https://example.com/login" }],
      look: () => { looked++; return form.promise; }, drive: async () => ({ state: "left" }) },
    vault: { listed: () => null, held: () => null, use: async () => "", keep: async () => "" } });
  return { db, signIns, gate, form, requested: () => requested, posted: () => posted, looked: () => looked,
    ready: () => { ready = true; }, remove: () => { present = false; } };
}

test("concurrent sign-ins after preparation make only one request", async () => {
  const w = waitingSignin();
  try {
    const first = w.signIns.ask("s", { site: "example.com", reason: "one" });
    const second = w.signIns.ask("s", { site: "example.com", reason: "two" });
    assert.equal(w.requested(), 2);
    w.ready(); w.gate.resolve();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(w.looked(), 2);
    w.form.resolve({ username: true, password: true, code: false, blocked: false });
    const results = await Promise.all([first, second]);
    assert.ok(results.every((r) => r.includes("g1")));
    assert.equal(w.posted(), 1);
    assert.equal(w.db.prepare("SELECT COUNT(*) AS n FROM signin_asks").get()?.n, 1);
  } finally { w.gate.resolve(); await w.signIns.close(); w.db.close(); }
});

test("a removed session does not get a sign-in after preparation or browser inspection", async () => {
  for (const during of ["preparation", "inspection"] as const) {
    const w = waitingSignin();
    try {
      if (during === "inspection") w.ready();
      const asking = w.signIns.ask("s", { site: "example.com", reason: "test" });
      w.remove();
      w.gate.resolve();
      w.form.resolve({ username: true, password: true, code: false, blocked: false });
      await assert.rejects(asking, /archived or gone/);
      assert.equal(w.posted(), 0);
      assert.equal(w.db.prepare("SELECT COUNT(*) AS n FROM signin_asks").get()?.n, 0);
    } finally { w.gate.resolve(); await w.signIns.close(); w.db.close(); }
  }
});

test("a failed sign-in destination preparation posts nothing", async () => {
  const w = waitingSignin();
  try {
    const asking = w.signIns.ask("s", { site: "example.com", reason: "test" });
    w.gate.reject(new Error("preparation stopped"));
    await assert.rejects(asking, /preparation stopped/);
    assert.equal(w.posted(), 0);
    assert.equal(w.db.prepare("SELECT COUNT(*) AS n FROM signin_asks").get()?.n, 0);
  } finally { await w.signIns.close(); w.db.close(); }
});
