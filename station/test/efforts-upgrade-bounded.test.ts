import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { addTellIndexes } from "../src/store/schema.ts";
import { EFFORTS_USED_BY, EFFORTS_USED_BY_BEFORE_INDEX, Store } from "../src/store/store.ts";

test("opening an older database does not build the effort lookup in one unbounded write", () => {
  const visits: number[] = [];
  for (const count of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      db.exec("DROP INDEX sessions_efforts");
      for (let i = 0; i < count; i++) store.insertSession({ key: `s${i}`, connect: "ember", runtime: "codex", profile: "cc",
        createdBy: "person", model: "model", effort: "high", workspace: `/w/${i}`, token: `s${i}`, createdAt: i, lastActiveAt: i });
      let seen = 0;
      db.function("effort_index_seen", { deterministic: true }, (value) => { seen++; return value; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => target.exec(sql.replace(
          "ON sessions (created_by, runtime, model, created_at, effort)",
          "ON sessions (created_by, runtime, model, created_at, effort_index_seen(effort))"));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      addTellIndexes(observed);
      visits.push(seen);
    } finally { store.close(); }
  }
  assert.ok(visits.every((count) => count <= 64), `one index build read ${visits.join(" / ")} old sessions under a write lock`);
});

test("an old large store answers effort choices while another connection changes sessions", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "efforts-upgrade-")), path = join(dir, "store.sqlite");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  let store = Store.open(path);
  try {
    for (let i = 0; i < 70; i++) store.insertSession({ key: `f${i}`, connect: "ember", runtime: "codex", profile: "cc",
      createdBy: "other", model: "model", effort: "low", workspace: `/w/${i}`, token: `f${i}`, createdAt: i, lastActiveAt: i });
    const add = (key: string, createdBy: string, model: string | null, effort: string, at: number) => store.insertSession({
      key, connect: "ember", runtime: "codex", profile: "cc", createdBy, model, effort, workspace: `/w/${key}`,
      token: key, createdAt: at, lastActiveAt: at,
    });
    add("a", "person", null, "high", 100);
    add("b", "person", null, "max", 101);
    add("c", "person", null, "max", 102);
    add("d", "person", "other-model", "low", 103);
    add("e", "person", null, "low", 99);
    store.db.exec("DROP INDEX sessions_efforts");
  } finally { store.close(); }
  store = Store.open(path);
  const oldWriter = new DatabaseSync(path, { timeout: 0 });
  try {
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'sessions_efforts'").get(), undefined);
    assert.deepEqual(store.effortsUsedBy("person", "codex", null, 100), [{ effort: "max", n: 2 }, { effort: "high", n: 1 }]);
    oldWriter.prepare("UPDATE sessions SET effort = ? WHERE key = ?").run("high", "c");
    assert.deepEqual(store.effortsUsedBy("person", "codex", null, 100), [{ effort: "high", n: 2 }, { effort: "max", n: 1 }]);
    // A previous station may finish creating its own index after this station chose its fallback.
    oldWriter.exec("CREATE INDEX sessions_efforts ON sessions (created_by, runtime, model, created_at, effort)");
    assert.deepEqual(store.effortsUsedBy("person", "codex", null, 100), [{ effort: "high", n: 2 }, { effort: "max", n: 1 }]);
  } finally { oldWriter.close(); store.close(); }
});

test("a writer adding sessions before the install lock cannot make the index build unbounded", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec("DROP INDEX sessions_efforts");
    let added = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE" && !added) {
          added = true;
          for (let i = 0; i < 65; i++) store.insertSession({ key: `s${i}`, connect: "ember", runtime: "codex", profile: "cc",
            workspace: `/w/${i}`, token: `s${i}`, createdAt: i, lastActiveAt: i });
        }
        return target.exec(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addTellIndexes(observed);
    assert.equal(added, true);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sessions_efforts'").get(), undefined);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sessions").get()?.n, 65);
  } finally { store.close(); }
});

test("an interrupted small-store index install rolls back and can be retried", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec("DROP INDEX sessions_efforts");
    const observed = new Proxy(db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (sql.startsWith("CREATE INDEX IF NOT EXISTS sessions_efforts")) throw new Error("interrupted");
        return target.exec(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.throws(() => addTellIndexes(observed), /interrupted/);
    addTellIndexes(db);
    assert.ok(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sessions_efforts'").get());
  } finally { store.close(); }
});

test("a store that already has the effort index keeps it as sessions grow", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (let i = 0; i < 70; i++) store.insertSession({ key: `s${i}`, connect: "ember", runtime: "codex", profile: "cc",
      createdBy: "person", model: "m", effort: "high", workspace: `/w/${i}`, token: `s${i}`, createdAt: i, lastActiveAt: i });
    addTellIndexes(db);
    assert.ok(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sessions_efforts'").get());
    assert.deepEqual(store.effortsUsedBy("person", "codex", "m", 0), [{ effort: "high", n: 70 }]);
  } finally { store.close(); }
});

test("the fallback does not visit older sessions or another person's sessions", () => {
  const counts: number[] = [];
  for (const count of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const put = db.prepare(`INSERT INTO sessions (key, connect, scope, runtime, profile, workspace, token,
        created_by, model, effort, created_at, last_active_at) VALUES (?, 'ember', 'thread', 'codex', 'cc', '/', ?, ?, 'm', 'max', ?, ?)`);
      put.run("mine", "mine", "person", 100, 100);
      for (let i = 0; i < count; i++) {
        put.run(`other-${i}`, `other-${i}`, "other", 100, 100);
        put.run(`old-${i}`, `old-${i}`, "person", 1, 1);
      }
      let visited = 0;
      db.function("effort_candidate_seen", (_key) => { visited++; return 1; });
      const sql = EFFORTS_USED_BY_BEFORE_INDEX.replace("created_by = ? AND runtime", "created_by = ? AND effort_candidate_seen(key) AND runtime");
      assert.equal(db.prepare(sql).all("person", "codex", "m", 100).length, 1);
      counts.push(visited);
    } finally { store.close(); }
  }
  assert.deepEqual(counts, [1, 1]);
});

test("the fallback and the installed effort index agree across interleaved changes", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const put = db.prepare(`INSERT OR REPLACE INTO sessions (key, connect, scope, runtime, profile, workspace, token,
      created_by, model, effort, created_at, last_active_at) VALUES (?, 'ember', 'thread', ?, 'cc', '/', ?, ?, ?, ?, ?, ?)`);
    const a = db.prepare(EFFORTS_USED_BY), b = db.prepare(EFFORTS_USED_BY_BEFORE_INDEX);
    const models: (string | null)[] = [null, "m", "other"], efforts: (string | null)[] = [null, "", "low", "max"];
    let seed = 0x32f61;
    let sawChoice = false;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return Math.floor(seed / 0x100000000 * n); };
    for (let i = 0; i < 160; i++) {
      const id = `s${next(31)}`, at = next(20);
      put.run(id, next(2) ? "codex" : "claude", id, next(2) ? "person" : "other", models[next(models.length)] ?? null,
        efforts[next(efforts.length)] ?? null, at, at);
      for (const model of models) {
        const expected = a.all("person", "codex", model, 10);
        if (expected.length > 0) sawChoice = true;
        assert.deepEqual(b.all("person", "codex", model, 10), expected);
      }
    }
    assert.ok(sawChoice, "the changing rows included a matching effort");
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${EFFORTS_USED_BY_BEFORE_INDEX}`).all("person", "codex", null, 10) as { detail: string }[];
    assert.ok(plan.some((row) => /SEARCH sessions USING INDEX sessions_models \(created_by=\? AND created_at>\?\)/.test(row.detail)), JSON.stringify(plan));
  } finally { store.close(); }
});
