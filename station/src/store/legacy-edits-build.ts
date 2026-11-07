// Prepare an older store's edit lookup in bounded ranges without holding a writer over its whole history.
import type { DatabaseSync, StatementSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type,name) !== undefined;

type MergedView = { version: number; legacy: boolean; indexed: boolean; oldIndexMissing: boolean };
const mergedViews = new WeakMap<DatabaseSync, MergedView>();
const schemaStatements = new WeakMap<DatabaseSync, StatementSync>();

function mergedView(db: DatabaseSync): MergedView {
  let schema = schemaStatements.get(db);
  if (!schema) { schema = db.prepare("PRAGMA schema_version"); schemaStatements.set(db, schema); }
  const version = Number(schema.get()!.schema_version);
  let view = mergedViews.get(db);
  if (!view || view.version !== version) {
    const sql = db.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql;
    const legacy = typeof sql === "string" && sql.includes("legacy_edit_meta");
    view = { version, legacy, indexed: exists(db, "index", "entries_edits"),
      oldIndexMissing: legacy && typeof sql === "string" && sql.includes("INDEXED BY entries_target") && !hasOldEditIndex(db) };
    mergedViews.set(db, view);
  }
  return view;
}

/// A view whose required index disappeared must be switched before it can read edits safely.
export function legacyMergedNeedsRepair(db: DatabaseSync): boolean {
  const view = mergedView(db);
  return view.oldIndexMissing || (!view.legacy && !view.indexed);
}

/// A single merged-message lookup is bounded once the old scan has finished and at most one batch of changed keys
/// remains. Inspect the actual view: another connection can create a native index before rebuilding that view.
/// Call inside the same snapshot as the message read.
export function legacyMergedReadReady(db: DatabaseSync): boolean {
  const view = mergedView(db);
  if (view.oldIndexMissing) return false;
  if (!view.legacy) return view.indexed;
  const row = db.prepare(`SELECT scanned=1 AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty LIMIT 1 OFFSET 64) AS ready
    FROM legacy_edit_meta WHERE id=1`).get();
  if (!row) throw new Error("legacy edit lookup metadata is missing");
  return row.ready === 1;
}

export function hasLegacyEdits(db: DatabaseSync): boolean {
  if (!exists(db,"table","legacy_edit_meta")) return false;
  const m = db.prepare("SELECT version,scanned,old_index FROM legacy_edit_meta WHERE id=1").get() as
    { version: number; scanned: number; old_index: number } | undefined;
  if (!m || m.version !== VERSION || (m.scanned !== 0 && m.scanned !== 1) || (m.old_index !== 0 && m.old_index !== 1))
    throw new Error("legacy edit lookup has an unsupported version");
  return true;
}

export function hasOldEditIndex(db: DatabaseSync): boolean {
  const columns = db.prepare("SELECT name,coll FROM pragma_index_xinfo('entries_target') WHERE \"key\"=1 ORDER BY seqno")
    .all() as { name: string; coll: string }[];
  if (columns.length !== 2 || columns[0]?.name !== "thread" || columns[0]?.coll !== "BINARY" || columns[1]?.name !== "target" || columns[1]?.coll !== "BINARY") return false;
  try {
    db.prepare("EXPLAIN QUERY PLAN SELECT MAX(n) FROM entries INDEXED BY entries_target WHERE thread=? AND target=?").all(0,0);
    return true;
  } catch { return false; }
}

export function legacyEditsUseOldIndex(db: DatabaseSync): boolean {
  if (!hasLegacyEdits(db)) throw new Error("legacy edit lookup has not been installed");
  return db.prepare("SELECT old_index FROM legacy_edit_meta WHERE id=1").get()!.old_index === 1;
}

// The fallback uses the old index when one exists while the bounded scan is incomplete. In the prepared branch the
// newest changed candidate bounds the prepared seek. Every arm reads the same SQLite snapshot. `filter` is a trusted
// SQL predicate on entry alias x, for callers such as the card lookup that need an eligible edit.
export function legacyEditLatest(thread: string, target: string, filter = "1", oldIndex = true): string {
  const eligible = filter === "1" ? "" : ` AND (${filter})`;
  const preparedEntry = filter === "1" ? "" : " CROSS JOIN entries x ON x.thread=s.thread AND x.n=s.n";
  // The old (thread,target) index is also ordered by rowid. One current row supplies a lower bound for both arms;
  // it need not have the highest n. If there is no current row, neither arm walks changed-away targets.
  const witness = oldIndex ? `witness AS MATERIALIZED (
    SELECT x.n FROM entries x INDEXED BY entries_target WHERE x.thread=${thread} AND x.target=${target}${eligible}
      ORDER BY x.rowid DESC LIMIT 1
  ), ` : "";
  const fromWitness = oldIndex ? "witness w CROSS JOIN " : "";
  const dirtyBound = oldIndex ? " AND t.n>=w.n" : "";
  const preparedBound = oldIndex ? "w.n" : "-9223372036854775808";
  const witnessResult = oldIndex ? "SELECT n FROM witness UNION ALL" : "";
  return `CASE WHEN (SELECT scanned FROM legacy_edit_meta WHERE id=1)=0 THEN
    (SELECT x.n FROM entries x${oldIndex ? " INDEXED BY entries_target" : ""} WHERE x.thread=${thread} AND x.target=${target}${eligible}
      ORDER BY x.n DESC LIMIT 1)
  WHEN NOT EXISTS (SELECT 1 FROM legacy_edit_dirty LIMIT 1) THEN
    (SELECT s.n FROM legacy_edit_build s${preparedEntry}
      WHERE s.thread=${thread} AND s.target=${target}${eligible} ORDER BY s.n DESC LIMIT 1)
  WHEN NOT EXISTS (SELECT 1 FROM legacy_edit_targets t WHERE t.thread=${thread} AND t.target=${target}) THEN
    (SELECT s.n FROM legacy_edit_build s${preparedEntry}
      WHERE s.thread=${thread} AND s.target=${target}${eligible}
        AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty d WHERE d.thread=s.thread AND d.n=s.n)
      ORDER BY s.n DESC LIMIT 1)
  ELSE (WITH ${witness}dirty_latest AS MATERIALIZED (
    SELECT x.n FROM ${fromWitness}legacy_edit_meta m CROSS JOIN legacy_edit_targets t
      CROSS JOIN entries x ON x.thread=t.thread AND x.n=t.n
    WHERE m.id=1 AND m.scanned=1 AND t.thread=${thread} AND t.target=${target} AND x.target=t.target${eligible}${dirtyBound}
    ORDER BY t.n DESC LIMIT 1
  ) SELECT n FROM (
    ${witnessResult}
    SELECT n FROM dirty_latest
    UNION ALL
    SELECT n FROM (SELECT s.n FROM ${fromWitness}legacy_edit_meta m CROSS JOIN legacy_edit_build s${preparedEntry}
      WHERE m.id=1 AND m.scanned=1 AND s.thread=${thread} AND s.target=${target}${eligible}
        AND s.n>=COALESCE((SELECT n FROM dirty_latest),${preparedBound})
        AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty d WHERE d.thread=s.thread AND d.n=s.n)
      ORDER BY s.n DESC LIMIT 1)
  ) ORDER BY n DESC LIMIT 1) END`;
}

const conflicts = `SELECT e.thread,e.n FROM (
  SELECT rowid AS id FROM entries WHERE thread=NEW.thread AND n=NEW.n
  UNION SELECT rowid FROM entries INDEXED BY entries_ts WHERE NEW.ts IS NOT NULL AND thread=NEW.thread AND ts=NEW.ts
  UNION SELECT rowid FROM entries WHERE rowid=NEW.rowid
) p CROSS JOIN entries e ON e.rowid=p.id WHERE e.target IS NOT NULL`;
const newKey = "SELECT NEW.thread AS thread,NEW.n AS n WHERE NEW.target IS NOT NULL";
const oldKey = "SELECT OLD.thread AS thread,OLD.n AS n WHERE OLD.target IS NOT NULL";
const proposed = "SELECT NEW.thread AS thread,NEW.target AS target,NEW.n AS n WHERE NEW.target IS NOT NULL";
const displacesEdit = `(EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.n=NEW.n AND e.target IS NOT NULL)
  OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.ts=NEW.ts AND e.target IS NOT NULL))
  OR EXISTS (SELECT 1 FROM entries e WHERE e.rowid=NEW.rowid AND e.target IS NOT NULL))`;
// Keep the first old target, and remember every current or proposed target before the write. This preserves reads
// through nested replacements and ignored writes; reconciliation must not clear a mark inside an entry trigger.
const mark = (keys: string, includeProposed: boolean) => `INSERT INTO legacy_edit_dirty(thread,n,old_target)
  SELECT k.thread,k.n,e.target FROM (${keys}) k LEFT JOIN entries e ON e.thread=k.thread AND e.n=k.n
  WHERE k.thread IS NOT NULL AND k.n IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty d WHERE d.thread=k.thread AND d.n=k.n);
  INSERT INTO legacy_edit_targets(thread,target,n)
    SELECT t.thread,t.target,t.n FROM (
      SELECT e.thread,e.target,e.n FROM (${keys}) k JOIN entries e ON e.thread=k.thread AND e.n=k.n
        WHERE e.target IS NOT NULL
      ${includeProposed ? `UNION ${proposed}` : ""}
    ) t WHERE t.thread IS NOT NULL AND t.n IS NOT NULL AND t.target IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM legacy_edit_targets x WHERE x.thread=t.thread AND x.target=t.target AND x.n=t.n);`;
const markNew = `INSERT INTO legacy_edit_dirty(thread,n,old_target)
  SELECT NEW.thread,NEW.n,e.target FROM (SELECT 1) x LEFT JOIN entries e ON e.thread=NEW.thread AND e.n=NEW.n
  WHERE NEW.thread IS NOT NULL AND NEW.n IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty d WHERE d.thread=NEW.thread AND d.n=NEW.n);
  INSERT INTO legacy_edit_targets(thread,target,n) SELECT NEW.thread,NEW.target,NEW.n
  WHERE NEW.thread IS NOT NULL AND NEW.n IS NOT NULL AND NEW.target IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM legacy_edit_targets x WHERE x.thread=NEW.thread AND x.target=NEW.target AND x.n=NEW.n);`;
const changed = `OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid
  OR OLD.target IS NOT NEW.target OR OLD.ts IS NOT NEW.ts`;

export function installLegacyEdits(db: DatabaseSync, preferNative = false): boolean {
  if (hasLegacyEdits(db)) return true;
  if (!exists(db,"index","entries_ts")) throw new Error("legacy edit preparation requires entries_ts");
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!hasLegacyEdits(db) && !(preferNative && exists(db,"index","entries_edits"))) {
      const oldIndex = hasOldEditIndex(db);
      db.exec(`
      CREATE TABLE legacy_edit_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,scanned INTEGER NOT NULL,old_index INTEGER NOT NULL,
        cursor_thread INTEGER,cursor_n INTEGER,end_thread INTEGER,end_n INTEGER) WITHOUT ROWID;
      INSERT INTO legacy_edit_meta VALUES(1,${VERSION},0,${oldIndex ? 1 : 0},NULL,NULL,
        (SELECT thread FROM entries ORDER BY thread DESC,n DESC LIMIT 1),
        (SELECT n FROM entries ORDER BY thread DESC,n DESC LIMIT 1));
      CREATE TABLE legacy_edit_build(thread INTEGER NOT NULL,target INTEGER NOT NULL,n INTEGER NOT NULL,
        PRIMARY KEY(thread,target,n)) WITHOUT ROWID;
      CREATE TABLE legacy_edit_dirty(thread INTEGER NOT NULL,n INTEGER NOT NULL,old_target INTEGER,
        PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TABLE legacy_edit_targets(thread INTEGER NOT NULL,target INTEGER NOT NULL,n INTEGER NOT NULL,
        PRIMARY KEY(thread,target,n)) WITHOUT ROWID;
      CREATE INDEX legacy_edit_targets_by_key ON legacy_edit_targets(thread,n,target);
      CREATE TRIGGER legacy_edit_before_insert BEFORE INSERT ON entries WHEN NEW.target IS NOT NULL BEGIN ${markNew} END;
      CREATE TRIGGER legacy_edit_before_insert_conflict BEFORE INSERT ON entries WHEN ${displacesEdit}
        BEGIN ${mark(conflicts,false)} END;
      CREATE TRIGGER legacy_edit_before_update BEFORE UPDATE ON entries WHEN (${changed}) AND
        (OLD.target IS NOT NULL OR NEW.target IS NOT NULL OR ${displacesEdit})
        BEGIN ${mark(`${oldKey} UNION ${newKey} UNION ${conflicts}`,true)} END;
      CREATE TRIGGER legacy_edit_before_delete BEFORE DELETE ON entries WHEN OLD.target IS NOT NULL BEGIN ${mark(oldKey,false)} END;
    `);
    }
    db.exec("COMMIT");
    return hasLegacyEdits(db);
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Meta = { version: number; scanned: number; cursor_thread: string | null; cursor_n: string | null;
  end_thread: string | null; end_n: string | null };
type Key = { thread: string; n: string };
const meta = (db: DatabaseSync) => db.prepare(`SELECT version,scanned,CAST(cursor_thread AS TEXT) cursor_thread,
  CAST(cursor_n AS TEXT) cursor_n,CAST(end_thread AS TEXT) end_thread,CAST(end_n AS TEXT) end_n
  FROM legacy_edit_meta WHERE id=1`).get() as Meta;
const limitOf = (limit: number) => {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("edit batch must be 1–64");
};

export function legacyEditStep(db: DatabaseSync, limit = BATCH): { ready: boolean; visited: number } {
  limitOf(limit);
  installLegacyEdits(db);
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error("unsupported legacy edit preparation");
    if (m.scanned) { db.exec("COMMIT"); return { ready: true,visited: 0 }; }
    const columns = "CAST(e.thread AS TEXT) thread,CAST(e.n AS TEXT) n";
    const rows: Key[] = [];
    if (m.end_thread !== null) {
      if (m.cursor_thread !== null) {
        const same = m.cursor_thread === m.end_thread;
        const sql = `SELECT ${columns} FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n>CAST(?2 AS INTEGER)
          ${same ? "AND e.n<=CAST(?3 AS INTEGER) ORDER BY e.n LIMIT ?4" : "ORDER BY e.n LIMIT ?3"}`;
        rows.push(...(same ? db.prepare(sql).all(m.cursor_thread,m.cursor_n,m.end_n,limit)
          : db.prepare(sql).all(m.cursor_thread,m.cursor_n,limit)) as Key[]);
      }
      if (rows.length < limit && m.cursor_thread !== m.end_thread) {
        const sql = `SELECT ${columns} FROM entries e WHERE e.thread<CAST(?1 AS INTEGER)
          ${m.cursor_thread === null ? "" : "AND e.thread>CAST(?2 AS INTEGER)"}
          ORDER BY e.thread,e.n LIMIT ?${m.cursor_thread === null ? 2 : 3}`;
        rows.push(...(m.cursor_thread === null ? db.prepare(sql).all(m.end_thread,limit-rows.length)
          : db.prepare(sql).all(m.end_thread,m.cursor_thread,limit-rows.length)) as Key[]);
        if (rows.length < limit) rows.push(...db.prepare(`SELECT ${columns} FROM entries e
          WHERE e.thread=CAST(?1 AS INTEGER) AND e.n<=CAST(?2 AS INTEGER) ORDER BY e.n LIMIT ?3`)
          .all(m.end_thread,m.end_n,limit-rows.length) as Key[]);
      }
    }
    // Keep target values inside SQLite: old stores can contain non-integer values and integers outside JS's range.
    const put = db.prepare(`INSERT INTO legacy_edit_build(thread,target,n)
      SELECT e.thread,e.target,e.n FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n=CAST(?2 AS INTEGER)
        AND e.target IS NOT NULL AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty d WHERE d.thread=e.thread AND d.n=e.n)
      ON CONFLICT(thread,target,n) DO NOTHING`);
    for (const row of rows) put.run(row.thread,row.n);
    const last = rows.at(-1), ready = rows.length < limit;
    db.prepare("UPDATE legacy_edit_meta SET scanned=?,cursor_thread=CAST(? AS INTEGER),cursor_n=CAST(? AS INTEGER) WHERE id=1")
      .run(ready ? 1 : 0,last?.thread ?? m.cursor_thread,last?.n ?? m.cursor_n);
    db.exec("COMMIT");
    return { ready,visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function legacyEditDrain(db: DatabaseSync, limit = BATCH): number {
  limitOf(limit);
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error("unsupported legacy edit preparation");
    if (!m.scanned) { db.exec("COMMIT"); return 0; }
    const first = db.prepare("SELECT CAST(d.thread AS TEXT) thread,CAST(d.n AS TEXT) n FROM legacy_edit_dirty d ORDER BY d.thread,d.n LIMIT 1");
    // A key can have arbitrarily many proposed targets. Remove at most this batch's budget before folding the key.
    const extras = db.prepare(`SELECT target FROM legacy_edit_targets INDEXED BY legacy_edit_targets_by_key
      WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER)
        AND target IS NOT (SELECT target FROM entries WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER))
      ORDER BY target LIMIT ?3`);
    extras.setReadBigInts(true);
    const dropTarget = db.prepare("DELETE FROM legacy_edit_targets WHERE thread=CAST(? AS INTEGER) AND target IS ? AND n=CAST(? AS INTEGER)");
    const drop = db.prepare(`DELETE FROM legacy_edit_build WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER)
      AND target IS (SELECT old_target FROM legacy_edit_dirty WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER))`);
    const put = db.prepare(`INSERT INTO legacy_edit_build(thread,target,n)
      SELECT thread,target,n FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)
        AND target IS NOT NULL ON CONFLICT(thread,target,n) DO NOTHING`);
    const dropCurrent = db.prepare(`DELETE FROM legacy_edit_targets WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER)
      AND target IS (SELECT target FROM entries WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER))`);
    const done = db.prepare("DELETE FROM legacy_edit_dirty WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)");
    let visited = 0;
    while (visited < limit) {
      const key = first.get() as Key | undefined;
      if (!key) break;
      const oldTargets = extras.all(key.thread,key.n,limit-visited) as { target: string | number | bigint | Uint8Array }[];
      for (const target of oldTargets) { dropTarget.run(key.thread,target.target,key.n); visited++; }
      if (visited === limit) break;
      drop.run(key.thread,key.n); put.run(key.thread,key.n); dropCurrent.run(key.thread,key.n); done.run(key.thread,key.n);
      visited++;
    }
    db.exec("COMMIT");
    return visited;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function legacyEditsNeedsWork(db: DatabaseSync): boolean {
  return hasLegacyEdits(db) && db.prepare(`SELECT 1 FROM legacy_edit_meta WHERE id=1 AND
    (scanned=0 OR EXISTS (SELECT 1 FROM legacy_edit_dirty LIMIT 1))`).get() !== undefined;
}

export function legacyEditsMaintenanceStep(db: DatabaseSync): { done: boolean; visited: number } {
  if (!hasLegacyEdits(db)) return { done: true,visited: 0 };
  if (!meta(db).scanned) {
    const result=legacyEditStep(db);
    return { done: false,visited: result.visited };
  }
  const visited=legacyEditDrain(db);
  return { done: visited < BATCH,visited };
}
