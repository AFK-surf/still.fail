// A usage range names its sessions: checking visibility must not read every unrelated session.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, seenBy } from "../src/read/store.ts";

test("visibility of usage sessions reads only those named, including missing and old sessions", () => {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE sessions (key TEXT PRIMARY KEY, ws TEXT)");
  const insert = db.prepare("INSERT INTO sessions VALUES (?, ?)");
  for (let i = 0; i < 2000; i++) insert.run(`other-${i}`, "elsewhere");
  insert.run("mine", "mine");
  insert.run("legacy", null);
  insert.run("unrequested", null);
  let rowsRead = 0;
  let firstQuery = "";
  let firstArgs: any[] = [];
  const observed = {
    prepare(sql: string) {
      const query = db.prepare(sql);
      return {
        all: (...args: any[]) => {
          if (!firstQuery) { firstQuery = sql; firstArgs = args; }
          const rows = query.all(...args); rowsRead += rows.length; return rows;
        },
        get: (...args: any[]) => query.get(...args),
      };
    },
  } as unknown as DatabaseSync;
  try {
    const seen = seenBy(makeStore(observed, "."), { workspace: "mine", home: true }, ["mine", "legacy", "gone"]);
    assert.equal(seen("mine"), true);
    assert.equal(seen("legacy"), true);
    assert.equal(seen("gone"), true);
    assert.equal(seen("unrequested"), false);
    assert.equal(rowsRead, 2);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${firstQuery}`).all(...firstArgs).map((r) => String(r.detail));
    assert.ok(plan.some((line) => /SEARCH sessions USING INDEX/i.test(line)), plan.join("; "));
    const away = seenBy(makeStore(observed, "."), { workspace: "mine", home: false }, ["mine", "legacy", "gone", "other-0"]);
    assert.equal(away("mine"), true);
    assert.equal(away("legacy"), false);
    assert.equal(away("gone"), false);
    assert.equal(away("other-0"), false);
    db.exec("DROP TABLE sessions; CREATE TABLE sessions (key TEXT PRIMARY KEY); INSERT INTO sessions VALUES ('old')");
    const beforeWorkspaces = seenBy(makeStore(observed, "."), { workspace: "mine", home: true }, ["old"]);
    assert.equal(beforeWorkspaces("old"), true);
  } finally { db.close(); }
});
