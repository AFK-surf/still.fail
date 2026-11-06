import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { decisionSessionIndexStep, hasLegacyDecisionSession, hasSharedDecisionSession, installDecisionSessionIndex } from "../src/store/legacy-decision-session.ts";
import { decisionTimeIndexStep, installDecisionTimeIndex } from "../src/store/legacy-decision-time.ts";

function database(size: number, path = ":memory:"): DatabaseSync {
  const db = new DatabaseSync(path);
  db.exec("CREATE TABLE decision_checks(id INTEGER PRIMARY KEY,session TEXT NOT NULL,created_at INTEGER NOT NULL,result TEXT NOT NULL)");
  const put = db.prepare("INSERT INTO decision_checks VALUES(?,?,?,?)");
  for (let id = 1; id <= size; id++) put.run(id, `s${id % 7}`, id, "{}");
  return db;
}

test("both missing indexes share one preparation without an extra shadow table", () => {
  const db = database(150);
  try {
    installDecisionTimeIndex(db, true);
    installDecisionSessionIndex(db);
    assert.equal(hasSharedDecisionSession(db), true);
    assert.equal(hasLegacyDecisionSession(db), false);
    const old = db.prepare("INSERT INTO decision_checks VALUES(?,?,?,?)");
    assert.equal(decisionTimeIndexStep(db, 8).done, false);
    old.run(151, "late", 1, "{}");
    db.exec("UPDATE decision_checks SET session='changed' WHERE id=1");
    while (!decisionTimeIndexStep(db, 8).done) { /* prepare both */ }
    assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_time ORDER BY id").all(),
      db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
    const plan = db.prepare(`EXPLAIN QUERY PLAN SELECT id FROM legacy_decision_time INDEXED BY legacy_decision_time_by_session
      WHERE session=? ORDER BY id DESC LIMIT 1`).all("late");
    assert.ok(plan.some((row) => /SEARCH.*legacy_decision_time_by_session.*session=/.test(String(row.detail))));
  } finally { db.close(); }
});

test("a native session index does not get a redundant shared index", () => {
  const db = database(80);
  try {
    db.exec("CREATE INDEX decision_checks_session ON decision_checks(session,id)");
    installDecisionTimeIndex(db, true);
    installDecisionSessionIndex(db);
    assert.equal(hasSharedDecisionSession(db), false);
    assert.equal(hasLegacyDecisionSession(db), false);
  } finally { db.close(); }
});

for (const state of ["native time", "existing time preparation"] as const)
  test(`${state} keeps its own time lookup when the session index is missing`, () => {
    const db = database(80);
    try {
      if (state === "native time") db.exec("CREATE INDEX decision_checks_lately ON decision_checks(created_at,session)");
      else { installDecisionTimeIndex(db); assert.equal(decisionTimeIndexStep(db, 8).done, false); }
      installDecisionTimeIndex(db, true);
      installDecisionSessionIndex(db);
      assert.equal(hasSharedDecisionSession(db), false);
      assert.equal(hasLegacyDecisionSession(db), true);
      while (!decisionSessionIndexStep(db, 8).done) { /* prepare */ }
      assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_session ORDER BY id").all(),
        db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
    } finally { db.close(); }
  });

test("small stores use the native index; a large store prepares at most 64 old checks per transaction", () => {
  for (const size of [0, 63, 64, 400]) {
    const db = database(size);
    try {
      installDecisionSessionIndex(db);
      const native = db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='decision_checks_session'").get();
      assert.equal(native !== undefined, size < 64);
      if (size < 64) continue;
      let visited = 0, step;
      do {
        step = decisionSessionIndexStep(db);
        assert.ok(step.visited <= 64);
        visited += step.visited;
      } while (!step.done);
      assert.equal(visited, size);
      assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_session ORDER BY id").all(),
        db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
    } finally { db.close(); }
  }
});

for (const winner of ["old writes", "native index", "another opener", "shared time"] as const) test(
  `session installation rechecks ${winner} under the writer lock`, () => {
    const dir = mkdtempSync(join(tmpdir(), "decision-session-install-")), path = join(dir, "station.db");
    const db = database(winner === "old writes" ? 40 : 100, path), old = new DatabaseSync(path, { timeout: 5000 });
    try {
      let intercepted = false;
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !intercepted) {
            intercepted = true;
            if (winner === "old writes") {
              const put = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('later',?,'{}')");
              for (let n = 40; n < 100; n++) put.run(n);
            } else if (winner === "native index") old.exec("CREATE INDEX decision_checks_session ON decision_checks(session,id)");
            else if (winner === "shared time") installDecisionTimeIndex(old, true);
            else installDecisionSessionIndex(old);
          }
          return target.exec(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      installDecisionSessionIndex(observed);
      assert.equal(intercepted, true);
      assert.equal(hasSharedDecisionSession(db), winner === "shared time");
      assert.equal(hasLegacyDecisionSession(db), winner === "old writes" || winner === "another opener");
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='decision_checks_session'").get() !== undefined,
        winner === "native index");
      if (winner === "native index") return;
      const shared = winner === "shared time";
      const step = shared ? decisionTimeIndexStep : decisionSessionIndexStep;
      while (!step(db, 7).done) { /* prepare */ }
      const table = shared ? "legacy_decision_time" : "legacy_decision_session";
      assert.deepEqual(db.prepare(`SELECT id,session FROM ${table} ORDER BY id`).all(),
        db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
    } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
  });

for (const winner of ["native session", "separate session", "shared time"] as const) test(
  `time installation rechecks ${winner} before choosing a shared session lookup`, () => {
    const dir = mkdtempSync(join(tmpdir(), "decision-shared-install-")), path = join(dir, "station.db");
    const db = database(100, path), old = new DatabaseSync(path, { timeout: 5000 });
    try {
      let intercepted = false;
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE" && !intercepted) {
            intercepted = true;
            if (winner === "native session") old.exec("CREATE INDEX decision_checks_session ON decision_checks(session,id)");
            else if (winner === "separate session") installDecisionSessionIndex(old);
            else installDecisionTimeIndex(old, true);
          }
          return target.exec(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      installDecisionTimeIndex(observed, true);
      installDecisionSessionIndex(db);
      assert.equal(intercepted, true);
      assert.equal(hasSharedDecisionSession(db), winner === "shared time");
      assert.equal(hasLegacyDecisionSession(db), winner === "separate session");
      while (!decisionTimeIndexStep(db, 7).done) { /* time lookup */ }
      if (winner === "separate session") while (!decisionSessionIndexStep(db, 7).done) { /* session lookup */ }
      assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_time ORDER BY id").all(),
        db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
    } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
  });

test("a failed session lookup installation rolls back and can be retried", () => {
  const db = database(80);
  try {
    const before = db.prepare("SELECT * FROM decision_checks ORDER BY id").all();
    db.exec("CREATE TRIGGER legacy_decision_session_insert AFTER INSERT ON decision_checks BEGIN SELECT 1; END");
    assert.throws(() => installDecisionSessionIndex(db), /already exists/);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='legacy_decision_session_meta'").get(), undefined);
    assert.deepEqual(db.prepare("SELECT * FROM decision_checks ORDER BY id").all(), before);
    db.exec("DROP TRIGGER legacy_decision_session_insert");
    installDecisionSessionIndex(db);
    while (!decisionSessionIndexStep(db, 7).done) { /* retry */ }
    assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_session ORDER BY id").all(),
      db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`old writes and rollback preserve the session lookup (recursive ${recursive})`, () => {
  const db = database(80);
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    installDecisionSessionIndex(db);
    assert.deepEqual(decisionSessionIndexStep(db, 16), { done: false, visited: 16 });
    db.exec(`UPDATE decision_checks SET session='moved' WHERE id=4;
      DELETE FROM decision_checks WHERE id=5;
      INSERT OR REPLACE INTO decision_checks VALUES(6,'replacement',200,'{}');
      INSERT OR IGNORE INTO decision_checks VALUES(7,'ignored',201,'{}');
      INSERT INTO decision_checks VALUES(500,'late',202,'{}')`);
    db.exec("BEGIN");
    db.exec("UPDATE decision_checks SET session='rolled-back' WHERE id=4");
    db.exec("ROLLBACK");
    while (!decisionSessionIndexStep(db, 16).done) { /* prepare */ }
    assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_session ORDER BY id").all(),
      db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
    assert.deepEqual(db.prepare(`SELECT d.id,d.result FROM legacy_decision_session s
      CROSS JOIN decision_checks d ON d.id=s.id WHERE s.session=? ORDER BY s.id DESC LIMIT 1`).get("replacement"),
      db.prepare("SELECT id,result FROM decision_checks WHERE session=? ORDER BY id DESC LIMIT 1").get("replacement"));
  } finally { db.close(); }
});

for (const recursive of [false, true]) for (const installedFirst of [false, true]) for (const when of ["BEFORE", "AFTER"]) {
  for (const action of ["delete", "replace"]) test(
    `nested ${when} ${action} keeps the session lookup exact (recursive ${recursive}, installed first ${installedFirst})`, () => {
      const db = database(80);
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
        const change = action === "delete" ? "DELETE FROM decision_checks WHERE id=NEW.id"
          : "INSERT OR REPLACE INTO decision_checks VALUES(NEW.id,'inner',22,'{}')";
        const nested = `CREATE TRIGGER nested_session ${when} INSERT ON decision_checks
          WHEN NEW.session='outer' BEGIN ${change}; END;`;
        if (!installedFirst) db.exec(nested);
        installDecisionSessionIndex(db);
        while (!decisionSessionIndexStep(db, 8).done) { /* prepare */ }
        if (installedFirst) db.exec(nested);
        db.exec("INSERT OR REPLACE INTO decision_checks VALUES(1,'outer',11,'{}')");
        assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_session ORDER BY id").all(),
          db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
      } finally { db.close(); }
    });
}

for (const conflict of ["ABORT", "IGNORE", "REPLACE"]) for (const installedFirst of [false, true]) {
  test(`an outer ${conflict} insert keeps the nested same-id session (installed first ${installedFirst})`, () => {
    const db = database(80);
    try {
      const nested = `CREATE TRIGGER nested_session_update AFTER INSERT ON decision_checks WHEN NEW.id=100 BEGIN
        UPDATE decision_checks SET session='inner' WHERE id=NEW.id;
      END;`;
      if (!installedFirst) db.exec(nested);
      installDecisionSessionIndex(db);
      while (!decisionSessionIndexStep(db, 8).done) { /* prepare */ }
      if (installedFirst) db.exec(nested);
      db.exec(`INSERT OR ${conflict} INTO decision_checks VALUES(100,'outer',11,'{}')`);
      assert.deepEqual(db.prepare("SELECT id,session FROM legacy_decision_session ORDER BY id").all(),
        db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all());
    } finally { db.close(); }
  });
}

test("a failed batch rolls back its cursor and can be retried", () => {
  const db = database(80);
  try {
    installDecisionSessionIndex(db);
    db.exec(`CREATE TRIGGER fail_session_copy BEFORE INSERT ON legacy_decision_session WHEN NEW.id=20
      BEGIN SELECT RAISE(ABORT,'stop'); END`);
    assert.throws(() => decisionSessionIndexStep(db, 64), /stop/);
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_decision_session").get()?.n, 0);
    assert.equal(db.prepare("SELECT cursor FROM legacy_decision_session_meta").get()?.cursor, null);
    db.exec("DROP TRIGGER fail_session_copy");
    while (!decisionSessionIndexStep(db, 64).done) { /* retry */ }
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_decision_session").get()?.n, 80);
  } finally { db.close(); }
});

test("preparation preserves keys beyond JavaScript's exact integer range", () => {
  const db = database(64);
  try {
    db.exec("INSERT INTO decision_checks VALUES(9007199254740993,'large',1,'{}')");
    installDecisionSessionIndex(db);
    while (!decisionSessionIndexStep(db, 16).done) { /* prepare */ }
    assert.deepEqual(db.prepare("SELECT CAST(id AS TEXT) id,session FROM legacy_decision_session ORDER BY legacy_decision_session.id").all(),
      db.prepare("SELECT CAST(id AS TEXT) id,session FROM decision_checks ORDER BY decision_checks.id").all());
  } finally { db.close(); }
});
