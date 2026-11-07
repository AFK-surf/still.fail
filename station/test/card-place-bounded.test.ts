import assert from "node:assert/strict";
import { test } from "node:test";
import { cardPlace } from "../src/sessions/card-place.ts";
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
        if (/\bFROM\s+merged\b/i.test(sql)) throw new Error("card identity merged an unrelated message");
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
