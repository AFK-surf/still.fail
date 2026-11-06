// An old store can prepare the per-chat closed-card lookup without indexing its whole history during open.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
export const CLOSED_SAMPLE_LIMIT = BATCH + 1;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type, name) !== undefined;

export const CLOSED_CARDS_PENDING = "closed cards pending:";
export const CLOSED_CARDS_INDEXED = `SELECT thread,n,viewer,at,rowid AS ordering
  FROM closed_cards INDEXED BY closed_cards_thread_at WHERE thread=? AND at>=?`;
export const LEGACY_CLOSED_CARDS = `SELECT c.thread,c.n,c.viewer,c.at,c.rowid AS ordering
  FROM legacy_closed_cards k INDEXED BY legacy_closed_by_time CROSS JOIN closed_cards c ON c.rowid=k.source_rowid
  WHERE k.thread=? AND k.at>=? AND c.thread=k.thread AND c.n=k.n AND c.at=k.at`;
// Read at most one more than the cutoff, so the reader can tell whether the bounded result is complete.
export const CLOSED_CHAT_SAMPLE = `SELECT * FROM (SELECT c.thread,CASE WHEN c.at>=?2 THEN c.n END AS n,
  CASE WHEN c.at>=?2 THEN c.viewer END AS viewer,CASE WHEN c.at>=?2 THEN c.at END AS at,
  CASE WHEN c.at>=?2 THEN c.rowid END AS ordering FROM closed_cards c
  WHERE c.thread=?1 ORDER BY c.n LIMIT ${CLOSED_SAMPLE_LIMIT}) ORDER BY at,ordering`;
// Count the whole bounded window, but decode values only for requested chats: unrelated old rows can contain
// 64-bit integers which the Node SQLite driver cannot represent as JavaScript numbers.
export const CLOSED_TIME_SAMPLE = `WITH recent AS MATERIALIZED (
  SELECT thread,n,viewer,at,rowid AS ordering FROM closed_cards INDEXED BY closed_cards_at
  WHERE at>=? ORDER BY at,rowid LIMIT ${CLOSED_SAMPLE_LIMIT}
), selected AS MATERIALIZED (
  SELECT *,thread IN (SELECT value FROM json_each(?2)) AS wanted FROM recent
)
SELECT CASE WHEN wanted THEN thread END AS thread,CASE WHEN wanted THEN n END AS n,
  CASE WHEN wanted THEN viewer END AS viewer,CASE WHEN wanted THEN at END AS at,
  CASE WHEN wanted THEN ordering END AS ordering FROM selected`;

export const hasNativeClosedCards = (db: DatabaseSync) => exists(db, "index", "closed_cards_thread_at");
export const hasClosedCardsTimeIndex = (db: DatabaseSync) => exists(db, "index", "closed_cards_at");
export function hasLegacyClosedCards(db: DatabaseSync): boolean {
  if (!exists(db, "table", "legacy_closed_meta")) return false;
  const row = db.prepare("SELECT version FROM legacy_closed_meta WHERE id=1").get() as { version: number } | undefined;
  if (!row || row.version !== VERSION) throw new Error("legacy closed-card lookup has an unsupported version");
  return true;
}

// A REPLACE can remove another row by either its (thread,n) key or its rowid without a DELETE trigger. Reconcile only
// those keys against the source after each write. Unlike a BEFORE marker this leaves no debris for ignored writes.
const candidates = (p: string) => `SELECT rowid AS id FROM closed_cards WHERE thread=${p}.thread AND n=${p}.n
  UNION SELECT rowid FROM closed_cards WHERE rowid=${p}.rowid`;
const remove = (p: string) => `DELETE FROM legacy_closed_cards WHERE thread=${p}.thread AND n=${p}.n;
  DELETE FROM legacy_closed_cards WHERE source_rowid=${p}.rowid;`;
const add = (ids: string) => `INSERT INTO legacy_closed_cards(thread,at,source_rowid,n)
  SELECT c.thread,c.at,c.rowid,c.n FROM (${ids}) p CROSS JOIN closed_cards c ON c.rowid=p.id
  WHERE EXISTS (SELECT 1 FROM legacy_closed_scopes s WHERE s.thread=c.thread)
    AND NOT EXISTS (SELECT 1 FROM legacy_closed_cards k WHERE k.thread=c.thread AND k.n=c.n);`;
const changed = `OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.at IS NOT NEW.at OR OLD.rowid IS NOT NEW.rowid`;

const LEGACY_CLOSED_SCHEMA = `
CREATE TABLE legacy_closed_meta (id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL) WITHOUT ROWID;
INSERT INTO legacy_closed_meta VALUES(1,${VERSION});
CREATE TABLE legacy_closed_scopes (thread INTEGER PRIMARY KEY,last_n INTEGER,end_n INTEGER,complete INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE legacy_closed_cards (source_rowid INTEGER PRIMARY KEY,thread INTEGER NOT NULL,n INTEGER NOT NULL,at INTEGER NOT NULL);
CREATE UNIQUE INDEX legacy_closed_by_entry ON legacy_closed_cards(thread,n);
CREATE INDEX legacy_closed_by_time ON legacy_closed_cards(thread,at);
CREATE TRIGGER legacy_closed_insert AFTER INSERT ON closed_cards BEGIN
  ${remove("NEW")}
  ${add(candidates("NEW"))}
END;
CREATE TRIGGER legacy_closed_update AFTER UPDATE ON closed_cards WHEN ${changed} BEGIN
  ${remove("OLD")}
  ${remove("NEW")}
  ${add(`${candidates("OLD")} UNION ${candidates("NEW")}`)}
END;
CREATE TRIGGER legacy_closed_delete AFTER DELETE ON closed_cards BEGIN
  ${remove("OLD")}
  ${add(candidates("OLD"))}
END;`;

/// Keep the native index on small or already upgraded stores. Recheck both choices under the writer lock.
export function installClosedCardsIndex(db: DatabaseSync): void {
  if (hasNativeClosedCards(db) || hasLegacyClosedCards(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!hasNativeClosedCards(db) && !hasLegacyClosedCards(db)) {
      if (db.prepare("SELECT 1 FROM closed_cards LIMIT 1 OFFSET 63").get() === undefined)
        db.exec("CREATE INDEX IF NOT EXISTS closed_cards_thread_at ON closed_cards (thread, at)");
      else db.exec(LEGACY_CLOSED_SCHEMA);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Scope = { last_n: string | null; end_n: string | null; complete: number };
const scope = (db: DatabaseSync, thread: number): Scope | undefined => db.prepare(`SELECT CAST(last_n AS TEXT) AS last_n,
  CAST(end_n AS TEXT) AS end_n,complete FROM legacy_closed_scopes WHERE thread=?`).get(thread) as Scope | undefined;

/// An empty chat needs no saved state; the reader's snapshot also sees any concurrent close consistently.
export function closedCardsReady(db: DatabaseSync, thread: number): boolean {
  if (hasNativeClosedCards(db)) return true;
  if (hasLegacyClosedCards(db)) {
    const found = scope(db, thread);
    if (found) return found.complete === 1;
  }
  return db.prepare("SELECT 1 FROM closed_cards WHERE thread=? LIMIT 1").get(thread) === undefined;
}

/// Save at most 64 old rows for the requested chat. Triggers cover writes from older connections between slices.
export function closedCardsStep(db: DatabaseSync, thread: number, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("closed-card batch must be 1–64");
  installClosedCardsIndex(db);
  if (hasNativeClosedCards(db)) return { done: true, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    // An older connection may change the schema between the installation and this writer lock.
    if (hasNativeClosedCards(db)) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    if (!hasLegacyClosedCards(db)) { db.exec("COMMIT"); return { done: false, visited: 0 }; }
    if (!scope(db, thread)) db.prepare(`INSERT INTO legacy_closed_scopes(thread,last_n,end_n,complete)
      VALUES(?1,NULL,(SELECT n FROM closed_cards WHERE thread=?1 ORDER BY n DESC LIMIT 1),0)`).run(thread);
    const s = scope(db, thread)!;
    if (s.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = s.end_n === null ? [] : (s.last_n === null
      ? db.prepare(`SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM closed_cards WHERE thread=?1 AND n<=CAST(?2 AS INTEGER)
          ORDER BY n LIMIT ?3)`).all(thread, s.end_n, limit)
      : db.prepare(`SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM closed_cards WHERE thread=?1 AND n>CAST(?2 AS INTEGER)
          AND n<=CAST(?3 AS INTEGER) ORDER BY n LIMIT ?4)`).all(thread, s.last_n, s.end_n, limit)) as { n: string }[];
    const put = db.prepare(`INSERT INTO legacy_closed_cards(thread,at,source_rowid,n)
      SELECT c.thread,c.at,c.rowid,c.n FROM closed_cards c WHERE c.thread=?1 AND c.n=CAST(?2 AS INTEGER)
        AND NOT EXISTS (SELECT 1 FROM legacy_closed_cards k WHERE k.thread=c.thread AND k.n=c.n)`);
    for (const row of rows) put.run(thread, row.n);
    const done = rows.length < limit;
    db.prepare("UPDATE legacy_closed_scopes SET last_n=CAST(? AS INTEGER),complete=? WHERE thread=?")
      .run(rows.at(-1)?.n ?? s.last_n, done ? 1 : 0, thread);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
