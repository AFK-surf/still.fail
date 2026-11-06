import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { LATEST_DECISIONS, LATEST_DECISIONS_SCOPED, Store } from "../src/store/store.ts";

test("a small workspace does not group every other workspace's recent decisions", () => {
  const visits: { grouped: number; recent: number; own: number }[] = [];
  for (const otherChecks of [100, 1000]) {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      for (const [key, ws] of [["mine", "mine"], ["other", "elsewhere"]]) {
        store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
          token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
      }
      const insert = db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
      db.exec("BEGIN");
      for (let i = 0; i < otherChecks; i++) insert.run("other", 100, "{}");
      insert.run("mine", 100, '{"result":{"selected":"earlier"}}');
      insert.run("mine", 90, '{"result":{"selected":"latest qualifying"}}');
      insert.run("mine", 10, '{"result":{"selected":"too old"}}');
      db.exec("COMMIT");
      const expected = (db.prepare(LATEST_DECISIONS).all(50) as any[])
        .filter((row) => row.session === "mine")
        .map((row) => ({ id: row.id, session: row.session, at: row.created_at, detail: JSON.parse(row.result) }));
      let grouped = 0, recent = 0, own = 0, instrumented = false, probed = false;
      db.function("visit_policy_check", (value) => { grouped++; return value; });
      db.function("visit_policy_recent", (value) => { recent++; return value; });
      db.function("visit_policy_own", (value) => { own++; return value; });
      Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (sql: string) => {
            const group = "MAX(id) AS id, session FROM decision_checks WHERE created_at >= ?1";
            if (sql.includes(group)) {
              instrumented = true;
              sql = sql.replace(group, group.replace("MAX(id)", "MAX(visit_policy_check(id))"));
            }
            const probe = "SELECT id FROM decision_checks INDEXED BY decision_checks_lately WHERE ?3 = 0 AND created_at >= ?1 LIMIT 65";
            if (sql.includes(probe)) {
              probed = true;
              sql = sql.replace(probe, probe.replace("SELECT id", "SELECT visit_policy_recent(id) AS id"));
            }
            sql = sql.replace("SELECT id, created_at FROM decision_checks INDEXED BY decision_checks_session",
              "SELECT id, visit_policy_own(created_at) AS created_at FROM decision_checks INDEXED BY decision_checks_session");
            return target.prepare(sql);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      }) });
      assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }), expected);
      assert.ok(instrumented, "the test must count the grouping query");
      assert.ok(probed, "the test must count the recent-check probe");
      assert.ok(own > 0, "the test must count the selected session's checks");
      visits.push({ grouped, recent, own });
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${LATEST_DECISIONS_SCOPED}`).all(50, "mine", 0) as { detail: string }[]).map((r) => r.detail);
      assert.ok(plan.some((p) => p.includes("sessions_by_connect") && p.includes("connect=?") && p.includes("ws=?")), plan.join(" | "));
      assert.ok(plan.some((p) => p.includes("decision_checks_session") && p.includes("session=?")), plan.join(" | "));
    } finally { store.close(); }
  }
  assert.ok(visits.every((n) => n.grouped <= 65 && n.recent <= 65 && n.own <= 65),
    `checks read for 100 and 1000 unrelated checks: ${JSON.stringify(visits)}`);
});

for (const scenario of [
  { name: "a short recent window", own: 1, connects: 1, otherChecks: 4, oldAfter: 0, fallback: true },
  { name: "an out-of-order check just inside the probe", own: 1, connects: 1, otherChecks: 100, oldAfter: 64, fallback: false },
  { name: "an out-of-order check beyond the probe", own: 1, connects: 1, otherChecks: 100, oldAfter: 65, fallback: true },
  { name: "64 workspace sessions", own: 64, connects: 1, otherChecks: 100, oldAfter: 0, fallback: false },
  { name: "65 workspace sessions", own: 65, connects: 1, otherChecks: 100, oldAfter: 0, fallback: true },
  { name: "64 connects", own: 1, connects: 64, otherChecks: 100, oldAfter: 0, fallback: false },
  { name: "65 connects", own: 1, connects: 65, otherChecks: 100, oldAfter: 0, fallback: true },
]) test(`a workspace's latest checks remain exact with ${scenario.name}`, () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const add = (key: string, connect: string, ws: string) => store.insertSession({
      key, connect, runtime: "claude", profile: "cc", workspace: "/work",
      token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws,
    });
    db.exec("BEGIN");
    for (let i = 0; i < scenario.own; i++) add(`mine-${i}`, "connect-0", "mine");
    for (let i = 0; i < scenario.connects; i++) add(`other-${i}`, `connect-${i}`, "elsewhere");
    const insert = db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
    for (let i = 0; i < scenario.otherChecks; i++) insert.run("other-0", 100, "{}");
    for (let i = 0; i < scenario.own; i++) insert.run(`mine-${i}`, 100 + i, JSON.stringify({ selected: i }));
    for (let i = 0; i < scenario.oldAfter; i++) insert.run("mine-0", 10, "{}");
    db.exec("COMMIT");
    const expected = (db.prepare(LATEST_DECISIONS).all(50) as any[])
      .filter((row) => row.session.startsWith("mine-"))
      .map((row) => ({ id: row.id, session: row.session, at: row.created_at, detail: JSON.parse(row.result) }));
    let grouped = 0;
    db.function("visit_policy_fallback", (id) => { grouped++; return id; });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql.replace(
          "MAX(id) AS id, session FROM decision_checks WHERE created_at >= ?1",
          "MAX(visit_policy_fallback(id)) AS id, session FROM decision_checks WHERE created_at >= ?1"));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }), expected);
    assert.equal(grouped > 0, scenario.fallback, `fallback grouping visited ${grouped} checks`);
  } finally { store.close(); }
});

test("a small workspace does not decode another workspace's 64-bit decision id", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [key, ws] of [["mine", "mine"], ["other", "elsewhere"]]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
    }
    const insert = db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
    insert.run("mine", 100, "{}");
    for (let i = 0; i < 100; i++) insert.run("other", 100, "{}");
    db.exec("INSERT INTO decision_checks(id,session,created_at,result) VALUES(9223372036854775806,'other',100,'{}')");
    assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }),
      [{ id: 1, session: "mine", at: 100, detail: {} }]);
  } finally { store.close(); }
});

test("workspace moves, deleted sessions and out-of-order checks match the whole-station view", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const workspaces = ["mine", "elsewhere", null, "mine", "elsewhere", null, "mine", "elsewhere"];
    db.exec("BEGIN");
    for (let i = 0; i < workspaces.length; i++) {
      store.insertSession({ key: `session-${i}`, connect: `connect-${i % 3}`, runtime: "claude", profile: "cc",
        workspace: "/work", token: `token-${i}`, createdAt: 1, lastActiveAt: 1, ws: workspaces[i] });
    }
    const insert = db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
    let seed = 47;
    for (let i = 0; i < 400; i++) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      const session = seed % 11 < 8 ? `session-${seed % 8}` : "deleted";
      seed = (seed * 1664525 + 1013904223) >>> 0;
      insert.run(session, seed % 150, JSON.stringify({ n: i }));
    }
    db.exec("COMMIT");
    const check = () => {
      for (const since of [0, 50, 100, 150]) {
        const whole = db.prepare(LATEST_DECISIONS).all(since) as any[];
        for (const [workspace, home] of [["mine", false], ["elsewhere", false], ["mine", true]] as const) {
          const expected = whole.filter((row) => {
            const session = store.getSession(row.session);
            return session?.ws === workspace || (home && session?.ws == null);
          }).map((row) => ({ id: row.id, session: row.session, at: row.created_at, detail: JSON.parse(row.result) }));
          assert.deepEqual(store.latestDecisionsSince(since, { workspace, home }), expected,
            `since ${since}, workspace ${workspace}, home ${home}`);
        }
      }
    };
    check();
    db.exec("UPDATE sessions SET ws='elsewhere' WHERE key='session-0'");
    db.exec("DELETE FROM sessions WHERE key='session-1'");
    check();
  } finally { store.close(); }
});

for (const index of ["sessions_by_connect", "decision_checks_session", "decision_checks_lately"]) {
  for (const prepared of [false, true]) {
    test(`a workspace read remains usable when ${index} is removed (prepared ${prepared})`, () => {
      const dir = mkdtempSync(join(tmpdir(), "policy-scoped-index-")), path = join(dir, "store.db");
      const store = Store.open(path);
      const db = store.db;
      const other = new DatabaseSync(path);
      try {
        for (const [key, ws] of [["mine", "mine"], ["other", "elsewhere"]]) {
          store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
            token: `token-${key}`, createdAt: 1, lastActiveAt: 1, ws });
        }
        const insert = db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
        for (let i = 0; i < 100; i++) insert.run("other", 100, "{}");
        insert.run("mine", 100, "{}");
        const expected = [{ id: 101, session: "mine", at: 100, detail: {} }];
        if (prepared) assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }), expected);
        other.exec(`DROP INDEX ${index}`);
        assert.deepEqual(store.latestDecisionsSince(50, { workspace: "mine", home: false }), expected);
      } finally { other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
    });
  }
}
