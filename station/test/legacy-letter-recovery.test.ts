import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { addLetterColumn } from "../src/store/schema.ts";

function oldStore(path: string): DatabaseSync {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,
    author_kind TEXT NOT NULL,author TEXT NOT NULL,text TEXT,PRIMARY KEY(thread,n));
    CREATE TABLE thread_sessions(thread INTEGER NOT NULL,session TEXT NOT NULL);
    INSERT INTO entries VALUES(1,1,'message','agent','other','来自 [备份](https://x/o/w/s/b)：');
    INSERT INTO entries VALUES(1,2,'message','agent','other','From <https://x/o/w/t/c|Backups>:');`);
  return db;
}

const expected = [
  { way: "in", title: "备份", link: "https://x/o/w/s/b" },
  { way: "in", title: "Backups", link: "https://x/o/w/t/c" },
];
const letters = (db: DatabaseSync) => db.prepare("SELECT letter FROM entries ORDER BY n").all().map((row) => JSON.parse(String(row.letter)));

for (const stage of ["read", "index", "mark"] as const) test(`an old-letter upgrade interrupted during ${stage} retries on reopen`, () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-letter-recovery-"));
  const path = join(dir, "old.db");
  let db = oldStore(path);
  try {
    let marked = 0;
    const interrupted = new Proxy(db, { get(target, key) {
      if (key === "exec") return (sql: string) => {
        if (stage === "index" && sql.startsWith("CREATE INDEX IF NOT EXISTS entries_letters")) throw new Error("interrupted");
        return target.exec(sql);
      };
      if (key === "prepare") return (sql: string) => {
        if (stage === "read" && sql.includes("SELECT thread, n, text FROM entries e")) throw new Error("interrupted");
        const statement = target.prepare(sql);
        if (stage !== "mark" || !sql.startsWith("UPDATE entries SET letter")) return statement;
        return new Proxy(statement, { get(query, method) {
          if (method === "run") return (...args: Parameters<typeof query.run>) => {
            if (++marked === 2) throw new Error("interrupted");
            return query.run(...args);
          };
          const value = Reflect.get(query, method, query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.throws(() => addLetterColumn(interrupted), /interrupted/);
    db.close();
    db = new DatabaseSync(path);
    addLetterColumn(db);
    assert.deepEqual(letters(db), expected);
  } finally { db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("two old-letter upgrades racing to install the column both finish", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-letter-opener-"));
  const path = join(dir, "old.db"), db = oldStore(path), other = new DatabaseSync(path);
  try {
    let installed = false;
    const raced = new Proxy(db, { get(target, key) {
      if (key === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.includes("SELECT thread, n, text FROM entries e")) return statement;
        return new Proxy(statement, { get(query, method) {
          if (method === "all") return (...args: Parameters<typeof query.all>) => {
            const found = query.all(...args);
            if (!installed) { installed = true; addLetterColumn(other); }
            return found;
          };
          const value = Reflect.get(query, method, query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addLetterColumn(raced);
    assert.equal(installed, true);
    assert.deepEqual(letters(db), expected);
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an older prepared writer sees the column only after the old letters are marked", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-letter-writer-"));
  const path = join(dir, "old.db"), db = oldStore(path), old = new DatabaseSync(path);
  old.exec("PRAGMA busy_timeout=0");
  const write = old.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text) VALUES(1,3,'message','agent','other','ordinary')");
  try {
    let checked = false;
    const during = new Proxy(db, { get(target, key) {
      if (key === "exec") return (sql: string) => {
        const result = target.exec(sql);
        if (sql.startsWith("CREATE INDEX IF NOT EXISTS entries_letters")) {
          checked = true;
          assert.equal(old.prepare("PRAGMA table_info(entries)").all().some((row) => row.name === "letter"), false);
          assert.throws(() => write.run(), /locked/);
        }
        return result;
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addLetterColumn(during);
    assert.equal(checked, true);
    assert.deepEqual(letters(db), expected);
    write.run();
    assert.equal(db.prepare("SELECT letter FROM entries WHERE n=3").get()?.letter, null);
  } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const journal of ["DELETE", "WAL"] as const) for (const change of ["messages", "join", "leave"] as const) test(`an old writer's ${change} between scan and lock is included in the upgrade (${journal})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-letter-scan-race-"));
  const path = join(dir, "old.db"), db = oldStore(path);
  db.exec(`PRAGMA journal_mode=${journal}`);
  const old = new DatabaseSync(path);
  try {
    if (change === "leave") old.exec("INSERT INTO thread_sessions VALUES(1,'other')");
    let changed = false;
    const raced = new Proxy(db, { get(target, key) {
      if (key === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.includes("SELECT thread, n, text FROM entries e")) return statement;
        return new Proxy(statement, { get(query, method) {
          if (method === "all") return (...args: Parameters<typeof query.all>) => {
            const found = query.all(...args);
            if (!changed) {
              changed = true;
              if (change === "messages") old.exec(`BEGIN;
                UPDATE entries SET text='ordinary' WHERE thread=1 AND n=1;
                INSERT INTO entries VALUES(1,3,'message','agent','other','From [New](https://x/new):');
                COMMIT`);
              else if (change === "join") old.exec("INSERT INTO thread_sessions VALUES(1,'other')");
              else old.exec("DELETE FROM thread_sessions WHERE thread=1 AND session='other'");
            }
            return found;
          };
          const value = Reflect.get(query, method, query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addLetterColumn(raced);
    assert.equal(changed, true);
    const want = change === "messages"
      ? [null, expected[1], { way: "in", title: "New", link: "https://x/new" }]
      : change === "join" ? [null, null] : expected;
    assert.deepEqual(letters(db), want);
  } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an old-letter upgrade interrupted on its locked reread rolls back and retries", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-letter-reread-"));
  const path = join(dir, "old.db");
  let db = oldStore(path);
  const old = new DatabaseSync(path);
  try {
    let reads = 0;
    const interrupted = new Proxy(db, { get(target, key) {
      if (key === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.includes("SELECT thread, n, text FROM entries e")) return statement;
        return new Proxy(statement, { get(query, method) {
          if (method === "all") return (...args: Parameters<typeof query.all>) => {
            if (++reads === 2) throw new Error("interrupted locked reread");
            const found = query.all(...args);
            old.exec("INSERT INTO thread_sessions VALUES(1,'other')");
            return found;
          };
          const value = Reflect.get(query, method, query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.throws(() => addLetterColumn(interrupted), /interrupted locked reread/);
    assert.equal(db.prepare("PRAGMA table_info(entries)").all().some((row) => row.name === "letter"), false);
    db.close();
    db = new DatabaseSync(path);
    addLetterColumn(db);
    assert.deepEqual(letters(db), [null, null]);
  } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
