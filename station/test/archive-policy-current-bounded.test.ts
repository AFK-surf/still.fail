import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

for (const target of ["mine", null, "missing"] as const) test(`reading ${target ?? "home"} policy skips other workspaces' changes`, () => {
  const visits: number[] = [];
  for (const otherChanges of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      const insert = db.prepare("INSERT INTO archive_policy(at,policy,author,summary,ws) VALUES(?,?,?,?,?)");
      if (target !== "missing") insert.run(1, '{"version":1}', '{"kind":"agent"}', "mine", target);
      db.exec("BEGIN");
      for (let i = 0; i < otherChanges; i++) insert.run(i + 2, '{"version":2}', '{"kind":"person"}', "other", "other");
      db.exec("COMMIT");
      db.exec("ANALYZE");
      const plan=db.prepare("EXPLAIN QUERY PLAN SELECT id, at, policy, author, summary FROM archive_policy WHERE ws IS ? ORDER BY id DESC LIMIT 1")
        .all(target).map(row=>row.detail).join(" | ");
      assert.match(plan,/archive_policy_by_ws/,`the policy read should seek its workspace after ANALYZE: ${plan}`);
      let visited = 0, instrumented = false;
      db.function("visit_archive_policy", (id) => { visited++; return id === null ? 0 : 1; });
      Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
        get(targetDb, property) {
          if (property === "prepare") return (sql: string) => {
            const source = "FROM archive_policy WHERE ws IS ? ORDER BY id DESC LIMIT 1";
            if (sql.includes(source)) {
              instrumented = true;
              sql = sql.replace(source, "FROM archive_policy WHERE visit_archive_policy(id) AND ws IS ? ORDER BY id DESC LIMIT 1");
            }
            return targetDb.prepare(sql);
          };
          const value = Reflect.get(targetDb, property, targetDb);
          return typeof value === "function" ? value.bind(targetDb) : value;
        },
      }) });
      assert.deepEqual(store.archivePolicy(target), target === "missing" ? null : {
        policy: { version: 1 }, change: { id: 1, at: 1, by: { kind: "agent" }, summary: "mine" },
      });
      assert.ok(instrumented, "the actual policy read must be instrumented");
      visits.push(visited);
    } finally { store.close(); }
  }
  assert.ok(visits[1]! <= visits[0]! + 2 && visits[1]! <= 4, `policy rows visited: ${visits.join(" / ")}`);
});
