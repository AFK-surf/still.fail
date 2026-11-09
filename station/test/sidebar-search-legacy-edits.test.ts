import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { sessionOps } from "../src/read/ops-sessions.ts";
import { Readers } from "../src/read/pool.ts";
import { LAST_MESSAGE_RECENT_EDIT, LAST_MESSAGE_WITH_EDIT, lastSaid, makeStore } from "../src/read/store.ts";
import { searchChats, type RecentChatList } from "../src/store/chat-list.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

function oldSearch(size: number, prepared: boolean, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `search-old-edits-${size}-${prepared}`, null, null).id;
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
    VALUES(?,?,?,?,?,?,?,?)`);
  db.exec("BEGIN");
  put.run(thread, 1, "message", null, "person", "me", "needle", 1);
  for (let n = 2; n <= size + 1; n++)
    put.run(thread, n, "edit", prepared ? 1 : n + 1000, "agent", "worker", `edit-${n}`, n);
  db.exec("COMMIT");
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  installLegacyEdits(db);
  if (prepared) {
    while (!legacyEditStep(db).ready) { /* prepare */ }
    db.prepare("UPDATE entries SET target=2 WHERE thread=? AND target=1").run(thread);
  }
  addClientColumn(db);
  return { store, db, thread };
}

const args = { ws: null, home: null, limit: 10, query: "needle" };
const search = (db: DatabaseSync, data = "/unused", query = args.query) =>
  sessionOps.searchChatList!(makeStore(db, data), { ...args, query }) as RecentChatList;

for (const prepared of [false, true])
  test(`a search leaves a long old edit lookup to bounded preparation (prepared ${prepared})`, () => {
    for (const size of [80, 800]) {
      const { store, db } = oldSearch(size, prepared);
      try {
        // Even an unmatched chat's old text must not be scanned before deciding whether it matches.
        assert.throws(() => search(db, "/unused", "absent"), { status: 503, message: "legacy edit lookup pending" });
        assert.throws(() => search(db), { status: 503, message: "legacy edit lookup pending" });
        while (!legacyEditStep(db).ready) { /* prepare */ }
        while (legacyEditDrain(db) > 0) { /* reconcile */ }
        assert.equal(search(db, "/unused", "absent").total, 0);
        const result = search(db);
        assert.equal(result.total, 1);
        assert.equal(result.threads[0]?.firstText, "needle");
        assert.equal(result.threads[0]?.lastMessage?.text, "needle");
      } finally { store.close(); }
    }
  });

for (const changed of [64, 65])
  test(`a search handles ${changed} pending old edit keys`, () => {
    const { store, db } = oldSearch(changed, true);
    try {
      if (changed === 64) assert.equal(search(db, "/unused", "absent").total, 0);
      else assert.throws(() => search(db, "/unused", "absent"), { status: 503, message: "legacy edit lookup pending" });
      while (legacyEditDrain(db) > 0) { /* reconcile */ }
      assert.equal(search(db).threads[0]?.firstText, "needle");
    } finally { store.close(); }
  });

test("a short old chat can be searched while the edit lookup is incomplete", () => {
  const { store, db, thread } = oldSearch(0, false);
  try {
    db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,'edit',1,'agent','worker','needle edited',2)`).run(thread, 9007199254740993n);
    const result = search(db);
    assert.equal(result.total, 1);
    assert.equal(result.threads[0]?.firstText, "needle edited");
    assert.equal(result.threads[0]?.lastMessage?.text, "needle edited");
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("only matching old chats have their full message loaded", () => {
  const { store, db } = oldSearch(0, false);
  try {
    let fullReads = 0;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LAST_MESSAGE_WITH_EDIT) fullReads++;
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal(search(observed, "/unused", "absent").total, 0);
    assert.equal(fullReads, 0);
    assert.equal(search(observed).total, 1);
    assert.equal(fullReads, 1);
  } finally { store.close(); }
});

test("bounded old-chat search keeps the regular search's results and ordering", () => {
  const { store, db } = oldSearch(0, false);
  try {
    store.insertSession({ key: "agent", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "token", createdAt: 1, lastActiveAt: 1 });
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,?,?,?,?,?,?)`);
    for (let i = 0; i < 3; i++) {
      const thread = store.openThread("ember", "CHAT", `search-parity-${i}`, i === 1 ? "titled" : null, null).id;
      store.joinThread(thread, "agent", "ember");
      put.run(thread, 1, "message", null, "person", "me", `first ${i}`, 2 + i);
      put.run(thread, 2, "message", null, "agent", "worker", `last ${i}`, 5 + i);
      put.run(thread, 3, "edit", 2, "agent", "worker", i === 0 ? null : `edited ${i}`, 8 + i);
    }
    const read = makeStore(db, "/unused");
    for (const query of ["", "needle", "first", "edited", "titled", "agent", "absent"]) {
      for (const limit of [1, 10]) {
        const expected = searchChats(db, null, null, limit, query, (id) => lastSaid(read, id));
        const actual = sessionOps.searchChatList!(read, { ws: null, home: null, limit, query });
        assert.deepEqual(actual, expected, `${query}, limit ${limit}`);
      }
    }
  } finally { store.close(); }
});

test("search text and its returned message share a snapshot during old-edit probing", () => {
  const dir = mkdtempSync(join(tmpdir(), "search-edit-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldSearch(80, false, path);
  db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
    VALUES(?,82,'edit',1,'agent','worker','needle before',82)`).run(thread);
  const writer = new DatabaseSync(path);
  try {
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LAST_MESSAGE_RECENT_EDIT && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET text='needle after' WHERE thread=? AND n=82").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const before = search(observed, dir);
    assert.ok(changed);
    assert.equal(before.total, 1);
    assert.equal(before.threads[0]?.firstText, "needle before");
    assert.equal(before.threads[0]?.lastMessage?.text, "needle before");
    const after = search(observed, dir);
    assert.equal(after.threads[0]?.firstText, "needle after");
    assert.equal(after.threads[0]?.lastMessage?.text, "needle after");
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("searches share old-edit preparation after handover even when one reader cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "search-old-edits-")), path = join(dir, "stillfail.db");
  const { store, db } = oldSearch(150, false, path);
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const abandoned = readers.read("searchChatList", args, "en", { signal: controller.signal });
    const kept = readers.read("searchChatList", args, "en");
    const empty = store.openThread("ember", "CHAT", "empty-search-edit", null, null).id;
    assert.deepEqual(JSON.parse(await readers.read("latestMessages", { thread: empty, limit: 2 }, "en")), []);
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    const result = JSON.parse(await kept);
    assert.equal(result.total, 1);
    assert.equal(result.threads[0]?.firstText, "needle");
    assert.equal(result.threads[0]?.lastMessage?.text, "needle");
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
