import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { message, Rig, settle } from "./hub-fakes.ts";

const turn = () => new Promise<void>((resolve) => setImmediate(resolve));

function oldThread(r: Rig, installed = true, last = 150) {
  const thread = r.store.openThread("slack:T1", "C1", "old-thread", null, null).id;
  r.store.insertMessage({ thread, ts: "old-post", authorKind: "person", author: "p", text: "original" });
  const db = r.store.db;
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p',?,?)");
  db.exec("BEGIN");
  put.run(thread, 2, 1, "previous", 2);
  for (let n = 3; n <= last; n++) put.run(thread, n, n + 10000, "other", n);
  db.exec("COMMIT");
  if (installed) { installLegacyEdits(db); addClientColumn(db); }
  return thread;
}

const event = (text: string) => ({ type: "changed" as const, channel: "C1", threadTs: "old-thread", ts: "old-post", text });
const build = (r: Rig) => {
  while (!legacyEditStep(r.store.db).ready) { /* bounded worker steps */ }
  while (legacyEditDrain(r.store.db)) { /* reconcile writes */ }
};

test("a platform edit waits for old edits off the station thread, then is recorded", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  let pending: Promise<unknown> | undefined;
  try {
    const thread = oldThread(r);
    let started = 0, settled = false;
    r.hub.prepareLegacyEdits = async () => { started++; await release.promise; build(r); };
    pending = r.hub.receive("cl", event("latest"));
    void pending.then(() => { settled = true; }, () => { settled = true; });
    await turn();
    assert.equal(started, 1, "preparation was requested");
    assert.equal(settled, false, "the platform event is not acknowledged before it is recorded");
    assert.equal(r.store.db.prepare("SELECT text FROM entries WHERE thread=? AND target=1 ORDER BY n DESC LIMIT 1").get(thread)?.text, "previous");
    release.resolve();
    await pending;
    assert.equal(r.store.messageAt(thread, "old-post")?.text, "latest");
  } finally { release.resolve(); await Promise.allSettled(pending ? [pending] : []); await r.close(); }
});

test("platform edits for the same thread keep their arrival order while old edits are prepared", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  const pending: Promise<unknown>[] = [];
  try {
    const thread = oldThread(r);
    let started = 0;
    r.hub.prepareLegacyEdits = async () => { started++; await release.promise; build(r); };
    pending.push(r.hub.receive("cl", event("first")), r.hub.receive("cl", event("second")));
    for (const p of pending) void p.catch(() => {});
    await turn();
    assert.equal(started, 1, "the second event waits behind the first");
    release.resolve();
    await Promise.all(pending);
    assert.deepEqual(r.store.db.prepare("SELECT text FROM entries WHERE thread=? AND target=1 ORDER BY n DESC LIMIT 2")
      .all(thread).map((row) => row.text), ["second", "first"]);
    assert.equal(r.store.messageAt(thread, "old-post")?.text, "second");
  } finally { release.resolve(); await Promise.allSettled(pending); await r.close(); }
});

test("a missing platform message does not wait for old edits", async () => {
  const r = new Rig();
  try {
    oldThread(r);
    let started = 0;
    r.hub.prepareLegacyEdits = async () => { started++; };
    await r.hub.receive("cl", { ...event("not found"), ts: "missing" });
    assert.equal(started, 0);
  } finally { await r.close(); }
});

for (const kind of ["short chat", "recent edit"] as const) {
  test(`a platform edit with a ${kind} does not wait for other old history`, async () => {
    const r = new Rig();
    try {
      const thread = oldThread(r, true, kind === "short chat" ? 10 : 150);
      if (kind === "recent edit") r.store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
        VALUES(?,151,'edit',1,'person','p','recent',151)`).run(thread);
      let started = 0;
      r.hub.prepareLegacyEdits = async () => { started++; throw new Error("unneeded preparation"); };
      await r.hub.receive("cl", event("updated"));
      assert.equal(started, 0);
      assert.equal(r.store.messageAt(thread, "old-post")?.text, "updated");
    } finally { await r.close(); }
  });
}

test("a bounded edit keeps the previous edit's attachments and quotes", async () => {
  const r = new Rig();
  try {
    const thread = oldThread(r, true, 10);
    const attachments = [{ name: "file.txt", path: "/file.txt", size: 4 }];
    const quotes = [{ author: "p", text: "quoted", comment: "" }];
    r.store.db.prepare("UPDATE entries SET attachments=?, quotes=? WHERE thread=? AND n=2")
      .run(JSON.stringify(attachments), JSON.stringify(quotes), thread);
    r.hub.prepareLegacyEdits = async () => { throw new Error("unneeded preparation"); };
    await r.hub.receive("cl", event("updated"));
    const saved = r.store.db.prepare("SELECT attachments,quotes FROM entries WHERE thread=? AND target=1 ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.deepEqual(JSON.parse(saved.attachments as string), attachments);
    assert.deepEqual(JSON.parse(saved.quotes as string), quotes);
  } finally { await r.close(); }
});

test("a later message in the thread waits for the pending edit", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  const pending: Promise<unknown>[] = [];
  try {
    const thread = oldThread(r);
    r.hub.prepareLegacyEdits = async () => { await release.promise; build(r); };
    pending.push(r.hub.receive("cl", event("first")));
    pending.push(r.hub.accept("cl", message({ channel: "C1", threadTs: "old-thread", ts: "later-post", text: "later", addressed: true })));
    for (const p of pending) void p.catch(() => {});
    await turn();
    assert.equal(r.store.messageNumberAt(thread, "later-post"), null, "the later message has not overtaken the edit");
    release.resolve();
    await Promise.all(pending);
    await settle();
    const edit = r.store.db.prepare("SELECT n FROM entries WHERE thread=? AND target=1 AND text='first'").get(thread)!.n as number;
    const later = r.store.messageNumberAt(thread, "later-post");
    assert.ok(later !== null && later > edit);
  } finally { release.resolve(); await Promise.allSettled(pending); await r.close(); }
});

test("a failed preparation leaves the event unrecorded and the thread can retry", async () => {
  const r = new Rig();
  try {
    const thread = oldThread(r);
    r.hub.prepareLegacyEdits = async () => { throw new Error("preparation failed"); };
    await assert.rejects(r.hub.receive("cl", event("retry")), /preparation failed/);
    assert.equal(r.store.db.prepare("SELECT text FROM entries WHERE thread=? AND target=1 ORDER BY n DESC LIMIT 1").get(thread)?.text, "previous");
    r.hub.prepareLegacyEdits = async () => build(r);
    await r.hub.receive("cl", event("retry"));
    assert.equal(r.store.messageAt(thread, "old-post")?.text, "retry");
  } finally { await r.close(); }
});

test("a message behind a failed edit is left for redelivery with it", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  const pending: Promise<unknown>[] = [];
  try {
    const thread = oldThread(r);
    r.hub.prepareLegacyEdits = async () => { await release.promise; throw new Error("preparation failed"); };
    pending.push(r.hub.receive("cl", event("first")));
    const later = message({ channel: "C1", threadTs: "old-thread", ts: "later-post", text: "later", addressed: true });
    pending.push(r.hub.accept("cl", later));
    for (const p of pending) void p.catch(() => {});
    await turn();
    release.resolve();
    for (const p of pending) await assert.rejects(p, /preparation failed/);
    assert.equal(r.store.messageNumberAt(thread, "later-post"), null);
    r.hub.prepareLegacyEdits = async () => build(r);
    await r.hub.receive("cl", event("first"));
    await r.hub.accept("cl", later);
    await settle();
    const edit = r.store.db.prepare("SELECT n FROM entries WHERE thread=? AND target=1 AND text='first'").get(thread)!.n as number;
    assert.ok(r.store.messageNumberAt(thread, "later-post")! > edit);
  } finally { release.resolve(); await Promise.allSettled(pending); await r.close(); }
});

test("a different short thread can accept an edit while an old thread waits", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  let waiting: Promise<unknown> | undefined;
  try {
    oldThread(r);
    const other = r.store.openThread("slack:T1", "C2", "other", null, null).id;
    r.store.insertMessage({ thread: other, ts: "post", authorKind: "person", author: "p", text: "before" });
    r.hub.prepareLegacyEdits = async () => { await release.promise; build(r); };
    waiting = r.hub.receive("cl", event("waiting"));
    void waiting.catch(() => {});
    await turn();
    await r.hub.receive("cl", { type: "changed", channel: "C2", threadTs: "other", ts: "post", text: "after" });
    assert.equal(r.store.db.prepare("SELECT text FROM entries WHERE thread=? AND target=1 ORDER BY n DESC LIMIT 1").get(other)?.text, "after");
    release.resolve();
    await waiting;
  } finally { release.resolve(); await Promise.allSettled(waiting ? [waiting] : []); await r.close(); }
});

test("an edit is checked again after preparation when another writer already recorded it", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  let waiting: Promise<unknown> | undefined;
  try {
    const thread = oldThread(r);
    r.hub.prepareLegacyEdits = async () => { await release.promise; build(r); };
    waiting = r.hub.receive("cl", event("raced"));
    void waiting.catch(() => {});
    await turn();
    r.store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,151,'edit',1,'person','p','raced',151)`).run(thread);
    release.resolve();
    await waiting;
    assert.equal(r.store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=? AND target=1 AND text='raced'").get(thread)?.n, 1);
  } finally { release.resolve(); await Promise.allSettled(waiting ? [waiting] : []); await r.close(); }
});

test("an edit prepares again if changed keys grow after the first preparation", async () => {
  const r = new Rig();
  try {
    const thread = oldThread(r);
    let preparations = 0;
    r.hub.prepareLegacyEdits = async () => {
      preparations++;
      build(r);
      if (preparations === 1) {
        const insert = r.store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
          VALUES(?,?,'edit',?,'person','p','other',?)`);
        for (let n = 151; n <= 215; n++) insert.run(thread, n, n + 10000, n);
      }
    };
    await r.hub.receive("cl", event("after preparation"));
    assert.equal(preparations, 2);
    assert.equal(r.store.messageAt(thread, "old-post")?.text, "after preparation");
  } finally { await r.close(); }
});

test("a platform edit repairs a removed index through the real background worker", async () => {
  const r = new Rig();
  await r.hub.shutdown();
  r.store.close();
  r.store = Store.open(join(r.dir, "stillfail.db"));
  r.hub = r.newHub({ chats: (id) => id === "cl" ? r.chat : undefined });
  const readers = new Readers(r.dir, 1, undefined, 1);
  try {
    const thread = oldThread(r, false);
    r.hub.prepareLegacyEdits = () => readers.prepareLegacyEdits();
    await r.hub.receive("cl", event("repaired"));
    assert.equal(r.store.messageAt(thread, "old-post")?.text, "repaired");
    assert.equal(r.store.db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 1);
  } finally { readers.close(); await r.close(); }
});

test("an edit's readiness and merged message use the same snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "platform-edit-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, other = new DatabaseSync(path);
  try {
    const thread = store.openThread("slack:T1", "C1", "old-thread", null, null).id;
    store.insertMessage({ thread, ts: "old-post", authorKind: "person", author: "p", text: "original" });
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db);
    addClientColumn(db);
    while (!legacyEditStep(db).ready) { /* prepare */ }
    while (legacyEditDrain(db)) { /* reconcile */ }
    let wrote = false;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        if (!sql.includes("SELECT scanned=1 AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty")) return stmt;
        return new Proxy(stmt, { get(statement, member) {
          if (member === "get") return (...args: Parameters<typeof statement.get>) => {
            const row = statement.get(...args);
            if (!wrote) {
              wrote = true;
              other.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,2,'edit',1,'person','p','concurrent',2)").run(thread);
            }
            return row;
          };
          const value = Reflect.get(statement, member, statement);
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = traced;
    assert.equal(store.editMessageIfReady("slack:T1", "C1", "old-thread", "old-post", "original"), null);
    assert.equal(wrote, true);
    assert.equal(store.messageAt(thread, "old-post")?.text, "concurrent");
  } finally { (store as any).db = db; other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("shutdown cancels an edit's background preparation without waiting for it", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  let pending: Promise<unknown> | undefined;
  try {
    oldThread(r);
    let started = false, rejected = false;
    r.hub.prepareLegacyEdits = (signal?: AbortSignal) => new Promise<void>((resolve, reject) => {
      started = true;
      release.promise.then(resolve);
      signal?.addEventListener("abort", () => reject(signal.reason), { once: true });
    });
    pending = r.hub.receive("cl", event("pending"));
    void pending.catch(() => { rejected = true; });
    await turn();
    assert.equal(started, true);
    await r.hub.shutdown();
    await turn();
    assert.equal(rejected, true);
    await assert.rejects(pending, { name: "AbortError" });
  } finally { release.resolve(); await Promise.allSettled(pending ? [pending] : []); await r.close(); }
});

for (const stop of ["shutdown", "handover"] as const) {
  test(`platform edits waiting for old preparation do not write after ${stop}`, async () => {
    const r = new Rig(), release = Promise.withResolvers<void>();
    const pending: Promise<unknown>[] = [];
    try {
      const thread = oldThread(r);
      r.hub.prepareLegacyEdits = async () => { await release.promise; build(r); };
      pending.push(r.hub.receive("cl", event("first")), r.hub.receive("cl", event("second")));
      pending.push(r.hub.accept("cl", message({ channel: "C1", threadTs: "old-thread", ts: "later-post", text: "later", addressed: true })));
      for (const p of pending) void p.catch(() => {});
      await turn();
      if (stop === "shutdown") await r.hub.shutdown();
      else await r.hub.handOver();
      release.resolve();
      for (const p of pending) await assert.rejects(p, { name: "AbortError" });
      assert.equal(r.store.db.prepare("SELECT text FROM entries WHERE thread=? AND target=1 ORDER BY n DESC LIMIT 1").get(thread)?.text, "previous");
      assert.equal(r.store.messageNumberAt(thread, "later-post"), null);
    } finally { release.resolve(); await Promise.allSettled(pending); await r.close(); }
  });
}
