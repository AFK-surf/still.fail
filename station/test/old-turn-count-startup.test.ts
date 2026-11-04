import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as read from "../src/read/store.ts";
import { addSessionTurns } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { TURN_COUNT_BATCH, turnCountStep, type TurnCountScan } from "../src/store/turn-state.ts";

function forgetCounts(db: DatabaseSync) {
  db.exec(`DROP TRIGGER IF EXISTS session_turns_add; DROP TRIGGER IF EXISTS session_turns_drop;
    DROP TRIGGER IF EXISTS session_turns_before_insert; DROP TRIGGER IF EXISTS session_turns_move;
    DROP TABLE IF EXISTS session_turns_guard; DROP TABLE session_turns`);
}

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "old-turn-count-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  for (const key of ["long", "short", "other"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
    workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
  const put = store.db.prepare("INSERT INTO turns(rowid,id,session_key,kind,started_at) VALUES (?, ?, ?, 'input', ?)");
  store.db.exec("BEGIN");
  for (let n = 0; n < 150; n++) put.run(n - 75, `old-${n}`, "long", 1);
  for (let n = 0; n < 5; n++) put.run(n + 200, `short-${n}`, "short", n);
  store.db.exec("COMMIT");
  forgetCounts(store.db);
  addSessionTurns(store.db);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function finish(db: DatabaseSync, session: string, scan: TurnCountScan | null = null): void {
  for (let i = 0; i < 30; i++) {
    const step = turnCountStep(db, session, scan);
    assert.ok(step.visited <= TURN_COUNT_BATCH);
    if (step.done) return;
    scan = step.scan;
  }
  assert.fail("the count did not finish");
}

test("installing turn counts does not visit an old station's turns", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const put = db.prepare("INSERT INTO turns(id,session_key,kind,started_at) VALUES (?,?,'user',?)");
    db.exec("BEGIN");
    for (let n = 0; n < 5_000; n++) put.run(`turn-${n}`, `session-${n % 5}`, n);
    db.exec("COMMIT");
    forgetCounts(db);
    let visited = 0;
    db.function("visit_old_turn", (_id) => { visited++; return 1; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "exec") return (sql: string) => target.exec(sql.replace(
          "SELECT session_key, COUNT(*) FROM turns GROUP BY session_key",
          "SELECT session_key, COUNT(visit_old_turn(id)) FROM turns GROUP BY session_key",
        ));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    addSessionTurns(instrumented);
    assert.equal(visited, 0, `opening an older station visited ${visited} old turns`);
  } finally { store.close(); }
});

test("short old sessions answer exactly without writing; long counts stay unknown until prepared", () => {
  const f = fixture();
  try {
    const r = read.makeStore(f.store.db, f.dir);
    assert.equal(read.sessionStats(r, "short").get("short")?.turns, 5);
    assert.equal(read.sessionStats(r, "other").get("other")?.turns, 0);
    assert.throws(() => read.sessionStats(r, "long"), read.TurnCountUnavailable);
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM session_turns").get()?.n, 0);
    finish(f.store.db, "long");
    assert.equal(read.sessionStats(r, "long").get("long")?.turns, 150);
    assert.deepEqual(f.store.db.prepare("SELECT session,n FROM session_turns").all().map((r: any) => [r.session, r.n]), [["long", 150]]);
  } finally { f.close(); }
});

test("old turn count discards slices changed by another connection and keeps new counts exact", () => {
  const f = fixture();
  const other = new DatabaseSync(f.path);
  try {
    let step = turnCountStep(f.store.db, "long", null);
    step = turnCountStep(f.store.db, "long", step.scan);
    assert.equal(step.visited, 64);
    other.prepare("INSERT INTO turns(rowid,id,session_key,kind,started_at) VALUES (?,?,'long','input',?)").run(-1000, "late-old", 0);
    other.prepare("DELETE FROM turns WHERE id=?").run("old-80");
    const stale = turnCountStep(f.store.db, "long", step.scan);
    assert.equal(stale.done, false);
    assert.equal(stale.scan, null);
    assert.equal(f.store.db.prepare("SELECT n FROM session_turns WHERE session='long'").get(), undefined);
    finish(f.store.db, "long");
    const r = read.makeStore(f.store.db, f.dir);
    assert.equal(read.sessionStats(r, "long").get("long")?.turns, 150);
    other.prepare("INSERT INTO turns(id,session_key,kind,started_at) VALUES ('after','long','input',2)").run();
    assert.equal(read.sessionStats(r, "long").get("long")?.turns, 151);
    other.prepare("DELETE FROM turns WHERE id='after'").run();
    assert.equal(read.sessionStats(r, "long").get("long")?.turns, 150);
    other.prepare("UPDATE turns SET session_key='other' WHERE id='old-1'").run();
    assert.throws(() => read.sessionStats(r, "long"), read.TurnCountUnavailable);
    assert.equal(read.sessionStats(r, "other").get("other")?.turns, 1);
    finish(f.store.db, "long");
    assert.equal(read.sessionStats(r, "long").get("long")?.turns, 149);
  } finally { other.close(); f.close(); }
});

for (const recursive of [false, true]) test(`replacing a turn cannot leave a stale old count (recursive triggers ${recursive})`, () => {
  const f = fixture();
  try {
    f.store.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    finish(f.store.db, "long");
    f.store.db.prepare("INSERT OR REPLACE INTO turns(id,session_key,kind,started_at) VALUES ('old-1','long','input',2)").run();
    const r = read.makeStore(f.store.db, f.dir);
    assert.throws(() => read.sessionStats(r, "long"), read.TurnCountUnavailable);
    finish(f.store.db, "long");
    assert.equal(read.sessionStats(r, "long").get("long")?.turns, 150);
  } finally { f.close(); }
});

test("a reader shares an old count after handover while short sessions remain immediately available", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const one = readers.read("summary", { key: "long" }, "en");
    const two = readers.read("summary", { key: "long" }, "en");
    const short = JSON.parse(await readers.read("summary", { key: "short" }, "en"));
    assert.equal(short.turns, 5);
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM session_turns_guard").get()?.n, 0);
    previous.resolve();
    const [first, second] = await Promise.all([one, two]);
    assert.equal(first, second);
    assert.equal(JSON.parse(first).turns, 150);
    assert.deepEqual(f.store.db.prepare("SELECT session,n FROM session_turns").all().map((r: any) => [r.session, r.n]), [["long", 150]]);
  } finally { readers.close(); previous.resolve(); f.close(); }
});

test("abandoning a read before handover does not start old turn work", async () => {
  const f = fixture();
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  const controller = new AbortController();
  try {
    const pending = readers.read("summary", { key: "long" }, "en", { signal: controller.signal });
    await readers.read("summary", { key: "short" }, "en");
    controller.abort();
    await assert.rejects(pending, /read cancelled/);
    previous.resolve();
    await Promise.resolve();
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM session_turns_guard").get()?.n, 0);
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM session_turns").get()?.n, 0);
  } finally { readers.close(); previous.resolve(); f.close(); }
});
