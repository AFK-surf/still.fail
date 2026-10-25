// The main thread's slow queries said (src/store/timed.ts).
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { SLOW_MS, askedBy, shortSql, timed } from "../src/store/timed.ts";

test("a statement run or an exec taking SLOW_MS or more is said, by its SQL and who asked it alone; a quicker one is not", () => {
  const said: [string, number, number | null][] = [];
  const by: string[] = [];
  // Each run takes as long as the test says, on the clock it gives.
  let takes = 0;
  let at = 0;
  const now = () => (at += takes);
  const db = timed(new DatabaseSync(":memory:"), (sql, ms, rows, who) => (said.push([sql, ms, rows]), by.push(who)), now);
  takes = SLOW_MS;
  db.exec("CREATE TABLE t (a TEXT)");
  const insert = db.prepare("INSERT INTO t (a) VALUES (?)");
  takes = 1;
  insert.run("someone's words");
  insert.run("more of them");
  takes = SLOW_MS + 1;
  const listEvery = () => db.prepare("SELECT a FROM t\n   ORDER BY a").all();
  const rows = listEvery();
  assert.equal(rows.length, 2);
  db.prepare("SELECT a FROM t WHERE a = ?").get("x");
  assert.deepEqual(said, [["CREATE TABLE t (a TEXT)", SLOW_MS, null], ["SELECT a FROM t\n   ORDER BY a", SLOW_MS + 1, 2], ["SELECT a FROM t WHERE a = ?", SLOW_MS + 1, null]]);
  assert.equal(shortSql("SELECT a FROM t\n   ORDER BY a"), "SELECT a FROM t ORDER BY a");
  assert.ok(!JSON.stringify(said).includes("words"), "never what it was given");
  // Who asked: the function that ran it, past the wrappers.
  assert.ok(by[1]!.startsWith("listEvery"), by[1]);
  // What is not a run is as it was.
  assert.equal(db.prepare("SELECT 1 AS one").sourceSQL, "SELECT 1 AS one");
  db.close();
});

test("who asked is said by the names of the functions past the wrappers and the store's own helpers", () => {
  const stack = [
    "Error",
    "    at time2 (file:///s/main.js:1:1)",
    "    at StatementSync.<anonymous> (file:///s/timed.ts:2:2)",
    "    at Store.#all (file:///s/store.ts:3:3)",
    "    at Store.listSessions (file:///s/store.ts:4:4)",
    "    at ColdRooms.archiveRoom (file:///s/cold.ts:5:5)",
    "    at async expireArchived (file:///s/lifecycle.ts:6:6)",
    "    at agents (file:///s/agents.ts:7:7)",
  ].join("\n");
  assert.equal(askedBy(stack), "Store.listSessions < ColdRooms.archiveRoom < expireArchived");
  assert.equal(askedBy(undefined), "");
});
