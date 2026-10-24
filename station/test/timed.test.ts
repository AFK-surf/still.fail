// The main thread's slow queries said (src/store/timed.ts).
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { SLOW_MS, shortSql, timed } from "../src/store/timed.ts";

test("a statement run or an exec taking SLOW_MS or more is said, by its SQL alone; a quicker one is not", () => {
  const said: [string, number, number | null][] = [];
  // Each run takes as long as the test says, on the clock it gives.
  let takes = 0;
  let at = 0;
  const now = () => (at += takes);
  const db = timed(new DatabaseSync(":memory:"), (sql, ms, rows) => said.push([sql, ms, rows]), now);
  takes = SLOW_MS;
  db.exec("CREATE TABLE t (a TEXT)");
  const insert = db.prepare("INSERT INTO t (a) VALUES (?)");
  takes = 1;
  insert.run("someone's words");
  insert.run("more of them");
  takes = SLOW_MS + 1;
  const rows = db.prepare("SELECT a FROM t\n   ORDER BY a").all();
  assert.equal(rows.length, 2);
  db.prepare("SELECT a FROM t WHERE a = ?").get("x");
  assert.deepEqual(said, [["CREATE TABLE t (a TEXT)", SLOW_MS, null], ["SELECT a FROM t\n   ORDER BY a", SLOW_MS + 1, 2], ["SELECT a FROM t WHERE a = ?", SLOW_MS + 1, null]]);
  assert.equal(shortSql("SELECT a FROM t\n   ORDER BY a"), "SELECT a FROM t ORDER BY a");
  assert.ok(!JSON.stringify(said).includes("words"), "never what it was given");
  // What is not a run is as it was.
  assert.equal(db.prepare("SELECT 1 AS one").sourceSQL, "SELECT 1 AS one");
  db.close();
});
