import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { hasLegacyPeopleSince, hasNativePeopleSince, installPeopleSinceIndex } from "../src/store/legacy-people-since.ts";
import { Store } from "../src/store/store.ts";

test("opening an old store bounds preparation of its per-chat people-time lookup", () => {
  const counts: number[] = [];
  for (const size of [40, 400]) {
    const dir = mkdtempSync(join(tmpdir(), "old-people-time-")), path = join(dir, "station.db");
    const initial = Store.open(path);
    const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(1,?,'message','person','p',?)");
    for (let n = 1; n <= size; n++) put.run(n,n);
    initial.db.exec("DROP INDEX entries_people_since");
    initial.close();
    const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const exec = descriptor.value as DatabaseSync["exec"];
    const prepareDescriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "prepare")!;
    const prepare = prepareDescriptor.value as DatabaseSync["prepare"];
    const marker = "CREATE INDEX IF NOT EXISTS entries_people_since ON entries (thread, at) WHERE";
    const visited = new Set<string>();
    Object.defineProperty(DatabaseSync.prototype, "exec", { ...descriptor, value(this: DatabaseSync, sql: string) {
      if (sql.includes(marker)) {
        this.function("visit_people_time_build", { deterministic: true }, (n) => { visited.add(String(n)); return 1; });
        sql = sql.replace(marker, `${marker} visit_people_time_build(n) AND`);
      }
      return exec.call(this, sql);
    } });
    Object.defineProperty(DatabaseSync.prototype, "prepare", { ...prepareDescriptor, value(this: DatabaseSync, sql: string) {
      if (sql === "SELECT 1 FROM entries LIMIT 1 OFFSET 63") {
        this.function("visit_people_time_probe", (n) => { visited.add(String(n)); return 1; });
        sql = "SELECT 1 FROM entries WHERE visit_people_time_probe(n) LIMIT 1 OFFSET 63";
      }
      return prepare.call(this, sql);
    } });
    let reopened: Store | null = null;
    try { reopened = Store.open(path); counts.push(visited.size); }
    finally {
      reopened?.close();
      Object.defineProperty(DatabaseSync.prototype, "exec", descriptor);
      Object.defineProperty(DatabaseSync.prototype, "prepare", prepareDescriptor);
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.ok(counts[0]! <= 64 && counts[1]! <= 64, `entries visited while opening: ${counts.join(" / ")}`);
});

for (const change of ["write","index"] as const) test(`installation rechecks an old connection's ${change} under the writer lock`, () => {
  const dir = mkdtempSync(join(tmpdir(),"old-people-time-install-")), path = join(dir,"old.db");
  const db = new DatabaseSync(path), old = new DatabaseSync(path);
  try {
    db.exec(`PRAGMA journal_mode=WAL; CREATE TABLE threads(id INTEGER PRIMARY KEY);
      CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,ts TEXT,
        author_kind TEXT NOT NULL,at INTEGER NOT NULL,PRIMARY KEY(thread,n));
      CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL;`);
    const put = db.prepare("INSERT INTO entries VALUES(1,?,'message',NULL,'person',?)");
    for (let n=1;n<=(change === "write" ? 63 : 65);n++) put.run(n,n);
    let raced = false;
    const intercepted = new Proxy(db,{ get(target,key) {
      if (key === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE" && !raced) {
          raced = true;
          if (change === "write") old.exec("INSERT INTO entries VALUES(1,64,'message',NULL,'person',64)");
          else old.exec("CREATE INDEX entries_people_since ON entries(thread,at) WHERE author_kind='person' AND kind='message'");
        }
        return target.exec(sql);
      };
      const value = Reflect.get(target,key,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    installPeopleSinceIndex(intercepted);
    assert.equal(raced,true);
    assert.equal(hasNativePeopleSince(db),change === "index");
    assert.equal(hasLegacyPeopleSince(db),change === "write");
  } finally { old.close(); db.close(); rmSync(dir,{ recursive:true, force:true }); }
});

test("a failed people-time installation rolls back and can be retried", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE threads(id INTEGER PRIMARY KEY);
      CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,ts TEXT,
        author_kind TEXT NOT NULL,at INTEGER NOT NULL,PRIMARY KEY(thread,n));
      CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL;
      CREATE TRIGGER legacy_people_time_insert BEFORE INSERT ON entries BEGIN SELECT 1; END;`);
    const put = db.prepare("INSERT INTO entries VALUES(1,?,'message',NULL,'person',?)");
    for (let n=1;n<=64;n++) put.run(n,n);
    assert.throws(() => installPeopleSinceIndex(db),/already exists/);
    assert.equal(hasLegacyPeopleSince(db),false);
    assert.equal(hasNativePeopleSince(db),false);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM entries").get()?.n,64);
    db.exec("DROP TRIGGER legacy_people_time_insert");
    installPeopleSinceIndex(db);
    assert.equal(hasLegacyPeopleSince(db),true);
  } finally { db.close(); }
});
