import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { LATEST_DECISIONS, Store } from "../src/store/store.ts";

const sql = "CREATE INDEX IF NOT EXISTS decision_checks_at ON decision_checks (created_at)";
const hasIndex = (db: DatabaseSync) => db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='decision_checks_at'").get() !== undefined;

test("opening an older store does not rebuild the redundant decision-time index", () => {
  const visited: number[] = [];
  const present: boolean[] = [];
  for (const size of [40, 400]) {
    const dir = mkdtempSync(join(tmpdir(), "unused-decision-at-")), path = join(dir, "station.db");
    const initial = Store.open(path);
    initial.db.exec("BEGIN");
    const put = initial.db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES('a',?, '{}')");
    for (let n = 0; n < size; n++) put.run(n);
    initial.db.exec("COMMIT");
    initial.db.exec("DROP INDEX IF EXISTS decision_checks_at");
    initial.close();
    const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const exec = descriptor.value as DatabaseSync["exec"];
    let count = 0;
    Object.defineProperty(DatabaseSync.prototype, "exec", { ...descriptor, value(this: DatabaseSync, source: string) {
      if (source.includes(sql)) {
        this.function("visit_decision_at_build", { deterministic: true }, (id) => { count++; return id === null ? 0 : 1; });
        source = source.replace(sql, `${sql} WHERE visit_decision_at_build(id)`);
      }
      return exec.call(this, source);
    } });
    let reopened: Store | null = null;
    try {
      reopened = Store.open(path);
      present.push(hasIndex(reopened.db));
      visited.push(count);
    } finally {
      reopened?.close();
      Object.defineProperty(DatabaseSync.prototype, "exec", descriptor);
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.deepEqual(visited, [0, 0], "opening should not visit old checks to build the redundant index");
  assert.deepEqual(present, [false, false]);
});

test("new stores omit the shorter index and existing stores retain it for old prepared statements", () => {
  const dir = mkdtempSync(join(tmpdir(), "old-decision-at-")), path = join(dir, "station.db");
  let store: Store | null = Store.open(path);
  let old: DatabaseSync | null = null;
  try {
    assert.equal(hasIndex(store.db), false);
    const put = store.db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES(?,?,?)");
    put.run("a", 5, '{"n":1}');
    put.run("a", 8, '{"n":2}');
    put.run("b", 8, '{"n":3}');
    assert.deepEqual(store.latestDecisionsSince(6).map((r) => r.session), ["a", "b"]);
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${LATEST_DECISIONS}`).all(6) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.some((p) => p.includes("COVERING INDEX decision_checks_lately")), plan.join(" | "));
    store.db.exec(sql);
    store.close();
    old = new DatabaseSync(path);
    const read = old.prepare("SELECT id FROM decision_checks INDEXED BY decision_checks_at WHERE created_at >= ? ORDER BY created_at, id");
    const write = old.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES(?,?,?)");
    store = Store.open(path);
    assert.equal(hasIndex(store.db), true);
    write.run("c", 9, '{"n":4}');
    assert.deepEqual(read.all(8).map((row) => row.id), [2, 3, 4]);
    assert.deepEqual(store.latestDecisionsSince(6).map((r) => r.session), ["a", "b", "c"]);
  } finally { old?.close(); store?.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a store missing both time indexes still builds the covering one", () => {
  const dir = mkdtempSync(join(tmpdir(), "missing-decision-time-")), path = join(dir, "station.db");
  let store: Store | null = Store.open(path);
  try {
    const put = store.db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES(?,?,?)");
    put.run("a", 5, '{"n":1}');
    put.run("b", 8, '{"n":2}');
    put.run("a", 8, '{"n":3}');
    store.db.exec("DROP INDEX decision_checks_lately");
    store.close();
    store = Store.open(path);
    assert.equal(hasIndex(store.db), false);
    assert.notEqual(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='decision_checks_lately'").get(), undefined);
    assert.deepEqual(store.latestDecisionsSince(6).map((r) => r.session), ["b", "a"]);
  } finally { store?.close(); rmSync(dir, { recursive: true, force: true }); }
});
