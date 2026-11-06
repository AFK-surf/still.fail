// An old store can prepare its per-chat people-time lookup without indexing all entries during open.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
export const PEOPLE_TIME_SAMPLE_LIMIT = BATCH + 1;
export const PEOPLE_TIME_PENDING = "people time pending:";
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type, name) !== undefined;

export const hasNativePeopleSince = (db: DatabaseSync): boolean => exists(db,"index","entries_people_since");
export function hasLegacyPeopleSince(db: DatabaseSync): boolean {
  if (!exists(db,"table","legacy_people_time_meta")) return false;
  const row = db.prepare("SELECT version FROM legacy_people_time_meta WHERE id=1").get() as { version: number } | undefined;
  if (!row || row.version !== VERSION) throw new Error("legacy people-time lookup has an unsupported version");
  return true;
}

/// The requested chat's people since a time; the source row is still authoritative.
const legacyFrom = `FROM legacy_people_time_rows k INDEXED BY legacy_people_time_by_at
  CROSS JOIN entries e ON e.rowid=k.source_rowid
  WHERE k.thread=?1 AND k.at>=?2 AND e.thread=k.thread AND e.n=k.n AND e.at=k.at
    AND e.kind='message' AND e.author_kind='person'`;
export const LEGACY_PEOPLE_SINCE = `SELECT e.thread,e.n ${legacyFrom}`;
export const LEGACY_HAS_PEOPLE_SINCE = `SELECT 1 ${legacyFrom} LIMIT 1`;
export const LEGACY_FIRST_PERSON_SINCE = `SELECT MIN(e.n) AS n ${legacyFrom}`;
export const LEGACY_PEOPLE_AFTER = `SELECT e.thread,e.n ${legacyFrom} AND e.n>?3 ORDER BY e.n`;

// Every direct small-chat probe is itself limited; the caller asks the builder if it sees the extra row. Keep
// comparisons in SQLite and return only selected keys, so unrelated 64-bit values need not be decoded by Node.
const sample = `WITH sample AS MATERIALIZED (SELECT n,kind,author_kind,at FROM entries WHERE thread=?1 ORDER BY n LIMIT ${PEOPLE_TIME_SAMPLE_LIMIT})`;
const recent = "kind='message' AND author_kind='person' AND at>=?2";
export const SMALL_PEOPLE_HAS = `${sample} SELECT COUNT(*) AS seen,MAX(CASE WHEN ${recent} THEN 1 ELSE 0 END) AS yes FROM sample`;
export const SMALL_PEOPLE_FIRST = `${sample} SELECT COUNT(*) AS seen,
  CASE WHEN COUNT(*)<${PEOPLE_TIME_SAMPLE_LIMIT} THEN MIN(CASE WHEN ${recent} THEN n END) END AS n FROM sample`;
export const SMALL_PEOPLE_AFTER = `${sample}
  SELECT ?1 AS thread,CASE WHEN (SELECT COUNT(*) FROM sample)<${PEOPLE_TIME_SAMPLE_LIMIT} THEN n END AS n,
    (SELECT COUNT(*) FROM sample) AS seen FROM sample WHERE ${recent} AND n>?3
  UNION ALL SELECT ?1,NULL,(SELECT COUNT(*) FROM sample) ORDER BY n`;

// A replacement may displace a row by number, timestamp or rowid without firing DELETE triggers. Reconcile these
// keys after the write, when ignored writes leave no trigger work and nested writes have their actual source rows.
const candidates = (p: string) => `SELECT rowid AS id FROM entries WHERE thread=${p}.thread AND n=${p}.n
  UNION SELECT rowid FROM entries INDEXED BY entries_ts WHERE ${p}.ts IS NOT NULL AND thread=${p}.thread AND ts=${p}.ts
  UNION SELECT rowid FROM entries WHERE rowid=${p}.rowid`;
const remove = (p: string) => `DELETE FROM legacy_people_time_rows WHERE thread=${p}.thread AND n=${p}.n;
  DELETE FROM legacy_people_time_rows WHERE source_rowid=${p}.rowid;
  DELETE FROM legacy_people_time_rows WHERE ${p}.ts IS NOT NULL AND thread=${p}.thread AND ts=${p}.ts;`;
const add = (ids: string) => `INSERT INTO legacy_people_time_rows(source_rowid,thread,n,at,ts)
  SELECT e.rowid,e.thread,e.n,e.at,e.ts FROM (${ids}) p CROSS JOIN entries e ON e.rowid=p.id
  WHERE e.kind='message' AND e.author_kind='person'
    AND EXISTS (SELECT 1 FROM legacy_people_time_scopes s WHERE s.thread=e.thread)
    AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.source_rowid=e.rowid)
    AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.thread=e.thread AND k.n=e.n);`;
const changed = `OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid
  OR OLD.ts IS NOT NEW.ts OR OLD.at IS NOT NEW.at OR OLD.kind IS NOT NEW.kind OR OLD.author_kind IS NOT NEW.author_kind`;

const LEGACY_PEOPLE_TIME_SCHEMA = `
CREATE TABLE legacy_people_time_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL) WITHOUT ROWID;
INSERT INTO legacy_people_time_meta VALUES(1,${VERSION});
CREATE TABLE legacy_people_time_scopes(thread INTEGER PRIMARY KEY,last_n INTEGER,end_n INTEGER,complete INTEGER NOT NULL) WITHOUT ROWID;
CREATE TABLE legacy_people_time_rows(source_rowid INTEGER PRIMARY KEY,thread INTEGER NOT NULL,n INTEGER NOT NULL,at INTEGER NOT NULL,ts TEXT);
CREATE UNIQUE INDEX legacy_people_time_by_entry ON legacy_people_time_rows(thread,n);
CREATE INDEX legacy_people_time_by_at ON legacy_people_time_rows(thread,at);
CREATE INDEX legacy_people_time_by_ts ON legacy_people_time_rows(thread,ts) WHERE ts IS NOT NULL;
CREATE TRIGGER legacy_people_time_insert AFTER INSERT ON entries WHEN
  EXISTS (SELECT 1 FROM legacy_people_time_scopes WHERE thread=NEW.thread)
  OR EXISTS (SELECT 1 FROM legacy_people_time_rows WHERE source_rowid=NEW.rowid) BEGIN
  ${remove("NEW")}
  ${add(candidates("NEW"))}
END;
CREATE TRIGGER legacy_people_time_update AFTER UPDATE ON entries WHEN (${changed}) AND (
  EXISTS (SELECT 1 FROM legacy_people_time_scopes WHERE thread IN (OLD.thread,NEW.thread))
  OR EXISTS (SELECT 1 FROM legacy_people_time_rows WHERE source_rowid=NEW.rowid)) BEGIN
  ${remove("OLD")}
  ${remove("NEW")}
  ${add(`${candidates("OLD")} UNION ${candidates("NEW")}`)}
END;
CREATE TRIGGER legacy_people_time_delete AFTER DELETE ON entries WHEN
  EXISTS (SELECT 1 FROM legacy_people_time_scopes WHERE thread=OLD.thread)
  OR EXISTS (SELECT 1 FROM legacy_people_time_rows WHERE source_rowid=OLD.rowid) BEGIN
  ${remove("OLD")}
  ${add(candidates("OLD"))}
END;
CREATE TRIGGER legacy_people_time_drop_thread AFTER DELETE ON threads
WHEN NOT EXISTS (SELECT 1 FROM entries WHERE thread=OLD.id LIMIT 1) BEGIN
  DELETE FROM legacy_people_time_scopes WHERE thread=OLD.id;
END;`;

/// A new or small store keeps the native index. A large old store prepares only requested chats.
export function installPeopleSinceIndex(db: DatabaseSync): void {
  if (hasNativePeopleSince(db) || hasLegacyPeopleSince(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!hasNativePeopleSince(db) && !hasLegacyPeopleSince(db)) {
      if (db.prepare("SELECT 1 FROM entries LIMIT 1 OFFSET 63").get() === undefined)
        db.exec("CREATE INDEX IF NOT EXISTS entries_people_since ON entries (thread, at) WHERE author_kind = 'person' AND kind = 'message'");
      else db.exec(LEGACY_PEOPLE_TIME_SCHEMA);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Scope = { last_n: string | null; end_n: string | null; complete: number };
const scope = (db: DatabaseSync, thread: number): Scope | undefined => db.prepare(`SELECT CAST(last_n AS TEXT) AS last_n,
  CAST(end_n AS TEXT) AS end_n,complete FROM legacy_people_time_scopes WHERE thread=?`).get(thread) as Scope | undefined;

export function peopleSinceReady(db: DatabaseSync, thread: number): boolean {
  if (hasNativePeopleSince(db)) return true;
  if (!hasLegacyPeopleSince(db)) return false;
  return scope(db,thread)?.complete === 1;
}

/// Save at most 64 old entries of the requested chat. The triggers keep changed rows current between slices.
export function peopleSinceStep(db: DatabaseSync, thread: number, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("people-time batch must be 1–64");
  installPeopleSinceIndex(db);
  if (hasNativePeopleSince(db)) return { done: true, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    if (hasNativePeopleSince(db)) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    if (!hasLegacyPeopleSince(db)) { db.exec("COMMIT"); return { done: false, visited: 0 }; }
    if (!scope(db,thread)) {
      // A queued request may outlive a chat deletion. Do not recreate a scope after both the chat and its entries go.
      if (db.prepare("SELECT 1 FROM threads WHERE id=?").get(thread) === undefined &&
          db.prepare("SELECT 1 FROM entries WHERE thread=? LIMIT 1").get(thread) === undefined) {
        db.exec("COMMIT"); return { done: true, visited: 0 };
      }
      db.prepare(`INSERT INTO legacy_people_time_scopes(thread,last_n,end_n,complete)
        VALUES(?1,NULL,(SELECT n FROM entries WHERE thread=?1 ORDER BY n DESC LIMIT 1),0)`).run(thread);
    }
    const s = scope(db,thread)!;
    if (s.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = s.end_n === null ? [] : (s.last_n === null
      ? db.prepare(`SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM entries WHERE thread=?1 AND n<=CAST(?2 AS INTEGER)
          ORDER BY n LIMIT ?3)`).all(thread,s.end_n,limit)
      : db.prepare(`SELECT CAST(n AS TEXT) AS n FROM (SELECT n FROM entries WHERE thread=?1 AND n>CAST(?2 AS INTEGER)
          AND n<=CAST(?3 AS INTEGER) ORDER BY n LIMIT ?4)`).all(thread,s.last_n,s.end_n,limit)) as { n: string }[];
    const put = db.prepare(`INSERT INTO legacy_people_time_rows(source_rowid,thread,n,at,ts)
      SELECT e.rowid,e.thread,e.n,e.at,e.ts FROM entries e WHERE e.thread=?1 AND e.n=CAST(?2 AS INTEGER)
        AND e.kind='message' AND e.author_kind='person'
        AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.source_rowid=e.rowid)
        AND NOT EXISTS (SELECT 1 FROM legacy_people_time_rows k WHERE k.thread=e.thread AND k.n=e.n)`);
    for (const row of rows) put.run(thread,row.n);
    const done = rows.length < limit;
    db.prepare("UPDATE legacy_people_time_scopes SET last_n=CAST(? AS INTEGER),complete=? WHERE thread=?")
      .run(rows.at(-1)?.n ?? s.last_n,done ? 1 : 0,thread);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}
