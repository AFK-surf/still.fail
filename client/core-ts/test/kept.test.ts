// Every value kept beside its record (db/kept.ts KEPT) held to what its declaration says, on the workspace of real size
// (real-size.ts): generated over every declaration, no code here for any one of them but its entry of HOW.
//
// - What is kept is what is made now: after everything the app asks was read (kept), and again after each change
//   the sync is told (real-size-asked.ts CAUSES, one after another), every value kept under the key in force is what
//   its maker makes of its record as the database holds it now, or none is kept. A write whose trigger or write hook
//   is missing, or a maker reading what its key does not say and that changed, fails here.
// - A hit reads no record: a core started anew on a database where every value was kept answers the way the app asks
//   it without one of their records' text coming back from SQLite (counted in the database's own calls).
// - What making costs follows the policy: `read`, a station's records all written before any reader read one make
//   none, and once a reader kept k of them, k; `written`, one for each record written.
// - What is kept made otherwise (another `making`) is dropped as the database opens; made the same, it stays.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dbName } from "../src/data.ts";
import { KEPT_ALL, type AnyKept, type Owner } from "../src/db/kept.ts";
import type { Sql } from "../src/host.ts";
import { NodeSql } from "../src/hosts/node-sql.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { FakeHost } from "../src/testing.ts";
import { work } from "../src/work.ts";
import { CAUSES, held, topicOf, type Held } from "./real-size-asked.ts";
import { UP } from "./real-size.ts";
import { overview } from "./views-rig.ts";

holdLanguage();

// deno-lint-ignore no-explicit-any
type J = any;
type Rig = Held["t"];

/// How each declaration is exercised: the way of `ASKED` that reads it; its owners in the database; a write of an
/// owner's record that changes it (`n` a number of the write's own), as the sync writes one; and one as a core that
/// knows nothing of what is kept writes it (its statement alone: what the triggers are for).
const HOW: Record<string, { asked: string; owners: (sql: Sql) => Owner[]; write: (t: Rig, owner: Owner, n: number) => void; older: (sql: Sql, owner: Owner) => void }> = {
  listRow: {
    asked: "chats",
    owners: (sql) => sql.all("SELECT station, id FROM chat WHERE archived = 0").map((r) => [String(r[0]), String(r[1])]),
    write: (t, [station, id], n) => {
      const r = t.data.chat(station, id) as J;
      t.data.putChat(station, { ...r, title: `${r.title ?? ""}·${n}` });
    },
    older: (sql, [station, id]) => sql.run("UPDATE chat SET json = json_set(json, '$.title', '旧的核心改了名') WHERE station = ? AND archived = 0 AND id = ?", [station, id]),
  },
  overviewFit: {
    asked: "stations",
    owners: (sql) => sql.all("SELECT address FROM station WHERE kind = 'overview'").map((r) => [String(r[0])]),
    write: (t, [station], n) => t.set(overview(station), { ...(t.data.shared(overview(station)) as J), written: n }),
    // (one this core cannot read: its verdict another)
    older: (sql, [station]) => sql.run("UPDATE station SET json = json_set(json, '$.profiles', 'older') WHERE address = ? AND kind = 'overview'", [station]),
  },
  profileRow: {
    asked: "profiles",
    owners: (sql) => sql.all("SELECT address FROM station_part").map((r) => [String(r[0])]),
    write: (t, [station], n) => {
      const o = t.data.shared(overview(station)) as J;
      t.set(overview(station), { ...o, profiles: o.profiles.map((p: J, i: number) => (i === 0 ? { ...p, name: `${p.name}·${n}` } : p)) });
    },
    older: (sql, [station]) => sql.run("UPDATE station SET json = json_set(json, '$.profiles[0].name', '旧的核心改了名') WHERE address = ? AND kind = 'overview'", [station]),
  },
};

const sqlOf = (host: FakeHost) => host.sqls.get(dbName("s1"))!;
const count = (name: string) => (work as Record<string, number>)[name];
const kept = (sql: Sql, d: AnyKept, station?: string): number =>
  Number(sql.all(`SELECT count(*) FROM ${d.table}${station === undefined ? "" : ` WHERE ${d.owner[0]} = ?`}`, station === undefined ? [] : [station])[0]![0]);

test("every_declaration_is_exercised_here", () => {
  for (const d of KEPT_ALL) assert.ok(HOW[d.name] !== undefined, `${d.name}: no entry in HOW (how it is asked, its owners, a write of its record)`);
  for (const name of Object.keys(HOW)) assert.ok(KEPT_ALL.some((d) => d.name === name), `${name}: no such declaration`);
  for (const d of KEPT_ALL) for (const c of ["Kept", "Written", "Made"]) assert.equal(typeof count(`${d.name}${c}`), "number", `work.${d.name}${c}`);
});

/// Every value kept under its key in force that is not what its maker makes of its record now: `<name> <owner>`. And
/// how many were compared, by declaration.
function differing(t: Rig): { wrong: string[]; compared: Map<string, number> } {
  const wrong: string[] = [];
  const compared = new Map<string, number>();
  const sql = sqlOf(t.host);
  for (const d of KEPT_ALL) {
    for (const owner of HOW[d.name]!.owners(sql)) {
      const db = t.data.of(owner[0])!;
      const maker = db.kept.maker(d)!;
      const key = maker.key(owner);
      if (key === null) continue;
      // (as the database holds it, and as a reader is given it: the cache's)
      const stored = db.kept.stored(d, owner, key);
      const read = db.kept.one(d, owner, key);
      if (stored === undefined && read === undefined) continue;
      const made = maker.make(owner, db.kept.record(d, owner));
      // (not one to keep now: what reads it makes it as it reads it, its kept one not read)
      if (made === null) continue;
      compared.set(d.name, (compared.get(d.name) ?? 0) + 1);
      for (const [how, v] of [["stored", stored], ["read", read]] as const) {
        if (v !== undefined && JSON.stringify(made) !== JSON.stringify(v)) wrong.push(`${d.name} ${owner.join(" ")} ${how}`);
      }
    }
  }
  return { wrong, compared };
}

test("what_is_kept_is_what_is_made_of_its_record_now_after_every_change", async () => {
  const h = await held(false);
  try {
    const first = differing(h.t);
    for (const d of KEPT_ALL) assert.ok((first.compared.get(d.name) ?? 0) > 0, `${d.name}: nothing kept once everything was read`);
    assert.deepEqual(first.wrong, [], "as everything was read");
    for (const [name, cause] of Object.entries(CAUSES)) {
      await h.during(() => cause.run(h), cause.ms ?? 1000);
      assert.deepEqual(differing(h.t).wrong, [], `after ${name}`);
    }
  } finally {
    h.t.store.runner.shutdown();
  }
  // Records written by a core that knows nothing of what is kept (one of each declaration's that has a value), the
  // database opened again after it.
  const sql = sqlOf(h.t.host);
  for (const d of KEPT_ALL) {
    const owner = HOW[d.name]!.owners(sql).find((o) => kept(sql, d, o[0]) > 0 && Number(sql.all(`SELECT count(*) FROM ${d.table} WHERE ${d.owner.map((c) => `${c} = ?`).join(" AND ")}`, o)[0]![0]) > 0)!;
    assert.ok(owner !== undefined, `${d.name}: none kept`);
    HOW[d.name]!.older(sql, owner);
  }
  const again = await anew(h.t.host);
  try {
    assert.deepEqual(differing(again.t).wrong, [], "written by a core that knows nothing of them");
  } finally {
    again.t.store.runner.shutdown();
  }
});

/// A database where everything the app asks was read and kept: its host, the core stopped.
async function everythingKept(): Promise<FakeHost> {
  const h = await held(false);
  await h.t.host.time.pass(100);
  h.t.store.runner.shutdown();
  return h.t.host;
}

/// A core started anew on `host` (nothing asked), told what is not kept there as the sync tells it.
async function anew(host: FakeHost): Promise<Held> {
  const h = await held(false, { host, cold: true });
  h.setLive();
  await h.t.host.time.pass(100);
  return h;
}

// The text of every cell SQLite gives back (NodeSql's `all`, as the test's host makes it), while `seen` is set.
let seen: Set<string> | null = null;
{
  const proto = NodeSql.prototype as J;
  const all = proto.all;
  proto.all = function (sql: string, params: unknown[] = []) {
    const rows = all.call(this, sql, params) as unknown[][];
    if (seen !== null) for (const row of rows) for (const v of row) if (typeof v === "string") seen.add(v);
    return rows;
  };
}

test("a_core_started_anew_answers_what_is_kept_reading_none_of_their_records", async () => {
  const host = await everythingKept();
  const sql = sqlOf(host);
  for (const d of KEPT_ALL) {
    // (the text of each record a value is kept of, as its table holds it)
    const s = d.source;
    const column = s.by ?? "json";
    const texts = new Map<string, string>();
    for (const r of sql.all(`SELECT ${d.owner.map((c) => `k.${c}`).join(", ")}, s.${column} FROM ${d.table} AS k JOIN ${s.table} AS s ON ${d.owner.map((c, i) => `s.${s.owner[i]} = k.${c}`).join(" AND ")}${s.of === undefined ? "" : ` AND ${s.of("s")}`}`)) {
      if (typeof r[d.owner.length] === "string") texts.set(String(r[d.owner.length]), r.slice(0, d.owner.length).join(" "));
    }
    assert.ok(texts.size > 0, `${d.name}: nothing kept`);
    const h = await anew(host);
    try {
      const before = count(`${d.name}Kept`);
      seen = new Set();
      h.t.store.subscribe(1, 1, topicOf(HOW[d.name]!.asked), true);
      await h.t.host.time.pass(100);
      const read = [...seen].filter((text) => texts.has(text)).map((text) => texts.get(text));
      seen = null;
      assert.ok(count(`${d.name}Kept`) > before, `${d.name}: ${HOW[d.name]!.asked} took none as kept`);
      assert.deepEqual(read, [], `${d.name}: ${HOW[d.name]!.asked} read the records of these`);
    } finally {
      seen = null;
      h.t.store.runner.shutdown();
    }
  }
});

test("what_making_costs_follows_each_declarations_policy", async () => {
  const station = UP[0]!;
  for (const d of KEPT_ALL) {
    const host = await everythingKept();
    const sql = sqlOf(host);
    const how = HOW[d.name]!;
    const owners = how.owners(sql).filter((o) => o[0] === station);
    assert.ok(owners.length > 0, `${d.name}: ${station} has no record`);
    /// Every record of the station written on a core started anew: what was made and put as they were.
    const writeAll = async (n: number): Promise<{ made: number; written: number }> => {
      const h = await anew(host);
      try {
        const made = count(`${d.name}Made`);
        const written = count(`${d.name}Written`);
        for (const owner of owners) how.write(h.t, owner, n);
        await h.t.host.time.pass(100);
        return { made: count(`${d.name}Made`) - made, written: count(`${d.name}Written`) - written };
      } finally {
        h.t.store.runner.shutdown();
      }
    };
    if (d.policy === "written") {
      assert.deepEqual(await writeAll(1), { made: owners.length, written: owners.length }, `${d.name}: one for each record written`);
      continue;
    }
    // None read: none made.
    sql.exec(`DELETE FROM ${d.table}`);
    assert.deepEqual(await writeAll(1), { made: 0, written: 0 }, `${d.name}: no reader read them`);
    // A reader read some: those made again, and those alone.
    const h = await anew(host);
    h.t.store.subscribe(1, 1, topicOf(how.asked), true);
    await h.t.host.time.pass(100);
    h.t.store.runner.shutdown();
    const k = kept(sql, d, station);
    assert.ok(k > 0, `${d.name}: ${how.asked} kept none of ${station}'s`);
    assert.deepEqual(await writeAll(2), { made: k, written: k }, `${d.name}: the ${k} a reader kept`);
    assert.equal(kept(sql, d, station), k);
  }
});

test("what_is_kept_made_otherwise_is_dropped_as_the_database_opens", async () => {
  const host = await everythingKept();
  const sql = sqlOf(host);
  const opened = async () => (await held(false, { host, cold: true })).t.store.runner.shutdown();
  const was = new Map(KEPT_ALL.map((d) => [d, kept(sql, d)]));
  for (const d of KEPT_ALL) assert.ok(was.get(d)! > 0, `${d.name}: nothing kept`);
  // Made the same: kept.
  await opened();
  for (const d of KEPT_ALL) assert.equal(kept(sql, d), was.get(d), `${d.name}: kept as it opened`);
  // Each made otherwise in turn: that one dropped, the others kept.
  for (const d of KEPT_ALL) {
    sql.run("UPDATE meta SET value = ? WHERE key = ?", [String(d.making + 1), `kept ${d.table}`]);
    await opened();
    for (const other of KEPT_ALL) assert.equal(kept(sql, other), other === d ? 0 : was.get(other), `${d.name} made otherwise: ${other.name}`);
    assert.equal(sql.all("SELECT value FROM meta WHERE key = ?", [`kept ${d.table}`])[0]![0], String(d.making));
    was.set(d, 0);
  }
});
