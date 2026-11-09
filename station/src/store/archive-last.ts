// Find an old chat's latest message in small slices when its tail of edits is long. Auto-archive needs its time and
// notifications need its key; a per-chat guard is invalidated by old writers.
import type { DatabaseSync, StatementSync } from "node:sqlite";

const BATCH = 64;
const VERSION = 1;
const MARK = "archive_last_v1";
const checked = new WeakMap<DatabaseSync, number>();
const nativeIndexes = new WeakMap<DatabaseSync, { version: number; ready: boolean }>();
const statements = new WeakMap<DatabaseSync, Map<string, StatementSync>>();
const statement = (db: DatabaseSync, sql: string): StatementSync => {
  let cached = statements.get(db);
  if (!cached) { cached = new Map(); statements.set(db, cached); }
  let result = cached.get(sql);
  if (!result) { result = db.prepare(sql); cached.set(sql, result); }
  return result;
};
const names = ["archive_last_insert", "archive_last_update", "archive_last_delete", "archive_last_thread_delete"];
const schema = (db: DatabaseSync) => Number(statement(db, "PRAGMA schema_version").get()!.schema_version);
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT sql FROM sqlite_master WHERE type=? AND name=?").get(type, name) as { sql: string } | undefined;

const sameVictim = `(EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.n=NEW.n AND e.kind='message')
  OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e
    WHERE e.thread=NEW.thread AND e.ts=NEW.ts AND e.kind='message')))`;
const rowidVictim = "SELECT e.thread FROM entries e WHERE e.rowid=NEW.rowid AND e.kind='message'";
const triggers = `
CREATE TRIGGER archive_last_insert BEFORE INSERT ON entries
  WHEN EXISTS (SELECT 1 FROM archive_last_guard LIMIT 1) BEGIN
  -- ${MARK}
  DELETE FROM archive_last_guard WHERE thread=NEW.thread AND (NEW.kind='message' OR ${sameVictim});
  DELETE FROM archive_last_guard WHERE thread=(${rowidVictim});
END;
CREATE TRIGGER archive_last_update BEFORE UPDATE OF thread,n,rowid,_rowid_,oid,kind,at,ts ON entries
  WHEN EXISTS (SELECT 1 FROM archive_last_guard LIMIT 1) AND
    (OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid OR OLD.kind IS NOT NEW.kind
      OR OLD.at IS NOT NEW.at OR OLD.ts IS NOT NEW.ts) BEGIN
  -- ${MARK}
  DELETE FROM archive_last_guard WHERE thread=OLD.thread AND OLD.kind='message';
  DELETE FROM archive_last_guard WHERE thread=NEW.thread AND (NEW.kind='message' OR ${sameVictim});
  DELETE FROM archive_last_guard WHERE thread=(${rowidVictim} AND OLD.rowid IS NOT NEW.rowid);
END;
CREATE TRIGGER archive_last_delete BEFORE DELETE ON entries
  WHEN OLD.kind='message' BEGIN
  -- ${MARK}
  DELETE FROM archive_last_guard WHERE thread=OLD.thread;
END;
CREATE TRIGGER archive_last_thread_delete AFTER DELETE ON threads BEGIN
  -- ${MARK}
  DELETE FROM archive_last_guard WHERE thread=OLD.id;
END;`;

/// Install without reading history. If another opener removed a guard trigger, change the epoch before restoring it:
/// answers produced while the trigger was absent cannot be trusted, but old rows need not be deleted all at once.
export function installArchiveLast(db: DatabaseSync, repair = true): boolean {
  const initial = schema(db);
  if (checked.get(db) === initial) return true;
  const current = () => {
    if (!exists(db, "table", "archive_last_meta") || !exists(db, "table", "archive_last_guard")) return false;
    const version = db.prepare("SELECT version FROM archive_last_meta WHERE id=1").get() as { version: number } | undefined;
    if (!version) return false;
    if (version.version !== VERSION) throw new Error("archive last metadata has an unsupported version");
    return names.every((name) => exists(db, "trigger", name)?.sql.includes(MARK));
  };
  if (current()) { checked.set(db, initial); return true; }
  if (!repair || db.isTransaction) return false;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!current()) {
      db.exec(`CREATE TABLE IF NOT EXISTS archive_last_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
          epoch TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS archive_last_guard(thread INTEGER PRIMARY KEY,epoch TEXT NOT NULL,
          before_n INTEGER,at INTEGER,ready INTEGER NOT NULL) WITHOUT ROWID;`);
      const version = db.prepare("SELECT version FROM archive_last_meta WHERE id=1").get() as { version: number } | undefined;
      if (version && version.version !== VERSION) throw new Error(`archive last version ${version.version} is incompatible`);
      db.prepare(`INSERT INTO archive_last_meta VALUES(1,?,lower(hex(randomblob(16))))
        ON CONFLICT(id) DO UPDATE SET epoch=excluded.epoch`).run(VERSION);
      for (const name of names) db.exec(`DROP TRIGGER IF EXISTS ${name}`);
      db.exec(triggers);
    }
    db.exec("COMMIT");
    checked.set(db, schema(db));
    return true;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export const ARCHIVE_LAST_FIRST = `SELECT CASE WHEN e.kind='message' THEN CAST(e.n AS TEXT) END AS n,
    CASE WHEN e.kind='message' THEN e.at END AS at
  FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT 1`;
export const ARCHIVE_LAST_TAIL = `WITH tail AS MATERIALIZED (
    SELECT e.n,e.kind,e.at FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT 65
  ), last AS MATERIALIZED (SELECT n,at FROM tail WHERE kind='message' ORDER BY n DESC LIMIT 1)
  SELECT (SELECT CAST(n AS TEXT) FROM last) AS n,(SELECT at FROM last) AS at,(SELECT COUNT(*) FROM tail) AS count`;
export const ARCHIVE_LAST_GUARD = `SELECT CAST(g.before_n AS TEXT) AS n,g.at FROM archive_last_meta m CROSS JOIN archive_last_guard g
  WHERE m.id=1 AND g.thread=? AND g.epoch=m.epoch AND g.ready=1`;
export const ARCHIVE_LAST_SLICE_FIRST = `SELECT CAST(e.n AS TEXT) AS n,CASE WHEN e.kind='message' THEN e.at END AS at
  FROM entries e WHERE e.thread=? ORDER BY e.n DESC LIMIT ?`;
export const ARCHIVE_LAST_SLICE_BEFORE = `SELECT CAST(e.n AS TEXT) AS n,CASE WHEN e.kind='message' THEN e.at END AS at
  FROM entries e WHERE e.thread=?1 AND e.n<CAST(?2 AS INTEGER) ORDER BY e.n DESC LIMIT ?3`;
export const ARCHIVE_LAST_SAID_KEY = `SELECT CAST(e.n AS TEXT) AS n,e.at FROM entries e INDEXED BY entries_said
  WHERE e.thread=? AND e.kind='message' AND e.letter IS NULL ORDER BY e.n DESC LIMIT 1`;
export const ARCHIVE_LAST_LETTER_AFTER = `SELECT 1 FROM entries e INDEXED BY entries_letters
  WHERE e.thread=?1 AND e.n>CAST(?2 AS INTEGER) AND e.letter IS NOT NULL ORDER BY e.n DESC LIMIT 1`;
export const ARCHIVE_LAST_LETTER_ANY = `SELECT 1 FROM entries e INDEXED BY entries_letters
  WHERE e.thread=? AND e.letter IS NOT NULL ORDER BY e.n DESC LIMIT 1`;

type Last = { known: boolean; at: number | null; n: string | null };

// With both native indexes, an ordinary message is certainly last if no later entry has letter metadata at all.
// Do not filter by kind here: many non-message entries with letter metadata must not become an unbounded scan.
function nativeLastKey(db: DatabaseSync, thread: number, version: number): Last {
  let indexes = nativeIndexes.get(db);
  if (!indexes || indexes.version !== version) {
    indexes = { version, ready: !!exists(db, "index", "entries_said") && !!exists(db, "index", "entries_letters") };
    nativeIndexes.set(db, indexes);
  }
  if (!indexes.ready) return { known: false, at: null, n: null };
  const said = statement(db, ARCHIVE_LAST_SAID_KEY).get(thread) as { n: string; at: number } | undefined;
  const letter = said ? statement(db, ARCHIVE_LAST_LETTER_AFTER).get(thread, said.n)
    : statement(db, ARCHIVE_LAST_LETTER_ANY).get(thread);
  return letter ? { known: false, at: null, n: null } : { known: true, at: said?.at ?? null, n: said?.n ?? null };
}

/// Read one snapshot. Older workers stored only the time in a ready guard; it remains useful to auto-archive, but a
/// notification needing the key must prepare that chat again. The key is kept as text until SQL compares it.
function archiveLast(db: DatabaseSync, thread: number, needKey: boolean): Last {
  if (!installArchiveLast(db, false)) return { known: false, at: null, n: null };
  const version = checked.get(db)!;
  db.exec("SAVEPOINT archive_last_read");
  try {
    // Pin the database snapshot before checking the schema and any cached answer.
    const meta = statement(db, "SELECT version FROM archive_last_meta WHERE id=1").get() as { version: number } | undefined;
    if (!meta) { checked.delete(db); return { known: false, at: null, n: null }; }
    if (schema(db) !== version) return { known: false, at: null, n: null };
    if (meta.version !== VERSION) throw new Error(`archive last version ${meta.version} is incompatible`);
    const first = statement(db, ARCHIVE_LAST_FIRST).get(thread) as { n: string | null; at: number | null } | undefined;
    if (!first) return { known: true, at: null, n: null };
    if (first.at !== null) return { known: true, at: first.at, n: first.n };
    const cached = statement(db, ARCHIVE_LAST_GUARD).get(thread) as { n: string | null; at: number | null } | undefined;
    if (cached && (!needKey || cached.at === null || cached.n !== null)) return { known: true, at: cached.at, n: cached.n };
    if (needKey) {
      const native = nativeLastKey(db, thread, version);
      if (native.known) return native;
    }
    const tail = statement(db, ARCHIVE_LAST_TAIL).get(thread) as { n: string | null; at: number | null; count: number };
    if (tail.at !== null || tail.count < 65) return { known: true, at: tail.at, n: tail.n };
    return { known: false, at: null, n: null };
  } catch (error) {
    if (/no such table: archive_last_(meta|guard)/.test((error as Error).message)) {
      checked.delete(db);
      return { known: false, at: null, n: null };
    }
    throw error;
  } finally { db.exec("RELEASE archive_last_read"); }
}

/// An unknown time waits for the requested chat before it may be archived.
export function archiveLastRead(db: DatabaseSync, thread: number): { known: boolean; at: number | null } {
  const { known, at } = archiveLast(db, thread, false);
  return { known, at };
}

/// The same guarded answer for a reader that needs the complete message.
export function archiveLastKey(db: DatabaseSync, thread: number): { known: boolean; n: string | null } {
  const { known, n } = archiveLast(db, thread, true);
  return { known, n };
}

/// Each transaction advances at most 64 source entries. Progress is shared between openers and rolls back with them.
export function archiveLastStep(db: DatabaseSync, thread: number, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("archive last batch must be 1–64");
  if (!installArchiveLast(db)) return { done: false, visited: 0 };
  const version = checked.get(db)!;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (schema(db) !== version) { db.exec("COMMIT"); return { done: false, visited: 0 }; }
    const meta = db.prepare("SELECT version,epoch FROM archive_last_meta WHERE id=1").get() as
      { version: number; epoch: string } | undefined;
    if (!meta) { db.exec("COMMIT"); checked.delete(db); return { done: false, visited: 0 }; }
    if (meta.version !== VERSION) throw new Error("archive last metadata has an unsupported version");
    const epoch = meta.epoch;
    db.prepare(`INSERT INTO archive_last_guard(thread,epoch,before_n,at,ready) VALUES(?,?,NULL,NULL,0)
      ON CONFLICT(thread) DO UPDATE SET epoch=excluded.epoch,before_n=NULL,at=NULL,ready=0
        WHERE archive_last_guard.epoch!=excluded.epoch`).run(thread, epoch);
    const state = db.prepare(`SELECT CAST(before_n AS TEXT) AS before_n,at,ready FROM archive_last_guard
      WHERE thread=? AND epoch=?`).get(thread, epoch) as { before_n: string | null; at: number | null; ready: number };
    // A ready guard from the earlier time-only worker has no key. Reuse its time for archive reads, but rescan it
    // when a message is requested. Older workers ignore before_n on ready rows, so they can share the same guard.
    if (state.ready && (state.before_n !== null || state.at === null)) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = (state.before_n === null
      ? db.prepare(ARCHIVE_LAST_SLICE_FIRST).all(thread, limit)
      : db.prepare(ARCHIVE_LAST_SLICE_BEFORE).all(thread, state.before_n, limit)) as { n: string; at: number | null }[];
    const last = rows.find((row) => row.at !== null);
    const done = last !== undefined || rows.length < limit;
    db.prepare(`UPDATE archive_last_guard SET before_n=CAST(? AS INTEGER),at=?,ready=? WHERE thread=? AND epoch=?`)
      .run(last?.n ?? (done ? null : rows.at(-1)!.n), last?.at ?? null, done ? 1 : 0, thread, epoch);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
