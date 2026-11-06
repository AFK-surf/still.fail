import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { addTellIndexes } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

test("installing an old message lookup holds a writer for a bounded number of old entries", () => {
  const counts: number[] = [];
  for (const size of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `old-${size}`, null, null).id;
      const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
      for (let n = 1; n <= size; n++) put.run(thread, n, n);
      db.exec("DROP INDEX entries_said");
      let writing = false, largest = 0;
      const seen = new Set<string>();
      db.function("visit_old_said_start", { deterministic: true }, (n) => {
        if (writing) seen.add(String(n));
        return n;
      });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE") { writing = true; seen.clear(); }
          const measured = sql.replace("ON entries (thread, n, author_kind, author, letter)",
            "ON entries (thread, visit_old_said_start(n), author_kind, author, letter)");
          const result = target.exec(measured);
          if (sql === "COMMIT" || sql === "ROLLBACK") { largest = Math.max(largest, seen.size); writing = false; }
          return result;
        };
        if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT 1 FROM entries LIMIT 1 OFFSET 63"
          ? "SELECT 1 FROM entries WHERE visit_old_said_start(n) IS NOT NULL LIMIT 1 OFFSET 63" : sql);
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      addTellIndexes(observed);
      counts.push(largest);
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_said'").get() !== undefined, size === 40);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [40, 64]);
});

test("an old writer adding entries just before the installation lock cannot make the native build unbounded", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-said-startup-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", "startup-race", null, null).id;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
  for (let n = 1; n <= 40; n++) put.run(thread, n, n);
  db.exec("DROP TRIGGER thread_state_add; DROP TRIGGER said_state_before_insert; DROP INDEX entries_said");
  const old = new DatabaseSync(path, { timeout: 5000 });
  try {
    let added = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (!added && sql === "BEGIN IMMEDIATE") {
          added = true;
          const insert = old.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
          old.exec("BEGIN");
          for (let n = 41; n <= 100; n++) insert.run(thread, n, n);
          old.exec("COMMIT");
        }
        return target.exec(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addTellIndexes(observed);
    assert.equal(added, true);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_said'").get(), undefined);
    assert.equal(db.prepare("SELECT COUNT(*) c FROM legacy_said WHERE thread=?").get(thread)?.c, 100);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an earlier station that installs the native lookup before staging keeps it without an extra lookup", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-said-native-race-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", "native-race", null, null).id;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
  for (let n = 1; n <= 100; n++) put.run(thread, n, n);
  db.exec("DROP INDEX entries_said");
  const old = new DatabaseSync(path, { timeout: 5000 });
  try {
    let begins = 0;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE" && ++begins === 2) old.exec(`CREATE INDEX entries_said
          ON entries(thread,n,author_kind,author,letter) WHERE kind='message' AND letter IS NULL`);
        return target.exec(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addTellIndexes(observed);
    assert.equal(begins, 2);
    assert.notEqual(db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_said'").get(), undefined);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='view' AND name='legacy_said'").get(), undefined);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='legacy_said_meta'").get(), undefined);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
