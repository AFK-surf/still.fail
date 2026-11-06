import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { overview } from "../src/api/overview.ts";
import { DECISION_SESSION_INDEX, DecisionSessionsUnavailable, decisionSessionIndexStep } from "../src/store/legacy-decision-session.ts";
import { decisionTimeIndexStep, installDecisionTimeIndex } from "../src/store/legacy-decision-time.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { LATEST_DECISIONS, RECENT_LAST_DECISION, Store } from "../src/store/store.ts";

test("opening an old store bounds the work to install its decision-session lookup", () => {
  const indexed: number[] = [], probed: number[] = [];
  for (const size of [80, 800]) {
    const dir = mkdtempSync(join(tmpdir(), "decision-session-open-")), path = join(dir, "station.db");
    const first = Store.open(path);
    try {
      const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('other',?,'{}')");
      first.db.exec("BEGIN");
      for (let n = 0; n < size; n++) put.run(n);
      first.db.exec("COMMIT; DROP INDEX decision_checks_session");
    } finally { first.close(); }
    const execDescriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "exec")!;
    const prepareDescriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "prepare")!;
    const exec = execDescriptor.value as DatabaseSync["exec"], prepare = prepareDescriptor.value as DatabaseSync["prepare"];
    let visits = 0, probes = 0, store: Store | null = null;
    try {
      Object.defineProperty(DatabaseSync.prototype, "exec", { ...execDescriptor, value(this: DatabaseSync, sql: string) {
        if (sql.includes(DECISION_SESSION_INDEX)) {
          this.function("visit_session_index", { deterministic: true }, (id) => { visits++; return id === null ? 0 : 1; });
          sql = sql.replace(DECISION_SESSION_INDEX, `${DECISION_SESSION_INDEX} WHERE visit_session_index(id)`);
        }
        return exec.call(this, sql);
      } });
      Object.defineProperty(DatabaseSync.prototype, "prepare", { ...prepareDescriptor, value(this: DatabaseSync, sql: string) {
        if (sql === "SELECT 1 FROM decision_checks LIMIT 1 OFFSET 63") {
          this.function("visit_session_probe", (id) => { probes++; return id === null ? 0 : 1; });
          sql = "SELECT 1 FROM decision_checks WHERE visit_session_probe(id) LIMIT 1 OFFSET 63";
        }
        return prepare.call(this, sql);
      } });
      store = Store.open(path);
      indexed.push(visits); probed.push(probes);
      assert.equal(store.decisionSessionsReady(), false);
    } finally {
      store?.close();
      Object.defineProperty(DatabaseSync.prototype, "exec", execDescriptor);
      Object.defineProperty(DatabaseSync.prototype, "prepare", prepareDescriptor);
      rmSync(dir, { recursive: true, force: true });
    }
  }
  assert.deepEqual(indexed, [0, 0], "opening did not build a native index over the history");
  assert.deepEqual(probed, [64, 64], "the size probe has the same bound for both histories");
});

for (const mode of ["shared", "separate", "existing time"] as const) test(
  `old session lookups keep exact answers while preparing (${mode})`, () => {
    const dir = mkdtempSync(join(tmpdir(), "decision-session-store-")), path = join(dir, "station.db");
    const first = Store.open(path);
    try {
      for (const key of ["mine", "other"]) first.insertSession({
        key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws: key,
      });
      const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
      for (let n = 0; n < 150; n++) put.run(n % 2 ? "other" : "missing", n % 100, JSON.stringify({ n }));
      for (let n = 0; n < 20; n++) put.run("other", 100, '{}');
      put.run("mine", 80, '{"mine":1}');
      put.run("mine", 5, '{"outOfOrder":true}');
      first.db.exec("DROP INDEX decision_checks_session");
      if (mode !== "separate") first.db.exec("DROP INDEX decision_checks_lately");
      if (mode === "existing time") installDecisionTimeIndex(first.db);
    } finally { first.close(); }
    const old = new DatabaseSync(path, { timeout: 5000 });
    const write = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    let store: Store | null = null;
    try {
      store = Store.open(path);
      const db = store.db;
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='decision_checks_session'").get(), undefined);
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='legacy_decision_time_by_session'").get() !== undefined, mode === "shared");
      assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='legacy_decision_session_meta'").get() !== undefined, mode !== "shared");
      const check = () => {
        for (const session of ["mine", "other", "missing", "absent"]) {
          const expected = db.prepare("SELECT result FROM decision_checks WHERE session=? ORDER BY id DESC LIMIT 1").get(session);
          assert.deepEqual(store!.lastDecision(session), expected ? JSON.parse(expected.result as string) : null);
        }
        for (const since of [0, 50, 99, 101]) {
          const expected = db.prepare(`WITH latest AS MATERIALIZED (
            SELECT MAX(id) id,session FROM decision_checks WHERE created_at>=?1 GROUP BY +session
          ) SELECT d.id,d.session,d.created_at,d.result FROM latest l
          LEFT JOIN sessions s ON s.key=l.session CROSS JOIN decision_checks d ON d.id=l.id
          WHERE s.ws=?2 ORDER BY d.created_at,d.id`).all(since, "mine")
            .map((row) => ({ id: row.id, session: row.session, at: row.created_at, detail: JSON.parse(row.result as string) }));
          assert.deepEqual(store!.latestDecisionsSince(since, { workspace: "mine", home: false }), expected);
        }
      };
      const pending = () => {
        const mine = db.prepare("SELECT result FROM decision_checks WHERE session='mine' ORDER BY id DESC LIMIT 1").get();
        assert.deepEqual(store!.lastDecision("mine"), mine ? JSON.parse(mine.result as string) : null);
        assert.throws(() => store!.lastDecision("absent"), DecisionSessionsUnavailable);
        assert.throws(() => store!.latestDecisionsSince(50, { workspace: "mine", home: false }), DecisionSessionsUnavailable);
        assert.doesNotThrow(() => store!.latestDecisionsSince(50));
        assert.doesNotThrow(() => store!.latestDecisionsSince(50, { workspace: "mine", home: true }));
      };
      pending();
      write.run("mine", 101, '{"oldWriter":1}');
      old.exec("UPDATE decision_checks SET session='mine' WHERE id=5; DELETE FROM decision_checks WHERE id=6");
      if (mode === "shared") assert.equal(decisionTimeIndexStep(db, 7).done, false);
      else assert.equal(decisionSessionIndexStep(db, 7).done, false);
      pending();
      if (mode === "shared") while (!decisionTimeIndexStep(db, 7).done) { /* prepare */ }
      else while (!decisionSessionIndexStep(db, 7).done) { /* prepare */ }
      if (mode === "existing time") while (!decisionTimeIndexStep(db, 7).done) { /* prepare */ }
      check();
      write.run("mine", 102, '{"oldWriter":2}');
      check();
    } finally { store?.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
  });

for (const time of ["native", "old", "missing"] as const) for (const recent of [0, 1, 64, 65]) test(
  `a ${time} time index can answer ${recent} recent checks while sessions prepare`, () => {
    const dir = mkdtempSync(join(tmpdir(), "decision-session-small-")), path = join(dir, "station.db");
    const first = Store.open(path);
    try {
      first.insertSession({ key: "mine", ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
        workspace: "/work", token: "mine", createdAt: 1, lastActiveAt: 1 });
      const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
      for (let n = 0; n < 80; n++) put.run("other", 1, '{}');
      for (let n = 0; n < recent; n++) put.run(n === 0 ? "mine" : "other", 100, JSON.stringify({ n }));
      first.db.exec("DROP INDEX decision_checks_session");
      if (time !== "native") first.db.exec("DROP INDEX decision_checks_lately");
      if (time === "old") first.db.exec("CREATE INDEX decision_checks_at ON decision_checks(created_at)");
    } finally { first.close(); }
    const store = Store.open(path);
    try {
      assert.equal(store.decisionSessionsReady(), false);
      const viewer = { workspace: "mine", home: false };
      if (time === "missing" || recent > 64) assert.throws(() => store.latestDecisionsSince(50, viewer), DecisionSessionsUnavailable);
      else {
        const expected = (store.db.prepare(LATEST_DECISIONS).all(50) as any[]).filter((row) => row.session === "mine")
          .map((row) => ({ id: row.id, session: row.session, at: row.created_at, detail: JSON.parse(row.result) }));
        assert.deepEqual(store.latestDecisionsSince(50, viewer), expected);
      }
    } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
  });

for (const time of ["native", "old", "prepared"] as const) test(`a small recent window seeks the ${time} time index`, () => {
  const visits: number[] = [];
  for (const oldChecks of [100, 1000, 10000]) {
    const dir = mkdtempSync(join(tmpdir(), "decision-session-small-scale-")), path = join(dir, "station.db");
    const first = Store.open(path);
    try {
      first.insertSession({ key: "mine", ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
        workspace: "/work", token: "mine", createdAt: 1, lastActiveAt: 1 });
      const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
      first.db.exec("BEGIN");
      for (let n = 0; n < oldChecks; n++) put.run("other", 1, '{}');
      put.run("mine", 100, '{"mine":true}');
      first.db.exec("COMMIT; DROP INDEX decision_checks_session");
      if (time !== "native") first.db.exec("DROP INDEX decision_checks_lately");
      if (time === "old") first.db.exec("CREATE INDEX decision_checks_at ON decision_checks(created_at)");
      if (time === "prepared") {
        installDecisionTimeIndex(first.db);
        while (!decisionTimeIndexStep(first.db).done) { /* time lookup finished before session installation */ }
      }
    } finally { first.close(); }
    const store = Store.open(path), db = store.db;
    try {
      db.exec("ANALYZE");
      let visited = 0, observed = "";
      db.function("visit_small_decision", (id) => { visited++; return id; });
      Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            if (sql.includes("recent AS MATERIALIZED (SELECT id,session FROM")) {
              observed = sql;
              sql = sql.replace("recent AS MATERIALIZED (SELECT id,session FROM",
                "recent AS MATERIALIZED (SELECT visit_small_decision(id) AS id,session FROM");
            }
            return target.prepare(sql);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      }) });
      assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }),
        [{ id: oldChecks + 1, session: "mine", at: 100, detail: { mine: true } }]);
      assert.ok(observed, "the limited recent query was observed");
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${observed}`).all(50, "mine") as { detail: string }[]).map((row) => row.detail);
      const expected = time === "native" ? "decision_checks_lately" : time === "old" ? "decision_checks_at" : "legacy_decision_time_at";
      assert.ok(plan.some((step) => step.includes(`USING ${time === "old" ? "INDEX" : "COVERING INDEX"} ${expected}`)
        && step.includes("created_at>?")), plan.join(" | "));
      assert.ok(plan.some((step) => /SEARCH s USING (?:COVERING )?INDEX .+\(key=\?/.test(step)), plan.join(" | "));
      visits.push(visited);
    } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
  }
  assert.deepEqual(visits, [1, 1, 1]);
});

for (const time of ["native", "old"] as const) test(`a small recent window keeps exact results and one snapshot with the ${time} time index`, () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-small-snapshot-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    for (const key of ["a", "b"]) first.insertSession({ key, ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1 });
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 80; n++) put.run("other", 1, '{}');
    put.run("a", 100, '{"a":1}');
    put.run("b", 90, '{"b":1}');
    put.run("a", 50, '{"a":2}');
    put.run("deleted", 99, '{}');
    first.db.exec("DROP INDEX decision_checks_session");
    if (time === "old") first.db.exec("DROP INDEX decision_checks_lately; CREATE INDEX decision_checks_at ON decision_checks(created_at)");
  } finally { first.close(); }
  const store = Store.open(path), old = new DatabaseSync(path, { timeout: 5000 });
  try {
    const viewer = { workspace: "mine", home: false };
    const expected = (since: number) => (store.db.prepare(LATEST_DECISIONS).all(since) as any[])
      .filter((row) => row.session === "a" || row.session === "b")
      .map((row) => ({ id: row.id, session: row.session, at: row.created_at, detail: JSON.parse(row.result) }));
    for (const since of [2, 51, 90, 101]) assert.deepEqual(store.latestDecisionsSince(since, viewer), expected(since));
    store.db.exec("BEGIN");
    const before = store.latestDecisionsSince(51, viewer);
    old.exec(`UPDATE decision_checks SET session='a',created_at=80 WHERE id=82;
      INSERT INTO decision_checks(session,created_at,result) VALUES('b',105,'{"b":2}')`);
    assert.deepEqual(store.latestDecisionsSince(51, viewer), before);
    store.db.exec("COMMIT");
    for (const since of [2, 51, 90, 101]) assert.deepEqual(store.latestDecisionsSince(since, viewer), expected(since));
    assert.notDeepEqual(store.latestDecisionsSince(51, viewer), before);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a small recent window does not decode another session's 64-bit id", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-small-int64-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    first.insertSession({ key: "mine", ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: "mine", createdAt: 1, lastActiveAt: 1 });
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 80; n++) put.run("other", 1, '{}');
    put.run("mine", 100, '{"mine":true}');
    first.db.exec("INSERT INTO decision_checks(id,session,created_at,result) VALUES(9007199254740993,'other',100,'{}')");
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path);
  try {
    assert.deepEqual(store.lastDecision("mine"), { mine: true });
    assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }),
      [{ id: 81, session: "mine", at: 100, detail: { mine: true } }]);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const after of [0, 63, 64] as const) test(`a latest decision ${after} rows behind the end is read without waiting when provable`, () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-last-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 80; n++) put.run("other", 1, '{}');
    put.run("mine", 100, '{"mine":true}');
    for (let n = 0; n < after; n++) put.run("other", 1, '{}');
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path), old = new DatabaseSync(path, { timeout: 5000 });
  try {
    assert.equal(store.decisionSessionsReady(), false);
    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${RECENT_LAST_DECISION}`).all("mine") as { id: number; parent: number; detail: string }[];
    const recent = plan.find((part) => part.detail === "MATERIALIZE recent");
    assert.ok(recent && plan.some((part) => part.parent === recent.id && part.detail === "SCAN decision_checks"));
    assert.ok(!plan.some((part) => part.parent === recent.id && part.detail.includes("TEMP B-TREE")), JSON.stringify(plan));
    if (after < 64) assert.deepEqual(store.lastDecision("mine"), { mine: true });
    else assert.throws(() => store.lastDecision("mine"), DecisionSessionsUnavailable);
    assert.throws(() => store.lastDecision("absent"), DecisionSessionsUnavailable);
    old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)").run("mine", 1, '{"newer":true}');
    assert.deepEqual(store.lastDecision("mine"), { newer: true });
    old.prepare("DELETE FROM decision_checks WHERE id=(SELECT MAX(id) FROM decision_checks)").run();
    if (after < 64) assert.deepEqual(store.lastDecision("mine"), { mine: true });
    else assert.throws(() => store.lastDecision("mine"), DecisionSessionsUnavailable);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a latest decision can be absent when the bounded tail contains the whole table", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-last-empty-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('other',1,'{}')");
    for (let n = 0; n < 80; n++) put.run();
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path);
  try {
    store.db.exec("DELETE FROM decision_checks WHERE id>10");
    assert.equal(store.decisionSessionsReady(), false);
    assert.equal(store.lastDecision("absent"), null);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const mode of ["shared", "separate"] as const) for (const scenario of [
  { name: "a short recent window", own: 1, connects: 1, checks: 4, oldAfter: 0 },
  { name: "out-of-order checks at the probe", own: 1, connects: 1, checks: 100, oldAfter: 64 },
  { name: "out-of-order checks beyond the probe", own: 1, connects: 1, checks: 100, oldAfter: 65 },
  { name: "64 workspace sessions", own: 64, connects: 1, checks: 100, oldAfter: 0 },
  { name: "65 workspace sessions", own: 65, connects: 1, checks: 100, oldAfter: 0 },
  { name: "64 connects", own: 1, connects: 64, checks: 100, oldAfter: 0 },
  { name: "65 connects", own: 1, connects: 65, checks: 100, oldAfter: 0 },
]) test(`the prepared ${mode} session lookup remains exact with ${scenario.name}`, () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-boundary-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    for (let n = 0; n < scenario.own; n++) first.insertSession({
      key: `mine-${n}`, ws: "mine", connect: "connect-0", runtime: "claude", profile: "cc",
      workspace: "/work", token: `mine-${n}`, createdAt: 1, lastActiveAt: 1,
    });
    for (let n = 0; n < scenario.connects; n++) first.insertSession({
      key: `other-${n}`, ws: "other", connect: `connect-${n}`, runtime: "claude", profile: "cc",
      workspace: "/work", token: `other-${n}`, createdAt: 1, lastActiveAt: 1,
    });
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 64; n++) put.run("other-0", 0, '{}');
    for (let n = 0; n < scenario.checks; n++) put.run("other-0", 100, '{}');
    for (let n = 0; n < scenario.own; n++) put.run(`mine-${n}`, 100 + n, JSON.stringify({ n }));
    for (let n = 0; n < scenario.oldAfter; n++) put.run("mine-0", 10, '{}');
    first.db.exec("DROP INDEX decision_checks_session");
    if (mode === "shared") first.db.exec("DROP INDEX decision_checks_lately");
  } finally { first.close(); }
  const store = Store.open(path);
  try {
    const step = mode === "shared" ? decisionTimeIndexStep : decisionSessionIndexStep;
    while (!step(store.db).done) { /* prepare */ }
    const expected = (store.db.prepare(LATEST_DECISIONS).all(50) as any[])
      .filter((row) => row.session.startsWith("mine-"))
      .map((row) => ({ id: row.id, session: row.session, at: row.created_at, detail: JSON.parse(row.result) }));
    assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }), expected);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const mode of ["shared", "separate"] as const) test(`a ${mode} session lookup keeps a reader snapshot during an old write`, () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-snapshot-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    first.insertSession({ key: "mine", ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: "mine", createdAt: 1, lastActiveAt: 1 });
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 130; n++) put.run("other", n, '{}');
    put.run("mine", 100, '{"before":true}');
    first.db.exec("DROP INDEX decision_checks_session");
    if (mode === "shared") first.db.exec("DROP INDEX decision_checks_lately");
  } finally { first.close(); }
  const store = Store.open(path), old = new DatabaseSync(path, { timeout: 5000 });
  try {
    const step = mode === "shared" ? decisionTimeIndexStep : decisionSessionIndexStep;
    while (!step(store.db).done) { /* prepare */ }
    const viewer = { workspace: "mine", home: false };
    store.db.exec("BEGIN");
    const before = store.latestDecisionsSince(50, viewer);
    assert.deepEqual(store.lastDecision("mine"), { before: true });
    old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)").run("mine", 101, '{"after":true}');
    assert.deepEqual(store.latestDecisionsSince(50, viewer), before);
    assert.deepEqual(store.lastDecision("mine"), { before: true });
    store.db.exec("COMMIT");
    assert.deepEqual(store.lastDecision("mine"), { after: true });
    assert.deepEqual(store.latestDecisionsSince(50, viewer).map((row) => row.detail), [{ after: true }]);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const mode of ["shared", "separate"] as const) test(`the ${mode} decision-session worker waits for handover`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-worker-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 130; n++) put.run(n % 2 ? "other" : "mine", n, JSON.stringify({ n }));
    first.db.exec("DROP INDEX decision_checks_session");
    if (mode === "shared") first.db.exec("DROP INDEX decision_checks_lately");
  } finally { first.close(); }
  const old = new DatabaseSync(path, { timeout: 5000 });
  const write = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
  let store: Store | null = null, builder: ReturnType<typeof buildLegacyEntryLookups> | null = null;
  try {
    store = Store.open(path);
    const meta = mode === "shared" ? "legacy_decision_time_meta" : "legacy_decision_session_meta";
    const previous = Promise.withResolvers<void>();
    builder = buildLegacyEntryLookups(store, previous.promise);
    store.waitForDecisionSessions = () => builder!.decisionSessionsReady;
    const waiting = store.prepareDecisionSessions();
    let settled = false;
    void builder.ready.then(() => { settled = true; });
    await Promise.resolve();
    assert.equal(settled, false);
    assert.equal(store.db.prepare(`SELECT complete FROM ${meta}`).get()?.complete, 0);
    write.run("mine", 131, '{"oldWriter":true}');
    assert.deepEqual(store.lastDecision("mine"), { oldWriter: true });
    previous.resolve();
    await waiting;
    assert.equal(await builder.ready, true);
    assert.equal(store.db.prepare(`SELECT complete FROM ${meta}`).get()?.complete, 1);
    assert.deepEqual(store.lastDecision("mine"), { oldWriter: true });
    write.run("mine", 132, '{"after":true}');
    assert.deepEqual(store.lastDecision("mine"), { after: true });
  } finally {
    await builder?.close();
    store?.close();
    old.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("another opener finishing during handover wakes the waiting session reads", { timeout: 3000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-handover-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 130; n++) put.run("mine", n, JSON.stringify({ n }));
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const builder = buildLegacyEntryLookups(store, previous.promise);
  store.waitForDecisionSessions = () => builder.decisionSessionsReady;
  try {
    const waiting = store.prepareDecisionSessions();
    while (!decisionSessionIndexStep(store.db, 64).done) { /* another opener finished the shared work */ }
    previous.resolve();
    await waiting;
    assert.deepEqual(store.lastDecision("mine"), { n: 129 });
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a stopped session lookup settles its wait and resumes saved work", { timeout: 5000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-retry-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 130; n++) put.run("mine", n, JSON.stringify({ n }));
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  let builder = buildLegacyEntryLookups(store, previous.promise);
  try {
    assert.equal(decisionSessionIndexStep(store.db, 7).done, false);
    const cursor = store.db.prepare("SELECT cursor FROM legacy_decision_session_meta").get();
    store.waitForDecisionSessions = () => builder.decisionSessionsReady;
    const waiting = store.prepareDecisionSessions();
    await builder.close();
    await assert.rejects(waiting, DecisionSessionsUnavailable);
    assert.deepEqual(store.db.prepare("SELECT cursor FROM legacy_decision_session_meta").get(), cursor);
    previous.resolve();
    builder = buildLegacyEntryLookups(store, Promise.resolve());
    store.waitForDecisionSessions = () => builder.decisionSessionsReady;
    await store.prepareDecisionSessions();
    assert.deepEqual(store.lastDecision("mine"), { n: 129 });
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an already installed native session index does not finish an unused old lookup", { timeout: 5000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-native-")), path = join(dir, "station.db");
  let store: Store | null = Store.open(path);
  try {
    const put = store.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('mine',?,'{}')");
    for (let n = 0; n < 130; n++) put.run(n);
    store.db.exec("DROP INDEX decision_checks_session");
    store.close(); store = null;
    store = Store.open(path);
    assert.equal(decisionSessionIndexStep(store.db, 7).done, false);
    const cursor = store.db.prepare("SELECT cursor,complete FROM legacy_decision_session_meta").get();
    store.close(); store = null;
    const old = new DatabaseSync(path);
    try { old.exec("CREATE INDEX decision_checks_session ON decision_checks(session,id)"); } finally { old.close(); }
    store = Store.open(path);
    const builder = buildLegacyEntryLookups(store, Promise.resolve());
    try {
      assert.equal(await builder.ready, true);
      assert.deepEqual(store.db.prepare("SELECT cursor,complete FROM legacy_decision_session_meta").get(), cursor);
      assert.deepEqual(store.lastDecision("mine"), {});
    } finally { await builder.close(); }
  } finally { store?.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const window of ["small", "large"] as const) test(`a ${window} recent window lets the overview wait only when needed`, { timeout: 3000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-overview-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    first.insertSession({ key: "mine", ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: "mine", createdAt: 1, lastActiveAt: 1 });
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let n = 0; n < 130; n++) put.run("other", window === "small" ? 1 : Date.now(), '{}');
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const old = new DatabaseSync(path, { timeout: 5000 });
  const store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const requested = Promise.withResolvers<void>();
  const builder = buildLegacyEntryLookups(store, previous.promise);
  let waits = 0;
  store.waitForDecisionSessions = () => { waits++; requested.resolve(); return builder.decisionSessionsReady; };
  const viewer = { sub: "s", email: "p@example.test", name: "P", role: "admin" as const,
    workspace: "mine", device: "d", home: false };
  const accounts: any = { profilesView: () => [], loginsView: () => [], apiProviders: () => [], machineLogins: () => [],
    decisionModels: () => [], automaticDecisionsView: (who: typeof viewer) => who.role === "admin" ? { recent: [] }
      : { canEdit: false, settings: {}, models: [], recent: [] } };
  const hub: any = { processes: () => [], config: () => ({ dataDir: dir }) };
  const deps = { store, hub, accounts, cloud: { state: null } as any, config: () => ({ connects: [] }) };
  try {
    const member: any = await overview(deps, { ...viewer, role: "member" }, "en");
    assert.deepEqual(member.automaticDecisions, { canEdit: false, settings: {}, models: [], recent: [] });
    assert.equal(waits, 0);
    const owner = window === "large" ? overview(deps, viewer, "en") : null;
    if (owner) {
      await requested.promise;
      let settled = false;
      void owner.then(() => { settled = true; });
      await new Promise((resolve) => setImmediate(resolve));
      assert.equal(settled, false);
    }
    old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)")
      .run("mine", Date.now(), '{"result":{"selected":"landed"}}');
    if (owner) previous.resolve();
    const result: any = await (owner ?? overview(deps, viewer, "en"));
    if (!owner) assert.equal(waits, 0, "a small recent range did not wait for old checks");
    assert.equal(result.automaticDecisions.policy.checked, 1);
    assert.equal(result.automaticDecisions.policy.options.find((o: any) => o.id === "landed").count, 1);
  } finally {
    previous.resolve();
    await builder.close();
    store.close(); old.close(); rmSync(dir, { recursive: true, force: true });
  }
});
