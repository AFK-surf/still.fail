import assert from "node:assert/strict";
import { test } from "node:test";
import { policyView } from "../src/sessions/archive-policy.ts";
import { LATEST_DECISIONS, LATEST_DECISIONS_SCOPED, Store } from "../src/store/store.ts";

test("a workspace's policy reads only its own latest decision details", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const check = db.prepare("INSERT INTO decision_checks(session, created_at, result) VALUES (?, ?, ?)");
    db.exec("BEGIN");
    for (let n = 0; n < 253; n++) {
      const key = `session-${n}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${n}`, createdAt: n, lastActiveAt: n, ws: n < 2 ? "mine" : n === 2 ? null : "elsewhere" });
      check.run(key, 100, JSON.stringify({ result: { selected: n % 2 ? "landed" : "answered" } }));
    }
    db.exec("UPDATE sessions SET archived_at = 10 WHERE key = 'session-1'");
    check.run("session-0", 90, JSON.stringify({ result: { selected: "dropped" } }));
    check.run("session-0", 10, JSON.stringify({ result: { selected: "old" } }));
    check.run("deleted-session", 95, JSON.stringify({ result: { selected: "answered" } }));
    db.exec("COMMIT");
    const baseline = (db.prepare(LATEST_DECISIONS).all(50) as any[]).map(r => ({
      id: r.id, session: r.session, at: r.created_at, detail: JSON.parse(r.result),
    }));
    const expected = (home: boolean) => baseline.filter((row: any) => row.session === "session-0" || row.session === "session-1"
      || (home && (row.session === "session-2" || row.session === "deleted-session")));
    assert.equal(baseline.find((row: any) => row.session === "session-0").detail.result.selected, "dropped");

    let visited = 0;
    db.function("visit_policy_result", (result) => { visited++; return result; });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql.includes("decision_checks") && sql.includes("MAX(id)")) {
            sql = sql.replace("created_at, result FROM decision_checks", "created_at, visit_policy_result(result) AS result FROM decision_checks")
              .replace("d.created_at, d.result", "d.created_at, visit_policy_result(d.result) AS result");
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    // A fresh statement is needed after installing the observer.
    const read = (store.latestDecisionsSince as any).bind(store);
    assert.deepEqual(read(50), baseline);
    visited = 0;
    assert.deepEqual(read(51, { workspace: "mine", home: false }), expected(false));
    assert.equal(visited, 2, `the joined workspace read ${visited} decision details for two sessions`);
    visited = 0;
    assert.deepEqual(read(52, { workspace: "mine", home: true }), expected(true));
    assert.equal(visited, 4);
    visited = 0;
    assert.deepEqual(read(53, { workspace: "absent", home: false }), []);
    assert.equal(visited, 0);

    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${LATEST_DECISIONS_SCOPED}`).all(50, "mine", 0) as { detail: string }[]).map(r => r.detail);
    assert.ok(plan.some(p => p.includes("COVERING INDEX decision_checks_lately")), plan.join(" | "));
    const sessionLookup = plan.findIndex(p => p.includes("SEARCH s USING INDEX"));
    const detailLookup = plan.findIndex(p => p.includes("SEARCH d USING INTEGER PRIMARY KEY"));
    assert.ok(sessionLookup >= 0 && detailLookup > sessionLookup, plan.join(" | "));

    visited = 0;
    const viewed = { archivePolicy: store.archivePolicy.bind(store), setArchivePolicy: store.setArchivePolicy.bind(store),
      latestDecisionsSince: read, getSession: store.getSession.bind(store), now: () => 50 + 7 * 86_400_000 };
    const policy = policyView(viewed, "mine", (session) => session === "session-0" || session === "session-1", s => s,
      { workspace: "mine", home: false });
    assert.equal(policy.checked, 2);
    assert.equal(visited, 2);

    db.prepare("UPDATE sessions SET ws = 'elsewhere' WHERE key = 'session-0'").run();
    visited = 0;
    assert.deepEqual(read(54, { workspace: "mine", home: false }).map((row: any) => row.session), ["session-1"]);
    assert.equal(visited, 1);
  } finally { store.close(); }
});
