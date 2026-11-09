import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

const indexSql = "CREATE INDEX IF NOT EXISTS entries_people_at ON entries (at) WHERE author_kind = 'person' AND kind = 'message'";
const hasIndex = (db: DatabaseSync) => db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_people_at'").get() !== undefined;
const closedIndexSql = "CREATE INDEX IF NOT EXISTS closed_cards_at ON closed_cards (at)";
const hasClosedIndex = (db: DatabaseSync) => db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='closed_cards_at'").get() !== undefined;

test("opening an older store does not rebuild the unused station-wide people index", () => {
  const visited: number[] = [];
  for (const size of [40, 400]) {
    const dir = mkdtempSync(join(tmpdir(), "unused-people-index-"));
    const path = join(dir, "station.db"), initial = Store.open(path);
    const thread = initial.openThread("ember", "CHAT", `people-${size}`, null, null).id;
    const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
    for (let n = 1; n <= size; n++) put.run(thread, n, n);
    initial.db.exec("DROP INDEX IF EXISTS entries_people_at");
    initial.close();
    const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const exec = descriptor.value as DatabaseSync["exec"];
    let count = 0;
    Object.defineProperty(DatabaseSync.prototype, "exec", { ...descriptor, value(this: DatabaseSync, sql: string) {
      if (sql.includes(indexSql)) {
        this.function("visit_people_at_build", { deterministic: true }, (_n) => { count++; return 1; });
        sql = sql.replace(indexSql, indexSql.replace(" WHERE ", " WHERE visit_people_at_build(n) AND "));
      }
      return exec.call(this, sql);
    } });
    let reopened: Store | null = null;
    try {
      reopened = Store.open(path);
      assert.equal(hasIndex(reopened.db), false);
      visited.push(count);
    } finally {
      reopened?.close();
      Object.defineProperty(DatabaseSync.prototype, "exec", descriptor);
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.deepEqual(visited, [0, 0], "opening should not read old entries to build an unused index");
});

test("opening an older store does not rebuild the unused station-wide closed-card index", () => {
  const visited: number[] = [];
  for (const size of [40, 400]) {
    const dir = mkdtempSync(join(tmpdir(), "unused-closed-index-"));
    const path = join(dir, "station.db"), initial = Store.open(path);
    const put = initial.db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(1,?,'p',?)");
    for (let n = 1; n <= size; n++) put.run(n, n);
    initial.db.exec("DROP INDEX IF EXISTS closed_cards_at");
    initial.close();
    const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const exec = descriptor.value as DatabaseSync["exec"];
    let count = 0;
    Object.defineProperty(DatabaseSync.prototype, "exec", { ...descriptor, value(this: DatabaseSync, sql: string) {
      if (sql.includes(closedIndexSql)) {
        this.function("visit_closed_at_build", { deterministic: true }, (_n) => { count++; return 1; });
        sql = sql.replace(closedIndexSql, `${closedIndexSql} WHERE visit_closed_at_build(n)`);
      }
      return exec.call(this, sql);
    } });
    let reopened: Store | null = null;
    try {
      reopened = Store.open(path);
      assert.equal(hasClosedIndex(reopened.db), false);
      visited.push(count);
    } finally {
      reopened?.close();
      Object.defineProperty(DatabaseSync.prototype, "exec", descriptor);
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.deepEqual(visited, [0, 0], "opening should not read old closed cards to build an unused index");
});

test("new stores omit the unused index while existing stores keep it for older connections", () => {
  const dir = mkdtempSync(join(tmpdir(), "old-people-index-")), path = join(dir, "station.db");
  let store: Store | null = Store.open(path);
  let old: DatabaseSync | null = null;
  try {
    assert.equal(hasIndex(store.db), false);
    assert.equal(hasClosedIndex(store.db), false);
    const thread = store.openThread("ember", "CHAT", "old-writer", null, null).id;
    store.db.exec(indexSql);
    store.db.exec(closedIndexSql);
    store.close();
    old = new DatabaseSync(path);
    const put = old.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','person','p',1)");
    const close = old.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,1,'p',1)");
    const people = old.prepare(`SELECT n FROM entries INDEXED BY entries_people_at
      WHERE author_kind='person' AND kind='message' AND at>=?`);
    const closed = old.prepare("SELECT n FROM closed_cards INDEXED BY closed_cards_at WHERE at>=?");
    store = Store.open(path);
    assert.equal(hasIndex(store.db), true);
    assert.equal(hasClosedIndex(store.db), true);
    put.run(thread);
    close.run(thread);
    assert.equal(people.get(0)?.n, 1);
    assert.equal(closed.get(0)?.n, 1);
  } finally { old?.close(); store?.close(); rmSync(dir, { recursive: true, force: true }); }
});
