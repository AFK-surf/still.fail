import assert from "node:assert/strict";
import { test } from "node:test";
import { outflowChats } from "../src/read/outflow.ts";
import { firstText, getThread, makeStore } from "../src/read/store.ts";
import { titleOf } from "../src/read/views.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { installOutflowChatIndex, outflowChatIndexStep, outflowChatScopes } from "../src/store/outflow-index.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

function fixture(surface: string, channel: string, title: string | null, autoTitle: string | null = null) {
  const store = Store.open(":memory:");
  store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a",
    token: "a", createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws: null });
  const thread = store.openThreadOf(surface, channel, "100.1", title, "ann@x", "a");
  store.joinThread(thread.id, "a", "ember");
  const db = store.db;
  if (autoTitle !== null) db.prepare("UPDATE threads SET auto_title = ? WHERE id = ?").run(autoTitle, thread.id);
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,?,?,?,?,?,?)`);
  put.run(thread.id, 1, "message", null, "person", "ann@x", "first words", 1);
  for (let n = 2; n <= 81; n++) put.run(thread.id, n, "edit", n + 1000, "agent", "worker", `edit-${n}`, n);
  installLegacyEdits(db);
  addClientColumn(db);
  installOutflowChatIndex(db);
  for (const scope of outflowChatScopes({ workspace: "\u0000home", home: true }))
    while (!outflowChatIndexStep(db, scope).done) { /* bounded batches */ }
  return { store, thread, reader: makeStore(db, ".") };
}

for (const [surface, channel, title, autoTitle] of [
  ["ember", "CHAT", null, null],
  ["chat", "CHAT", "Given title", null],
  ["stillfail", "CHAT", "  ", null],
  ["slack:fs", "C1", " Named thread ", null],
  ["slack:fs", "C1", "  ", "Agent title"],
] as const) {
  test(`exporting ${surface} with title ${String(title)} and auto title ${String(autoTitle)} needs no first text`, () => {
    const f = fixture(surface, channel, title, autoTitle);
    try {
      assert.throws(() => firstText(f.reader, f.thread.id), { status: 503, message: "legacy edit lookup pending" });
      const thread = getThread(f.reader, f.thread.id)!;
      const result = outflowChats(f.reader, 0);
      assert.equal(result.chats.length, 1);
      assert.equal(result.chats[0].title, titleOf(thread, null, null));
      const page = outflowChats(f.reader, 0, undefined, { limit: 1, before: null });
      assert.deepEqual(page.chats, result.chats);
      assert.equal(page.more, false);
      assert.equal(page.next, null);
    } finally { f.store.close(); }
  });
}

for (const title of [null, "  \t "] as const) {
  test(`an external chat with title ${String(title)} waits for its first text and uses it when ready`, () => {
    const f = fixture("slack:fs", "C1", title, "  ");
    try {
      assert.throws(() => outflowChats(f.reader, 0), { status: 503, message: "legacy edit lookup pending" });
      while (!legacyEditStep(f.store.db).ready) { /* bounded batches */ }
      while (legacyEditDrain(f.store.db) > 0) { /* reconcile */ }
      assert.equal(outflowChats(f.reader, 0).chats[0].title, "first words");
    } finally { f.store.close(); }
  });
}
