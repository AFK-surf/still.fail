// An older store can prepare its login-card lookup without building a native index over all entries in one write.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type,name) !== undefined;

export function hasLegacyLoginCards(db: DatabaseSync): boolean {
  if (!exists(db,"table","login_card_meta")) return false;
  const m = db.prepare("SELECT version,scanned FROM login_card_meta WHERE id=1").get() as
    { version: number; scanned: number } | undefined;
  if (!m || m.version !== VERSION || (m.scanned !== 0 && m.scanned !== 1)) {
    throw new Error("legacy login-card lookup has an unsupported version");
  }
  return true;
}

// Each index on the candidates corresponds to one of entries' possible REPLACE conflicts.
const insertKeys = (ids: string) => `INSERT INTO login_card_keys(login,thread,n,entry_rowid,ts)
  SELECT k.login,k.thread,k.n,k.entry_rowid,k.ts FROM (
    WITH RECURSIVE targets AS (
      SELECT e.thread,e.n,e.rowid AS entry_rowid,e.ts,lower(e.card) AS rest
      FROM (${ids}) p CROSS JOIN entries e ON e.rowid=p.id
      WHERE e.kind='message' AND e.author_kind='agent' AND e.card LIKE '%"login"%'
    ), fragments(thread,n,entry_rowid,ts,rest) AS (
      SELECT thread,n,entry_rowid,ts,rest FROM targets
      UNION ALL
      SELECT thread,n,entry_rowid,ts,substr(rest,instr(rest,'"login":"')+9)
      FROM fragments WHERE instr(rest,'"login":"')>0
    ), tails AS (
      SELECT thread,n,entry_rowid,ts,substr(rest,instr(rest,'"login":"')+9) AS tail
      FROM fragments WHERE instr(rest,'"login":"')>0
    ), tokens AS (
      SELECT thread,n,entry_rowid,ts,substr(tail,1,instr(tail,'"')-1) AS login
      FROM tails WHERE instr(tail,'"')>0
    )
    SELECT DISTINCT login,thread,n,entry_rowid,ts FROM tokens
    WHERE length(login) BETWEEN 1 AND 40 AND login NOT GLOB '*[^0-9a-z]*'
  ) k WHERE NOT EXISTS (SELECT 1 FROM login_card_keys x WHERE x.login=k.login AND x.thread=k.thread AND x.n=k.n);`;

const idsFor = (prefix: string) => `SELECT rowid AS id FROM entries WHERE thread=${prefix}.thread AND n=${prefix}.n
  UNION SELECT rowid FROM entries WHERE rowid=${prefix}.rowid
  UNION SELECT rowid FROM entries WHERE ${prefix}.ts IS NOT NULL AND thread=${prefix}.thread AND ts=${prefix}.ts`;
const candidatesFor = (prefix: string) => `(login_card_keys.thread=${prefix}.thread AND login_card_keys.n=${prefix}.n)
  OR login_card_keys.entry_rowid=${prefix}.rowid OR (${prefix}.ts IS NOT NULL AND login_card_keys.thread=${prefix}.thread AND login_card_keys.ts=${prefix}.ts)`;
const hasCandidates = (prefix: string) => `EXISTS(SELECT 1 FROM login_card_keys WHERE ${candidatesFor(prefix)})`;
const newCard = `NEW.kind='message' AND NEW.author_kind='agent' AND NEW.card LIKE '%"login"%'`;
const removeStale = (which: string) => `DELETE FROM login_card_keys WHERE (${which}) AND NOT EXISTS (
  SELECT 1 FROM entries e WHERE e.rowid=login_card_keys.entry_rowid AND e.thread=login_card_keys.thread
    AND e.n=login_card_keys.n AND e.ts IS login_card_keys.ts AND e.kind='message' AND e.author_kind='agent'
    AND e.card LIKE '%"login":"' || login_card_keys.login || '"%');`;

// The triggers reconcile against current entries, not the triggering NEW or OLD card. Another trigger can have changed
// the row first. They run after the write, so an INSERT OR IGNORE cannot erase an existing candidate.
export const LEGACY_LOGIN_CARD_SCHEMA = `
CREATE TABLE login_card_keys(login TEXT NOT NULL,thread INTEGER NOT NULL,n INTEGER NOT NULL,entry_rowid INTEGER NOT NULL,ts TEXT,
  PRIMARY KEY(login,thread,n)) WITHOUT ROWID;
CREATE INDEX login_card_keys_by_entry ON login_card_keys(thread,n,login);
CREATE INDEX login_card_keys_by_rowid ON login_card_keys(entry_rowid,login);
CREATE INDEX login_card_keys_by_ts ON login_card_keys(thread,ts,login) WHERE ts IS NOT NULL;
CREATE TRIGGER login_card_keys_insert AFTER INSERT ON entries WHEN (${newCard}) OR ${hasCandidates("NEW")} BEGIN
  ${removeStale(candidatesFor("NEW"))}
  ${insertKeys(idsFor("NEW"))}
END;
CREATE TRIGGER login_card_keys_update_same AFTER UPDATE ON entries WHEN OLD.thread IS NEW.thread AND OLD.n IS NEW.n
  AND OLD.rowid IS NEW.rowid AND OLD.ts IS NEW.ts AND (OLD.kind IS NOT NEW.kind
  OR OLD.author_kind IS NOT NEW.author_kind OR OLD.card IS NOT NEW.card) AND ((${newCard}) OR ${hasCandidates("NEW")}) BEGIN
  ${removeStale("(login_card_keys.thread=NEW.thread AND login_card_keys.n=NEW.n)")}
  ${insertKeys("SELECT rowid AS id FROM entries WHERE thread=NEW.thread AND n=NEW.n")}
END;
CREATE TRIGGER login_card_keys_update_moved AFTER UPDATE ON entries WHEN (OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n
  OR OLD.rowid IS NOT NEW.rowid OR OLD.ts IS NOT NEW.ts) AND ((${newCard}) OR ${hasCandidates("OLD")} OR ${hasCandidates("NEW")}) BEGIN
  ${removeStale(`${candidatesFor("OLD")} OR ${candidatesFor("NEW")}`)}
  ${insertKeys(`${idsFor("OLD")} UNION ${idsFor("NEW")}`)}
END;
CREATE TRIGGER login_card_keys_delete AFTER DELETE ON entries WHEN ${hasCandidates("OLD")} BEGIN
  ${removeStale(candidatesFor("OLD"))}
  ${insertKeys(idsFor("OLD"))}
END;`;

// Both arms see one snapshot. The existing cards index is a superset while preparation is unfinished; afterwards,
// only the requested login is read. CROSS JOIN makes SQLite test readiness before it enters either source.
export const LEGACY_LOGIN_CARDS = `SELECT e.thread,e.n,e.author FROM login_card_meta m
  CROSS JOIN entries e INDEXED BY entries_cards WHERE m.id=1 AND m.scanned=0 AND e.card IS NOT NULL
    AND e.kind='message' AND e.author_kind='agent' AND e.card LIKE '%"login"%' AND e.card LIKE ?2
    AND NOT EXISTS(SELECT 1 FROM closed_cards c WHERE c.thread=e.thread AND c.n=e.n)
  UNION ALL
  SELECT e.thread,e.n,e.author FROM login_card_meta m CROSS JOIN login_card_keys k
    CROSS JOIN entries e ON e.thread=k.thread AND e.n=k.n WHERE m.id=1 AND m.scanned=1 AND k.login=?1
    AND e.kind='message' AND e.author_kind='agent' AND e.card LIKE '%"login"%' AND e.card LIKE ?2
    AND NOT EXISTS(SELECT 1 FROM closed_cards c WHERE c.thread=e.thread AND c.n=e.n)`;

// SQLite LIKE gives %, _, and quoted characters their usual meaning. Keep the former query for such inputs.
export const LEGACY_LOGIN_CARDS_FALLBACK = `SELECT thread,n,author FROM entries INDEXED BY entries_cards
  WHERE card IS NOT NULL AND kind='message' AND author_kind='agent' AND card LIKE '%"login"%' AND card LIKE ?
    AND NOT EXISTS(SELECT 1 FROM closed_cards c WHERE c.thread=entries.thread AND c.n=entries.n)`;

// Until scanned, callers use the existing card lookup. The triggers are installed before the first batch, so a previous
// writer changing even an already visited key keeps the candidates live.
type Meta = { version: number; scanned: number; end_thread: string | null; end_n: string | null;
  cursor_thread: string | null; cursor_n: string | null; offset: number | null };
type Row = { thread: string; n: string; entry_rowid: string; ts: string | null; kind: string; author_kind: string; card: string | null };
const fields = `CAST(thread AS TEXT) thread,CAST(n AS TEXT) n,CAST(rowid AS TEXT) entry_rowid,ts,kind,author_kind,
  CASE WHEN card LIKE '%"login"%' THEN CAST(card AS TEXT) END AS card`;
const readMeta = (db: DatabaseSync) => db.prepare(`SELECT version,scanned,CAST(end_thread AS TEXT) end_thread,
  CAST(end_n AS TEXT) end_n,CAST(cursor_thread AS TEXT) cursor_thread,CAST(cursor_n AS TEXT) cursor_n,offset
  FROM login_card_meta WHERE id=1`).get() as Meta;

export function installLegacyLoginCards(db: DatabaseSync, preferNative = false): boolean {
  if (hasLegacyLoginCards(db)) return true;
  db.exec("BEGIN IMMEDIATE");
  try {
    const indexed = exists(db,"index","entries_login_cards");
    if (!hasLegacyLoginCards(db) && !(preferNative && indexed)) {
      db.exec(LEGACY_LOGIN_CARD_SCHEMA);
      db.exec(`CREATE TABLE login_card_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,scanned INTEGER NOT NULL,
        end_thread INTEGER,end_n INTEGER,cursor_thread INTEGER,cursor_n INTEGER,offset INTEGER) WITHOUT ROWID;
        INSERT INTO login_card_meta VALUES(1,${VERSION},NOT EXISTS(SELECT 1 FROM entries LIMIT 1),
          (SELECT thread FROM entries ORDER BY thread DESC,n DESC LIMIT 1),
          (SELECT n FROM entries ORDER BY thread DESC,n DESC LIMIT 1),NULL,NULL,NULL);`);
    }
    db.exec("COMMIT");
    return hasLegacyLoginCards(db);
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function legacyLoginCardsStep(db: DatabaseSync, limit = 64): { ready: boolean; visited: number; tokens: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("login card batch must be 1–64");
  installLegacyLoginCards(db);
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = readMeta(db);
    if (m.version !== VERSION || (m.scanned !== 0 && m.scanned !== 1)) {
      throw new Error("unsupported login card preparation");
    }
    if (m.scanned) { db.exec("COMMIT"); return { ready: true, visited: 0, tokens: 0 }; }
    // Qualify the sort keys: the selected aliases are text for lossless JS transport, but SQLite must sort integers.
    const from = "FROM entries WHERE 1";
    const first = db.prepare(`SELECT ${fields} ${from} AND thread<=CAST(?1 AS INTEGER) ORDER BY entries.thread,entries.n LIMIT 1`);
    const same = db.prepare(`SELECT ${fields} ${from} AND thread=CAST(?1 AS INTEGER) AND n>CAST(?2 AS INTEGER) ORDER BY entries.n LIMIT 1`);
    const later = db.prepare(`SELECT ${fields} ${from} AND thread>CAST(?1 AS INTEGER) AND thread<=CAST(?2 AS INTEGER) ORDER BY entries.thread,entries.n LIMIT 1`);
    const exact = db.prepare(`SELECT ${fields} ${from} AND thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER)`);
    const put = db.prepare(`INSERT INTO login_card_keys(login,thread,n,entry_rowid,ts)
      SELECT ?1,CAST(?2 AS INTEGER),CAST(?3 AS INTEGER),CAST(?4 AS INTEGER),?5
      WHERE NOT EXISTS (SELECT 1 FROM login_card_keys WHERE login=?1 AND thread=CAST(?2 AS INTEGER) AND n=CAST(?3 AS INTEGER))`);
    let visited = 0, tokens = 0, ready = m.end_thread === null;
    while (!ready && visited < limit && tokens < limit) {
      let row: Row | undefined;
      if (m.offset !== null) {
        row = exact.get(m.cursor_thread!,m.cursor_n!) as Row | undefined;
        if (!row) { m.offset = null; continue; }
      } else {
        row = (m.cursor_thread === null ? first.get(m.end_thread!) : same.get(m.cursor_thread,m.cursor_n!)) as Row | undefined;
        if (!row && m.cursor_thread !== null) row = later.get(m.cursor_thread,m.end_thread!) as Row | undefined;
        if (!row || BigInt(row.thread) > BigInt(m.end_thread!) || (row.thread === m.end_thread && BigInt(row.n) > BigInt(m.end_n!))) {
          ready = true; break;
        }
        m.cursor_thread = row.thread; m.cursor_n = row.n; m.offset = 0;
      }
      visited++;
      if (row.kind !== "message" || row.author_kind !== "agent" || typeof row.card !== "string") { m.offset = null; continue; }
      // SQLite's default LIKE folds only ASCII. LIKE also stops at NUL, so no candidate after it can match.
      let text = row.card.replace(/[A-Z]/g, (c) => c.toLowerCase());
      const nul = text.indexOf("\0"); if (nul !== -1) text = text.slice(0,nul);
      const prefix = '"login":"';
      let offset = m.offset!;
      while (tokens < limit) {
        const start = text.indexOf(prefix,offset);
        if (start === -1) { m.offset = null; break; }
        offset = start + prefix.length;
        const end = text.indexOf('"',offset);
        const login = end === -1 ? "" : text.slice(offset,end);
        if (/^[0-9a-z]{1,40}$/.test(login)) put.run(login,row.thread,row.n,row.entry_rowid,row.ts);
        tokens++;
        m.offset = offset;
      }
    }
    db.prepare(`UPDATE login_card_meta SET scanned=?,cursor_thread=CAST(? AS INTEGER),cursor_n=CAST(? AS INTEGER),offset=? WHERE id=1`)
      .run(ready ? 1 : 0,m.cursor_thread,m.cursor_n,m.offset);
    db.exec("COMMIT");
    return { ready,visited,tokens };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function legacyLoginCardsNeedsWork(db: DatabaseSync): boolean {
  return hasLegacyLoginCards(db) && readMeta(db).scanned === 0;
}

export function legacyLoginCardsMaintenanceStep(db: DatabaseSync): { done: boolean; visited: number } {
  if (!hasLegacyLoginCards(db)) return { done: true,visited: 0 };
  const result = legacyLoginCardsStep(db);
  return { done: result.ready,visited: result.visited };
}
