import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as readStore from "../src/read/store.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

const pending = (readStore as any).pendingDeliveries as (store: readStore.Store, session: string) => any[];

function session(store: Store, key = "worker") {
  store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: key, createdAt: 1, lastActiveAt: 1 });
}
function chat(store: Store, name: string, key = "worker") {
  const thread = store.openThread("ember", "CHAT", name, null, null).id;
  store.joinThread(thread, key, "ember");
  return thread;
}
function message(store: Store, thread: number, n: number, at = n) {
  store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
    VALUES(?,?,'message',?,'person','person',?,?)`).run(thread, n, `${n}.1`, `message-${n}`, at);
}
function deliver(store: Store, thread: number, n: number, key = "worker") {
  store.db.prepare("INSERT INTO deliveries(thread,n,session) VALUES(?,?,?)").run(thread, n, key);
}

test("pending delivery reads preserve edited messages, letters, and delivery order", () => {
  const store = Store.open(":memory:");
  try {
    session(store);
    const thread = chat(store, "history");
    message(store, thread, 1, 1);
    message(store, thread, 2, 3);
    deliver(store, thread, 1);
    deliver(store, thread, 2);
    deliver(store, thread, 999); // An orphaned delivery is not a message.
    store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,3,'edit',1,'person','person','edited',4)`).run(thread);
    store.db.prepare(`INSERT INTO letters(thread,n,ts,author_kind,author,text,at,letter)
      VALUES(?,1,'letter.1','agent','other','letter',2,?)`).run(thread, JSON.stringify({ way: "in", title: "other", link: null }));
    store.db.prepare("INSERT INTO letter_deliveries(thread,n,session) VALUES(?,1,'worker')").run(thread);
    const expected = store.pendingMessages("worker");
    assert.deepEqual(expected.map((item) => item.message.text), ["edited", "letter", "message-2"]);
    assert.deepEqual(pending(readStore.makeStore(store.db, ""), "worker"), expected);
  } finally { store.close(); }
});

test("an old pending message does not synchronously traverse an unrelated edit tail", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    session(store);
    const thread = chat(store, "old");
    message(store, thread, 1);
    deliver(store, thread, 1);
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','other','edit',?)");
    for (let n = 2; n <= 151; n++) edit.run(thread, n, n + 1000, n);
    edit.run(thread, 9007199254740993n, 999, 999);
    installLegacyEdits(db);
    addClientColumn(db);
    assert.throws(() => pending(readStore.makeStore(db, ""), "worker"), /legacy edit lookup pending/);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("delivery keys and their edited text use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "pending-delivery-snapshot-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  try {
    session(store);
    const thread = chat(store, "snapshot");
    message(store, thread, 1);
    deliver(store, thread, 1);
    store.db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(store.db);
    addClientColumn(store.db);
    let changed = false;
    const observed = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === readStore.LAST_MESSAGE_WITH_EDIT && !changed) {
          changed = true;
          writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
            VALUES(?,2,'edit',1,'person','person','edited later',2)`).run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, dir);
    assert.equal(pending(read, "worker")[0].message.text, "message-1");
    assert.ok(changed);
    assert.equal(pending(read, "worker")[0].message.text, "edited later");
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an agent recovers pending messages through a reader", async () => {
  const rig = new Rig();
  await rig.hub.shutdown();
  rig.store.close();
  rig.store = Store.open(join(rig.dir, "stillfail.db"));
  rig.hub = rig.newHub({ chats: () => undefined });
  const readers = new Readers(rig.dir, 1, undefined, 1);
  try {
    session(rig.store);
    const thread = chat(rig.store, "recover");
    message(rig.store, thread, 1);
    deliver(rig.store, thread, 1);
    let reads = 0;
    (rig.hub as any).pendingDeliveries = async (key: string, signal?: AbortSignal) => {
      reads++;
      return JSON.parse(await readers.read("pendingDeliveries", { key }, "en", { signal }));
    };
    rig.store.pendingMessages = () => { throw new Error("station pending message lookup used"); };
    await rig.hub.actor(rig.session("worker")).recover();
    assert.equal(reads, 1, "recovery requested the reader");
    assert.match(rig.claude.last().prompts.at(-1)!, /message-1/);
  } finally { readers.close(); await rig.close(); }
});

test("suspending an actor cancels its pending read and leaves the message undelivered", async () => {
  const rig = new Rig();
  try {
    session(rig.store);
    const thread = chat(rig.store, "suspend");
    message(rig.store, thread, 1);
    deliver(rig.store, thread, 1);
    const asked = Promise.withResolvers<AbortSignal>();
    (rig.hub as any).pendingDeliveries = (_key: string, signal: AbortSignal) => new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(new Error("read cancelled")), { once: true });
      asked.resolve(signal);
    });
    const actor = rig.hub.actor(rig.session("worker"));
    const pumping = actor.kick();
    const signal = await asked.promise;
    await Promise.all([pumping, actor.suspend()]);
    assert.equal(signal.aborted, true);
    assert.equal(rig.store.pendingMessages("worker").length, 1);
    assert.equal(rig.claude.count(), 0);
  } finally { await rig.close(); }
});

for (const action of ["suspend", "stop"] as const) {
  test(`${action} during a pending recovery keeps the correct restart state`, async () => {
    const rig = new Rig();
    try {
      session(rig.store);
      const thread = chat(rig.store, "recovery");
      message(rig.store, thread, 1);
      deliver(rig.store, thread, 1);
      rig.store.setRunning("worker", true);
      const asked = Promise.withResolvers<void>();
      (rig.hub as any).pendingDeliveries = (_key: string, signal: AbortSignal) => new Promise((_resolve, reject) => {
        signal.addEventListener("abort", () => reject(new Error("read cancelled")), { once: true });
        asked.resolve();
      });
      const actor = rig.hub.actor(rig.session("worker"));
      const recovering = actor.recover();
      await asked.promise;
      await Promise.all([recovering, actor[action]()]);
      assert.equal(rig.session("worker").running, action === "suspend");
      assert.equal(rig.store.pendingMessages("worker").length, 1);
      assert.equal(rig.claude.count(), 0);
      if (action === "suspend") {
        (rig.hub as any).pendingDeliveries = async (key: string) => rig.store.pendingMessages(key);
        await actor.recover();
        assert.match(rig.claude.last().prompts[0]!, /restarted while you were in the middle of a turn/);
        assert.match(rig.claude.last().prompts[0]!, /message-1/);
        assert.equal(rig.store.pendingMessages("worker").length, 0);
      }
    } finally { await rig.close(); }
  });

  test(`${action} does not start a queued retry after cancelling a pending read`, async () => {
    const rig = new Rig();
    try {
      session(rig.store);
      const thread = chat(rig.store, "queued-recovery");
      message(rig.store, thread, 1);
      deliver(rig.store, thread, 1);
      rig.store.setRunning("worker", true);
      const asked = Promise.withResolvers<void>();
      let reads = 0;
      (rig.hub as any).pendingDeliveries = (_key: string, signal: AbortSignal) => {
        if (++reads > 1) return Promise.resolve([]);
        return new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(new Error("read cancelled")), { once: true });
          asked.resolve();
        });
      };
      const actor = rig.hub.actor(rig.session("worker"));
      const recovering = actor.recover();
      await asked.promise;
      const retry = actor.kick();
      await Promise.all([recovering, retry, actor[action]()]);
      assert.equal(reads, 1);
      assert.equal(rig.store.pendingMessages("worker").length, 1);
    } finally { await rig.close(); }
  });

  test(`${action} also prevents a queued recovery from starting a new read`, async () => {
    const rig = new Rig();
    try {
      session(rig.store);
      const thread = chat(rig.store, "queued-pump");
      message(rig.store, thread, 1);
      deliver(rig.store, thread, 1);
      rig.store.setRunning("worker", true);
      const asked = Promise.withResolvers<void>();
      let reads = 0;
      (rig.hub as any).pendingDeliveries = (_key: string, signal: AbortSignal) => {
        if (++reads > 1) return Promise.resolve([]);
        return new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(new Error("read cancelled")), { once: true });
          asked.resolve();
        });
      };
      const actor = rig.hub.actor(rig.session("worker"));
      const pumping = actor.kick();
      await asked.promise;
      const recovering = actor.recover();
      await Promise.all([pumping, recovering, actor[action]()]);
      assert.equal(reads, 1);
      assert.equal(rig.session("worker").running, action === "suspend");
      assert.equal(rig.store.pendingMessages("worker").length, 1);
      assert.equal(rig.claude.count(), 0);
    } finally { await rig.close(); }
  });

  test(`${action} before compaction checking finishes does not start a pending read`, async () => {
    const rig = new Rig();
    try {
      session(rig.store);
      const thread = chat(rig.store, "checking-compaction");
      message(rig.store, thread, 1);
      deliver(rig.store, thread, 1);
      const entered = Promise.withResolvers<void>(), finished = Promise.withResolvers<void>();
      let reads = 0;
      (rig.hub as any).pendingDeliveries = async () => { reads++; return []; };
      const actor = rig.hub.actor(rig.session("worker"));
      (actor as any).compactingToCap = async () => { entered.resolve(); await finished.promise; return false; };
      const pumping = actor.kick();
      await entered.promise;
      const interrupted = actor[action]();
      finished.resolve();
      await Promise.all([pumping, interrupted]);
      assert.equal(reads, 0);
      assert.equal(rig.store.pendingMessages("worker").length, 1);
    } finally { await rig.close(); }
  });

  for (const mode of ["kick", "recover"] as const) {
    test(`${action} as ${mode} finishes formatting keeps the delivery pending`, async () => {
      const rig = new Rig();
      try {
        session(rig.store);
        const thread = chat(rig.store, "formatted");
        message(rig.store, thread, 1);
        deliver(rig.store, thread, 1);
        if (mode === "recover") rig.store.setRunning("worker", true);
        const entered = Promise.withResolvers<void>(), finished = Promise.withResolvers<void>();
        const actor = rig.hub.actor(rig.session("worker"));
        const pendingAndFormat = (actor as any).pendingAndFormat.bind(actor);
        (actor as any).pendingAndFormat = async (allowEmpty: boolean) => {
          const delivery = await pendingAndFormat(allowEmpty);
          entered.resolve();
          await finished.promise;
          return delivery;
        };
        const delivering = actor[mode]();
        await entered.promise;
        const interrupted = actor[action]();
        finished.resolve();
        await Promise.all([delivering, interrupted]);
        assert.equal(rig.store.pendingMessages("worker").length, 1);
        assert.equal(rig.claude.count(), 0);
        if (mode === "recover") assert.equal(rig.session("worker").running, action === "suspend");
      } finally { await rig.close(); }
    });
  }
}

test("closing before compaction checking finishes does not start a pending read", async () => {
  const rig = new Rig();
  try {
    session(rig.store);
    const thread = chat(rig.store, "closing-during-compaction");
    message(rig.store, thread, 1);
    deliver(rig.store, thread, 1);
    const entered = Promise.withResolvers<void>(), finished = Promise.withResolvers<void>();
    let reads = 0;
    (rig.hub as any).pendingDeliveries = async () => { reads++; return []; };
    const actor = rig.hub.actor(rig.session("worker"));
    (actor as any).compactingToCap = async () => { entered.resolve(); await finished.promise; return false; };
    const pumping = actor.kick();
    await entered.promise;
    actor.close();
    finished.resolve();
    await pumping;
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(reads, 0);
    assert.equal(rig.store.pendingMessages("worker").length, 1);
  } finally { await rig.close(); }
});

test("a held recovery waits, then resumes the cut-off turn when released", async () => {
  const rig = new Rig();
  try {
    session(rig.store);
    const thread = chat(rig.store, "held-recovery");
    message(rig.store, thread, 1);
    deliver(rig.store, thread, 1);
    rig.store.setRunning("worker", true);
    const entered = Promise.withResolvers<void>(), finished = Promise.withResolvers<void>();
    let reads = 0;
    (rig.hub as any).pendingDeliveries = async (key: string) => {
      if (++reads === 1) { entered.resolve(); await finished.promise; }
      return rig.store.pendingMessages(key);
    };
    const actor = rig.hub.actor(rig.session("worker"));
    const recovering = actor.recover();
    await entered.promise;
    rig.hub.hold("drain");
    finished.resolve();
    await recovering;
    assert.equal(rig.claude.count(), 0);
    assert.equal(rig.session("worker").running, true);
    assert.equal(rig.store.pendingMessages("worker").length, 1);
    rig.hub.release("drain");
    await actor.flushed();
    assert.match(rig.claude.last().prompts[0]!, /restarted while you were in the middle of a turn/);
    assert.match(rig.claude.last().prompts[0]!, /message-1/);
    assert.equal(rig.store.pendingMessages("worker").length, 0);
  } finally { await rig.close(); }
});

test("releasing a hold does not duplicate an already queued recovery", async () => {
  const rig = new Rig();
  try {
    session(rig.store);
    const thread = chat(rig.store, "held-retry");
    message(rig.store, thread, 1);
    deliver(rig.store, thread, 1);
    rig.store.setRunning("worker", true);
    let reads = 0;
    (rig.hub as any).pendingDeliveries = async (key: string) => { reads++; return rig.store.pendingMessages(key); };
    const actor = rig.hub.actor(rig.session("worker"));
    rig.hub.hold("drain");
    await actor.recover();
    assert.equal(reads, 0);
    rig.hub.recover();
    rig.hub.release("drain");
    await actor.flushed();
    assert.equal(reads, 1);
    assert.equal(rig.claude.count(), 1);
    assert.match(rig.claude.last().prompts[0]!, /restarted while you were in the middle of a turn/);
    assert.equal(rig.store.pendingMessages("worker").length, 0);
  } finally { await rig.close(); }
});

test("stopping a deferred recovery clears its restart state", async () => {
  const rig = new Rig();
  try {
    session(rig.store);
    rig.store.setRunning("worker", true);
    const actor = rig.hub.actor(rig.session("worker"));
    rig.hub.hold("drain");
    await actor.recover();
    await actor.stop();
    assert.equal(rig.session("worker").running, false);
    rig.hub.release("drain");
    await actor.flushed();
    assert.equal(rig.claude.count(), 0);
  } finally { await rig.close(); }
});

test("archiving while a recovery reads leaves its messages pending", async () => {
  const rig = new Rig();
  try {
    session(rig.store);
    const thread = chat(rig.store, "archived-recovery");
    message(rig.store, thread, 1);
    deliver(rig.store, thread, 1);
    rig.store.setRunning("worker", true);
    const entered = Promise.withResolvers<void>(), finished = Promise.withResolvers<void>();
    (rig.hub as any).pendingDeliveries = async (key: string) => {
      entered.resolve();
      await finished.promise;
      return rig.store.pendingMessages(key);
    };
    const actor = rig.hub.actor(rig.session("worker"));
    const recovering = actor.recover();
    await entered.promise;
    rig.store.setArchived("worker", true, "manual");
    finished.resolve();
    await recovering;
    assert.equal(rig.claude.count(), 0);
    assert.equal(rig.session("worker").running, false);
    assert.equal(rig.store.pendingMessages("worker").length, 1);
  } finally { await rig.close(); }
});

test("pending readers share old edit preparation after handover when one cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pending-delivery-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    session(store);
    const thread = chat(store, "old");
    message(store, thread, 1);
    deliver(store, thread, 1);
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','other','edit',?)");
    for (let n = 2; n <= 151; n++) edit.run(thread, n, n + 1000, n);
    installLegacyEdits(db);
    addClientColumn(db);
    const controller = new AbortController();
    const abandoned = readers.read("pendingDeliveries", { key: "worker" }, "en", { signal: controller.signal });
    const kept = readers.read("pendingDeliveries", { key: "worker" }, "en");
    void abandoned.catch(() => {}); void kept.catch(() => {});
    assert.deepEqual(JSON.parse(await readers.read("pendingDeliveries", { key: "nobody" }, "en")), []);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.equal(JSON.parse(await kept)[0].message.text, "message-1");
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a post reports unread timestamps without loading every pending message", async () => {
  const rig = new Rig();
  try {
    session(rig.store);
    const here = chat(rig.store, "1.1"), elsewhere = chat(rig.store, "2.1");
    message(rig.store, here, 1);
    deliver(rig.store, here, 1);
    message(rig.store, elsewhere, 1);
    deliver(rig.store, elsewhere, 1);
    rig.store.pendingMessages = () => { throw new Error("all pending messages were loaded"); };
    const result = await rig.call("worker", "chat_post", { to: "CHAT/1.1", text: "posted" });
    assert.match(result, /Before this post went up, a message you had not read yet came in this thread \(ts 1\.1\)/);
  } finally { await rig.close(); }
});

test("unread timestamps preserve delivery order, scope, and missing timestamps", () => {
  const store = Store.open(":memory:");
  try {
    session(store);
    const here = chat(store, "1.1"), elsewhere = chat(store, "2.1");
    for (let n = 1; n <= 4; n++) message(store, here, n);
    store.db.prepare("UPDATE entries SET ts=NULL WHERE thread=? AND n=2").run(here);
    message(store, elsewhere, 1);
    deliver(store, here, 3);
    deliver(store, elsewhere, 1);
    deliver(store, here, 1);
    deliver(store, here, 2);
    deliver(store, here, 4);
    deliver(store, here, 999);
    const old = store.pendingMessages("worker").filter((p) => p.message.apart !== true && p.message.thread === here && p.message.n < 4)
      .map((p) => p.message.ts);
    assert.deepEqual(old, ["3.1", "1.1", ""]);
    assert.deepEqual(store.pendingBefore("worker", here, 4), old);
  } finally { store.close(); }
});
