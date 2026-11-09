import assert from "node:assert/strict";
import { test } from "node:test";
import { autoArchive, startAutoArchiveTimer } from "../src/sessions/lifecycle.ts";
import { installSessionBindingsIndex, sessionBindingsReady, sessionBindingsStep } from "../src/store/session-bindings-index.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function session(store: Store, key: string) {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
    token: key, createdAt: 1, lastActiveAt: 1 });
}

function makeOld(store: Store) {
  const db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_binding_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_binding_rows; DROP TABLE session_binding_replaced; DROP TABLE session_binding_meta");
  installSessionBindingsIndex(db);
}

function observe(store: Store) {
  const db = store.db;
  let visits = 0;
  const plans: string[][] = [];
  db.function("visit_binding_use", () => { visits++; return 1; });
  Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (source: string) => {
        let sql = source;
        sql = sql.replace("SELECT connect, session_key FROM bindings", "SELECT visit_binding_use() AS visit, connect, session_key FROM bindings")
          .replace("SELECT i.session, i.connect", "SELECT visit_binding_use() AS visit, i.session, i.connect")
          .replace("SELECT 1 FROM session_binding_rows WHERE", "SELECT 1 FROM session_binding_rows WHERE visit_binding_use() AND")
          .replace("DELETE FROM bindings WHERE session_key = ?", "DELETE FROM bindings WHERE visit_binding_use() AND session_key = ?")
          .replace("SELECT binding_rowid FROM session_binding_rows WHERE", "SELECT binding_rowid FROM session_binding_rows WHERE visit_binding_use() AND");
        const statement = target.prepare(sql);
        if (!source.includes("FROM bindings") && !source.includes("session_binding_rows")) return statement;
        return new Proxy(statement, { get(t, p) {
          if (p === "all" || p === "run" || p === "get") return (...args: unknown[]) => {
            plans.push((target.prepare(`EXPLAIN QUERY PLAN ${source}`).all(...args as any[]) as { detail: string }[]).map((row) => row.detail));
            return (t[p] as any)(...args);
          };
          const value = Reflect.get(t, p, t);
          return typeof value === "function" ? value.bind(t) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) });
  return { reset: () => { visits = 0; plans.length = 0; }, visits: () => visits, plans: () => plans,
    restore: () => Object.defineProperty(store, "db", { configurable: true, value: db }) };
}

test("auto-archive checks bindings only for active sessions", async () => {
  const r = new Rig(), db = r.store.db;
  try {
    session(r.store, "mine");
    const put = db.prepare("INSERT INTO bindings(connect,session_key) VALUES(?,?)");
    put.run("mine-connect", "mine");
    const extra = (from: number, to: number) => { for (let i = from; i < to; i++) put.run(`other-${i}`, `old-${i}`); };
    const observed = observe(r.store);
    try {
      extra(0, 40); observed.reset(); autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      const before = observed.visits();
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      extra(40, 400); observed.reset(); autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      assert.equal(r.store.getSession("mine")?.archivedAt, null);
      assert.equal(observed.visits(), before, `binding visits grew from ${before} to ${observed.visits()}`);
      assert.ok(observed.plans().some((plan) => plan.some((line) => line.includes("SEARCH session_binding_rows") && line.includes("session=?"))));
      for (let i = 0; i < 400; i++) put.run(`also-mine-${i}`, "mine");
      observed.reset(); autoArchive(r.hub, Date.now() + 3 * 86_400_000);
      assert.equal(observed.visits(), before, "one binding is enough to keep a session active");
    } finally { observed.restore(); }
  } finally { await r.close(); }
});

test("deleting a session does not scan unrelated bindings", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    session(store, "first"); session(store, "second");
    const put = db.prepare("INSERT INTO bindings(connect,session_key) VALUES(?,?)");
    put.run("first-connect", "first"); put.run("second-connect", "second");
    const extra = (from: number, to: number) => { for (let i = from; i < to; i++) put.run(`other-${i}`, `old-${i}`); };
    const observed = observe(store);
    try {
      extra(0, 40); observed.reset(); store.deleteSession("first");
      const before = observed.visits();
      assert.equal(store.binding("first-connect"), null);
      extra(40, 400); observed.reset(); store.deleteSession("second");
      assert.equal(store.binding("second-connect"), null);
      assert.equal(observed.visits(), before, `binding visits grew from ${before} to ${observed.visits()}`);
      assert.ok(observed.plans().some((plan) => plan.some((line) => line.includes("session_binding_rows") && line.includes("session=?"))));
    } finally { observed.restore(); }
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM bindings").get()?.n, 400);
  } finally { store.close(); }
});

test("archive waits for old bindings without guessing which sessions are bound", async () => {
  const r = new Rig(), db = r.store.db;
  try {
    session(r.store, "bound"); session(r.store, "free");
    db.exec("INSERT INTO bindings(connect,session_key) VALUES('old-connect','bound')");
    const own = r.store.openThread("ember", "CHAT", "own", null, null).id;
    makeOld(r.store);
    assert.equal(sessionBindingsReady(db), false);
    let requested = 0;
    autoArchive(r.hub, Date.now() + 3 * 86_400_000, undefined, () => { requested++; });
    assert.equal(requested, 1);
    assert.equal(r.store.getSession("bound")?.archivedAt, null);
    assert.equal(r.store.getSession("free")?.archivedAt, null);
    assert.notEqual(r.store.getThread(own)?.hiddenAt, null, "an unrelated own chat can still be archived");
    while (!sessionBindingsReady(db)) sessionBindingsStep(db, 1);
    autoArchive(r.hub, Date.now() + 3 * 86_400_000, undefined, () => { requested++; });
    assert.equal(requested, 1);
    assert.equal(r.store.getSession("bound")?.archivedAt, null);
    assert.notEqual(r.store.getSession("free")?.archivedAt, null);
  } finally { await r.close(); }
});

test("deleting a session removes all its indexed bindings, including wide rowids", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    session(store, "gone"); session(store, "kept");
    db.exec("INSERT INTO bindings(rowid,connect,session_key) VALUES(-9007199254740993,'low','gone'),(1,NULL,'gone'),(2,'other','kept'),(9007199254740993,'high','gone')");
    store.deleteSession("gone");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM bindings WHERE session_key='gone'").get()?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_binding_rows WHERE session='gone'").get()?.n, 0);
    assert.equal(store.binding("other"), "kept");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_binding_rows WHERE session='kept'").get()?.n, 1);
  } finally { store.close(); }
});

test("deleting a session still removes unseen old bindings before preparation", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    session(store, "gone"); session(store, "kept");
    db.exec("INSERT INTO bindings(connect,session_key) VALUES('first','gone'),('other','kept'),('last','gone')");
    makeOld(store);
    assert.equal(sessionBindingsReady(db), false);
    store.deleteSession("gone");
    assert.equal(store.binding("first"), null);
    assert.equal(store.binding("last"), null);
    assert.equal(store.binding("other"), "kept");
    while (!sessionBindingsReady(db)) sessionBindingsStep(db, 1);
    assert.deepEqual([...store.listBindings()], [["kept", ["other"]]]);
  } finally { store.close(); }
});

test("the archive timer prepares old bindings once and retries when ready", async () => {
  const r = new Rig(), ready = Promise.withResolvers<void>();
  let timer: { ms: number; run: () => void } | null = null, signal: AbortSignal | undefined, calls = 0;
  const time = { after(ms: number, run: () => void) {
    const next = { ms, run }; timer = next;
    return () => { if (timer === next) timer = null; };
  } };
  const fire = (ms: number) => { const task = timer; assert.ok(task); assert.equal(task.ms, ms); timer = null; task.run(); };
  let stop = () => {};
  try {
    session(r.store, "bound"); session(r.store, "free");
    r.store.db.exec("INSERT INTO bindings(connect,session_key) VALUES('old-connect','bound')");
    makeOld(r.store);
    stop = startAutoArchiveTimer(r.hub, time, {
      prepareSaid: async () => {}, prepareSessionBindings: (s) => { signal = s; calls++; return ready.promise; }, prepareSessionUpJobs: async () => {},
    });
    fire(60_000);
    assert.equal(calls, 1);
    assert.equal(r.store.getSession("free")?.archivedAt, null);
    fire(600_000);
    assert.equal(calls, 1);
    while (!sessionBindingsReady(r.store.db)) sessionBindingsStep(r.store.db, 1);
    ready.resolve();
    await ready.promise;
    await Promise.resolve();
    fire(0);
    assert.equal(r.store.getSession("bound")?.archivedAt, null);
    assert.notEqual(r.store.getSession("free")?.archivedAt, null);
    stop();
    assert.equal(signal?.aborted, true);
    assert.equal(timer, null);
  } finally { stop(); ready.resolve(); await r.close(); }
});

test("stopping the archive timer cancels pending binding preparation", async () => {
  const r = new Rig(), ready = Promise.withResolvers<void>();
  let timer: { ms: number; run: () => void } | null = null, signal: AbortSignal | undefined;
  const time = { after(ms: number, run: () => void) {
    const next = { ms, run }; timer = next;
    return () => { if (timer === next) timer = null; };
  } };
  let stop = () => {};
  try {
    session(r.store, "bound");
    r.store.db.exec("INSERT INTO bindings(connect,session_key) VALUES('old-connect','bound')");
    makeOld(r.store);
    stop = startAutoArchiveTimer(r.hub, time, {
      prepareSaid: async () => {}, prepareSessionBindings: (s) => { signal = s; return ready.promise; }, prepareSessionUpJobs: async () => {},
    });
    const task = timer as { ms: number; run: () => void } | null;
    assert.ok(task); assert.equal(task.ms, 60_000); timer = null; task.run();
    stop();
    assert.equal(signal?.aborted, true);
    ready.resolve();
    await ready.promise;
    await Promise.resolve();
    assert.equal(timer, null);
    assert.equal(r.store.getSession("bound")?.archivedAt, null);
  } finally { stop(); ready.resolve(); await r.close(); }
});
