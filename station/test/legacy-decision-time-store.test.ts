import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { DecisionSessionsUnavailable } from "../src/store/legacy-decision-session.ts";
import { decisionTimeIndexStep } from "../src/store/legacy-decision-time.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { LEGACY_LATEST_DECISIONS_SCOPED, Store } from "../src/store/store.ts";

function oldStore(path: string, oldIndex = true): void {
  const store = Store.open(path), db = store.db;
  try {
    for (const [key, ws] of [["mine", "mine"], ["other", "other"], ["home", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
    }
    const put = db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let i = 0; i < 130; i++) put.run(i % 2 ? "other" : "missing", i % 100, JSON.stringify({ i }));
    put.run("mine", 75, '{"mine":true}');
    put.run("home", 80, '{"home":true}');
    if (oldIndex) db.exec("CREATE INDEX decision_checks_at ON decision_checks(created_at)");
    db.exec("DROP INDEX decision_checks_lately");
  } finally { store.close(); }
}
const reference = `WITH latest AS MATERIALIZED (
  SELECT MAX(id) AS id,session FROM decision_checks WHERE created_at>=?1 GROUP BY +session
) SELECT d.id,d.session,d.created_at,d.result FROM latest l
LEFT JOIN sessions s ON s.key=l.session CROSS JOIN decision_checks d ON d.id=l.id
WHERE s.ws=?2 OR (?3 AND s.ws IS NULL) ORDER BY d.created_at,d.id`;
function expected(store: Store, since: number, ws?: string, home = false) {
  const sql = ws === undefined
    ? "SELECT id,session,created_at,result FROM decision_checks WHERE id IN (SELECT MAX(id) FROM decision_checks WHERE created_at>=? GROUP BY +session) ORDER BY created_at,id"
    : reference;
  const rows = ws === undefined ? store.db.prepare(sql).all(since) : store.db.prepare(sql).all(since, ws, home ? 1 : 0);
  return rows.map((r) => ({ id: r.id, session: r.session, at: r.created_at, detail: JSON.parse(r.result as string) }));
}
function check(store: Store): void {
  for (const since of [0, 50, 99, 101]) {
    assert.deepEqual(store.latestDecisionsSince(since), expected(store, since));
    for (const [ws, home] of [["mine", false], ["missing", false], ["mine", true]] as const)
      assert.deepEqual(store.latestDecisionsSince(since, { workspace: ws, home }), expected(store, since, ws, home));
  }
}

for (const oldIndex of [false, true]) test(`old connections and snapshots remain correct while the lookup is prepared (old time index ${oldIndex})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-time-store-")), path = join(dir, "station.db");
  oldStore(path, oldIndex);
  const old = new DatabaseSync(path, { timeout: 5000 });
  const write = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
  let store: Store | null = null;
  try {
    store = Store.open(path);
    assert.equal(store.db.prepare("SELECT complete FROM legacy_decision_time_meta").get()?.complete, 0);
    check(store);
    write.run("mine", 102, '{"new":1}');
    assert.deepEqual(decisionTimeIndexStep(store.db, 7), { done: false, visited: 7 });
    old.exec("UPDATE decision_checks SET created_at=103,session='mine' WHERE id=5; DELETE FROM decision_checks WHERE id=6");
    check(store);
    while (!decisionTimeIndexStep(store.db, 7).done) { /* finish */ }
    check(store);
    write.run("mine", 104, '{"new":2}');
    check(store);
  } finally { store?.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the decision-time worker waits for handover and continues saved batches after old writes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-time-worker-")), path = join(dir, "station.db");
  oldStore(path);
  const old = new DatabaseSync(path, { timeout: 5000 });
  let store: Store | null = null, builder: ReturnType<typeof buildLegacyEntryLookups> | null = null;
  try {
    store = Store.open(path);
    assert.equal(decisionTimeIndexStep(store.db, 7).done, false);
    const before = store.db.prepare("SELECT cursor,complete FROM legacy_decision_time_meta").get();
    const previous = Promise.withResolvers<void>();
    builder = buildLegacyEntryLookups(store, previous.promise);
    let settled = false; void builder.ready.then(() => { settled = true; });
    await Promise.resolve();
    assert.equal(settled, false);
    assert.deepEqual(store.db.prepare("SELECT cursor,complete FROM legacy_decision_time_meta").get(), before);
    old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)").run("mine", 105, '{"later":true}');
    check(store);
    previous.resolve();
    assert.equal(await builder.ready, true);
    assert.equal(store.db.prepare("SELECT complete FROM legacy_decision_time_meta").get()?.complete, 1);
    check(store);
  } finally { await builder?.close(); store?.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a stopped decision-time worker resumes its saved progress", async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-time-retry-")), path = join(dir, "station.db");
  oldStore(path);
  let store: Store | null = null, builder: ReturnType<typeof buildLegacyEntryLookups> | null = null;
  try {
    store = Store.open(path);
    decisionTimeIndexStep(store.db, 7);
    const before = store.db.prepare("SELECT cursor,complete FROM legacy_decision_time_meta").get();
    const previous = Promise.withResolvers<void>();
    builder = buildLegacyEntryLookups(store, previous.promise);
    await builder.close();
    assert.equal(await builder.ready, false);
    assert.deepEqual(store.db.prepare("SELECT cursor,complete FROM legacy_decision_time_meta").get(), before);
    previous.resolve();
    const marker = join(dir, "failed"), script = join(dir, "flaky-worker.mjs");
    const worker = new URL("../src/sessions/workspace-activity-worker.ts", import.meta.url).href;
    writeFileSync(script, `import { existsSync, writeFileSync } from 'node:fs';\n` +
      `if (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, 'failed'); process.exit(1); }\n` +
      `await import(${JSON.stringify(worker)});\n`);
    builder = buildLegacyEntryLookups(store, Promise.resolve(), pathToFileURL(script));
    assert.equal(await builder.ready, true);
    assert.equal(existsSync(marker), true);
    assert.equal(store.db.prepare("SELECT complete FROM legacy_decision_time_meta").get()?.complete, 1);
    check(store);
  } finally { await builder?.close(); store?.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("one read snapshot keeps its results as preparation finishes and an old writer adds a check", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-time-snapshot-")), path = join(dir, "station.db");
  oldStore(path);
  const old = new DatabaseSync(path, { timeout: 5000 }), reader = new DatabaseSync(path, { timeout: 5000 });
  let store: Store | null = null;
  try {
    store = Store.open(path);
    reader.exec("BEGIN");
    const query = reader.prepare(LEGACY_LATEST_DECISIONS_SCOPED), before = query.all(50, "mine", 0);
    old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)").run("mine", 105, '{"later":true}');
    while (!decisionTimeIndexStep(store.db, 7).done) { /* finish */ }
    assert.deepEqual(query.all(50, "mine", 0), before);
    reader.exec("COMMIT");
    assert.notDeepEqual(query.all(50, "mine", 0), before);
    check(store);
  } finally { reader.close(); store?.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a scoped read never decodes another workspace's 64-bit decision id", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-time-int64-")), path = join(dir, "station.db");
  oldStore(path);
  const old = new DatabaseSync(path, { timeout: 5000 });
  let store: Store | null = null;
  try {
    old.prepare("INSERT INTO decision_checks(id,session,created_at,result) VALUES(?,?,?,?)")
      .run(9007199254740993n, "other", 200, "{}");
    store = Store.open(path);
    const viewer = { workspace: "mine", home: false };
    const before = store.latestDecisionsSince(50, viewer);
    while (!decisionTimeIndexStep(store.db, 7).done) { /* finish */ }
    assert.deepEqual(store.latestDecisionsSince(50, viewer), before);
  } finally { store?.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const prepared of [false, true]) test(`a missing auxiliary time index falls back correctly (prepared ${prepared})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-time-drop-")), path = join(dir, "station.db");
  oldStore(path);
  let store: Store | null = Store.open(path);
  try {
    if (prepared) while (!decisionTimeIndexStep(store.db, 7).done) { /* finish */ }
    store.db.exec("DROP INDEX legacy_decision_time_at");
    check(store);
    store.close();
    store = Store.open(path);
    check(store);
  } finally { store?.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const prepared of [false, true]) test(`a small workspace avoids unrelated checks after the auxiliary index is removed (prepared ${prepared})`, () => {
  const visits: number[] = [];
  for (const otherChecks of [100, 1000]) {
    const dir = mkdtempSync(join(tmpdir(), "decision-time-drop-scope-")), path = join(dir, "station.db");
    oldStore(path, false);
    const old = new DatabaseSync(path, { timeout: 5000 });
    let store: Store | null = null;
    try {
      const put = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
      for (let i = 0; i < otherChecks; i++) put.run("other", 100, "{}");
      store = Store.open(path);
      if (prepared) while (!decisionTimeIndexStep(store.db, 64).done) { /* finish */ }
      store.db.exec("DROP INDEX legacy_decision_time_at");
      const expectedRows = expected(store, 50, "mine", false), db = store.db;
      let grouped = 0, instrumented = false;
      db.function("visit_missing_time_fallback", (id) => { grouped++; return id; });
      Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            const counted = sql.replace("MAX(id) AS id, session FROM", "MAX(visit_missing_time_fallback(id)) AS id, session FROM");
            instrumented ||= counted !== sql;
            return target.prepare(counted);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      }) });
      assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }), expectedRows);
      assert.ok(instrumented, "the test must count the fallback grouping");
      visits.push(grouped);
    } finally { store?.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
  }
  assert.ok(visits.every((count) => count <= 65), `unrelated checks grouped: ${visits}`);
});

for (const missing of ["sessions_by_connect", "decision_checks_session"]) {
  test(`reads stay correct when the auxiliary time index and ${missing} are removed`, async () => {
    const dir = mkdtempSync(join(tmpdir(), "decision-time-two-indexes-")), path = join(dir, "station.db");
    oldStore(path, false);
    const store = Store.open(path);
    const builder = missing === "decision_checks_session" ? buildLegacyEntryLookups(store, Promise.resolve()) : null;
    if (builder) store.waitForDecisionSessions = () => builder.waitForDecisionSessions();
    try {
      store.db.exec(`DROP INDEX legacy_decision_time_at; DROP INDEX ${missing}`);
      if (builder) {
        assert.throws(() => store.latestDecisionsSince(0, { workspace: "mine", home: false }), DecisionSessionsUnavailable);
        await store.prepareDecisionSessions();
      }
      check(store);
    } finally { await builder?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
  });
}
