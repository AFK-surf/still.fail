// Prepare an older store's message lookup in bounded ranges. Until the scan finishes, the view answers from entries;
// afterwards it answers from the prepared keys and the keys changed by older writers.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type,name) !== undefined;

/// Whether this database uses the legacy lookup. A future version must not be read as this one.
export function hasLegacySaid(db: DatabaseSync): boolean {
  if (!exists(db,"view","legacy_said")) return false;
  if (!exists(db,"table","legacy_said_meta")) throw new Error("legacy said view has no metadata");
  const m = db.prepare("SELECT version,scanned FROM legacy_said_meta WHERE id=1").get() as { version: number; scanned: number } | undefined;
  if (!m || m.version !== VERSION || (m.scanned !== 0 && m.scanned !== 1)) throw new Error("legacy said view has an unsupported version");
  return true;
}

/// First find the newest current changed message. The prepared arm need only seek keys at least that new: without
/// that bound it walks an entire changed tail before the UNION can return its newest row. `except` is a trigger's row.
export function legacySaidLatest(except?: string): string {
  const exceptEntry = except ? ` AND e.n != ${except}` : "";
  const exceptPrepared = except ? ` AND s.n != ${except}` : "";
  return `WITH dirty_latest AS MATERIALIZED (
    SELECT e.n,e.author_kind,e.author FROM legacy_said_meta m CROSS JOIN legacy_said_dirty d
      CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n
    WHERE m.id=1 AND m.scanned=1 AND d.thread=?1 AND e.kind='message' AND e.letter IS NULL${exceptEntry}
    ORDER BY d.n DESC LIMIT 1
  )
  SELECT n,author_kind,author FROM dirty_latest
  UNION ALL
  SELECT n,author_kind,author FROM (
    SELECT s.n,s.author_kind,s.author FROM legacy_said_meta m CROSS JOIN legacy_said_build s
    WHERE m.id=1 AND m.scanned=1 AND s.thread=?1${exceptPrepared}
      AND s.n >= COALESCE((SELECT n FROM dirty_latest), -9223372036854775808)
      AND NOT EXISTS (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=s.thread AND d.n=s.n)
    ORDER BY s.n DESC LIMIT 1
  )
  UNION ALL
  SELECT n,author_kind,author FROM (
    SELECT e.n,e.author_kind,e.author FROM legacy_said_meta m CROSS JOIN entries e
    WHERE m.id=1 AND m.scanned=0 AND e.thread=?1 AND e.kind='message' AND e.letter IS NULL${exceptEntry}
    ORDER BY e.n DESC LIMIT 1
  )
  ORDER BY n DESC LIMIT 1`;
}
export const LEGACY_SAID_LATEST = legacySaidLatest();
export const LEGACY_SAID_SCAN = "SELECT n, author_kind, author FROM legacy_said WHERE thread = ?1 AND n < ?2 ORDER BY n DESC LIMIT ?3";

// Mark before the entry changes. The view reads marked keys from entries, so it remains correct regardless of the
// order in which other triggers run, and even if INSERT OR IGNORE never runs an AFTER INSERT trigger. A REPLACE may
// remove several rows without firing their DELETE triggers, including one identified only by its rowid. Do not fold
// a key from an AFTER trigger: a nested write could clear the outer write's mark before that outer write takes effect.
const conflicts = `SELECT e.thread,e.n FROM (
  SELECT rowid AS id FROM entries WHERE thread=NEW.thread AND n=NEW.n
  UNION SELECT rowid FROM entries INDEXED BY entries_ts WHERE NEW.ts IS NOT NULL AND thread=NEW.thread AND ts=NEW.ts
  UNION SELECT rowid FROM entries WHERE rowid=NEW.rowid
) p CROSS JOIN entries e ON e.rowid=p.id WHERE e.kind='message' AND e.letter IS NULL`;
const mark = (keys: string) => `INSERT INTO legacy_said_dirty(thread,n)
  SELECT k.thread,k.n FROM (${keys}) k WHERE NOT EXISTS
    (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=k.thread AND d.n=k.n);`;
// An edit or letter with a new key has no ordinary-message lookup to change. A conflicting ordinary row is marked by
// `conflicts`; an already marked key stays marked across nested writes, even when the new row is not a message.
const newKey = "SELECT NEW.thread AS thread,NEW.n AS n WHERE NEW.kind='message' AND NEW.letter IS NULL";
const oldKey = "SELECT OLD.thread AS thread,OLD.n AS n WHERE OLD.kind='message' AND OLD.letter IS NULL";
const changed = `OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid
  OR OLD.kind IS NOT NEW.kind OR OLD.letter IS NOT NEW.letter OR OLD.author_kind IS NOT NEW.author_kind
  OR OLD.author IS NOT NEW.author OR OLD.ts IS NOT NEW.ts`;

// Count the prepared range once, subtract changed keys that were present there, then add their current entries. This
// avoids probing the dirty table for every old message; both correction arms seek only this thread and range.
const notSelf = (alias: string) => `NOT (${alias}.author_kind='person' AND ${alias}.author IN (SELECT value FROM json_each(?3)))`;
const preparing = "(SELECT scanned FROM legacy_said_meta WHERE id=1)=0";
export const LEGACY_UNREAD = `SELECT CASE WHEN ${preparing} THEN
  (SELECT COUNT(*) FROM entries e WHERE e.thread=?1 AND e.n>?2 AND e.kind='message' AND e.letter IS NULL AND ${notSelf("e")})
  ELSE
  (SELECT COUNT(*) FROM legacy_said_build s WHERE s.thread=?1 AND s.n>?2 AND ${notSelf("s")})
  - (SELECT COUNT(*) FROM legacy_said_dirty d CROSS JOIN legacy_said_build s ON s.thread=d.thread AND s.n=d.n
      WHERE d.thread=?1 AND d.n>?2 AND ${notSelf("s")})
  + (SELECT COUNT(*) FROM legacy_said_dirty d CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n
      WHERE d.thread=?1 AND d.n>?2 AND e.kind='message' AND e.letter IS NULL AND ${notSelf("e")}) END AS c`;
export const LEGACY_HAS_UNREAD = `SELECT CASE WHEN ${preparing} THEN EXISTS
    (SELECT 1 FROM entries e WHERE e.thread=?1 AND e.n>?2 AND e.kind='message' AND e.letter IS NULL AND ${notSelf("e")})
  WHEN EXISTS
    (SELECT 1 FROM legacy_said_dirty WHERE thread=?1 AND n>?2)
  THEN EXISTS (SELECT 1 FROM legacy_said s WHERE s.thread=?1 AND s.n>?2 AND ${notSelf("s")})
  ELSE EXISTS (SELECT 1 FROM legacy_said_build s WHERE s.thread=?1 AND s.n>?2 AND ${notSelf("s")}) END AS c`;
/// Begin without scanning old messages. The view answers from the old table until the prepared keys are complete.
/// Its metadata is the outer loop of each arm: otherwise SQLite can visit an entire chat in an inactive arm.
/// `preferNative` handles an older station installing its native index while this one was about to prepare.
export function installLegacySaid(db: DatabaseSync, preferNative = false): boolean {
  if (exists(db,"table","legacy_said_meta")) {
    if (!hasLegacySaid(db)) throw new Error("legacy said metadata has no view");
    return true;
  }
  if (!exists(db,"index","entries_ts")) throw new Error("legacy said preparation requires entries_ts");
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!exists(db,"table","legacy_said_meta") && !(preferNative && exists(db,"index","entries_said"))) db.exec(`
      CREATE TABLE legacy_said_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,scanned INTEGER NOT NULL,
        cursor_thread INTEGER,cursor_n INTEGER,end_thread INTEGER,end_n INTEGER) WITHOUT ROWID;
      INSERT INTO legacy_said_meta VALUES(1,${VERSION},0,NULL,NULL,
        (SELECT thread FROM entries ORDER BY thread DESC,n DESC LIMIT 1),
        (SELECT n FROM entries ORDER BY thread DESC,n DESC LIMIT 1));
      CREATE TABLE legacy_said_build(thread INTEGER NOT NULL,n INTEGER NOT NULL,author_kind TEXT NOT NULL,author TEXT NOT NULL,
        PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TABLE legacy_said_dirty(thread INTEGER NOT NULL,n INTEGER NOT NULL,PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TRIGGER legacy_said_before_insert BEFORE INSERT ON entries BEGIN ${mark(`${newKey} UNION ${conflicts}`)} END;
      CREATE TRIGGER legacy_said_before_update BEFORE UPDATE ON entries
        WHEN ${changed} BEGIN ${mark(`${oldKey} UNION ${newKey} UNION ${conflicts}`)} END;
      CREATE TRIGGER legacy_said_before_delete BEFORE DELETE ON entries BEGIN ${mark(oldKey)} END;
      CREATE VIEW legacy_said AS
        SELECT e.thread,e.n,e.author_kind,e.author FROM legacy_said_meta m CROSS JOIN entries e
          WHERE m.id=1 AND m.scanned=0 AND e.kind='message' AND e.letter IS NULL
        UNION ALL
        SELECT s.thread,s.n,s.author_kind,s.author FROM legacy_said_meta m CROSS JOIN legacy_said_build s
          WHERE m.id=1 AND m.scanned=1
            AND NOT EXISTS (SELECT 1 FROM legacy_said_dirty d WHERE d.thread=s.thread AND d.n=s.n)
        UNION ALL
        SELECT d.thread,d.n,e.author_kind,e.author FROM legacy_said_meta m CROSS JOIN legacy_said_dirty d
          CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n
          WHERE m.id=1 AND m.scanned=1 AND e.kind='message' AND e.letter IS NULL;
    `);
    db.exec("COMMIT");
    const installed = hasLegacySaid(db);
    if (!installed && exists(db,"table","legacy_said_meta")) throw new Error("legacy said metadata has no view");
    return installed;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Meta = { version: number; scanned: number; cursor_thread: string | null; cursor_n: string | null;
  end_thread: string | null; end_n: string | null };
type Entry = { thread: string; n: string; kind: string; letter: string | null; author_kind: string; author: string };
const meta = (db: DatabaseSync) => db.prepare(`SELECT version,scanned,CAST(cursor_thread AS TEXT) cursor_thread,
  CAST(cursor_n AS TEXT) cursor_n,CAST(end_thread AS TEXT) end_thread,CAST(end_n AS TEXT) end_n
  FROM legacy_said_meta WHERE id=1`).get() as Meta;
const limitOf = (limit: number) => {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("said batch must be 1–64");
};

/// Prepare at most one bounded key range; the same transaction protects its cursor and staged rows.
export function legacySaidStep(db: DatabaseSync, limit = BATCH): { ready: boolean; visited: number } {
  limitOf(limit);
  installLegacySaid(db);
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error(`legacy said version ${m.version} is incompatible with ${VERSION}`);
    if (m.scanned) { db.exec("COMMIT"); return { ready: true,visited: 0 }; }
    const columns = "CAST(e.thread AS TEXT) thread,CAST(e.n AS TEXT) n,e.kind,e.letter,e.author_kind,e.author";
    const rows: Entry[] = [];
    if (m.end_thread !== null) {
      if (m.cursor_thread !== null) {
        const same = m.cursor_thread === m.end_thread;
        const sql = `SELECT ${columns} FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n>CAST(?2 AS INTEGER)
          ${same ? "AND e.n<=CAST(?3 AS INTEGER) ORDER BY e.n LIMIT ?4" : "ORDER BY e.n LIMIT ?3"}`;
        rows.push(...(same ? db.prepare(sql).all(m.cursor_thread,m.cursor_n,m.end_n,limit)
          : db.prepare(sql).all(m.cursor_thread,m.cursor_n,limit)) as Entry[]);
      }
      if (rows.length < limit && m.cursor_thread !== m.end_thread) {
        const sql = `SELECT ${columns} FROM entries e WHERE e.thread<CAST(?1 AS INTEGER)
          ${m.cursor_thread === null ? "" : "AND e.thread>CAST(?2 AS INTEGER)"}
          ORDER BY e.thread,e.n LIMIT ?${m.cursor_thread === null ? 2 : 3}`;
        rows.push(...(m.cursor_thread === null ? db.prepare(sql).all(m.end_thread,limit-rows.length)
          : db.prepare(sql).all(m.end_thread,m.cursor_thread,limit-rows.length)) as Entry[]);
        if (rows.length < limit) rows.push(...db.prepare(`SELECT ${columns} FROM entries e
          WHERE e.thread=CAST(?1 AS INTEGER) AND e.n<=CAST(?2 AS INTEGER) ORDER BY e.n LIMIT ?3`)
          .all(m.end_thread,m.end_n,limit-rows.length) as Entry[]);
      }
    }
    const put = db.prepare(`INSERT INTO legacy_said_build VALUES(CAST(? AS INTEGER),CAST(? AS INTEGER),?,?)
      ON CONFLICT(thread,n) DO UPDATE SET author_kind=excluded.author_kind,author=excluded.author`);
    for (const row of rows) if (row.kind === "message" && row.letter === null) put.run(row.thread,row.n,row.author_kind,row.author);
    const last = rows.at(-1);
    const ready = rows.length < limit;
    db.prepare("UPDATE legacy_said_meta SET scanned=?,cursor_thread=CAST(? AS INTEGER),cursor_n=CAST(? AS INTEGER) WHERE id=1")
      .run(ready ? 1 : 0,last?.thread ?? m.cursor_thread,last?.n ?? m.cursor_n);
    db.exec("COMMIT");
    return { ready,visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// The scan's last batch atomically makes the prepared arms of the view visible.
export function publishLegacySaid(db: DatabaseSync): boolean {
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error(`legacy said version ${m.version} is incompatible with ${VERSION}`);
    if (!hasLegacySaid(db)) throw new Error("legacy said metadata has no view");
    db.exec("COMMIT");
    return m.scanned === 1;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// Fold no more than `limit` dirty keys back into the shadow, including keys left by ignored writes or deletes.
export function legacySaidDrain(db: DatabaseSync, limit = BATCH): number {
  limitOf(limit);
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error(`legacy said version ${m.version} is incompatible with ${VERSION}`);
    const keys = db.prepare(`SELECT CAST(thread AS TEXT) thread,CAST(n AS TEXT) n FROM legacy_said_dirty
      ORDER BY thread,n LIMIT ?`).all(limit) as { thread: string; n: string }[];
    const drop = db.prepare("DELETE FROM legacy_said_build WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)");
    const put = db.prepare(`INSERT INTO legacy_said_build(thread,n,author_kind,author)
      SELECT thread,n,author_kind,author FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)
        AND kind='message' AND letter IS NULL`);
    const done = db.prepare("DELETE FROM legacy_said_dirty WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)");
    for (const key of keys) { drop.run(key.thread,key.n); put.run(key.thread,key.n); done.run(key.thread,key.n); }
    db.exec("COMMIT");
    return keys.length;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// Check only the metadata and the first changed key. A previous connection can write without a local notification.
export function legacySaidNeedsWork(db: DatabaseSync): boolean {
  if (!hasLegacySaid(db)) return false;
  return db.prepare(`SELECT 1 FROM legacy_said_meta WHERE id=1 AND
    (scanned=0 OR EXISTS (SELECT 1 FROM legacy_said_dirty LIMIT 1))`).get() !== undefined;
}

/// One low-priority transaction: finish the old scan first, then fold changed keys in bounded batches.
export function legacySaidMaintenanceStep(db: DatabaseSync): { done: boolean; visited: number } {
  if (!hasLegacySaid(db)) return { done: true, visited: 0 };
  if (!meta(db).scanned) {
    const result = legacySaidStep(db);
    return { done: false, visited: result.visited };
  }
  const visited = legacySaidDrain(db);
  return { done: visited < BATCH, visited };
}
