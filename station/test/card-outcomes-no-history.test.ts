import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { decisionCards, makeStore, usageChatsReady } from "../src/read/store.ts";
import { addCardOutcomes } from "../src/store/schema.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";
import { fileAway } from "./archived-before.ts";

const card = { type: "options" as const, options: [{ label: "yes" }] };

test("installing decision statistics only checks whether old messages exist", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "EMBER", "old", null, null).id;
    store.insertMessage({ ...newMessage(thread, "1", "agent", "agent", "pick"), card });
    store.db.exec("DROP TRIGGER card_outcomes_asked; DROP TRIGGER card_outcomes_answered; DROP TRIGGER card_outcomes_dropped; DROP TABLE card_outcomes");
    store.db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "entries" && column
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { addCardOutcomes(store.db); }
    finally { store.db.setAuthorizer(null); }
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM card_outcomes").get() as { n: number }).n, 0);
  } finally { store.close(); }
});

test("an old database keeps new decisions but never reports its missing history as complete", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-no-history-"));
  const path = join(dir, "stillfail.db");
  let store: Store | null = null;
  try {
    store = Store.open(path);
    const thread = store.openThread("ember", "EMBER", "old", null, null).id;
    store.insertMessage({ ...newMessage(thread, "1", "agent", "agent", "pick"), card });
    store.insertMessage(newMessage(thread, "2", "person", "person", "yes"));
    // Simulate a station from before either derived table existed.
    const objects = store.db.prepare("SELECT type, name FROM sqlite_master WHERE type IN ('trigger', 'table')").all() as { type: string; name: string }[];
    for (const type of ["trigger", "table"] as const) {
      for (const object of objects.filter((x) => x.type === type && x.name.startsWith("usage_chat_"))) {
        store.db.exec(`DROP ${type.toUpperCase()} "${object.name.replaceAll('"', '""')}"`);
      }
    }
    store.db.exec("DROP TRIGGER card_outcomes_asked; DROP TRIGGER card_outcomes_answered; DROP TRIGGER card_outcomes_dropped; DROP TABLE card_outcomes");
    store.close();
    store = Store.open(path);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM card_outcomes").get() as { n: number }).n, 0);
    // Even if the other chat summaries are complete, the old card results are not.
    store.db.exec("UPDATE usage_chat_progress SET done = 1; DELETE FROM usage_chat_dirty; DELETE FROM usage_chat_dirty_scope");
    assert.throws(() => usageChatsReady(makeStore(store!.db, dir), null), /usage chat statistics/);
    assert.throws(() => decisionCards(makeStore(store!.db, dir)), /usage chat statistics/);
    store.insertMessage({ ...newMessage(thread, "3", "agent", "agent", "new pick"), card });
    store.insertMessage(newMessage(thread, "4", "person", "person", "yes"));
    assert.deepEqual((store.db.prepare("SELECT answered, said FROM card_outcomes").all() as { answered: number; said: number }[])
      .map((row) => [row.answered, row.said]), [[1, 1]]);
    store.close();
    store = Store.open(path);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM card_outcomes").get() as { n: number }).n, 1);
    assert.throws(() => usageChatsReady(makeStore(store!.db, dir), null), /usage chat statistics/);
    const reader = new MinuteReader(path);
    try { await assert.rejects(reader.readyChats(null), /chat.*unavailable/i); }
    finally { await reader.close(); }
  } finally {
    store?.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("restoring old archived chats does not reconstruct their decision statistics", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-archive-no-history-"));
  const path = join(dir, "stillfail.db");
  let store: Store | null = null;
  try {
    store = Store.open(path);
    const threads = ["a", "b"].map((name) => store!.openThread("ember", "EMBER", name, null, null).id);
    for (const thread of threads) {
      store.insertMessage({ ...newMessage(thread, "1", "agent", "agent", "pick"), card });
      store.insertMessage(newMessage(thread, "2", "person", "person", "yes"));
      fileAway(store, thread);
    }
    store.close();
    store = Store.open(path);
    for (const thread of threads) assert.equal(store.entriesAfter(thread, 0).length, 2);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM card_outcomes").get() as { n: number }).n, 0);
    assert.throws(() => usageChatsReady(makeStore(store!.db, dir), null), /usage chat statistics/);
    store.insertMessage({ ...newMessage(threads[0]!, "3", "agent", "agent", "new pick"), card });
    store.insertMessage(newMessage(threads[0]!, "4", "person", "person", "yes"));
    assert.deepEqual((store.db.prepare("SELECT answered, said FROM card_outcomes").all() as { answered: number; said: number }[])
      .map((row) => [row.answered, row.said]), [[1, 1]]);
    store.close();
    store = Store.open(path);
    assert.throws(() => usageChatsReady(makeStore(store!.db, dir), null), /usage chat statistics/);
  } finally {
    store?.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
