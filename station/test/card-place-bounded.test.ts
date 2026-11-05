import assert from "node:assert/strict";
import { test } from "node:test";
import { cardPlace } from "../src/sessions/card-place.ts";
import { Store, newMessage } from "../src/store/store.ts";

test("an operation finds its original card without reading the session's other conversations", () => {
  const store = Store.open(":memory:");
  try {
    const original = store.openThread("ember", "EMBER", "original", null, null).id;
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
  } finally { store.close(); }
});

test("a card place keeps its membership and pending-card semantics", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "EMBER", "place", null, null).id;
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
