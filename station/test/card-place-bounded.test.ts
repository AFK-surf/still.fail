import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { cardPlace, postCard } from "../src/sessions/card-place.ts";
import { cardPostsStep } from "../src/store/card-post-index.ts";
import { Store, newMessage } from "../src/store/store.ts";

test("an operation finds its original card without reading the session's other conversations", () => {
  const store = Store.open(":memory:");
  try {
    const original = store.openThread("ember", "CHAT", "original", null, null).id;
    store.joinThread(original, "s", "local");
    store.insertMessage({ ...newMessage(original, "card", "agent", "s", "choose"), card: { type: "text" } });
    const add = (from: number, to: number) => {
      store.db.exec("BEGIN");
      for (let i = from; i <= to; i++) {
        const t = store.openThread("slack", "C", `other-${i}`, null, null);
        store.joinThread(t.id, "s", "slack");
      }
      store.db.exec("COMMIT");
    };
    let read = 0;
    const sessionThreads = store.sessionThreads.bind(store);
    store.sessionThreads = (session) => {
      const rows = sessionThreads(session);
      read += rows.length;
      return rows;
    };
    const locate = () => {
      read = 0;
      const place = cardPlace(store, "s", original, "card");
      assert.equal(place?.thread.thread.id, original);
      assert.equal(place?.thread.connect, "local");
      assert.equal(place?.state, "same");
      return read;
    };
    add(1, 40);
    const before = locate();
    add(41, 400);
    const after = locate();
    assert.equal(after, before, `finding the card read ${before}, then ${after}, linked conversations`);
    assert.equal(after, 0, "finding the card does not list the session's conversations");
  } finally { store.close(); }
});

test("a card place keeps its membership and pending-card semantics", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "place", null, null).id;
    store.joinThread(thread, "s", "local");
    assert.equal(cardPlace(store, "s", null, "card"), null);
    assert.equal(cardPlace(store, "s", thread, null), null);
    assert.equal(cardPlace(store, "s", thread, "card")?.state, "none");
    store.insertMessage({ ...newMessage(thread, "card", "agent", "s", "choose"), card: { type: "text" } });
    assert.equal(cardPlace(store, "s", thread, "card")?.state, "same");
    assert.equal(cardPlace(store, "s", thread, "other")?.state, "other");
    store.leaveThread(thread, "s");
    assert.equal(cardPlace(store, "s", thread, "card")?.state, "same", "a left member may still post");
    assert.throws(() => cardPlace(store, "different", thread, "card"), /no longer available/);
    store.db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='s'").run(thread);
    assert.throws(() => cardPlace(store, "s", thread, "card"), /no longer available/);
  } finally { store.close(); }
});

test("finding an operation's pending card does not merge its message", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "card-identity", null, null).id;
    store.joinThread(thread, "s", "local");
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','1.1','agent','s','choose',?,1)")
      .run(thread, JSON.stringify({ type: "text" }));
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, { get(target, key) {
      if (key === "prepare") return (sql: string) => {
        if (/\bFROM\s+merged\b/i.test(sql)) throw new Error("card identity merged its message");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } }) });
    try {
      assert.equal(cardPlace(store, "s", thread, "1.1")?.state, "same");
      assert.equal(cardPlace(store, "s", thread, "other")?.state, "other");
      db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,2,'message','2.2','person','p','answer',2)").run(thread);
      assert.equal(cardPlace(store, "s", thread, "1.1")?.state, "none");
    } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); }
  } finally { store.close(); }
});

test("a card place defers an old thread until its card posts are prepared", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-card-place", null, null).id;
    store.joinThread(thread, "s", "local");
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','1.1','agent','s','choose',?,1)")
      .run(thread, JSON.stringify({ type: "text" }));
    db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread);
    db.prepare("DELETE FROM card_posts WHERE thread=?").run(thread);
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, { get(target, key) {
      if (key === "prepare") return (sql: string) => {
        if (/SELECT n FROM entries WHERE thread = \? AND kind = 'message' AND (card|options) IS NOT NULL/i.test(sql))
          throw new Error("the station scanned an unprepared card index");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } }) });
    assert.equal(cardPlace(store, "s", thread, "1.1"), undefined);
    while (!cardPostsStep(db, thread).done) { /* bounded worker batches */ }
    assert.equal(cardPlace(store, "s", thread, "1.1")?.state, "same");
  } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); store.close(); }
});

test("a reasked card does not replace a card another connection wrote during confirmation", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-place-race-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "card-race", null, null).id;
    store.joinThread(thread, "s", "local");
    const where = store.sessionThreadById("s", thread)!;
    const header = store.pendingCardHeaderIfReady.bind(store);
    let changed = false;
    store.pendingCardHeaderIfReady = (id) => {
      const result = header(id);
      if (!changed) {
        changed = true;
        writer.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','other','agent','other','ask',?,1)")
          .run(thread, JSON.stringify({ type: "text" }));
      }
      return result;
    };
    const hub = { store, chat: () => ({ post: async () => "reasked" }), shared: () => {} };
    await assert.rejects(postCard(hub, "s", where, "ask again", { type: "text" }, (why) => new Error(why)), /Another card is pending/);
    assert.equal(changed, true);
    assert.deepEqual(dbRows(store, thread), ["other"]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a reasked card waits off the station thread for an external writer", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-place-busy-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  let transaction = false;
  try {
    const thread = store.openThread("ember", "CHAT", "card-busy", null, null).id;
    store.joinThread(thread, "s", "local");
    const where = store.sessionThreadById("s", thread)!;
    writer.exec("BEGIN IMMEDIATE"); transaction = true;
    const posted = Promise.withResolvers<void>();
    const hub = { store, chat: () => ({ post: async () => { posted.resolve(); return "reasked"; } }), shared: () => {} };
    let settled = false;
    const reask = postCard(hub, "s", where, "ask again", { type: "text" }, (why) => new Error(why));
    void reask.then(() => { settled = true; }, () => { settled = true; });
    await posted.promise;
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(settled, false, "the writer did not block the station or end the reask");
    writer.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','other','agent','other','ask',?,1)")
      .run(thread, JSON.stringify({ type: "text" }));
    writer.exec("COMMIT"); transaction = false;
    await assert.rejects(reask, /Another card is pending/);
    assert.deepEqual(dbRows(store, thread), ["other"]);
  } finally { if (transaction) writer.exec("ROLLBACK"); writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a cancelled reasked card stops waiting for an external writer", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-place-cancel-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  const controller = new AbortController();
  let transaction = false;
  try {
    const thread = store.openThread("ember", "CHAT", "card-cancel", null, null).id;
    store.joinThread(thread, "s", "local");
    const where = store.sessionThreadById("s", thread)!;
    writer.exec("BEGIN IMMEDIATE"); transaction = true;
    const posted = Promise.withResolvers<void>();
    const hub = { store, chat: () => ({ post: async () => { posted.resolve(); return "reasked"; } }), shared: () => {} };
    const reask = postCard(hub, "s", where, "ask again", { type: "text" }, (why) => new Error(why), undefined, controller.signal);
    void reask.catch(() => {});
    await posted.promise;
    await new Promise((resolve) => setImmediate(resolve));
    controller.abort();
    await assert.rejects(reask, { name: "AbortError" });
    assert.deepEqual(dbRows(store, thread), [], "no card was recorded after cancellation");
  } finally { if (transaction) writer.exec("ROLLBACK"); writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an external message already sent is recorded even if its caller cancels", async () => {
  const store = Store.open(":memory:"), controller = new AbortController();
  try {
    const thread = store.openThread("slack", "C", "sent", null, null).id;
    store.joinThread(thread, "s", "slack");
    const where = store.sessionThreadById("s", thread)!;
    const hub = { store, chat: () => ({ post: async () => { controller.abort(); return "sent"; } }), shared: () => {} };
    await postCard(hub, "s", where, "ask again", null, (why) => new Error(why), undefined, controller.signal);
    assert.deepEqual(dbRows(store, thread), ["sent"]);
  } finally { store.close(); }
});

test("a reasked card continues after an unrelated external write", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-place-busy-unrelated-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  let transaction = false;
  try {
    const thread = store.openThread("ember", "CHAT", "card-busy-unrelated", null, null).id;
    store.joinThread(thread, "s", "local");
    const where = store.sessionThreadById("s", thread)!;
    writer.exec("BEGIN IMMEDIATE"); transaction = true;
    const posted = Promise.withResolvers<void>();
    const hub = { store, chat: () => ({ post: async () => { posted.resolve(); return "reasked"; } }), shared: () => {} };
    const reask = postCard(hub, "s", where, "ask again", { type: "text" }, (why) => new Error(why));
    await posted.promise;
    await new Promise((resolve) => setImmediate(resolve));
    writer.prepare("UPDATE threads SET title='unrelated' WHERE id=?").run(thread);
    writer.exec("COMMIT"); transaction = false;
    assert.equal(await reask, "reasked");
    assert.deepEqual(dbRows(store, thread), ["reasked"]);
  } finally { if (transaction) writer.exec("ROLLBACK"); writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an error after a reasked card was recorded does not retry the write", async () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "card-after-write", null, null).id;
    store.joinThread(thread, "s", "local");
    const where = store.sessionThreadById("s", thread)!;
    let announced = 0;
    const busy = Object.assign(new Error("synthetic post-commit busy"), { errcode: 5 });
    const hub = { store, chat: () => ({ post: async () => "reasked" }), shared: () => { announced++; throw busy; } };
    await assert.rejects(postCard(hub, "s", where, "ask again", { type: "text" }, (why) => new Error(why)), /synthetic post-commit busy/);
    assert.equal(announced, 1);
    assert.deepEqual(dbRows(store, thread), ["reasked"]);
  } finally { store.close(); }
});

function dbRows(store: Store, thread: number): string[] {
  return (store.db.prepare("SELECT ts FROM entries WHERE thread=? AND kind='message' ORDER BY n").all(thread) as { ts: string }[]).map((r) => r.ts);
}
