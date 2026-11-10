import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { decisionTimeIndexNeedsWork, decisionTimeIndexStep, hasLegacyDecisionTime, installDecisionTimeIndex } from "../src/store/legacy-decision-time.ts";

function database(size: number, path = ":memory:"): DatabaseSync {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE decision_checks(id INTEGER PRIMARY KEY,session TEXT NOT NULL,created_at INTEGER NOT NULL,result TEXT NOT NULL);
    CREATE INDEX decision_checks_at ON decision_checks(created_at);`);
  const put = db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('old',?, '{}')");
  for (let i = 0; i < size; i++) put.run(i);
  return db;
}
function same(db: DatabaseSync): void {
  const fields = "CAST(id AS TEXT) id,CAST(created_at AS TEXT) created_at,session";
  assert.deepEqual(db.prepare(`SELECT ${fields} FROM legacy_decision_time ORDER BY legacy_decision_time.id`).all(),
    db.prepare(`SELECT ${fields} FROM decision_checks ORDER BY decision_checks.id`).all());
}

test("small stores get a native index; larger stores copy at most 64 checks per transaction", () => {
  for (const size of [0, 63, 64, 400]) {
    const db = database(size);
    try {
      installDecisionTimeIndex(db);
      if (size < 64) {
        assert.equal(hasLegacyDecisionTime(db), false);
        assert.notEqual(db.prepare("SELECT 1 FROM sqlite_master WHERE name='decision_checks_lately'").get(), undefined);
      } else {
        assert.equal(hasLegacyDecisionTime(db), true);
        assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='decision_checks_lately'").get(), undefined);
        let total = 0, batch;
        do {
          batch = decisionTimeIndexStep(db);
          assert.ok(batch.visited <= 64);
          total += batch.visited;
        } while (!batch.done);
        assert.equal(total, size);
        assert.equal(decisionTimeIndexNeedsWork(db), false);
        same(db);
      }
    } finally { db.close(); }
  }
});

for (const winner of ["old writes", "native index", "another opener"] as const) {
  test(`installation rechecks ${winner} after acquiring the writer lock`, () => {
    const dir = mkdtempSync(join(tmpdir(), "decision-time-install-")), path = join(dir, "station.db");
    const db = database(winner === "old writes" ? 40 : 100, path);
    const old = new DatabaseSync(path, { timeout: 5000 });
    try {
      let intercepted = false;
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !intercepted) {
            intercepted = true;
            if (winner === "old writes") {
              const put = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('old',?, '{}')");
              for (let i = 40; i < 100; i++) put.run(i);
            } else if (winner === "native index") {
              old.exec("CREATE INDEX decision_checks_lately ON decision_checks(created_at,session)");
            } else installDecisionTimeIndex(old);
          }
          return target.exec(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      installDecisionTimeIndex(observed);
      assert.equal(intercepted, true);
      assert.equal(hasLegacyDecisionTime(db), winner !== "native index");
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='decision_checks_lately'").get() !== undefined,
        winner === "native index");
      if (winner !== "native index") {
        while (!decisionTimeIndexStep(db, 7).done) { /* prepare */ }
        same(db);
      }
    } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
  });
}

test("a failed installation rolls back and can be retried", () => {
  const db = database(80);
  try {
    const before = db.prepare("SELECT * FROM decision_checks ORDER BY id").all();
    db.exec("CREATE TRIGGER legacy_decision_time_insert AFTER INSERT ON decision_checks BEGIN SELECT 1; END");
    assert.throws(() => installDecisionTimeIndex(db), /already exists/);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='legacy_decision_time_meta'").get(), undefined);
    assert.deepEqual(db.prepare("SELECT * FROM decision_checks ORDER BY id").all(), before);
    db.exec("DROP TRIGGER legacy_decision_time_insert");
    installDecisionTimeIndex(db);
    while (!decisionTimeIndexStep(db, 7).done) { /* retry */ }
    same(db);
  } finally { db.close(); }
});

for (const recursive of [false, true]) for (const installedFirst of [false, true]) for (const when of ["BEFORE", "AFTER"]) {
  test(`old nested and ignored writes keep the time lookup exact (${when}, recursive ${recursive}, installed first ${installedFirst})`, () => {
    const db = database(80);
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const nested = `CREATE TRIGGER nested_decision ${when} INSERT ON decision_checks WHEN NEW.session='outer' BEGIN
        UPDATE decision_checks SET created_at=-5,session='changed' WHERE id=1;
        INSERT OR REPLACE INTO decision_checks(id,session,created_at,result) VALUES(81,'inner',88,'{}');
      END;`;
      if (!installedFirst) db.exec(nested);
      installDecisionTimeIndex(db);
      assert.equal(decisionTimeIndexStep(db, 3).done, false);
      if (installedFirst) db.exec(nested);
      db.exec(`INSERT INTO decision_checks(id,session,created_at,result) VALUES(100,'outer',99,'{}');
        INSERT OR IGNORE INTO decision_checks(id,session,created_at,result) VALUES(1,'ignored',999,'{}');
        UPDATE decision_checks SET id=120,session='moved',created_at=12 WHERE id=2;
        DELETE FROM decision_checks WHERE id=3;`);
      while (!decisionTimeIndexStep(db, 7).done) { /* finish old rows */ }
      same(db);
      db.exec("INSERT OR REPLACE INTO decision_checks(id,session,created_at,result) VALUES(120,'replacement',500,'{}')");
      same(db);
    } finally { db.close(); }
  });
}

for (const conflict of ["ABORT", "IGNORE", "REPLACE"]) for (const installedFirst of [false, true]) {
  test(`an outer ${conflict} insert keeps a nested same-id update (installed first ${installedFirst})`, () => {
    const db = database(80);
    try {
      const nested = `CREATE TRIGGER nested_update AFTER INSERT ON decision_checks WHEN NEW.id=100 BEGIN
        UPDATE decision_checks SET session='inner',created_at=22 WHERE id=NEW.id;
      END;`;
      if (!installedFirst) db.exec(nested);
      installDecisionTimeIndex(db);
      while (!decisionTimeIndexStep(db, 8).done) { /* prepare */ }
      if (installedFirst) db.exec(nested);
      db.exec(`INSERT OR ${conflict} INTO decision_checks(id,session,created_at,result) VALUES(100,'outer',11,'{}')`);
      same(db);
    } finally { db.close(); }
  });
}

for (const recursive of [false, true]) for (const installedFirst of [false, true]) for (const when of ["BEFORE", "AFTER"]) {
  for (const action of ["delete", "replace"]) {
    test(`nested ${when} ${action} of the inserted id stays exact (recursive ${recursive}, installed first ${installedFirst})`, () => {
      const db = database(80);
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
        const change = action === "delete" ? "DELETE FROM decision_checks WHERE id=NEW.id"
          : "INSERT OR REPLACE INTO decision_checks(id,session,created_at,result) VALUES(NEW.id,'inner',22,'{}')";
        const nested = `CREATE TRIGGER nested_same_id ${when} INSERT ON decision_checks WHEN NEW.session='outer' BEGIN ${change}; END;`;
        if (!installedFirst) db.exec(nested);
        installDecisionTimeIndex(db);
        while (!decisionTimeIndexStep(db, 8).done) { /* prepare */ }
        if (installedFirst) db.exec(nested);
        db.exec("INSERT OR REPLACE INTO decision_checks(id,session,created_at,result) VALUES(1,'outer',11,'{}')");
        same(db);
      } finally { db.close(); }
    });
  }
}

test("a failed batch rolls back its rows and cursor and can be retried", () => {
  const db = database(80);
  try {
    installDecisionTimeIndex(db);
    db.exec("CREATE TRIGGER fail_decision_time BEFORE INSERT ON legacy_decision_time WHEN NEW.id=3 BEGIN SELECT RAISE(ABORT,'interrupted'); END");
    assert.throws(() => decisionTimeIndexStep(db, 8), /interrupted/);
    assert.equal(db.prepare("SELECT COUNT(*) c FROM legacy_decision_time").get()?.c, 0);
    assert.equal(db.prepare("SELECT cursor FROM legacy_decision_time_meta").get()?.cursor, null);
    db.exec("DROP TRIGGER fail_decision_time");
    while (!decisionTimeIndexStep(db, 8).done) { /* resume */ }
    same(db);
  } finally { db.close(); }
});

test("preparation preserves keys and times beyond JavaScript's exact integer range", () => {
  const db = database(80);
  try {
    db.exec("INSERT INTO decision_checks(id,session,created_at,result) VALUES(9007199254740993,'large',9007199254740995,'{}')");
    installDecisionTimeIndex(db);
    while (!decisionTimeIndexStep(db, 13).done) { /* prepare */ }
    same(db);
  } finally { db.close(); }
});
