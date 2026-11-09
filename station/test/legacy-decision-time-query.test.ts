import assert from "node:assert/strict";
import { test } from "node:test";
import { decisionTimeIndexStep, installDecisionTimeIndex } from "../src/store/legacy-decision-time.ts";
import { LATEST_DECISIONS, LATEST_DECISIONS_SCOPED_NO_TIME, LEGACY_LATEST_DECISIONS, LEGACY_LATEST_DECISIONS_SCOPED,
  LEGACY_LATEST_DECISIONS_SCOPED_FALLBACK, Store } from "../src/store/store.ts";

const reference = `WITH latest AS MATERIALIZED (
  SELECT MAX(id) AS id,session FROM decision_checks WHERE created_at>=?1 GROUP BY +session
) SELECT d.id,d.session,d.created_at,d.result FROM latest l
LEFT JOIN sessions s ON s.key=l.session CROSS JOIN decision_checks d ON d.id=l.id
WHERE s.ws=?2 OR (?3 AND s.ws IS NULL) ORDER BY d.created_at,d.id`;

test("the old, preparing and prepared time lookups return the same decisions", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, ws] of [["mine", "mine"], ["other", "other"], ["home", null]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
    }
    db.exec("CREATE INDEX decision_checks_at ON decision_checks(created_at); BEGIN");
    const put = db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let i = 0; i < 200; i++) put.run(i % 2 ? "other" : "missing", (i * 53) % 100, JSON.stringify({ i }));
    put.run("mine", 91, '{"latest":true}');
    put.run("home", 83, '{"home":true}');
    for (let i = 0; i < 70; i++) put.run("mine", 5, "{}"); // A newer id can have an older time.
    db.exec("COMMIT; DROP INDEX decision_checks_lately");
    installDecisionTimeIndex(db);
    const check = () => {
      for (const since of [0, 6, 50, 90, 101]) {
        assert.deepEqual(db.prepare(LEGACY_LATEST_DECISIONS).all(since), db.prepare(LATEST_DECISIONS).all(since));
        for (const [ws, home] of [["mine", 0], ["missing", 0], ["mine", 1]] as const) {
          const args = [since, ws, home] as const, expected = db.prepare(reference).all(...args);
          assert.deepEqual(db.prepare(LEGACY_LATEST_DECISIONS_SCOPED).all(...args), expected);
          assert.deepEqual(db.prepare(LEGACY_LATEST_DECISIONS_SCOPED_FALLBACK).all(...args), expected);
        }
      }
    };
    check();
    assert.equal(decisionTimeIndexStep(db, 8).done, false);
    put.run("other", 105, '{"during":true}');
    check();
    while (!decisionTimeIndexStep(db, 31).done) { /* finish preparation */ }
    check();
    db.exec("UPDATE decision_checks SET created_at=110 WHERE id=2; DELETE FROM decision_checks WHERE id=3");
    put.run("mine", 111, '{"after":true}');
    check();
  } finally { store.close(); }
});

for (const scenario of [
  { name: "a short recent window", own: 1, connects: 1, otherChecks: 4, oldAfter: 0, fallback: true },
  { name: "64 newer old checks", own: 1, connects: 1, otherChecks: 100, oldAfter: 64, fallback: false },
  { name: "65 newer old checks", own: 1, connects: 1, otherChecks: 100, oldAfter: 65, fallback: true },
  { name: "64 workspace sessions", own: 64, connects: 1, otherChecks: 100, oldAfter: 0, fallback: false },
  { name: "65 workspace sessions", own: 65, connects: 1, otherChecks: 100, oldAfter: 0, fallback: true },
  { name: "64 connects", own: 1, connects: 64, otherChecks: 100, oldAfter: 0, fallback: false },
  { name: "65 connects", own: 1, connects: 65, otherChecks: 100, oldAfter: 0, fallback: true },
]) test(`legacy decision lookups stay exact with ${scenario.name}`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const add = (key: string, connect: string, ws: string) => store.insertSession({
      key, connect, runtime: "claude", profile: "cc", workspace: "/work",
      token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws,
    });
    db.exec("BEGIN");
    for (let i = 0; i < scenario.own; i++) add(`mine-${i}`, "connect-0", "mine");
    for (let i = 0; i < scenario.connects; i++) add(`other-${i}`, `connect-${i}`, "elsewhere");
    const put = db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    for (let i = 0; i < scenario.otherChecks; i++) put.run("other-0", 100, "{}");
    for (let i = 0; i < scenario.own; i++) put.run(`mine-${i}`, 100 + i, JSON.stringify({ selected: i }));
    for (let i = 0; i < scenario.oldAfter; i++) put.run("mine-0", 10, "{}");
    // Ensure every case prepares the legacy lookup, including the short-window case.
    for (let i = 0; i < 70; i++) put.run("other-0", 10, "{}");
    db.exec("COMMIT; CREATE INDEX decision_checks_at ON decision_checks(created_at); DROP INDEX decision_checks_lately");
    installDecisionTimeIndex(db);
    let grouped = 0;
    db.function("visit_legacy_policy_fallback", (id) => { grouped++; return id; });
    const counted = LEGACY_LATEST_DECISIONS_SCOPED.replaceAll("MAX(d.id)", "MAX(visit_legacy_policy_fallback(d.id))");
    const countedWithoutTime = LATEST_DECISIONS_SCOPED_NO_TIME.replace("MAX(id)", "MAX(visit_legacy_policy_fallback(id))");
    const check = () => {
      const expected = db.prepare(reference).all(50, "mine", 0);
      grouped = 0;
      assert.deepEqual(db.prepare(counted).all(50, "mine", 0), expected);
      assert.equal(grouped > 0, scenario.fallback, `fallback grouped ${grouped} checks`);
      grouped = 0;
      assert.deepEqual(db.prepare(countedWithoutTime).all(50, "mine", 0), expected);
      const noTimeFallback = scenario.name !== "a short recent window" && scenario.fallback;
      assert.equal(grouped > 0, noTimeFallback, `fallback without a time index grouped ${grouped} checks`);
    };
    check();
    assert.equal(decisionTimeIndexStep(db, 8).done, false);
    check();
    while (!decisionTimeIndexStep(db, 31).done) { /* prepare */ }
    check();
  } finally { store.close(); }
});

for (const removedAfterInstall of [false, true]) {
  test(`a small workspace skips old unrelated checks without a source time index (removed after install ${removedAfterInstall})`, () => {
    const visits: number[] = [];
    for (const otherChecks of [100, 1000]) {
      const store = Store.open(":memory:"), db = store.db;
      try {
        for (const [key, ws] of [["mine", "mine"], ["other", "elsewhere"]] as const) {
          store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
            token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
        }
        db.exec("BEGIN");
        const put = db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
        for (let i = 0; i < otherChecks; i++) put.run("other", 1, "{}");
        for (let i = 0; i < 100; i++) put.run("other", 100, "{}");
        put.run("mine", 100, '{"selected":true}');
        db.exec("COMMIT; DROP INDEX decision_checks_lately");
        if (removedAfterInstall) db.exec("CREATE INDEX decision_checks_at ON decision_checks(created_at)");
        installDecisionTimeIndex(db);
        if (removedAfterInstall) db.exec("DROP INDEX decision_checks_at");
        db.exec("ANALYZE");
        const expected = db.prepare(reference).all(50, "mine", 0);
        let visited = 0;
        db.function("visit_legacy_time_source", (at) => { visited++; return at; });
        const counted = LEGACY_LATEST_DECISIONS_SCOPED.replace("d.created_at>=?1 LIMIT 65",
          "visit_legacy_time_source(d.created_at)>=?1 LIMIT 65");
        assert.notEqual(counted, LEGACY_LATEST_DECISIONS_SCOPED, "the test must count the source time probe");
        const check = () => {
          visited = 0;
          assert.deepEqual(db.prepare(counted).all(50, "mine", 0), expected);
          visits.push(visited);
        };
        check();
        decisionTimeIndexStep(db, 8);
        check();
        while (!decisionTimeIndexStep(db, 31).done) { /* prepare */ }
        check();
      } finally { store.close(); }
    }
    assert.ok(visits.every((count) => count <= 65), `source checks visited: ${visits}`);
  });
}
