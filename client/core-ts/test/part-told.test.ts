// A station's overview written tells what of its part changed (account.ts #overviewWritten, schema.ts partRev), and
// that alone, on the workspace of real size (real-size.ts) with everything the app asks held: generated over every
// column of the part (schema.ts PART_COLUMNS), no code here for any one of them but its entry of CHANGE.
//
// - An overview written with what a column is made of changed tells `$overview-<column>` for each column whose text
//   is another (as SQLite holds them, read here), that one among them, and no other.
// - One written the same tells nothing, and no text comes back from SQLite for it.
// - One written by a core that knows nothing of the revisions (its JSON put by a statement alone): the database opened
//   again after it holds each part as SQLite makes it of its overview, every row counted.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dbName } from "../src/data.ts";
import type { Changes } from "../src/db/account.ts";
import { PART_COLUMNS, partRev } from "../src/db/schema.ts";
import { NodeSql } from "../src/hosts/node-sql.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { FakeHost } from "../src/testing.ts";
import { held } from "./real-size-asked.ts";
import { UP } from "./real-size.ts";
import { overview } from "./views-rig.ts";

holdLanguage();

// deno-lint-ignore no-explicit-any
type J = any;

/// How each column's overview is changed in what it is made of (schema.ts, its `of`), `n` a number of the write's own.
const CHANGE: Record<string, (o: J, n: number) => J> = {
  part: (o, n) => ({ ...o, slackUsers: [...o.slackUsers, `U-TOLD-${n}`] }),
  row: (o, n) => ({ ...o, viewer: { ...o.viewer, name: `${o.viewer.name}·${n}` } }),
  chat: (o, n) => ({ ...o, context: { ...o.context, afreshAbove: n / 100 } }),
  formerly: (o, n) => ({ ...o, copies: { ...o.copies, formerly: [...o.copies.formerly, `ws/gone-${n}`] } }),
  profiles: (o, n) => ({ ...o, profiles: o.profiles.map((p: J, i: number) => (i === 0 ? { ...p, name: `${p.name}·${n}` } : p)) }),
  profiled: (o, n) => ({ ...o, mesh: { ...o.mesh, name: `${o.mesh.name}·${n}` } }),
  software: (o, n) => ({ ...o, updates: o.updates.map((u: J) => (u.id === "station" ? { ...u, latest: `0.1.${9000 + n}` } : u)) }),
};

const station = UP[0]!;
const sqlOf = (host: FakeHost) => host.sqls.get(dbName("s1"))!;
/// Each column of a station's part as SQLite holds it.
const texts = (host: FakeHost, at: string) => sqlOf(host).all(`SELECT ${PART_COLUMNS.map(([c]) => c).join(", ")} FROM station_part WHERE address = ?`, [at])[0]!;

// The text of every cell SQLite gives back (NodeSql's `all`, as the test's host makes it), while `seen` is set.
let seen: string[] | null = null;
{
  const proto = NodeSql.prototype as J;
  const all = proto.all;
  proto.all = function (sql: string, params: unknown[] = []) {
    const rows = all.call(this, sql, params) as unknown[][];
    if (seen !== null) for (const row of rows) for (const v of row) if (typeof v === "string") seen.push(v);
    return rows;
  };
}

test("every_column_of_the_part_is_changed_here", () => {
  assert.deepEqual(Object.keys(CHANGE).sort(), PART_COLUMNS.map(([c]) => c).sort());
});

test("an_overview_written_tells_the_columns_of_its_part_that_changed_and_no_other", async () => {
  const h = await held(false);
  try {
    const { t } = h;
    // (what each burst told of the part)
    const told: string[] = [];
    const db = t.data.of(station)!;
    const committed = db.onCommit;
    db.onCommit = (changes: Changes) => {
      for (const topic of changes.topics.values()) if (topic.topic.startsWith("$overview-") && topic.station === station) told.push(topic.topic.slice("$overview-".length));
      committed(changes);
    };
    let n = 0;
    for (const [column] of PART_COLUMNS) {
      const before = texts(t.host, station);
      told.length = 0;
      t.set(overview(station), CHANGE[column]!(t.data.shared(overview(station)) as J, ++n));
      await t.host.time.pass(100);
      const after = texts(t.host, station);
      const changed = PART_COLUMNS.filter((_, i) => before[i] !== after[i]).map(([c]) => c);
      assert.ok(changed.includes(column), `${column}: its change left its text as it was`);
      assert.deepEqual([...told].filter((c) => c !== "fit").sort(), [...changed].sort(), `${column} changed`);
      assert.ok(told.includes("fit"), `${column}: the overview's verdict told`);
    }
    // Written the same: nothing told, no text read.
    told.length = 0;
    seen = [];
    t.set(overview(station), t.data.shared(overview(station)));
    await t.host.settle();
    const read = seen;
    seen = null;
    assert.deepEqual(told, [], "written the same: told");
    assert.deepEqual(read, [], "written the same: text read");
  } finally {
    seen = null;
    h.t.store.runner.shutdown();
  }
});

test("an_overview_written_by_a_core_that_knows_nothing_of_the_revisions_has_its_part_as_its_overview_makes_it_at_the_next_open", async () => {
  const h = await held(false);
  h.t.store.runner.shutdown();
  const host = h.t.host;
  const sql = sqlOf(host);
  // (each column's change, put by a statement alone)
  let n = 100;
  for (const [column] of PART_COLUMNS) {
    const o = JSON.parse(String(sql.all("SELECT json FROM station WHERE address = ? AND kind = 'overview'", [station])[0]![0]));
    sql.run("UPDATE station SET json = ? WHERE address = ? AND kind = 'overview'", [JSON.stringify(CHANGE[column]!(o, ++n)), station]);
  }
  const again = await held(false, { host, cold: true });
  again.t.store.runner.shutdown();
  const made = sql.all(`SELECT st.address, ${PART_COLUMNS.map(([, of]) => of("st.json")).join(", ")} FROM station AS st WHERE st.kind = 'overview' ORDER BY st.address`);
  const kept = sql.all(`SELECT address, ${PART_COLUMNS.map(([c]) => c).join(", ")} FROM station_part ORDER BY address`);
  assert.ok(made.length > 0);
  assert.deepEqual(kept, made, "each part as its overview makes it");
  assert.deepEqual(sql.all(`SELECT count(*) FROM station_part WHERE ${PART_COLUMNS.map(([c]) => `${partRev(c)} IS NULL`).join(" OR ")}`)[0], [0], "every column counted");
});
