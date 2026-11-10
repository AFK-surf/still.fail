import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { recentChatPage, RECENT_CHAT_PENDING } from "../src/read/recent-chat.ts";
import { installRecentHomeIndex } from "../src/store/chat-list-home-index.ts";
import { installRecentHomeOverlap } from "../src/store/chat-list-home-overlap.ts";
import { installRecentChatIndex } from "../src/store/chat-list-index.ts";
import { installRecentScopeJournal, trackRecentScope } from "../src/store/chat-list-scope-journal.ts";
import { RECENT_CHAT_SCHEMA_VERSION, recentChatIndexInstalled } from "../src/store/chat-list-schema.ts";
import { Store } from "../src/store/store.ts";

for (const part of ["global", "scope", "home", "overlap"] as const) test(`a recent ${part} index with another version is not read or built`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    assert.throws(() => recentChatPage(db, null, "home", 5), new RegExp(RECENT_CHAT_PENDING));
    installRecentChatIndex(db);
    installRecentHomeOverlap(db);
    trackRecentScope(db, { kind: "workspace", workspace: "here" });
    db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = 'here'").run();
    const page = () => part === "global" ? recentChatPage(db, null, "home", 5)
      : part === "scope" ? recentChatPage(db, "here", "other", 5) : recentChatPage(db, "here", "here", 5);
    assert.deepEqual(page(), { ids: [], total: 0 });
    db.exec("CREATE TABLE IF NOT EXISTS recent_chat_versions (part TEXT PRIMARY KEY, version INTEGER NOT NULL) WITHOUT ROWID");
    db.prepare(`INSERT INTO recent_chat_versions(part, version) VALUES (?, 2)
      ON CONFLICT(part) DO UPDATE SET version = excluded.version`).run(part);
    assert.throws(page, /recent chat.*version/i, "a ready-looking incompatible index must not return a stale page");
    const install = { global: installRecentChatIndex, scope: installRecentScopeJournal,
      home: installRecentHomeIndex, overlap: installRecentHomeOverlap }[part];
    assert.throws(() => install(db), /recent chat.*version/i, "the builder must not write an incompatible index");
    if (part === "scope") assert.throws(() => recentChatPage(db, "here", "here", 5), /recent chat.*version/i);
    if (part !== "global") assert.deepEqual(recentChatPage(db, null, "home", 5), { ids: [], total: 0 });
    db.prepare("UPDATE recent_chat_versions SET version = 1 WHERE part = ?").run(part);
    assert.deepEqual(page(), { ids: [], total: 0 });
    db.prepare("DELETE FROM recent_chat_versions WHERE part = ?").run(part);
    assert.throws(page, /recent chat.*version/i, "an existing index without its marker is not assumed compatible");
    assert.throws(() => install(db), /recent chat.*version/i);
  } finally { store.close(); }
});

test("a component installed on another connection during the version check is recognized", () => {
  const dir = mkdtempSync(join(tmpdir(), "recent-index-version-")), path = join(dir, "station.db");
  const store = Store.open(path), other = new DatabaseSync(path, { timeout: 5000 });
  try {
    let installed = false;
    const interleaved = new Proxy(store.db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          try { return target.prepare(sql); }
          catch (error) {
            if (sql === RECENT_CHAT_SCHEMA_VERSION && !installed) { installed = true; installRecentScopeJournal(other); }
            throw error;
          }
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.equal(recentChatIndexInstalled(interleaved, "scope"), true);
    assert.ok(installed);
  } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const part of ["global", "scope", "home", "overlap"] as const) test(`a failed recent ${part} version marker rolls back its component`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    if (part === "home") installRecentScopeJournal(db);
    if (part === "overlap") installRecentHomeIndex(db);
    const install = { global: installRecentChatIndex, scope: installRecentScopeJournal,
      home: installRecentHomeIndex, overlap: installRecentHomeOverlap }[part];
    const table = { global: "recent_chat_meta", scope: "recent_scope_tracked",
      home: "recent_home_meta", overlap: "recent_home_overlap_meta" }[part];
    db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "recent_chat_versions"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.throws(() => install(db)); }
    finally { db.setAuthorizer(null); }
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(table), undefined);
    install(db);
    assert.equal(db.prepare("SELECT version FROM recent_chat_versions WHERE part = ?").get(part)?.version, 1);
  } finally { db.setAuthorizer(null); store.close(); }
});
