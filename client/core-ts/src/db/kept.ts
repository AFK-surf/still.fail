// What the core makes of one record and of what else its key says, kept beside that record in the account's database
// (core-ts AGENTS.md, "What is made of a record is kept beside it"): a chat list's row beside its chat (`chat_row`),
// whether this core can read a station's overview beside it (`station_fit`), a station's accounts' rows beside its
// overview's part (`profile_row`). Each is a declaration here (KEPT); this file does for all of them what each did by
// hand: its table and the triggers that drop a value as its record changes, whoever writes it; reading one by its owner
// and key, many in one statement, or joined to a read of their records; keeping one a reader made as it read; making
// it again as its record is written, in the same burst; counting it (work.ts `<name>Kept`, `Written`, `Made`).
// test/kept.test.ts holds every declaration to what it says.
import type { Sql, SqlRow, SqlValue } from "../host.ts";
import { work } from "../work.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// Whose a kept value is: its record's key, as the kept table's owner columns hold it (one or two of them: the first
/// a station's address).
export type Owner = readonly string[];

/// A kept value's declaration.
export type Kept<V> = {
  /// Its name: what the views make it by (Data.makes) and its counters' (work.ts `<name>Kept`, `Written`, `Made`).
  readonly name: string;
  /// Its table: the owner's columns (text), the key's (what else it was made with, the views' to say), and the value's
  /// own (`columns`). `older`: columns an older core's values had beside these, kept (nullable, never written here) so
  /// that one opening the database after this one still puts and reads its own.
  readonly table: string;
  readonly owner: readonly string[];
  readonly key: string;
  readonly columns: readonly (readonly [string, string])[];
  readonly older?: readonly string[];
  /// What it is made of: the records of `table` (those `of` says, of a trigger's row `new` or `old`), its owner's
  /// columns there in the order of the kept table's, and the column whose change makes it another record (none: any).
  readonly source: { readonly table: string; readonly owner: readonly string[]; readonly of?: (row: string) => string; readonly by?: string };
  /// When it is made: `read`, as a reader first reads it, then again at every write of its record (a write costs by
  /// what was shown, not by how many records there are); `written`, at every write of its record.
  readonly policy: "read" | "written";
  /// One value an owner (a new key replaces it) or one an owner and key.
  readonly each: "owner" | "key";
  /// How it is made: raised as a value made of the same could be another (each declaration's digest test says when).
  /// What a database kept made otherwise is dropped as it opens; its key says it too.
  readonly making: number;
  /// The topic its record's writer tells as the record changes (account.ts), which a reader reads it by (Data.kept).
  readonly told?: string;
  /// Whether its record can be shown otherwise than it is held (an overview with what is being done to it here:
  /// data.ts #overlaid): then nothing kept is read.
  readonly overlaid?: boolean;
  /// Its value as the columns hold it, and back (undefined: none).
  put(value: V): SqlValue[];
  take(cells: readonly SqlValue[]): V | undefined;
};

/// How the views make a declaration's value: `key`, what else an owner's is made with now (null: not there yet);
/// `make`, its value of `record` (as account.ts holds it), null where it is not one to keep; `taken`, a value read
/// back from its columns made what one made is (frozen, its shape beside it).
export type Maker<V> = {
  key(owner: Owner): string | null;
  make(owner: Owner, record: J): V | null;
  taken?(value: V): void;
};

/// A chat list's row (views.ts #listRow) whole, as the core reads it, and as it goes out (`sent`); what its stand-in
/// says of it (`state`).
export type ListRow = { readonly state: string | null; readonly whole: J; readonly sent: J };

const json = (v: SqlValue): J => (typeof v === "string" ? JSON.parse(v) : undefined);

/// The registry: every value kept beside its record. A new one is a declaration here and an entry of
/// test/kept.test.ts's table.
export const KEPT = {
  /// Each listed chat's row (views.ts #listRow, listRowKey), kept as a list first reads it.
  listRow: {
    name: "listRow",
    table: "chat_row",
    owner: ["station", "id"],
    key: "key",
    columns: [["state", "TEXT"], ["whole", "TEXT NOT NULL"], ["sent", "TEXT NOT NULL"]],
    source: { table: "chat", owner: ["station", "id"] },
    policy: "read",
    each: "owner",
    making: 1,
    put: (v) => [v.state, JSON.stringify(v.whole), JSON.stringify(v.sent)],
    take: (c) => (typeof c[1] === "string" && typeof c[2] === "string" ? { state: typeof c[0] === "string" ? c[0] : null, whole: json(c[1]), sent: json(c[2]) } : undefined),
  } satisfies Kept<ListRow>,
  /// Whether this core can read a station's overview (views.ts OVERVIEW_FIT), judged as it is written, by the id of
  /// the shapes that judged it.
  overviewFit: {
    name: "overviewFit",
    table: "station_fit",
    owner: ["address"],
    key: "shapes",
    columns: [["readable", "INTEGER NOT NULL"]],
    source: { table: "station", owner: ["address"], of: (row) => `${row}.kind = 'overview'`, by: "json" },
    policy: "written",
    each: "key",
    making: 1,
    told: "$overview-fit",
    overlaid: true,
    put: (v) => [v ? 1 : 0],
    take: (c) => (typeof c[0] === "number" ? c[0] === 1 : undefined),
  } satisfies Kept<boolean>,
  /// A station's accounts' rows (views.ts profileRowKey) of its overview's `profiled` part, kept as the accounts' list
  /// first reads them. The part is kept in place as the overview is written (schema.ts overviewTriggers), so its rows go
  /// only as `profiled` changes, and most writes, which reach no account, keep them. (`profiled`: what the cores that
  /// made the rows of the part their `made` said, 2026-11-12, till OLDEST_CORE is past them.)
  profileRow: {
    name: "profileRow",
    table: "profile_row",
    owner: ["address"],
    key: "key",
    columns: [["rows", "TEXT NOT NULL"]],
    older: ["profiled"],
    source: { table: "station_part", owner: ["address"], by: "profiled" },
    policy: "read",
    each: "owner",
    making: 1,
    told: "$overview-profiled",
    overlaid: true,
    put: (v) => [JSON.stringify(v)],
    take: (c) => (typeof c[0] === "string" ? json(c[0]) : undefined),
  } satisfies Kept<J>,
} as const;

export type AnyKept = Kept<J>;
export const KEPT_ALL: readonly AnyKept[] = Object.values(KEPT) as AnyKept[];

const spaced = (s: string) => s.replace(/\s+/g, " ").trim();

/// `owner` = the owner of `row` (a trigger's `new` or `old`).
const ownerOf = (d: AnyKept, row: string) => d.owner.map((c, i) => `${c} = ${row}.${d.source.owner[i]}`).join(" AND ");

/// The triggers dropping a declaration's values as their record is put, changed or goes, whoever writes it (a core
/// that knows nothing of them too), by name as sqlite_master keeps them. Changed: in any column (its owner too, old and
/// new), or in `by`.
export function keptTriggers(d: AnyKept): [string, string][] {
  const s = d.source;
  const when = (...c: (string | undefined)[]) => {
    const all = c.filter((x): x is string => x !== undefined);
    return all.length === 0 ? "" : ` WHEN ${all.join(" AND ")}`;
  };
  const drop = (row: string) => `DELETE FROM ${d.table} WHERE ${ownerOf(d, row)};`;
  return [
    [`${d.table}_put`, `CREATE TRIGGER ${d.table}_put AFTER INSERT ON ${s.table}${when(s.of?.("new"))} BEGIN ${drop("new")} END`],
    [
      `${d.table}_set`,
      s.by === undefined
        ? `CREATE TRIGGER ${d.table}_set AFTER UPDATE ON ${s.table} BEGIN ${drop("old")} ${drop("new")} END`
        : `CREATE TRIGGER ${d.table}_set AFTER UPDATE OF ${s.by} ON ${s.table}${when(s.of?.("new"), `old.${s.by} IS NOT new.${s.by}`)} BEGIN ${drop("new")} END`,
    ],
    [`${d.table}_drop`, `CREATE TRIGGER ${d.table}_drop AFTER DELETE ON ${s.table}${when(s.of?.("old"))} BEGIN ${drop("old")} END`],
  ];
}

/// A declaration's table and triggers, made where missing at every open; a table not this core's (its columns
/// otherwise: an earlier core's) made again, its values with it. Where a trigger was missing or not this core's (an
/// older core made its record's table again, its triggers with it), or what is kept was made otherwise (`making`, as
/// the database's `meta` says it was made: none said, a database from before, whose values' keys say it), every value
/// kept goes, nothing left that a record outlived.
export function openKept(sql: Sql, d: AnyKept): void {
  sql.exec("BEGIN IMMEDIATE");
  try {
    const pk = d.each === "owner" ? d.owner : [...d.owner, d.key];
    const columns = [...d.owner.map((c) => `${c} TEXT NOT NULL`), `${d.key} TEXT NOT NULL`, ...d.columns.map(([c, ty]) => `${c} ${ty}`), ...(d.older ?? []).map((c) => `${c} TEXT`)];
    const table = `CREATE TABLE ${d.table} (${columns.join(", ")}, PRIMARY KEY (${pk.join(", ")}))${d.each === "key" ? " WITHOUT ROWID" : ""}`;
    const was = sql.all("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [d.table])[0]?.[0];
    const ours = was !== undefined && spaced(String(was)) === spaced(table);
    if (was !== undefined && !ours) sql.exec(`DROP TABLE ${d.table}`);
    if (!ours) sql.exec(table);
    const triggers = keptTriggers(d);
    const had = new Map(sql.all(`SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND name IN (${triggers.map(() => "?").join(", ")})`, triggers.map(([name]) => name)).map((r) => [String(r[0]), String(r[1])]));
    let remade = false;
    for (const [name, statement] of triggers) {
      const was = had.get(name);
      if (was !== undefined && spaced(was) === spaced(statement)) continue;
      if (was !== undefined) sql.exec(`DROP TRIGGER ${name}`);
      sql.exec(statement);
      remade = true;
    }
    const at = `kept ${d.table}`;
    const making = sql.all("SELECT value FROM meta WHERE key = ?", [at])[0]?.[0];
    if (remade || (making !== undefined && making !== String(d.making))) sql.exec(`DELETE FROM ${d.table}`);
    if (making !== String(d.making)) sql.run("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", [at, String(d.making)]);
    sql.exec("COMMIT");
  } catch (e) {
    try {
      sql.exec("ROLLBACK");
    } catch {
      // Rolled back already.
    }
    throw e;
  }
}

/// What a database gives the kept values: its connection, its burst (`write`: runs in the burst's transaction, none in a
/// database only read; `run`: a statement in it), its cache of what was read, and its records: as held now (read or
/// written this run, the very object a reader was given: `held`), and read (`record`, for tests).
export type KeptHost = {
  readonly sql: Sql;
  write(fn: () => void): void;
  run(sql: string, params: readonly SqlValue[]): void;
  readonly cache: { get(key: string): J; set(key: string, value: J): void; delete(key: string): void };
  held(source: string, owner: Owner): J;
  record(source: string, owner: Owner): J;
};

/// A record about to be written: the declarations it is the record of, and whether each makes its value again.
export type Writing = { readonly owner: Owner; readonly makes: [AnyKept, boolean][] };

/// What a value is cached as: its key, and it (undefined: none kept under that key).
type Cached = { key: string; value: J };

/// One database's kept values.
export class KeptValues {
  readonly #host: KeptHost;
  /// The declarations whose table is there (made at open; none in a database a newer core wrote, or without room).
  readonly #ready = new Set<AnyKept>();
  readonly #makers = new Map<AnyKept, Maker<J>>();
  /// The owners that have a value kept (`read` declarations), by declaration and the owner's first column: read of the
  /// table once a run, before the first write of one of its records (whose triggers take it), and kept since.
  readonly #held = new Map<string, Set<string>>();

  constructor(host: KeptHost) {
    this.#host = host;
  }

  /// Each declaration's table made where missing (openKept). One that cannot be made keeps nothing this time.
  open(declarations: readonly AnyKept[]): void {
    for (const d of declarations) {
      try {
        openKept(this.#host.sql, d);
        this.#ready.add(d);
      } catch {
        // No room to make it (or its record's table is missing): made as it is read, this time.
      }
    }
  }

  /// How the views make a declaration's values (none: nothing read, kept or made).
  made<V>(d: Kept<V>, maker: Maker<V> | null): void {
    if (maker === null) this.#makers.delete(d as AnyKept);
    else this.#makers.set(d as AnyKept, maker as Maker<J>);
  }

  /// Whether a declaration's values are kept here and made (its table is there, the views make it).
  keeps(d: AnyKept): boolean {
    return this.#ready.has(d) && this.#makers.has(d);
  }

  /// The key in force of an owner's value (null: none can be said now).
  keyOf(d: AnyKept, owner: Owner): string | null {
    return this.#makers.get(d)?.key(owner) ?? null;
  }

  /// How the views make a declaration's values (tests: what is kept is what is made of its record now).
  maker<V>(d: Kept<V>): Maker<V> | undefined {
    return this.#makers.get(d as AnyKept) as Maker<V> | undefined;
  }

  #cacheKey(d: AnyKept, owner: Owner): string {
    return ["kept", d.table, ...owner].join("\u0001");
  }

  /// What the cache knows of an owner's value under `key`: it (or undefined: none kept), else null (not known).
  #cached(d: AnyKept, owner: Owner, key: string): { value: J } | null {
    const c = this.#host.cache.get(this.#cacheKey(d, owner)) as Cached | undefined;
    if (c === undefined) return null;
    if (c.key === key) return { value: c.value };
    // (one an owner: another key's value kept is none of this one's)
    return d.each === "owner" && c.value !== undefined ? { value: undefined } : null;
  }

  /// A value read back from its columns, made what one made is, counted.
  #take(d: AnyKept, cells: readonly SqlValue[]): J {
    const v = d.take(cells);
    if (v === undefined) return undefined;
    (work as Record<string, number>)[`${d.name}Kept`]++;
    this.#makers.get(d)?.taken?.(v);
    return v;
  }

  /// An owner's value kept under `key` (the key in force where none is given): as read or kept this run, else read.
  one<V>(d: Kept<V>, owner: Owner, key?: string): V | undefined {
    const k = d as AnyKept;
    if (!this.keeps(k)) return undefined;
    const at = key ?? this.keyOf(k, owner);
    if (at === null) return undefined;
    const c = this.#cached(k, owner, at);
    if (c !== null) return c.value;
    const v = this.stored(d, owner, at);
    this.#host.cache.set(this.#cacheKey(k, owner), { key: at, value: v });
    return v;
  }

  /// An owner's value under `key` as the database holds it (read, the cache not looked at).
  stored<V>(d: Kept<V>, owner: Owner, key: string): V | undefined {
    const r = this.#host.sql.all(`SELECT ${d.columns.map(([c]) => `k.${c}`).join(", ")} FROM ${d.table} AS k WHERE ${d.owner.map((c) => `k.${c} = ?`).join(" AND ")} AND k.${d.key} = ?`, [...owner, key])[0];
    return r === undefined ? undefined : this.#take(d as AnyKept, r);
  }

  /// The values of `owners` kept under their keys (`keys`, each owner's): those read or kept this run, the rest read by
  /// one statement (their owners and keys as one JSON array: json_each), undefined where none is.
  many<V>(d: Kept<V>, owners: readonly Owner[], keys: readonly string[]): (V | undefined)[] {
    const k = d as AnyKept;
    const out: (V | undefined)[] = owners.map(() => undefined);
    if (!this.keeps(k)) return out;
    const missing: number[] = [];
    owners.forEach((owner, i) => {
      const c = this.#cached(k, owner, keys[i]);
      if (c === null) missing.push(i);
      else out[i] = c.value;
    });
    if (missing.length === 0) return out;
    const n = d.owner.length;
    const read = new Map<string, SqlRow>();
    const rows = this.#host.sql.all(
      `SELECT ${[...d.owner, ...d.columns.map(([c]) => c)].map((c) => `k.${c}`).join(", ")} FROM json_each(?) AS j CROSS JOIN ${d.table} AS k WHERE ${[...d.owner, d.key].map((c, i) => `k.${c} = json_extract(j.value, '$[${i}]')`).join(" AND ")}`,
      [JSON.stringify(missing.map((i) => [...owners[i], keys[i]]))],
    );
    for (const r of rows) read.set(r.slice(0, n).join("\u0001"), r);
    for (const i of missing) {
      const r = read.get(owners[i].join("\u0001"));
      const v = r === undefined ? undefined : this.#take(k, r.slice(n));
      this.#host.cache.set(this.#cacheKey(k, owners[i]), { key: keys[i], value: v });
      out[i] = v;
    }
    return out;
  }

  /// A read of records joined to their values kept under the key `key` (an expression of the read's, with its
  /// parameters where it has them: given in the read's order, the join's after its columns'): the join, and the
  /// value's columns (`width` of them), which `taken` takes of each row.
  joined(d: AnyKept, alias: string, owner: readonly string[], key: string): { join: string; columns: string; width: number } {
    return {
      join: `LEFT JOIN ${d.table} AS ${alias} ON ${d.owner.map((c, i) => `${alias}.${c} = ${owner[i]}`).join(" AND ")} AND ${alias}.${d.key} = ${key}`,
      columns: d.columns.map(([c]) => `${alias}.${c}`).join(", "),
      width: d.columns.length,
    };
  }

  /// An owner's value under `key` as a joined read gave its columns (`cells`): as read or kept this run, else of them.
  taken<V>(d: Kept<V>, owner: Owner, key: string, cells: readonly SqlValue[]): V | undefined {
    const k = d as AnyKept;
    if (!this.keeps(k)) return undefined;
    const c = this.#cached(k, owner, key);
    if (c !== null) return c.value;
    const v = this.#take(k, cells);
    this.#host.cache.set(this.#cacheKey(k, owner), { key, value: v });
    return v;
  }

  /// A value a reader made of `record` as it read it, kept beside it under `key`: only while that is still the record
  /// held (as it was read), else nothing (it was written since, its own value with it); none where it is kept already.
  keep<V>(d: Kept<V>, owner: Owner, record: J, key: string, value: V): void {
    const k = d as AnyKept;
    if (!this.keeps(k)) return;
    if (record === undefined || this.#host.held(d.source.table, owner) !== record) return;
    const c = this.#cached(k, owner, key);
    if (c !== null && c.value !== undefined) return;
    this.#host.write(() => this.#put(k, owner, key, value));
  }

  #put(d: AnyKept, owner: Owner, key: string, value: J): void {
    (work as Record<string, number>)[`${d.name}Written`]++;
    const columns = [...d.owner, d.key, ...d.columns.map(([c]) => c)];
    this.#host.run(`INSERT OR REPLACE INTO ${d.table} (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")})`, [...owner, key, ...d.put(value)]);
    this.#host.cache.set(this.#cacheKey(d, owner), { key, value });
    if (d.policy === "read") this.#heldOf(d, owner).add(owner[owner.length - 1]);
  }

  /// The owners of `owner`'s first column that have a value kept (read once a run, before the triggers take one).
  #heldOf(d: AnyKept, owner: Owner): Set<string> {
    const at = `${d.table}\u0001${owner[0]}`;
    let held = this.#held.get(at);
    if (held === undefined) {
      held = new Set(this.#host.sql.all(`SELECT ${d.owner[d.owner.length - 1]} FROM ${d.table} WHERE ${d.owner[0]} = ?`, [owner[0]]).map((r) => String(r[0])));
      this.#held.set(at, held);
    }
    return held;
  }

  /// A record of `source` about to be written (before it is, whose triggers take what was kept): which of its
  /// declarations make their value again as it is written (`written`; `read`, where one was kept).
  writing(source: string, owner: Owner): Writing {
    const makes: [AnyKept, boolean][] = [];
    for (const d of this.#ready) {
      if (d.source.table !== source || !this.#makers.has(d)) continue;
      makes.push([d, d.policy === "written" || this.#heldOf(d, owner).has(owner[owner.length - 1])]);
    }
    return { owner, makes };
  }

  /// The record `writing` said was written, as `record` gives it now (undefined: gone, or none to make a value of;
  /// asked only where a value is to be made again): what was kept of it went (the triggers), and its value is made
  /// again where `writing` said so, in the burst.
  wrote(w: Writing, record: () => J): void {
    const owner = w.owner;
    for (const [d, makes] of w.makes) {
      this.#host.cache.delete(this.#cacheKey(d, owner));
      if (!makes) continue;
      const now = record();
      if (now === undefined) {
        if (d.policy === "read") this.#heldOf(d, owner).delete(owner[owner.length - 1]);
        continue;
      }
      const maker = this.#makers.get(d)!;
      const key = maker.key(owner);
      if (key === null) continue;
      const value = maker.make(owner, now);
      if (value === null) continue;
      (work as Record<string, number>)[`${d.name}Made`]++;
      this.#put(d, owner, key, value);
    }
  }

  /// What is held of the table is not known any more (a burst rolled back, a station forgotten).
  forget(): void {
    this.#held.clear();
  }

  /// A station forgotten: every value kept of it goes.
  forgetStation(station: string): void {
    for (const d of this.#ready) this.#host.run(`DELETE FROM ${d.table} WHERE ${d.owner[0]} = ?`, [station]);
    this.#held.clear();
  }

  /// An owner's record as its database reads it now, of the source of `d` (test/kept.test.ts: what is kept is what is
  /// made of it).
  record(d: AnyKept, owner: Owner): J {
    return this.#host.record(d.source.table, owner);
  }
}
