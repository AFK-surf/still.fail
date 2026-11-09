import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { SessionDirectoryBuilder } from "../src/sessions/session-directory-builder.ts";
import { installSessionDirectories, sessionDirectoriesReady, sessionDirectoriesStep, sessionDirectory } from "../src/store/session-directory.ts";
import { Store } from "../src/store/store.ts";

const add = `INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,cwd,token,created_at,last_active_at,archived_at)
  VALUES (?,'connected','thread','codex','default',?,?,?,0,?,?)`;

function oldSession(store: Store, dir: string): string | null {
  const from = (sessions: { key: string; workspace: string; cwd: string | null }[]) => {
    let best: { key: string; length: number } | null = null;
    for (const s of sessions) for (const root of [s.workspace, s.cwd]) {
      if (!root || !(dir === root || dir.startsWith(root.endsWith("/") ? root : `${root}/`))) continue;
      if (best === null || root.length > best.length) best = { key: s.key, length: root.length };
    }
    return best?.key ?? null;
  };
  return from(store.liveSessions()) ?? from(store.listSessions());
}

function finish(db: DatabaseSync) { while (!sessionDirectoriesReady(db)) sessionDirectoriesStep(db, 3); }

test("directory lookup follows the old longest-root, live and activity rules as sessions change", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const put = db.prepare(add);
    put.run("shallow", "/code", null, "one", 2, null);
    put.run("deep-old", "/other", "/code/app", "two", 3, null);
    put.run("deep-new", "/else", "/code/app", "three", 3, null);
    put.run("archived", "/code/app/more", null, "four", 99, 1);
    put.run("slash", "/code//", null, "five", 1, null);
    put.run("relative", "repo/", null, "six", 1, null);
    installSessionDirectories(db);
    finish(db);
    const dirs = ["/code/app/more/file", "/code/app", "/code//sub", "/code/", "/elsewhere", "repo/file", "", "/"];
    const check = () => { for (const dir of dirs) assert.equal(sessionDirectory(db, dir)?.key, oldSession(store, dir), dir); };
    check();
    db.prepare("UPDATE sessions SET last_active_at = 7 WHERE key = 'deep-old'").run();
    check(); // Activity changes need no directory-index write.
    db.prepare("UPDATE sessions SET archived_at = 1 WHERE key IN ('deep-old', 'deep-new')").run();
    check(); // A live shallow root still wins over a deeper archived root.
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_dir_dirty").get()?.n, 0, "activity and archive changes need no directory journal");
    db.prepare("UPDATE sessions SET cwd = '/code/app/more' WHERE key = 'deep-new'").run();
    check(); // Its not-yet-prepared journal entry is overlaid immediately.
    db.prepare("UPDATE sessions SET archived_at = NULL WHERE key = 'deep-new'").run();
    check();
    db.prepare("DELETE FROM sessions WHERE key = 'deep-new'").run();
    check();
    finish(db);
    check();
    db.exec("UPDATE sessions SET rowid = 9007199254740993 WHERE key = 'deep-old'");
    check(); // Tie ordering stays in SQLite even when an old rowid cannot be represented exactly in JavaScript.
    db.exec("VACUUM");
    check();
  } finally { store.close(); }
});

test("directory ownership agrees with the old rule across interleaved changes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const put = db.prepare(add.replace("INSERT INTO", "INSERT OR REPLACE INTO"));
    const roots = ["/repo", "/repo/a", "/repo/a/", "/repo/b", "/tmp", "relative/", ""];
    const dirs = ["/repo/a/file", "/repo/a/", "/repo/b/x", "/repo/c", "/tmp/file", "relative/file", "/none"];
    let seed = 982451653;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    for (let i = 0; i < 20; i++) put.run(`s${i}`, roots[next(roots.length)]!, roots[next(roots.length)]!, `t${i}`, next(5), next(2) ? null : 1);
    installSessionDirectories(db);
    finish(db);
    for (let i = 0; i < 150; i++) {
      const id = next(20), key = `s${id}`;
      switch (next(5)) {
        case 0: put.run(key, roots[next(roots.length)]!, roots[next(roots.length)]!, `t${id}`, next(5), next(2) ? null : 1); break;
        case 1: db.prepare("UPDATE sessions SET cwd = ? WHERE key = ?").run(roots[next(roots.length)]!, key); break;
        case 2: db.prepare("UPDATE sessions SET last_active_at = ? WHERE key = ?").run(next(5), key); break;
        case 3: db.prepare("UPDATE sessions SET archived_at = ? WHERE key = ?").run(next(2) ? null : 1, key); break;
        case 4: db.prepare("DELETE FROM sessions WHERE key = ?").run(key); break;
      }
      if (i % 7 === 0) sessionDirectoriesStep(db, 3);
      for (const dir of dirs) assert.equal(sessionDirectory(db, dir)?.key, oldSession(store, dir), `step ${i}: ${dir}`);
    }
  } finally { store.close(); }
});

test("old directories are prepared in bounded batches while sessions change", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const put = db.prepare(add);
    for (let i = 0; i < 40; i++) put.run(`s${String(i).padStart(2, "0")}`, `/old/${i}`, null, `t${i}`, i, null);
    installSessionDirectories(db);
    assert.equal(sessionDirectory(db, "/old/0/sub"), null);
    assert.equal(sessionDirectoriesStep(db, 3).visited, 3);
    put.run("aaa", "/new/behind", null, "behind", 2, null);
    put.run("zzz", "/new/ahead", null, "ahead", 2, null);
    db.prepare("UPDATE sessions SET cwd = '/new/changed' WHERE key = 's01'").run();
    db.prepare("DELETE FROM sessions WHERE key = 's39'").run();
    while (!sessionDirectoriesReady(db)) assert.ok(sessionDirectoriesStep(db, 3).visited <= 3);
    for (const dir of ["/old/0/sub", "/old/39", "/new/behind/x", "/new/ahead/x", "/new/changed/x"])
      assert.equal(sessionDirectory(db, dir)?.key, oldSession(store, dir), dir);
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`older writers and replacements keep directory ownership exact (recursive triggers ${recursive})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "session-dir-old-"));
  const path = join(dir, "store.db"), store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    old.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const insert = old.prepare(add);
    const replace = old.prepare(add.replace("INSERT INTO", "INSERT OR REPLACE INTO"));
    const ignored = old.prepare(add.replace("INSERT INTO", "INSERT OR IGNORE INTO"));
    insert.run("a", "/a", "/common", "a", 1, null);
    insert.run("b", "/b", "/common", "b", 2, null);
    installSessionDirectories(db);
    finish(db);
    const check = () => { for (const root of ["/a", "/b", "/c", "/d", "/common", "/other"])
      assert.equal(sessionDirectory(db, `${root}/x`)?.key, oldSession(store, `${root}/x`), root); };
    replace.run("c", "/c", "/common", "a", 4, null); // Replaces a different key by token.
    check();
    ignored.run("ignored", "/other", null, "b", 5, null);
    check();
    old.prepare("UPDATE sessions SET cwd = '/other' WHERE key = 'b'").run();
    check();
    const rowid = old.prepare("SELECT rowid AS id FROM sessions WHERE key = 'b'").get()?.id as number;
    old.prepare(`INSERT OR REPLACE INTO sessions(rowid,key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES (?,?,'connected','thread','codex','default',?,?,0,9)`).run(rowid, "d", "/d", "d");
    check();
    finish(db);
    check();
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a large pending journal uses the old answer until the worker catches up", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const put = db.prepare(add);
    put.run("target", "/target", null, "target", 1, null);
    installSessionDirectories(db);
    finish(db);
    for (let i = 0; i < 65; i++) put.run(`new-${i}`, `/new/${i}`, null, `new-${i}`, i, null);
    assert.equal(sessionDirectory(db, "/target/sub"), null);
    finish(db);
    assert.equal(sessionDirectory(db, "/target/sub")?.key, "target");
  } finally { store.close(); }
});

test("a directory lookup answers through the old path while the previous station writes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "session-dir-handover-"));
  const path = join(dir, "store.db"), store = Store.open(path), old = new DatabaseSync(path);
  const previous = Promise.withResolvers<void>();
  const builder = new SessionDirectoryBuilder(store, previous.promise);
  try {
    const put = old.prepare(add);
    put.run("before", "/before", null, "before", 1, null);
    assert.equal(builder.find("/before/sub"), null);
    assert.equal(old.prepare("SELECT 1 FROM sqlite_master WHERE name = 'session_dir_meta'").get(), undefined);
    put.run("after", "/after", null, "after", 2, null);
    previous.resolve();
    await builder.settled();
    assert.equal(builder.find("/before/sub")?.key, "before");
    assert.equal(builder.find("/after/sub")?.key, "after");
  } finally { previous.resolve(); await builder.close(); old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("closing a directory lookup while the previous station is up settles the wait", async () => {
  const store = Store.open(":memory:"), previous = Promise.withResolvers<void>();
  const builder = new SessionDirectoryBuilder(store, previous.promise);
  try {
    assert.equal(builder.find("/anything"), null);
    await builder.close();
    assert.equal(builder.find("/anything"), null);
  } finally { previous.resolve(); await builder.close(); store.close(); }
});

test("a later memory check retries a stopped directory worker", async () => {
  const dir = mkdtempSync(join(tmpdir(), "session-dir-retry-"));
  const store = Store.open(join(dir, "store.db")), worker = join(dir, "worker.mjs");
  writeFileSync(worker, "process.exit(1);\n");
  const builder = new SessionDirectoryBuilder(store, Promise.resolve(), pathToFileURL(worker));
  try {
    store.db.prepare(add).run("session", "/session", null, "token", 1, null);
    assert.equal(builder.find("/session/sub"), null);
    await builder.settled();
    const actual = new URL("../src/sessions/workspace-activity-worker.ts", import.meta.url).href;
    writeFileSync(worker, `import ${JSON.stringify(actual)};\n`);
    assert.equal(builder.find("/session/sub"), null);
    await builder.settled();
    assert.equal(builder.find("/session/sub")?.key, "session");
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed directory batch rolls its rows and cursor back together", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.prepare(add).run("a", "/a", null, "a", 0, null);
    installSessionDirectories(db);
    db.exec("CREATE TRIGGER reject_directory BEFORE INSERT ON session_dir_rows BEGIN SELECT RAISE(ABORT, 'stop'); END");
    assert.throws(() => sessionDirectoriesStep(db, 3), /stop/);
    const meta = db.prepare("SELECT phase, cursor FROM session_dir_meta").get();
    assert.equal(meta?.phase, 0);
    assert.equal(meta?.cursor, null);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_dir_rows").get()?.n, 0);
    db.exec("DROP TRIGGER reject_directory");
    finish(db);
    assert.equal(sessionDirectory(db, "/a/sub")?.key, "a");
  } finally { store.close(); }
});

test("a directory decision and its pending journal share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "session-dir-snapshot-"));
  const path = join(dir, "store.db"), store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    const put = old.prepare(add);
    put.run("first", "/same", null, "first", 1, null);
    installSessionDirectories(db);
    finish(db);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT 1 FROM session_dir_meta")) return statement;
        return new Proxy(statement, { get(stmt, part) {
          if (part === "get") return (...args: Parameters<typeof statement.get>) => {
            const result = stmt.get(...args);
            if (!changed) { changed = true; put.run("later", "/same", null, "later", 2, null); }
            return result;
          };
          const value = Reflect.get(stmt, part, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal(sessionDirectory(observed, "/same/file")?.key, "first");
    assert.equal(sessionDirectory(db, "/same/file")?.key, "later");
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
