import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installPostBlocks, postBlocksReady, postBlocksStep } from "../src/store/post-blocks.ts";

const entries = `CREATE TABLE entries (thread INTEGER NOT NULL, n INTEGER NOT NULL, kind TEXT NOT NULL,
  author_kind TEXT NOT NULL, author TEXT NOT NULL, ts TEXT, PRIMARY KEY(thread,n));
  CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL;`;
const add = (db: DatabaseSync) => db.prepare("INSERT INTO entries VALUES (?, ?, 'message', ?, ?, ?)");
const blocks = (db: DatabaseSync) => db.prepare("SELECT thread, author, bucket FROM post_blocks ORDER BY thread, author, bucket").all();
const expected = (db: DatabaseSync) => db.prepare(`SELECT DISTINCT thread, author,
  n / 64 - CASE WHEN n < 0 AND n % 64 != 0 THEN 1 ELSE 0 END AS bucket FROM entries
  WHERE kind = 'message' AND author_kind = 'agent' ORDER BY thread, author, bucket`).all();

test("installing the post markers checks only whether old entries exist", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(entries);
    add(db).run(1, 1, "agent", "old", "old");
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "entries" && column
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installPostBlocks(db); } finally { db.setAuthorizer(null); }
    assert.equal(postBlocksReady(db, 1, 0), false);
    assert.deepEqual(blocks(db), []);
    installPostBlocks(db);
  } finally { db.close(); }
});

test("an old thread indexes only the requested suffix and resumes in bounded batches", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(entries);
    const put = add(db);
    for (let n = 1; n <= 200; n++) put.run(1, n, n % 3 ? "person" : "agent", n % 3 ? "person" : `s${n % 4}`, `m${n}`);
    put.run(2, 1, "agent", "other-thread", "other");
    installPostBlocks(db);
    assert.deepEqual(postBlocksStep(db, 1, 190, 16, () => false), { done: false, visited: 11 });
    assert.equal(postBlocksReady(db, 1, 190), false, "foreground work can refuse the write after the read");
    assert.deepEqual(postBlocksStep(db, 1, 190, 16), { done: true, visited: 11 });
    assert.equal(postBlocksReady(db, 1, 190), true);
    assert.equal(postBlocksReady(db, 1, 180), false);
    assert.equal(postBlocksReady(db, 2, 0), false);
    for (;;) {
      const result = postBlocksStep(db, 1, 0, 16);
      assert.ok(result.visited <= 16);
      if (result.done) break;
    }
    assert.equal(postBlocksReady(db, 1, 0), true);
    assert.deepEqual(blocks(db), expected(db).filter((row) => row.thread === 1));
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`post markers follow replacements, ignored conflicts and removals (recursive triggers ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`${entries} PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    installPostBlocks(db);
    db.exec(`INSERT INTO entries VALUES (1, 1, 'message', 'agent', 'A', 'first');
      INSERT INTO entries VALUES (1, 130, 'message', 'agent', 'B', 'second');
      INSERT OR REPLACE INTO entries VALUES (1, 1, 'message', 'agent', 'C', 'second');`);
    assert.deepEqual(blocks(db), expected(db));
    db.exec(`INSERT OR IGNORE INTO entries VALUES (1, 1, 'message', 'agent', 'D', 'ignored');`);
    assert.deepEqual(blocks(db), expected(db));
    db.exec(`INSERT INTO entries VALUES (1, 2, 'message', 'agent', 'A', 'third');
      INSERT INTO entries VALUES (1, 129, 'message', 'agent', 'E', 'fourth');
      UPDATE OR REPLACE entries SET n=129, ts='second', author='F' WHERE thread=1 AND n=2;
      INSERT INTO entries VALUES (2, -1, 'message', 'agent', 'A', 'neg1');
      INSERT INTO entries VALUES (2, -64, 'message', 'agent', 'A', 'neg64');
      INSERT INTO entries VALUES (2, -65, 'message', 'agent', 'A', 'neg65');`);
    assert.deepEqual(blocks(db), expected(db));
    db.exec("DELETE FROM entries");
    assert.deepEqual(blocks(db), []);
  } finally { db.close(); }
});

test("a writer can change an old post after a batch reads and before it takes the write lock", () => {
  const dir = mkdtempSync(join(tmpdir(), "post-blocks-"));
  const path = join(dir, "old.db");
  const db = new DatabaseSync(path);
  const other = new DatabaseSync(path);
  try {
    db.exec(`PRAGMA journal_mode=WAL; ${entries}`);
    const put = add(db);
    for (let n = 1; n <= 30; n++) put.run(1, n, "agent", "old", `m${n}`);
    installPostBlocks(db);
    let changed = false;
    const interleaved = new Proxy(db, {
      get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !changed) {
            changed = true;
            other.prepare("UPDATE entries SET author = 'new' WHERE thread = 1 AND n = 30").run();
            other.prepare("DELETE FROM entries WHERE thread = 1 AND n = 29").run();
          }
          return target.exec(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.deepEqual(postBlocksStep(interleaved, 1, 0, 64), { done: true, visited: 30 });
    assert.ok(changed);
    assert.deepEqual(blocks(db), expected(db));
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
