// Coarser, grouped usage statistics. They are made only from usage_compact, never from the original calls.
import type { DatabaseSync } from "node:sqlite";

const key = ["session", "minute", "thread", "person", "profile", "runtime", "model", "fast"] as const;
const scopedKey = ["minute", "session", "thread", "person", "profile", "runtime", "model", "fast"] as const;
const dimensions = ["session", "thread", "person", "profile", "runtime", "model", "fast"] as const;
const values = ["calls", "input", "cache_read", "cache_write", "cache_write_long", "output"] as const;
const keyDecl = `session TEXT NOT NULL, minute INTEGER NOT NULL, thread INTEGER NOT NULL, person TEXT NOT NULL,
  profile TEXT NOT NULL, runtime TEXT NOT NULL, model TEXT NOT NULL, fast INTEGER NOT NULL`;
const dimensionsDecl = `session TEXT NOT NULL, thread INTEGER NOT NULL, person TEXT NOT NULL, profile TEXT NOT NULL,
  runtime TEXT NOT NULL, model TEXT NOT NULL, fast INTEGER NOT NULL`;
const valuesDecl = values.map((name) => `${name} INTEGER NOT NULL`).join(", ");
const sameKey = (table: string, row: string) => key.map((name) => `${table}.${name} = ${row}.${name}`).join(" AND ");
const fields = (row: string, names: readonly string[]) => names.map((name) => `${row}.${name}`).join(", ");
const BATCH = 32;
export const USAGE_SUMMARY_PENDING = "usage summary statistics are being prepared";
export const hasUsageSummaryBlocks = (db: DatabaseSync): boolean =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_summary_blocks_progress'").get() !== undefined;

/// Install empty structures and a change queue. The existence check seeks one compact row; no old calls or summaries
/// are traversed in this transaction. Updates coalesce until a worker applies their latest state.
export function installUsageSummaryBlocks(db: DatabaseSync): void {
  const has = (name: string) => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name) !== undefined;
  if (!has("usage_compact") || hasUsageSummaryBlocks(db)) return;
  const mark = (row: string, when = "1") => `INSERT INTO usage_summary_blocks_dirty (${key.join(", ")}, old_scope, new_scope)
    SELECT ${fields(row, key)},
      (SELECT scope FROM usage_summary_blocks_shadow s WHERE ${sameKey("s", row)}),
      (SELECT scope FROM usage_compact c WHERE ${sameKey("c", row)} AND c.records > 0)
    WHERE ${when}
    ON CONFLICT (${key.join(", ")}) DO UPDATE SET old_scope = excluded.old_scope, new_scope = excluded.new_scope
      WHERE usage_summary_blocks_dirty.old_scope IS NOT excluded.old_scope OR usage_summary_blocks_dirty.new_scope IS NOT excluded.new_scope;`;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (has("usage_summary_blocks_progress")) { db.exec("COMMIT"); return; }
    db.exec(`
      CREATE TABLE usage_summary_blocks_progress (id INTEGER PRIMARY KEY CHECK (id = 1), done INTEGER NOT NULL,
        after_session TEXT, after_minute INTEGER, after_thread INTEGER, after_person TEXT, after_profile TEXT,
        after_runtime TEXT, after_model TEXT, after_fast INTEGER);
      INSERT INTO usage_summary_blocks_progress (id, done) VALUES (1, NOT EXISTS (SELECT 1 FROM usage_compact LIMIT 1));
      CREATE TABLE usage_summary_blocks_scope_progress (scope TEXT PRIMARY KEY, done INTEGER NOT NULL,
        after_session TEXT, after_minute INTEGER, after_thread INTEGER, after_person TEXT, after_profile TEXT,
        after_runtime TEXT, after_model TEXT, after_fast INTEGER) WITHOUT ROWID;
      CREATE TABLE usage_summary_blocks_shadow (${keyDecl}, scope TEXT NOT NULL, ${valuesDecl},
        PRIMARY KEY (${key.join(", ")})) WITHOUT ROWID;
      CREATE INDEX usage_summary_blocks_shadow_time ON usage_summary_blocks_shadow (minute, ${dimensions.join(", ")});
      CREATE INDEX usage_summary_blocks_shadow_scope_time ON usage_summary_blocks_shadow (scope, minute, ${dimensions.join(", ")});
      CREATE TABLE usage_summary_blocks_dirty (${keyDecl}, old_scope TEXT, new_scope TEXT,
        PRIMARY KEY (${key.join(", ")})) WITHOUT ROWID;
      CREATE INDEX usage_summary_blocks_dirty_time ON usage_summary_blocks_dirty (minute, ${dimensions.join(", ")});
      CREATE INDEX usage_summary_blocks_dirty_old ON usage_summary_blocks_dirty (old_scope, minute, ${dimensions.join(", ")});
      CREATE INDEX usage_summary_blocks_dirty_new ON usage_summary_blocks_dirty (new_scope, minute, ${dimensions.join(", ")});
      CREATE TABLE usage_summary_blocks (scope TEXT NOT NULL, level INTEGER NOT NULL, bucket INTEGER NOT NULL,
        ${dimensionsDecl}, parts INTEGER NOT NULL, ${valuesDecl},
        PRIMARY KEY (scope, level, bucket, ${dimensions.join(", ")})) WITHOUT ROWID;
      CREATE INDEX usage_summary_blocks_time ON usage_summary_blocks (level, bucket, scope, ${dimensions.join(", ")});
      CREATE TRIGGER usage_summary_blocks_add AFTER INSERT ON usage_compact BEGIN ${mark("NEW")} END;
      CREATE TRIGGER usage_summary_blocks_change AFTER UPDATE OF ${[...key, "scope", "records", ...values].join(", ")} ON usage_compact
        WHEN ${[...key, "scope", "records", ...values].map((name) => `OLD.${name} IS NOT NEW.${name}`).join(" OR ")} BEGIN
          ${mark("OLD")} ${mark("NEW", key.map((name) => `OLD.${name} IS NOT NEW.${name}`).join(" OR "))}
      END;
      CREATE TRIGGER usage_summary_blocks_drop AFTER DELETE ON usage_compact BEGIN ${mark("OLD")} END;
    `);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

export type UsageSummaryKey = { session: string; minute: bigint; thread: bigint; person: string; profile: string; runtime: string; model: string; fast: bigint };
export type UsageSummaryRange = { from: bigint; to: bigint; after?: UsageSummaryKey; converted?: boolean };
type Key = UsageSummaryKey;
type Snapshot = Key & { scope: string; calls: bigint; input: bigint; cache_read: bigint; cache_write: bigint; cache_write_long: bigint; output: bigint };
type Progress = { done: bigint; after_session: string | null; after_minute: bigint | null; after_thread: bigint | null;
  after_person: string | null; after_profile: string | null; after_runtime: string | null; after_model: string | null; after_fast: bigint | null };
type Change = { scope: string; level: bigint; bucket: bigint; dimensions: (string | bigint)[]; parts: bigint } & Record<typeof values[number], bigint>;
const floorDiv = (n: bigint, d: bigint) => n >= 0n ? n / d : -1n - ((-1n - n) / d);
const argsOf = (row: Key): (string | bigint)[] => key.map((name) => row[name]);
const dimensionArgs = (row: Key): (string | bigint)[] => dimensions.map((name) => row[name]);
const serialize = (row: (string | bigint)[]) => JSON.stringify(row.map((v) => typeof v === "bigint" ? v.toString() : v));
const indexed = (db: DatabaseSync, sql: string) => { const stmt = db.prepare(sql); stmt.setReadBigInts(true); return stmt; };

/// The global cursor follows the primary key; a requested workspace seeks its own time index.
export function usageSummaryBlocksScan(scoped: boolean, after: boolean): string {
  const order = scoped ? scopedKey : key;
  const where = scoped ? "WHERE scope = ?" : "";
  const afterCursor = !after ? "" : `${scoped ? " AND" : "WHERE"} (${order.join(", ")}) > (${order.map(() => "?").join(", ")})`;
  return `SELECT ${key.join(", ")} FROM usage_compact ${scoped ? "INDEXED BY usage_compact_scope_time" : ""}
    ${where} ${afterCursor} ORDER BY ${order.join(", ")} LIMIT ?`;
}

/// Only the requested minutes, in the same order as their scope/time index.
export function usageSummaryBlocksRangeScan(scoped: boolean, after: boolean): string {
  const scope = scoped ? "scope = ? AND " : "";
  const cursor = after ? ` AND (${scopedKey.join(", ")}) > (${scopedKey.map(() => "?").join(", ")})` : "";
  return `SELECT ${key.join(", ")} FROM usage_compact INDEXED BY usage_compact_${scoped ? "scope_time" : "time"}
    WHERE ${scope}minute >= ? AND minute < ?${cursor} ORDER BY ${scopedKey.join(", ")} LIMIT ?`;
}

/// A scope can finish before the station-wide conversion. A missing cursor means it has not yet been requested.
export function usageSummaryBlocksReady(db: DatabaseSync, scope?: string): boolean {
  const progress = db.prepare("SELECT done FROM usage_summary_blocks_progress WHERE id = 1").get() as { done: number };
  if (progress.done === 1) return true;
  if (scope === undefined || scope === "G") return false;
  const scoped = db.prepare("SELECT done FROM usage_summary_blocks_scope_progress WHERE scope = ?").get(scope) as { done: number } | undefined;
  return scoped?.done === 1;
}

/// The queue is indexed for either side of a scope change. No other workspace's pending rows need be enumerated.
export function usageSummaryBlocksPending(db: DatabaseSync, scope?: string, range?: UsageSummaryRange): boolean {
  if (!usageSummaryBlocksReady(db, scope) && (range === undefined || !range.converted)) return true;
  const bounds = range === undefined ? "" : " AND minute >= ? AND minute < ?";
  const times = range === undefined ? [] : [range.from, range.to];
  if (scope === undefined || scope === "G") return range === undefined
    ? db.prepare("SELECT 1 FROM usage_summary_blocks_dirty LIMIT 1").get() !== undefined
    : db.prepare("SELECT 1 FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_time WHERE minute >= ? AND minute < ? LIMIT 1")
      .get(...times) !== undefined;
  return db.prepare(`SELECT 1 FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_old WHERE old_scope = ?${bounds} LIMIT 1`).get(scope, ...times) !== undefined
    || db.prepare(`SELECT 1 FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_new WHERE new_scope = ?${bounds} LIMIT 1`).get(scope, ...times) !== undefined;
}

/// One bounded transaction converts existing compact rows or reconciles changed ones. Shadow rows record precisely
/// what has reached the blocks, including scope and zero-valued groups; they make replacement and deletion exact.
export function usageSummaryBlocksStep(db: DatabaseSync, batch = BATCH, scope?: string, range?: UsageSummaryRange):
  { done: boolean; processed: number; after?: Key; converted?: boolean } {
  if (!Number.isSafeInteger(batch) || batch < 1) throw new RangeError("usage summary batch must be positive");
  batch = Math.min(batch, BATCH);
  db.exec("BEGIN IMMEDIATE");
  try {
    const progress = indexed(db, "SELECT * FROM usage_summary_blocks_progress WHERE id = 1").get() as Progress;
    const scoped = range === undefined && progress.done === 0n && scope !== undefined && scope !== "G";
    let cursor = progress;
    if (scoped) {
      db.prepare("INSERT OR IGNORE INTO usage_summary_blocks_scope_progress (scope, done) VALUES (?, 0)").run(scope);
      cursor = indexed(db, "SELECT * FROM usage_summary_blocks_scope_progress WHERE scope = ?").get(scope) as Progress;
    }
    const converting = range === undefined ? cursor.done === 0n : !range.converted && !usageSummaryBlocksReady(db, scope);
    const order = scoped ? scopedKey : key;
    const after = cursor.after_session === null ? [] : order.map((name) => cursor[`after_${name}`]!);
    let rows: Key[];
    if (converting && range !== undefined) {
      const onlyScope = scope !== undefined && scope !== "G";
      const afterRange = range.after === undefined ? [] : scopedKey.map((name) => range.after![name]);
      rows = indexed(db, usageSummaryBlocksRangeScan(onlyScope, range.after !== undefined))
        .all(...(onlyScope ? [scope!] : []), range.from, range.to, ...afterRange, batch) as Key[];
    } else if (converting) {
      rows = indexed(db, usageSummaryBlocksScan(scoped, cursor.after_session !== null))
        .all(...(scoped ? [scope!] : []), ...after, batch) as Key[];
    } else if (scope === undefined || scope === "G") {
      rows = range === undefined
        ? indexed(db, `SELECT ${key.join(", ")} FROM usage_summary_blocks_dirty ORDER BY ${key.join(", ")} LIMIT ?`).all(batch) as Key[]
        : indexed(db, `SELECT ${key.join(", ")} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_time
          WHERE minute >= ? AND minute < ? LIMIT ?`).all(range.from, range.to, batch) as Key[];
    } else {
      const bounds = range === undefined ? "" : " AND minute >= ? AND minute < ?";
      const times = range === undefined ? [] : [range.from, range.to];
      rows = indexed(db, `SELECT ${key.join(", ")} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_old
        WHERE old_scope = ?${bounds} LIMIT ?`).all(scope, ...times, batch) as Key[];
      if (rows.length < batch) {
        const seen = new Set(rows.map((row) => serialize(argsOf(row))));
        const next = indexed(db, `SELECT ${key.join(", ")} FROM usage_summary_blocks_dirty INDEXED BY usage_summary_blocks_dirty_new
          WHERE new_scope = ?${bounds} LIMIT ?`).all(scope, ...times, batch + rows.length) as Key[];
        for (const row of next) {
          const id = serialize(argsOf(row));
          if (!seen.has(id)) { rows.push(row); seen.add(id); }
          if (rows.length === batch) break;
        }
      }
    }
    const where = key.map((name) => `${name} = ?`).join(" AND ");
    const old = indexed(db, `SELECT ${key.join(", ")}, scope, ${values.join(", ")} FROM usage_summary_blocks_shadow WHERE ${where}`);
    const current = indexed(db, `SELECT ${key.join(", ")}, scope, ${values.join(", ")} FROM usage_compact WHERE ${where} AND records > 0`);
    const forget = db.prepare(`DELETE FROM usage_summary_blocks_shadow WHERE ${where}`);
    const clear = db.prepare(`DELETE FROM usage_summary_blocks_dirty WHERE ${where}`);
    const save = db.prepare(`INSERT INTO usage_summary_blocks_shadow (${key.join(", ")}, scope, ${values.join(", ")})
      VALUES (${[...key, "scope", ...values].map(() => "?").join(", ")}) ON CONFLICT (${key.join(", ")}) DO UPDATE SET
      scope = excluded.scope, ${values.map((name) => `${name} = excluded.${name}`).join(", ")}`);
    const changed = new Map<string, Change>();
    const add = (row: Snapshot, sign: bigint) => {
      for (const size of [15n, 60n]) {
        const bucket = floorDiv(row.minute, size);
        const dims = dimensionArgs(row);
        const id = serialize([row.scope, size, bucket, ...dims]);
        let delta = changed.get(id);
        if (delta === undefined) {
          delta = { scope: row.scope, level: size, bucket, dimensions: dims, parts: 0n,
            calls: 0n, input: 0n, cache_read: 0n, cache_write: 0n, cache_write_long: 0n, output: 0n };
          changed.set(id, delta);
        }
        delta.parts += sign;
        for (const name of values) delta[name] += sign * row[name];
      }
    };
    for (const row of rows) {
      const args = argsOf(row);
      const previous = old.get(...args) as Snapshot | undefined;
      const now = current.get(...args) as Snapshot | undefined;
      if (previous !== undefined) add(previous, -1n);
      if (now !== undefined) {
        add(now, 1n);
        save.run(...args, now.scope, ...values.map((name) => now[name]));
      } else if (previous !== undefined) forget.run(...args);
      clear.run(...args);
    }
    const columns = ["scope", "level", "bucket", ...dimensions, "parts", ...values];
    const pk = ["scope", "level", "bucket", ...dimensions];
    const put = db.prepare(`INSERT INTO usage_summary_blocks (${columns.join(", ")}) VALUES (${columns.map(() => "?").join(", ")})
      ON CONFLICT (${pk.join(", ")}) DO UPDATE SET ${["parts", ...values].map((name) => `${name} = ${name} + excluded.${name}`).join(", ")}`);
    const clean = db.prepare(`DELETE FROM usage_summary_blocks WHERE ${pk.map((name) => `${name} = ?`).join(" AND ")} AND parts = 0`);
    for (const delta of changed.values()) {
      if (delta.parts === 0n && values.every((name) => delta[name] === 0n)) continue;
      const id = [delta.scope, delta.level, delta.bucket, ...delta.dimensions];
      put.run(...id, delta.parts, ...values.map((name) => delta[name]));
      clean.run(...id);
    }
    if (range !== undefined) {
      if (converting && rows.length === batch) {
        db.exec("COMMIT");
        return { done: false, processed: rows.length, after: rows[rows.length - 1]! };
      }
      const complete = !usageSummaryBlocksPending(db, scope, { ...range, converted: true });
      db.exec("COMMIT");
      return complete ? { done: true, processed: rows.length } : { done: false, processed: rows.length, converted: true };
    }
    if (converting) {
      const table = scoped ? "usage_summary_blocks_scope_progress" : "usage_summary_blocks_progress";
      const condition = scoped ? "scope = ?" : "id = 1";
      const scopeArgs = scoped ? [scope!] : [];
      if (rows.length < batch) db.prepare(`UPDATE ${table} SET done = 1 WHERE ${condition}`).run(...scopeArgs);
      else {
        const last = rows[rows.length - 1]!;
        db.prepare(`UPDATE ${table} SET ${key.map((name) => `after_${name} = ?`).join(", ")} WHERE ${condition}`)
          .run(...argsOf(last), ...scopeArgs);
      }
    }
    const complete = !usageSummaryBlocksPending(db, scope);
    db.exec("COMMIT");
    return { done: complete, processed: rows.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
