// The bound each read of the `chat` table declares (db/chat-reads.ts `bound`) holds for the work SQLite does for it, not
// only for what it returns: held of its plan (EXPLAIN QUERY PLAN) on a database made as a core opens one (data.ts open:
// its schema, its migrations, the indexes made at every open), for every declaration in CHAT_READS, a new one with no
// code here.
//
// - `one`: every row of `chat` it reads is found through an index by a key beyond its station (and whether it is
//   archived): never a walk of a station's rows, nor of every row the device has.
// - `first`: it has a LIMIT, and its rows come walked in the order of an index, so the LIMIT stops the walk: no walk of
//   `chat` is sorted whole (`USE TEMP B-TREE FOR ORDER BY`; `FOR LAST n TERMS OF ORDER BY` sorts only the rows tied on
//   the index's terms).
// - `count`: `chat` is read of covering indexes alone: no row of the table (each row's page holds its JSON) touched.
//
// A plan depends on the indexes and the statement, not on what the database holds: the core never runs ANALYZE (no
// `sqlite_stat1`, which the test holds too), so the plan here is the one a device's SQLite makes with no statistics.
// But it is Node's SQLite that plans it here, and the native apps bundle another (rusqlite's, 3.50.2 on 2026-11-12; the
// web's is sqlite-wasm's): a statement whose plan could go either way is given one, by an index more of its terms
// match, a `+` on a term, or INDEXED BY (chat-reads.ts `archived`, which 3.50.2 planned otherwise with its parameters
// bound). One that cannot hold yet is in OVER_PLAN with why; it only falls.
import assert from "node:assert/strict";
import { test } from "node:test";
import { DatabaseSync } from "node:sqlite";
import { Data, dbName } from "../src/data.ts";
import { CHAT_READS, type ChatRead } from "../src/db/chat-reads.ts";
import type { SqlRow } from "../src/host.ts";
import { NodeSql } from "../src/hosts/node-sql.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";
import { run } from "./run.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The reads whose bound their plan does not hold yet, with why. Only falls.
const OVER_PLAN: Record<string, string> = {};

/// What a read is asked with, each parameter any declaration takes, as a list of real size asks it: two stations, one
/// thread and one session overlaid, a window of 30.
const ASKED: J = {
  station: "ws/maple",
  stations: ["ws/maple", "ws/willow"],
  id: "k-maple-1",
  session: "k-maple-1",
  thread: 7,
  key: "ck-1",
  keys: { "ws/maple": "1.a", "ws/willow": "1.b" },
  mine: false,
  hidden: 0,
  watching: false,
  threads: ["ws/maple\u00017"],
  sessions: ["ws/willow\u0001k-willow-2"],
  limit: 30,
  archived: false,
  from: 1_790_000_000_000,
  to: 1_790_086_400_000,
  offset: 480 * 60_000,
  day: 86_400_000,
};

type Step = { id: number; parent: number; detail: string };
/// An access to a table in a plan: its name (or alias), how, and the columns it is searched by with `=` (or IN).
type Access = { step: Step; of: string; covering: boolean; byRowid: boolean; index: boolean; equal: string[] };

function access(step: Step): Access | null {
  const m = /^(SEARCH|SCAN) (\S+)(?: USING (COVERING INDEX|INDEX|INTEGER PRIMARY KEY|PRIMARY KEY)(?: ([^\s(]+))?(?: \((.*)\))?)?/.exec(step.detail);
  if (m === null) return null;
  const terms = (m[5] ?? "").split(" AND ").map((t) => t.trim());
  const equal = terms.filter((t) => /^[\w<>]+=\?$/.test(t)).map((t) => t.slice(0, -2));
  return { step, of: m[2], covering: m[3] === "COVERING INDEX", byRowid: m[3] === "INTEGER PRIMARY KEY" && terms.includes("rowid=?"), index: m[3] !== undefined, equal };
}

/// The names `chat` goes by in a statement: its own and its aliases (`chat AS c`), not `chat_row` and the like.
function chatNames(sql: string): Set<string> {
  const out = new Set<string>();
  for (const m of sql.matchAll(/\b(?:FROM|JOIN)\s+chat\b(?!_)(?:\s+AS\s+(\w+))?/gi)) out.add(m[1] ?? "chat");
  return out;
}

/// Whether an access to `chat` walks rows: not by rowid, and searched by no column beyond the station and whether it is
/// archived (so every row of a station, or of the device, it does not stop by).
const walks = (a: Access): boolean => !a.byRowid && a.equal.every((c) => c === "station" || c === "archived");

/// What of a read's plan breaks its bound, as lines to print (none: it holds).
function faults(read: ChatRead<J>, steps: Step[]): string[] {
  const names = chatNames(read.sql);
  const chat = steps.map(access).filter((a): a is Access => a !== null && names.has(a.of));
  const out: string[] = [];
  if (chat.length === 0) out.push("reads no `chat` in its plan: is it a read of the chat table?");
  if (read.bound === "one") {
    for (const a of chat) if (walks(a)) out.push(`walks rows not found by its key: ${a.step.detail}`);
  } else if (read.bound === "first") {
    if (!/\bLIMIT\b/i.test(read.sql)) out.push("has no LIMIT to stop its walk");
    for (const a of chat) if (walks(a) && !a.index) out.push(`walks the table in no index's order: ${a.step.detail}`);
    for (const s of steps) {
      if (s.detail !== "USE TEMP B-TREE FOR ORDER BY") continue;
      const beside = chat.filter((a) => a.step.parent === s.parent && walks(a));
      for (const a of beside) out.push(`sorts a walk whole before its LIMIT: ${a.step.detail}`);
    }
  } else {
    for (const a of chat) if (!a.covering) out.push(`reads rows of the table: ${a.step.detail}`);
  }
  return out;
}

async function opened(): Promise<{ sql: NodeSql; runner: Runner }> {
  const host = new FakeHost();
  const sql = new NodeSql(new DatabaseSync(":memory:"), true);
  host.openDbHook = (name) => (name === dbName("s1") ? sql : null);
  const runner = new Runner(host.time.clock);
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  return { sql, runner };
}

const planOf = (sql: NodeSql, read: ChatRead<J>): Step[] =>
  sql.all(`EXPLAIN QUERY PLAN ${read.sql}`, read.params(ASKED)).map((r: SqlRow) => ({ id: Number(r[0]), parent: Number(r[1]), detail: String(r[3]) }));

const shown = (steps: Step[]): string => {
  const depth = new Map<number, number>([[0, 0]]);
  return steps.map((s) => {
    const d = (depth.get(s.parent) ?? 0) + 1;
    depth.set(s.id, d);
    return `${"  ".repeat(d)}${s.detail}`;
  }).join("\n");
};

test("every_declared_read_of_the_chat_table_does_the_work_its_bound_says_in_sqlite", async () => {
  const { sql, runner } = await opened();
  try {
    assert.deepEqual(sql.all("SELECT name FROM sqlite_master WHERE name LIKE 'sqlite_stat%'"), [], "no statistics: the core never runs ANALYZE, and a plan is made without them");
    if (process.env.CHAT_PLANS_PRINT) console.log(`SQLite ${sql.all("SELECT sqlite_version()")[0][0]}`);
    const failed: string[] = [];
    for (const [name, read] of Object.entries(CHAT_READS) as [string, ChatRead<J>][]) {
      const steps = planOf(sql, read);
      const found = faults(read, steps);
      if (process.env.CHAT_PLANS_PRINT) console.log(`== ${name} (${read.bound})\n${shown(steps)}`);
      if (name in OVER_PLAN) {
        if (found.length === 0) failed.push(`${name}: holds its bound now: take it out of OVER_PLAN`);
        continue;
      }
      if (found.length > 0) failed.push(`${name} (${read.bound}):\n    ${found.join("\n    ")}\n  its plan:\n${shown(steps)}`);
    }
    for (const name of Object.keys(OVER_PLAN)) if (!(name in CHAT_READS)) failed.push(`${name}: no such read: take it out of OVER_PLAN`);
    assert.equal(failed.join("\n"), "");
  } finally {
    runner.shutdown();
  }
});

test("a_plan_that_walks_a_station_or_sorts_a_walk_whole_is_found", () => {
  // (the rules find what they are for: plans of the statements as they were before chat-plans.test.ts)
  const one = { bound: "one", sql: "SELECT station FROM chat WHERE station = ? AND archived = 0 AND session = ? ORDER BY ord LIMIT 1" } as ChatRead<J>;
  assert.equal(faults(one, [{ id: 2, parent: 0, detail: "SEARCH chat USING INDEX chat_ord (station=? AND archived=?)" }, { id: 3, parent: 0, detail: "USE TEMP B-TREE FOR LAST TERM OF ORDER BY" }]).length, 1);
  assert.deepEqual(faults(one, [{ id: 2, parent: 0, detail: "SEARCH chat USING INDEX chat_session (station=? AND session=?)" }, { id: 3, parent: 0, detail: "USE TEMP B-TREE FOR ORDER BY" }]), []);
  const first = { bound: "first", sql: "SELECT c.id FROM json_each(?) AS s JOIN chat AS c ON c.station = s.value ORDER BY c.last_active DESC LIMIT ?" } as ChatRead<J>;
  assert.equal(faults(first, [{ id: 2, parent: 0, detail: "SEARCH c USING INDEX chat_recent (archived=?)" }, { id: 9, parent: 0, detail: "SCAN s VIRTUAL TABLE INDEX 1:" }, { id: 10, parent: 0, detail: "USE TEMP B-TREE FOR ORDER BY" }]).length, 1);
  assert.deepEqual(faults(first, [{ id: 2, parent: 0, detail: "SEARCH c USING INDEX chat_recent (archived=?)" }, { id: 10, parent: 0, detail: "USE TEMP B-TREE FOR LAST 3 TERMS OF ORDER BY" }]), []);
  const count = { bound: "count", sql: "SELECT count(*) FROM chat WHERE station = ? AND archived = 0" } as ChatRead<J>;
  assert.equal(faults(count, [{ id: 2, parent: 0, detail: "SEARCH chat USING INDEX chat_ord (station=? AND archived=?)" }]).length, 1);
  assert.deepEqual(faults(count, [{ id: 2, parent: 0, detail: "SEARCH chat USING COVERING INDEX chat_listed (station=? AND archived=?)" }]), []);
});
