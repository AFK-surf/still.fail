import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { SessionDirectoryBuilder } from "../src/sessions/session-directory-builder.ts";
import { installSessionDirectories, sessionDirectoriesReady, sessionDirectoriesStep, sessionDirectoryArguments } from "../src/store/session-directory.ts";
import { Store } from "../src/store/store.ts";

const HOME = "/home/me";
const put = `INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,cwd,token,created_at,last_active_at,archived_at)
  VALUES (?,'connected','thread','codex','default',?,?,?,0,?,?)`;

function oldAnswers(store: Store, lines: readonly string[]): Map<string, string> {
  const places = store.liveSessions().filter((s) => s.workspace && s.workspace !== "/" && s.workspace !== HOME)
    .map((s) => ({ key: s.key, dir: s.workspace.endsWith("/") ? s.workspace : `${s.workspace}/` }))
    .sort((a, b) => b.dir.length - a.dir.length);
  const answers = new Map<string, string>();
  for (const line of lines) {
    const found = places.find((p) => line.includes(p.dir));
    if (found) answers.set(line, found.key);
  }
  return answers;
}

function finish(store: Store) { while (!sessionDirectoriesReady(store.db)) sessionDirectoriesStep(store.db, 3); }
function unrelated(db: DatabaseSync) {
  const add = db.prepare(put);
  for (let i = 0; i < 33; i++) add.run(`unrelated-${i}`, `/unrelated/${i}`, null, `unrelated-${i}`, i, null);
}

test("argument ownership keeps substring, longest workspace and activity ordering", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const add = db.prepare(put);
    add.run("a", "/same/a", null, "a", 3, null);
    add.run("b", "/same/b/", null, "b", 5, null);
    add.run("b-new", "/same/b", null, "b-new", 5, null);
    add.run("deep", "/same/a/deep", null, "deep", 1, null);
    add.run("relative", "repo", null, "relative", 2, null);
    add.run("unicode", "/编程/🔧", null, "unicode", 2, null);
    add.run("unicode-initial", "🔧repo", null, "unicode-initial", 2, null);
    add.run("cwd-only", "/other", "/cwd", "cwd", 9, null);
    add.run("archived", "/same/a/deep/more", null, "archived", 99, 1);
    add.run("home", HOME, null, "home", 99, null);
    add.run("root", "/", null, "root", 99, null);
    unrelated(db);
    const lines = ["sh /same/a/deep/more/run /same/b/x", "sh /same/a/x /same/b/x", "prefixrepo/file",
      "sh /编程/🔧/run", "prefix🔧repo/run", "sh /cwd/run", "sh /home/me/run", "sh /same/a", "nothing"];
    assert.equal(sessionDirectoryArguments(db, lines, HOME), null, "old stores answer via the old path while preparing");
    installSessionDirectories(db);
    finish(store);
    assert.deepEqual(sessionDirectoryArguments(db, lines, HOME), oldAnswers(store, lines));
    assert.equal(sessionDirectoryArguments(db, lines, HOME)?.get(lines[0]!), "deep");
    assert.equal(sessionDirectoryArguments(db, lines, HOME)?.get(lines[1]!), "b-new");
    assert.equal(sessionDirectoryArguments(db, lines, HOME)?.get(lines[2]!), "relative");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`argument ownership follows pending changes and replacements (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const add = db.prepare(put), replace = db.prepare(put.replace("INSERT INTO", "INSERT OR REPLACE INTO"));
    add.run("one", "/a", null, "one", 1, null);
    add.run("two", "/b", null, "two", 2, null);
    unrelated(db);
    installSessionDirectories(db);
    finish(store);
    const lines = ["/a/file /b/file /c/file", "prefixrelative/sub", "/only-cwd/file", "/new/file"];
    const check = () => assert.deepEqual(sessionDirectoryArguments(db, lines, HOME), oldAnswers(store, lines));
    check();
    db.prepare("UPDATE sessions SET workspace = 'relative', cwd = '/only-cwd', last_active_at = 8 WHERE key = 'one'").run();
    check();
    replace.run("three", "/c", null, "two", 9, null); // Replaces two by token.
    check();
    db.prepare("UPDATE sessions SET archived_at = 1 WHERE key = 'three'").run();
    check();
    db.prepare("DELETE FROM sessions WHERE key = 'one'").run();
    check();
    finish(store);
    check();
    db.exec("UPDATE sessions SET rowid = 9007199254740993 WHERE key = 'three'");
    db.exec("VACUUM");
    check();
    for (let i = 0; i < 65; i++) add.run(`new-${i}`, `/new/${i}`, null, `new-${i}`, i, null);
    assert.equal(sessionDirectoryArguments(db, lines, HOME), null, "a large journal uses the immediate old lookup");
    finish(store);
    check();
  } finally { store.close(); }
});

test("argument lookup avoids preparing when no slash can match and falls back for unusually large input", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    assert.deepEqual(sessionDirectoryArguments(db, ["hello", ""], HOME), new Map());
    unrelated(db);
    installSessionDirectories(db);
    finish(store);
    assert.equal(sessionDirectoryArguments(db, ["a".repeat(262_145) + "/x"], HOME), null);
    assert.equal(sessionDirectoryArguments(db, ["a\0/b"], HOME), null);
    assert.equal(sessionDirectoryArguments(db, [String.fromCharCode(0xd800) + "/x"], HOME), null);
    assert.equal(sessionDirectoryArguments(db, [String.fromCodePoint(0x10ffff) + "/x"], HOME), null);
  } finally { store.close(); }
});

test("argument ownership agrees with the old rule across interleaved changes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const replace = db.prepare(put.replace("INSERT INTO", "INSERT OR REPLACE INTO"));
    const roots = ["/repo", "/repo/a", "/repo/a/", "/repo/b", "/tmp", "relative/", "", HOME];
    const lines = ["sh /repo/a/file /tmp/file", "sh /repo/a/ /repo/b/x", "prefixrelative/file", "/none", "/home/me/x"];
    let seed = 982451653;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    for (let i = 0; i < 20; i++) replace.run(`s${i}`, roots[next(roots.length)]!, roots[next(roots.length)]!, `t${i}`, next(5), next(2) ? null : 1);
    unrelated(db);
    installSessionDirectories(db);
    finish(store);
    for (let i = 0; i < 100; i++) {
      const id = next(20), key = `s${id}`;
      switch (next(5)) {
        case 0: replace.run(key, roots[next(roots.length)]!, roots[next(roots.length)]!, `t${id}`, next(5), next(2) ? null : 1); break;
        case 1: db.prepare("UPDATE sessions SET workspace = ? WHERE key = ?").run(roots[next(roots.length)]!, key); break;
        case 2: db.prepare("UPDATE sessions SET last_active_at = ? WHERE key = ?").run(next(5), key); break;
        case 3: db.prepare("UPDATE sessions SET archived_at = ? WHERE key = ?").run(next(2) ? null : 1, key); break;
        case 4: db.prepare("DELETE FROM sessions WHERE key = ?").run(key); break;
      }
      if (i % 7 === 0) sessionDirectoriesStep(db, 3);
      assert.deepEqual(sessionDirectoryArguments(db, lines, HOME), oldAnswers(store, lines), `step ${i}`);
    }
  } finally { store.close(); }
});

test("the argument decision and pending changes share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "resource-dir-snapshot-"));
  const path = join(dir, "store.db"), store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    const add = old.prepare(put);
    add.run("first", "/same", null, "first", 1, null);
    unrelated(old);
    installSessionDirectories(db);
    finish(store);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT 1 FROM session_dir_meta")) return statement;
        return new Proxy(statement, { get(stmt, part) {
          if (part === "get") return (...args: Parameters<typeof statement.get>) => {
            const result = stmt.get(...args);
            if (!changed) { changed = true; add.run("later", "/same", null, "later", 2, null); }
            return result;
          };
          const value = Reflect.get(stmt, part, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const lines = ["sh /same/file"];
    assert.equal(sessionDirectoryArguments(observed, lines, HOME)?.get(lines[0]!), "first");
    assert.equal(sessionDirectoryArguments(db, lines, HOME)?.get(lines[0]!), "later");
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("argument lookup immediately falls back through handover and prepares afterward", async () => {
  const dir = mkdtempSync(join(tmpdir(), "resource-dir-handover-"));
  const path = join(dir, "store.db"), store = Store.open(path), old = new DatabaseSync(path);
  const previous = Promise.withResolvers<void>();
  const builder = new SessionDirectoryBuilder(store, previous.promise);
  try {
    const add = old.prepare(put), lines = ["sh /before/file", "sh /after/file"];
    add.run("before", "/before", null, "before", 1, null);
    unrelated(old);
    assert.equal(builder.findArguments(lines, HOME), null);
    assert.equal(old.prepare("SELECT 1 FROM sqlite_master WHERE name = 'session_dir_meta'").get(), undefined);
    add.run("after", "/after", null, "after", 2, null);
    previous.resolve();
    await builder.settled();
    assert.deepEqual(builder.findArguments(lines, HOME), oldAnswers(store, lines));
  } finally { previous.resolve(); await builder.close(); old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("at most 32 live sessions answer directly without preparing historical directories", async () => {
  const store = Store.open(":memory:"), db = store.db;
  const previous = Promise.withResolvers<void>();
  const builder = new SessionDirectoryBuilder(store, previous.promise);
  try {
    const add = db.prepare(put), lines = ["sh /live/0/run", "sh /missing/run"];
    for (let i = 0; i < 32; i++) add.run(`live-${i}`, i === 30 ? "/live/0" : `/live/${i}`, null, `live-${i}`, i, null);
    for (let i = 0; i < 50; i++) add.run(`archived-${i}`, i === 0 ? "/live/0" : `/archived/${i}`, null, `archived-${i}`, i + 100, 1);
    assert.deepEqual(builder.findArguments(lines, HOME), oldAnswers(store, lines));
    assert.equal(builder.findArguments(lines, HOME)?.get(lines[0]!), "live-30");
    await builder.settled();
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'session_dir_meta'").get(), undefined);
    add.run("live-32", "/live/32", null, "live-32", 32, null);
    assert.equal(builder.findArguments(lines, HOME), null, "the 33rd live session uses the old lookup during handover");
    previous.resolve();
    await builder.settled();
    assert.deepEqual(builder.findArguments(lines, HOME), oldAnswers(store, lines));
  } finally { previous.resolve(); await builder.close(); store.close(); }
});
