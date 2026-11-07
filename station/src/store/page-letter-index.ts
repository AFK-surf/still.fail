// A requested old chat's letter-message keys. The source is still entries: this shadow lets a page skip a long tail
// of non-message entries with letter metadata without creating an index over the whole database under a write lock.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
const MARK = "page_letter_v1";
const names = ["page_letter_insert", "page_letter_update", "page_letter_delete", "page_letter_thread_delete"];
const checked = new WeakMap<DatabaseSync, number>();
const missing = new WeakMap<DatabaseSync, number>();
const schema = (db: DatabaseSync) => Number(db.prepare("PRAGMA schema_version").get()!.schema_version);
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT sql FROM sqlite_master WHERE type=? AND name=?").get(type, name) as { sql: string } | undefined;

// REPLACE can displace entries without running their DELETE triggers, even in another chat through rowid. Mark before
// any write, including an ignored one: dirty keys are reconciled from the actual entries, not from the attempted row.
const conflicts = `SELECT e.thread,e.n FROM (
  SELECT rowid AS id FROM entries WHERE thread=NEW.thread AND n=NEW.n
  UNION SELECT rowid FROM entries WHERE NEW.ts IS NOT NULL AND thread=NEW.thread AND ts=NEW.ts
  UNION SELECT rowid FROM entries WHERE rowid=NEW.rowid
) p CROSS JOIN entries e ON e.rowid=p.id WHERE e.kind='message' AND e.letter IS NOT NULL`;
const newKey = "SELECT NEW.thread AS thread,NEW.n AS n WHERE NEW.kind='message' AND NEW.letter IS NOT NULL";
const oldKey = "SELECT OLD.thread AS thread,OLD.n AS n WHERE OLD.kind='message' AND OLD.letter IS NOT NULL";
const mark = (keys: string) => `INSERT INTO page_letter_dirty(thread,token,n)
  SELECT k.thread,s.token,k.n FROM (${keys}) k CROSS JOIN page_letter_scopes s ON s.thread=k.thread
  CROSS JOIN page_letter_meta m ON m.id=1 AND s.epoch=m.epoch
  WHERE NOT EXISTS (SELECT 1 FROM page_letter_dirty d WHERE d.thread=k.thread AND d.token=s.token AND d.n=k.n);`;
const changed = `OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid
  OR OLD.kind IS NOT NEW.kind OR OLD.letter IS NOT NEW.letter OR OLD.ts IS NOT NEW.ts`;
const trackedNew = `EXISTS (SELECT 1 FROM page_letter_scopes WHERE thread=NEW.thread)
  OR EXISTS (SELECT 1 FROM entries e JOIN page_letter_scopes s ON s.thread=e.thread WHERE e.rowid=NEW.rowid)`;
const queueOld = `INSERT INTO page_letter_garbage(thread,token)
  SELECT s.thread,s.token FROM page_letter_scopes s WHERE s.thread=OLD.id
    AND NOT EXISTS (SELECT 1 FROM page_letter_garbage g WHERE g.thread=s.thread AND g.token=s.token);`;
const triggers = `
CREATE TRIGGER page_letter_insert BEFORE INSERT ON entries WHEN ${trackedNew} BEGIN -- ${MARK}
  ${mark(`${newKey} UNION ${conflicts}`)} END;
CREATE TRIGGER page_letter_update BEFORE UPDATE ON entries WHEN (${changed}) AND
  ((${trackedNew}) OR EXISTS (SELECT 1 FROM page_letter_scopes WHERE thread=OLD.thread)) BEGIN -- ${MARK}
  ${mark(`${oldKey} UNION ${newKey} UNION ${conflicts}`)} END;
CREATE TRIGGER page_letter_delete BEFORE DELETE ON entries WHEN OLD.kind='message' AND OLD.letter IS NOT NULL
  AND EXISTS (SELECT 1 FROM page_letter_scopes WHERE thread=OLD.thread) BEGIN -- ${MARK}
  ${mark(oldKey)} END;
CREATE TRIGGER page_letter_thread_delete AFTER DELETE ON threads BEGIN -- ${MARK}
  ${queueOld} DELETE FROM page_letter_scopes WHERE thread=OLD.id; END;`;

/// Check the trigger set on schema changes. Repair invalidates old scopes in constant time; their rows are collected
/// in bounded batches. A reader in a snapshot may check but cannot repair the schema.
export function installPageLetterIndex(db: DatabaseSync, repair = true): boolean {
  const initial = schema(db);
  if (checked.get(db) === initial) return true;
  if (!repair && missing.get(db) === initial) return false;
  const current = () => {
    for (const name of ["page_letter_meta", "page_letter_scopes", "page_letter_rows", "page_letter_dirty", "page_letter_garbage"])
      if (!exists(db, "table", name)) return false;
    if (!exists(db, "index", "page_letter_scope_epoch")) return false;
    const meta = db.prepare("SELECT version FROM page_letter_meta WHERE id=1").get() as { version: number } | undefined;
    if (!meta) return false;
    if (meta.version !== VERSION) throw new Error(`page letter version ${meta.version} is incompatible`);
    return names.every((name) => exists(db, "trigger", name)?.sql.includes(MARK));
  };
  if (current()) { checked.set(db, initial); return true; }
  if (!repair || db.isTransaction) { missing.set(db, initial); return false; }
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!current()) {
      db.exec(`CREATE TABLE IF NOT EXISTS page_letter_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
          epoch INTEGER NOT NULL) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS page_letter_scopes(thread INTEGER PRIMARY KEY,token TEXT NOT NULL,epoch INTEGER NOT NULL,
          cursor_n INTEGER,end_n INTEGER,complete INTEGER NOT NULL) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS page_letter_scope_epoch ON page_letter_scopes(epoch,thread);
        CREATE TABLE IF NOT EXISTS page_letter_rows(thread INTEGER NOT NULL,token TEXT NOT NULL,n INTEGER NOT NULL,
          PRIMARY KEY(thread,token,n)) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS page_letter_dirty(thread INTEGER NOT NULL,token TEXT NOT NULL,n INTEGER NOT NULL,
          PRIMARY KEY(thread,token,n)) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS page_letter_garbage(thread INTEGER NOT NULL,token TEXT NOT NULL,
          PRIMARY KEY(thread,token)) WITHOUT ROWID;`);
      const meta = db.prepare("SELECT version FROM page_letter_meta WHERE id=1").get() as { version: number } | undefined;
      if (meta && meta.version !== VERSION) throw new Error(`page letter version ${meta.version} is incompatible`);
      db.prepare(`INSERT INTO page_letter_meta VALUES(1,?,1)
        ON CONFLICT(id) DO UPDATE SET epoch=epoch+1`).run(VERSION);
      for (const name of names) db.exec(`DROP TRIGGER IF EXISTS ${name}`);
      db.exec(triggers);
    }
    db.exec("COMMIT");
    checked.set(db, schema(db));
    return true;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Scope = { token: string; epoch: number; cursor_n: string | null; end_n: string | null; complete: number };
const scope = (db: DatabaseSync, thread: number) => db.prepare(`SELECT token,epoch,
  CAST(cursor_n AS TEXT) AS cursor_n,CAST(end_n AS TEXT) AS end_n,complete FROM page_letter_scopes WHERE thread=?`)
  .get(thread) as Scope | undefined;
const epochOf = (db: DatabaseSync) => (db.prepare("SELECT epoch FROM page_letter_meta WHERE id=1").get() as { epoch: number }).epoch;
const dirtyOverflow = (db: DatabaseSync, thread: number, token: string) =>
  db.prepare("SELECT 1 FROM page_letter_dirty WHERE thread=? AND token=? LIMIT 1 OFFSET 64").get(thread, token) !== undefined;

/// The metadata, dirty bound and later keyed reads must all be checked in the caller's single read snapshot.
export function pageLetterReady(db: DatabaseSync, thread: number): string | null {
  if (!installPageLetterIndex(db, false)) return null;
  const s = scope(db, thread);
  if (!s || s.epoch !== epochOf(db) || s.complete !== 1 || dirtyOverflow(db, thread, s.token)) return null;
  return s.token;
}

// Each arm is ordered by its integer key. The stale prepared keys skipped by the first arm and all dirty keys in the
// second arm total at most 64 because pageLetterReady checked the same snapshot.
export const PAGE_LETTER_KEYS = `SELECT CAST(p.n AS TEXT) AS n FROM (
    SELECT b.n FROM page_letter_rows b WHERE b.thread=?1 AND b.token=?2 AND b.n<CAST(?3 AS INTEGER)
      AND NOT EXISTS (SELECT 1 FROM page_letter_dirty d WHERE d.thread=b.thread AND d.token=b.token AND d.n=b.n)
    UNION ALL
    SELECT e.n FROM page_letter_dirty d CROSS JOIN entries e ON e.thread=d.thread AND e.n=d.n
      WHERE d.thread=?1 AND d.token=?2 AND d.n<CAST(?3 AS INTEGER) AND e.kind='message' AND e.letter IS NOT NULL
    ORDER BY n DESC LIMIT ?4
  ) p ORDER BY p.n DESC`;

function queueScope(db: DatabaseSync, thread: number, token: string): void {
  db.prepare(`INSERT INTO page_letter_garbage(thread,token) SELECT ?,?
    WHERE NOT EXISTS (SELECT 1 FROM page_letter_garbage WHERE thread=? AND token=?)`).run(thread, token, thread, token);
}

/// Scan at most 64 source keys or reconcile at most 64 changes in one transaction. A handover resumes its scope.
export function pageLetterStep(db: DatabaseSync, thread: number, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("page letter batch must be 1–64");
  if (!installPageLetterIndex(db)) return { done: false, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    const epoch = epochOf(db);
    let s = scope(db, thread);
    if (!s || s.epoch !== epoch) {
      if (s) { queueScope(db, thread, s.token); db.prepare("DELETE FROM page_letter_scopes WHERE thread=?").run(thread); }
      db.prepare(`INSERT INTO page_letter_scopes(thread,token,epoch,cursor_n,end_n,complete)
        VALUES(?,lower(hex(randomblob(16))),?,NULL,(SELECT n FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1),0)`)
        .run(thread, epoch, thread);
      s = scope(db, thread)!;
    }
    if (s.complete === 0) {
      const indexed = !!exists(db, "index", "entries_letters");
      const sql = `SELECT CAST(e.n AS TEXT) AS n,e.kind,e.letter FROM entries e ${indexed ? "INDEXED BY entries_letters" : ""}
        WHERE e.thread=?1 AND e.n<=CAST(?2 AS INTEGER) ${s.cursor_n === null ? "" : "AND e.n>CAST(?3 AS INTEGER)"}
        ${indexed ? "AND e.letter IS NOT NULL" : ""} ORDER BY e.n LIMIT ?${s.cursor_n === null ? 3 : 4}`;
      const rows = (s.cursor_n === null ? db.prepare(sql).all(thread, s.end_n, limit)
        : db.prepare(sql).all(thread, s.end_n, s.cursor_n, limit)) as { n: string; kind: string; letter: string | null }[];
      const put = db.prepare(`INSERT INTO page_letter_rows(thread,token,n) VALUES(?,?,CAST(? AS INTEGER))
        ON CONFLICT(thread,token,n) DO NOTHING`);
      for (const row of rows) if (row.kind === "message" && row.letter !== null) put.run(thread, s.token, row.n);
      db.prepare("UPDATE page_letter_scopes SET cursor_n=CAST(? AS INTEGER),complete=? WHERE thread=? AND token=?")
        .run(rows.at(-1)?.n ?? s.cursor_n, rows.length < limit ? 1 : 0, thread, s.token);
      const done = rows.length < limit && !dirtyOverflow(db, thread, s.token);
      db.exec("COMMIT");
      return { done, visited: rows.length };
    }
    const keys = db.prepare(`SELECT CAST(d.n AS TEXT) AS n FROM page_letter_dirty d
      WHERE d.thread=? AND d.token=? ORDER BY d.n LIMIT ?`).all(thread, s.token, limit) as { n: string }[];
    const drop = db.prepare("DELETE FROM page_letter_rows WHERE thread=? AND token=? AND n=CAST(? AS INTEGER)");
    const put = db.prepare(`INSERT INTO page_letter_rows(thread,token,n) SELECT e.thread,?,e.n FROM entries e
      WHERE e.thread=? AND e.n=CAST(? AS INTEGER) AND e.kind='message' AND e.letter IS NOT NULL`);
    const done = db.prepare("DELETE FROM page_letter_dirty WHERE thread=? AND token=? AND n=CAST(? AS INTEGER)");
    for (const key of keys) { drop.run(thread, s.token, key.n); put.run(s.token, thread, key.n); done.run(thread, s.token, key.n); }
    const ready = !dirtyOverflow(db, thread, s.token);
    db.exec("COMMIT");
    return { done: ready, visited: keys.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

/// Orphaned scopes and rows are reclaimed without deleting a chat's entire shadow in one foreground transaction.
export function pageLetterGcNeedsWork(db: DatabaseSync): boolean {
  if (!installPageLetterIndex(db, false)) return false;
  if (db.prepare("SELECT 1 FROM page_letter_garbage LIMIT 1").get()) return true;
  return db.prepare("SELECT 1 FROM page_letter_scopes WHERE epoch<? ORDER BY epoch,thread LIMIT 1").get(epochOf(db)) !== undefined;
}

export function pageLetterGcStep(db: DatabaseSync, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("page letter batch must be 1–64");
  if (!installPageLetterIndex(db)) return { done: true, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    const stale = db.prepare(`SELECT thread,token FROM page_letter_scopes WHERE epoch<? ORDER BY epoch,thread LIMIT 1`)
      .get(epochOf(db)) as { thread: number; token: string } | undefined;
    if (stale) {
      queueScope(db, stale.thread, stale.token);
      db.prepare("DELETE FROM page_letter_scopes WHERE thread=? AND token=?").run(stale.thread, stale.token);
    }
    const garbage = db.prepare("SELECT thread,token FROM page_letter_garbage ORDER BY thread,token LIMIT 1").get() as
      { thread: number; token: string } | undefined;
    if (!garbage) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const remove = (table: "page_letter_rows" | "page_letter_dirty", count: number) => Number(db.prepare(`DELETE FROM ${table}
      WHERE thread=?1 AND token=?2 AND n IN (SELECT n FROM ${table} WHERE thread=?1 AND token=?2 ORDER BY n LIMIT ?3)`)
      .run(garbage.thread, garbage.token, count).changes);
    const rows = remove("page_letter_rows", limit);
    const dirty = rows < limit ? remove("page_letter_dirty", limit - rows) : 0;
    if (rows + dirty < limit) db.prepare("DELETE FROM page_letter_garbage WHERE thread=? AND token=?")
      .run(garbage.thread, garbage.token);
    const remaining = db.prepare("SELECT 1 FROM page_letter_garbage LIMIT 1").get() !== undefined
      || db.prepare("SELECT 1 FROM page_letter_scopes WHERE epoch<? ORDER BY epoch,thread LIMIT 1").get(epochOf(db)) !== undefined;
    db.exec("COMMIT");
    return { done: !remaining, visited: rows + dirty };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
