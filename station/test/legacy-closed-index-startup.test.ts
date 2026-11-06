import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { hasLegacyClosedCards, hasNativeClosedCards, installClosedCardsIndex } from "../src/store/legacy-closed-cards.ts";

test("opening an older store bounds preparation of its per-chat closed-card lookup", () => {
  const counts: number[] = [];
  for (const size of [40, 400]) {
    const dir = mkdtempSync(join(tmpdir(), "old-closed-cards-")), path = join(dir, "station.db");
    const initial = Store.open(path);
    const put = initial.db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(1,?,'p',?)");
    for (let n=1;n<=size;n++) put.run(n,n);
    initial.db.exec("DROP INDEX IF EXISTS closed_cards_thread_at");
    initial.close();
    const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const exec = descriptor.value as DatabaseSync["exec"];
    const prepareDescriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "prepare")!;
    const prepare = prepareDescriptor.value as DatabaseSync["prepare"];
    const marker = "CREATE INDEX IF NOT EXISTS closed_cards_thread_at ON closed_cards (thread, at)";
    const visited = new Set<string>();
    Object.defineProperty(DatabaseSync.prototype, "exec", { ...descriptor, value(this: DatabaseSync, sql: string) {
      if (sql.includes(marker)) {
        this.function("visit_closed_thread_build", { deterministic: true }, (n) => { visited.add(String(n)); return 1; });
        sql = sql.replace(marker, `${marker} WHERE visit_closed_thread_build(n)`);
      }
      return exec.call(this, sql);
    } });
    Object.defineProperty(DatabaseSync.prototype, "prepare", { ...prepareDescriptor, value(this: DatabaseSync, sql: string) {
      if (sql === "SELECT 1 FROM closed_cards LIMIT 1 OFFSET 63") {
        this.function("visit_closed_thread_probe", (n) => { visited.add(String(n)); return 1; });
        sql = "SELECT 1 FROM closed_cards WHERE visit_closed_thread_probe(n) LIMIT 1 OFFSET 63";
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
  assert.ok(counts[0]! <= 64 && counts[1]! <= 64, `closed cards visited while opening: ${counts.join(" / ")}`);
});

for (const change of ["write", "index"] as const) {
  test(`installation rechecks an old connection's ${change} under the writer lock`, () => {
    const dir = mkdtempSync(join(tmpdir(), "closed-cards-install-race-"));
    const file = join(dir, "old.db"), db = new DatabaseSync(file), old = new DatabaseSync(file);
    try {
      db.exec(`PRAGMA journal_mode=WAL; CREATE TABLE closed_cards(thread INTEGER NOT NULL,n INTEGER NOT NULL,
        viewer TEXT NOT NULL,at INTEGER NOT NULL,PRIMARY KEY(thread,n));`);
      const put = db.prepare("INSERT INTO closed_cards VALUES(1,?,'p',?)");
      for (let n=1;n<=(change === "write" ? 63 : 65);n++) put.run(n,n);
      let raced = false;
      const intercepted = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !raced) {
            raced = true;
            if (change === "write") old.exec("INSERT INTO closed_cards VALUES(1,64,'p',64)");
            else old.exec("CREATE INDEX closed_cards_thread_at ON closed_cards(thread,at)");
          }
          return target.exec(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      installClosedCardsIndex(intercepted);
      assert.equal(raced, true);
      assert.equal(hasNativeClosedCards(db), change === "index");
      assert.equal(hasLegacyClosedCards(db), change === "write");
    } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
  });
}

test("a failed installation rolls back its tables without touching old closed cards", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE closed_cards(thread INTEGER NOT NULL,n INTEGER NOT NULL,viewer TEXT NOT NULL,at INTEGER NOT NULL,
      PRIMARY KEY(thread,n)); CREATE TRIGGER legacy_closed_insert BEFORE INSERT ON closed_cards BEGIN SELECT 1; END;`);
    const put = db.prepare("INSERT INTO closed_cards VALUES(1,?,'p',?)");
    for (let n=1;n<=64;n++) put.run(n,n);
    assert.throws(() => installClosedCardsIndex(db), /already exists/);
    assert.equal(hasLegacyClosedCards(db), false);
    assert.equal(hasNativeClosedCards(db), false);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards").get()?.n,64);
    db.exec("DROP TRIGGER legacy_closed_insert");
    installClosedCardsIndex(db);
    assert.equal(hasLegacyClosedCards(db), true);
  } finally { db.close(); }
});
