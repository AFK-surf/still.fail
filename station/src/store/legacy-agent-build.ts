// An older store can keep its agent-message time lookup without building an index over every entry under one writer.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type,name) !== undefined;

export function hasLegacyAgent(db: DatabaseSync): boolean {
  if (!exists(db,"table","legacy_agent_meta")) return false;
  const m = db.prepare("SELECT version,scanned FROM legacy_agent_meta WHERE id=1").get() as { version: number; scanned: number } | undefined;
  if (!m || m.version !== VERSION || (m.scanned !== 0 && m.scanned !== 1)) throw new Error("legacy agent lookup has an unsupported version");
  return true;
}

// Once prepared, the first arm seeks just the requested time range. Dirty keys are read from their current entries;
// all arms see one SQLite snapshot, including during nested writes by a previous station.
export const LEGACY_ASKED_DURING = `SELECT MAX(n) AS n FROM (
  SELECT e.n FROM legacy_agent_meta m CROSS JOIN entries e
    WHERE m.id=1 AND m.scanned=0 AND e.thread=?1 AND e.kind='message' AND e.author_kind='agent' AND e.at>=?2 AND e.at<=?3
  UNION ALL
  SELECT s.n FROM legacy_agent_meta m CROSS JOIN legacy_agent_build s
    WHERE m.id=1 AND m.scanned=1 AND s.thread=?1 AND s.at>=?2 AND s.at<=?3
      AND NOT EXISTS (SELECT 1 FROM legacy_agent_dirty d WHERE d.thread=s.thread AND d.n=s.n)
  UNION ALL
  SELECT e.n FROM legacy_agent_meta m CROSS JOIN legacy_agent_times t
    CROSS JOIN entries e ON e.thread=t.thread AND e.n=t.n
    WHERE m.id=1 AND m.scanned=1 AND t.thread=?1 AND t.at>=?2 AND t.at<=?3
      AND e.kind='message' AND e.author_kind='agent' AND e.at=t.at
)`;

const conflicts = `SELECT e.thread,e.n FROM (
  SELECT rowid AS id FROM entries WHERE thread=NEW.thread AND n=NEW.n
  UNION SELECT rowid FROM entries INDEXED BY entries_ts WHERE NEW.ts IS NOT NULL AND thread=NEW.thread AND ts=NEW.ts
  UNION SELECT rowid FROM entries WHERE rowid=NEW.rowid
) p CROSS JOIN entries e ON e.rowid=p.id WHERE e.kind='message' AND e.author_kind='agent'`;
const newKey = "SELECT NEW.thread AS thread,NEW.n AS n WHERE NEW.kind='message' AND NEW.author_kind='agent'";
const oldKey = "SELECT OLD.thread AS thread,OLD.n AS n WHERE OLD.kind='message' AND OLD.author_kind='agent'";
const newAgent = "NEW.kind='message' AND NEW.author_kind='agent'";
const oldAgent = "OLD.kind='message' AND OLD.author_kind='agent'";
const displacesAgent = `(EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.n=NEW.n
    AND e.kind='message' AND e.author_kind='agent')
  OR (NEW.ts IS NOT NULL AND EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.ts=NEW.ts
    AND e.kind='message' AND e.author_kind='agent'))
  OR EXISTS (SELECT 1 FROM entries e WHERE e.rowid=NEW.rowid AND e.kind='message' AND e.author_kind='agent'))`;
// Keep the time of the first changed row, which is the time of its staged key if there is one. The scanner never
// stages a dirty key. This lets reconciliation delete by the time-ordered primary key without a second reverse index.
const proposedTime = "SELECT NEW.thread AS thread,NEW.at AS at,NEW.n AS n WHERE NEW.kind='message' AND NEW.author_kind='agent'";
// A BEFORE trigger records the current and proposed times. Even if a nested write replaces one before the outer write
// finishes, each possible current time stays searchable; the actual entry is checked before the result is returned.
const mark = (keys: string, proposed: boolean) => `INSERT INTO legacy_agent_dirty(thread,n,old_at)
  SELECT k.thread,k.n,e.at FROM (${keys}) k LEFT JOIN entries e ON e.thread=k.thread AND e.n=k.n
    AND e.kind='message' AND e.author_kind='agent'
  WHERE NOT EXISTS (SELECT 1 FROM legacy_agent_dirty d WHERE d.thread=k.thread AND d.n=k.n);
  INSERT INTO legacy_agent_times(thread,at,n)
    SELECT t.thread,t.at,t.n FROM (
      SELECT e.thread,e.at,e.n FROM (${keys}) k JOIN entries e ON e.thread=k.thread AND e.n=k.n
        WHERE e.kind='message' AND e.author_kind='agent'
      ${proposed ? `UNION ${proposedTime}` : ""}
    ) t WHERE NOT EXISTS (SELECT 1 FROM legacy_agent_times x WHERE x.thread=t.thread AND x.at=t.at AND x.n=t.n);`;
// An ordinary append has no displaced row. Record its key and proposed time directly, leaving the more expensive
// collision lookup to a separate trigger which runs only if a conflicting agent message actually exists.
const markNew = `INSERT INTO legacy_agent_dirty(thread,n,old_at)
  SELECT NEW.thread,NEW.n,e.at FROM (SELECT 1) x LEFT JOIN entries e ON e.thread=NEW.thread AND e.n=NEW.n
    AND e.kind='message' AND e.author_kind='agent'
  WHERE NOT EXISTS (SELECT 1 FROM legacy_agent_dirty d WHERE d.thread=NEW.thread AND d.n=NEW.n);
  INSERT INTO legacy_agent_times(thread,at,n) SELECT NEW.thread,NEW.at,NEW.n
  WHERE NOT EXISTS (SELECT 1 FROM legacy_agent_times x WHERE x.thread=NEW.thread AND x.at=NEW.at AND x.n=NEW.n);`;
const changed = `OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.rowid IS NOT NEW.rowid
  OR OLD.kind IS NOT NEW.kind OR OLD.author_kind IS NOT NEW.author_kind OR OLD.at IS NOT NEW.at OR OLD.ts IS NOT NEW.ts`;

export function installLegacyAgent(db: DatabaseSync, preferNative = false): boolean {
  if (hasLegacyAgent(db)) return true;
  if (!exists(db,"index","entries_ts")) throw new Error("legacy agent preparation requires entries_ts");
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!hasLegacyAgent(db) && !(preferNative && exists(db,"index","entries_agent_at"))) db.exec(`
      CREATE TABLE legacy_agent_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,scanned INTEGER NOT NULL,
        cursor_thread INTEGER,cursor_n INTEGER,end_thread INTEGER,end_n INTEGER) WITHOUT ROWID;
      INSERT INTO legacy_agent_meta VALUES(1,${VERSION},0,NULL,NULL,
        (SELECT thread FROM entries ORDER BY thread DESC,n DESC LIMIT 1),
        (SELECT n FROM entries ORDER BY thread DESC,n DESC LIMIT 1));
      CREATE TABLE legacy_agent_build(thread INTEGER NOT NULL,at INTEGER NOT NULL,n INTEGER NOT NULL,
        PRIMARY KEY(thread,at,n)) WITHOUT ROWID;
      CREATE TABLE legacy_agent_dirty(thread INTEGER NOT NULL,n INTEGER NOT NULL,old_at INTEGER,
        PRIMARY KEY(thread,n)) WITHOUT ROWID;
      CREATE TABLE legacy_agent_times(thread INTEGER NOT NULL,at INTEGER NOT NULL,n INTEGER NOT NULL,
        PRIMARY KEY(thread,at,n)) WITHOUT ROWID;
      CREATE INDEX legacy_agent_times_by_key ON legacy_agent_times(thread,n,at);
      CREATE TRIGGER legacy_agent_before_insert BEFORE INSERT ON entries WHEN ${newAgent} BEGIN ${markNew} END;
      CREATE TRIGGER legacy_agent_before_insert_conflict BEFORE INSERT ON entries WHEN ${displacesAgent}
        BEGIN ${mark(conflicts,false)} END;
      CREATE TRIGGER legacy_agent_before_update BEFORE UPDATE ON entries WHEN (${changed}) AND
        ((${oldAgent}) OR (${newAgent}) OR ${displacesAgent})
        BEGIN ${mark(`${oldKey} UNION ${newKey} UNION ${conflicts}`,true)} END;
      CREATE TRIGGER legacy_agent_before_delete BEFORE DELETE ON entries WHEN ${oldAgent} BEGIN ${mark(oldKey,false)} END;
    `);
    db.exec("COMMIT");
    return hasLegacyAgent(db);
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Meta = { version: number; scanned: number; cursor_thread: string | null; cursor_n: string | null;
  end_thread: string | null; end_n: string | null };
type Entry = { thread: string; n: string; at: string; kind: string; author_kind: string };
const meta = (db: DatabaseSync) => db.prepare(`SELECT version,scanned,CAST(cursor_thread AS TEXT) cursor_thread,
  CAST(cursor_n AS TEXT) cursor_n,CAST(end_thread AS TEXT) end_thread,CAST(end_n AS TEXT) end_n
  FROM legacy_agent_meta WHERE id=1`).get() as Meta;
const limitOf = (limit: number) => {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("agent batch must be 1–64");
};

export function legacyAgentStep(db: DatabaseSync, limit = BATCH): { ready: boolean; visited: number } {
  limitOf(limit);
  installLegacyAgent(db);
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error(`legacy agent version ${m.version} is incompatible with ${VERSION}`);
    if (m.scanned) { db.exec("COMMIT"); return { ready: true,visited: 0 }; }
    const columns = "CAST(e.thread AS TEXT) thread,CAST(e.n AS TEXT) n,CAST(e.at AS TEXT) at,e.kind,e.author_kind";
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
    const put = db.prepare(`INSERT INTO legacy_agent_build(thread,at,n)
      SELECT CAST(?1 AS INTEGER),CAST(?2 AS INTEGER),CAST(?3 AS INTEGER)
      WHERE NOT EXISTS (SELECT 1 FROM legacy_agent_dirty WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?3 AS INTEGER))
      ON CONFLICT(thread,at,n) DO NOTHING`);
    for (const row of rows) if (row.kind === "message" && row.author_kind === "agent") put.run(row.thread,row.at,row.n);
    const last = rows.at(-1), ready = rows.length < limit;
    db.prepare("UPDATE legacy_agent_meta SET scanned=?,cursor_thread=CAST(? AS INTEGER),cursor_n=CAST(? AS INTEGER) WHERE id=1")
      .run(ready ? 1 : 0,last?.thread ?? m.cursor_thread,last?.n ?? m.cursor_n);
    db.exec("COMMIT");
    return { ready,visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function legacyAgentDrain(db: DatabaseSync, limit = BATCH): number {
  limitOf(limit);
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error(`legacy agent version ${m.version} is incompatible with ${VERSION}`);
    // Before the scan has passed a key, folding it could make the scanner stage an older time for the same key.
    if (!m.scanned) { db.exec("COMMIT"); return 0; }
    const first = db.prepare(`SELECT CAST(thread AS TEXT) thread,CAST(n AS TEXT) n,CAST(old_at AS TEXT) old_at
      FROM legacy_agent_dirty ORDER BY thread,n LIMIT 1`);
    const current = db.prepare(`SELECT CAST(at AS TEXT) at FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)
      AND kind='message' AND author_kind='agent'`);
    const extras = db.prepare(`SELECT CAST(at AS TEXT) at FROM legacy_agent_times INDEXED BY legacy_agent_times_by_key
      WHERE thread=CAST(?1 AS INTEGER) AND n=CAST(?2 AS INTEGER) AND (?3 IS NULL OR at != CAST(?3 AS INTEGER))
      ORDER BY legacy_agent_times.at LIMIT ?4`);
    const dropTime = db.prepare("DELETE FROM legacy_agent_times WHERE thread=CAST(? AS INTEGER) AND at=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)");
    const drop = db.prepare("DELETE FROM legacy_agent_build WHERE thread=CAST(? AS INTEGER) AND at=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)");
    const put = db.prepare(`INSERT INTO legacy_agent_build(thread,at,n)
      SELECT thread,at,n FROM entries WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)
        AND kind='message' AND author_kind='agent' ON CONFLICT(thread,at,n) DO NOTHING`);
    const done = db.prepare("DELETE FROM legacy_agent_dirty WHERE thread=CAST(? AS INTEGER) AND n=CAST(? AS INTEGER)");
    let visited = 0;
    while (visited < limit) {
      const key = first.get() as { thread: string; n: string; old_at: string | null } | undefined;
      if (!key) break;
      const now = (current.get(key.thread,key.n) as { at: string } | undefined)?.at ?? null;
      const oldTimes = extras.all(key.thread,key.n,now,limit-visited) as { at: string }[];
      for (const time of oldTimes) { dropTime.run(key.thread,time.at,key.n); visited++; }
      if (visited === limit) break;
      if (key.old_at !== null) drop.run(key.thread,key.old_at,key.n);
      put.run(key.thread,key.n);
      if (now !== null) dropTime.run(key.thread,now,key.n);
      done.run(key.thread,key.n);
      visited++;
    }
    db.exec("COMMIT");
    return visited;
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function legacyAgentNeedsWork(db: DatabaseSync): boolean {
  if (!hasLegacyAgent(db)) return false;
  return db.prepare(`SELECT 1 FROM legacy_agent_meta WHERE id=1 AND
    (scanned=0 OR EXISTS (SELECT 1 FROM legacy_agent_dirty LIMIT 1))`).get() !== undefined;
}

export function legacyAgentMaintenanceStep(db: DatabaseSync): { done: boolean; visited: number } {
  if (!hasLegacyAgent(db)) return { done: true,visited: 0 };
  if (!meta(db).scanned) {
    const result = legacyAgentStep(db);
    return { done: false,visited: result.visited };
  }
  const visited = legacyAgentDrain(db);
  return { done: visited < BATCH,visited };
}
