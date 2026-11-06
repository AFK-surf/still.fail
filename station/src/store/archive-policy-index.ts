// A workspace's current archive policy, without building an index over an old store in one long write.
import type { DatabaseSync } from "node:sqlite";

const VERSION = 1;
const BATCH = 64;
const exists = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type=? AND name=?").get(type, name) !== undefined;

export const ARCHIVE_POLICY = "SELECT id, at, policy, author, summary FROM archive_policy WHERE ws IS ? ORDER BY id DESC LIMIT 1";

// Both branches use the same snapshot. CASE tests readiness before entering either lookup; while the old rows are
// being copied, the original query remains exact. Once complete only the requested workspace's index is visited.
export const LEGACY_ARCHIVE_POLICY = `SELECT p.id,p.at,p.policy,p.author,p.summary FROM archive_policy p WHERE p.id = CASE
  WHEN (SELECT complete FROM archive_policy_lookup_meta WHERE id=1)=1 THEN
    (SELECT k.id FROM archive_policy_lookup k INDEXED BY archive_policy_lookup_ws WHERE k.ws IS ?1 ORDER BY k.id DESC LIMIT 1)
  ELSE (SELECT q.id FROM archive_policy q WHERE q.ws IS ?1 ORDER BY q.id DESC LIMIT 1) END`;

export function hasLegacyArchivePolicy(db: DatabaseSync): boolean {
  if (!exists(db, "table", "archive_policy_lookup_meta")) return false;
  const row = db.prepare("SELECT version,complete FROM archive_policy_lookup_meta WHERE id=1").get() as
    { version: number; complete: number } | undefined;
  if (!row || row.version !== VERSION || (row.complete !== 0 && row.complete !== 1))
    throw new Error("archive policy lookup has an unsupported version");
  return true;
}

// Reconcile the keys after each write against the source. An ignored insert fires no AFTER trigger, and REPLACE can
// remove an older row without firing DELETE. Looking up the source also handles nested writes that changed NEW/OLD.
const reconcile = (ids: string) => `DELETE FROM archive_policy_lookup WHERE id IN (${ids});
  INSERT INTO archive_policy_lookup(id,ws) SELECT id,ws FROM archive_policy WHERE id IN (${ids});`;

const LEGACY_SCHEMA = `
  CREATE TABLE archive_policy_lookup_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
    complete INTEGER NOT NULL,cursor INTEGER,end_id INTEGER) WITHOUT ROWID;
  INSERT INTO archive_policy_lookup_meta VALUES(1,${VERSION},0,NULL,(SELECT MAX(id) FROM archive_policy));
  CREATE TABLE archive_policy_lookup(id INTEGER PRIMARY KEY,ws TEXT);
  -- id aliases rowid and is already the trailing key of this index.
  CREATE INDEX archive_policy_lookup_ws ON archive_policy_lookup(ws);
  CREATE TRIGGER archive_policy_lookup_insert AFTER INSERT ON archive_policy BEGIN ${reconcile("NEW.id")} END;
  CREATE TRIGGER archive_policy_lookup_update AFTER UPDATE OF id,ws ON archive_policy
    WHEN OLD.id IS NOT NEW.id OR OLD.ws IS NOT NEW.ws BEGIN ${reconcile("OLD.id,NEW.id")} END;
  CREATE TRIGGER archive_policy_lookup_delete AFTER DELETE ON archive_policy BEGIN ${reconcile("OLD.id")} END;`;

/// Small and new stores use a native index. A larger old store installs empty structures and copies later.
export function installArchivePolicyIndex(db: DatabaseSync): void {
  const native = () => exists(db, "index", "archive_policy_by_ws");
  if (native() || hasLegacyArchivePolicy(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!native() && !hasLegacyArchivePolicy(db)) {
      if (db.prepare("SELECT 1 FROM archive_policy LIMIT 1 OFFSET 63").get() === undefined)
        db.exec("CREATE INDEX IF NOT EXISTS archive_policy_by_ws ON archive_policy(ws)");
      else db.exec(LEGACY_SCHEMA);
    }
    db.exec("COMMIT");
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

type Meta = { version: number; complete: number; cursor: string | null; end_id: string | null };
const meta = (db: DatabaseSync) => db.prepare(`SELECT version,complete,CAST(cursor AS TEXT) cursor,CAST(end_id AS TEXT) end_id
  FROM archive_policy_lookup_meta WHERE id=1`).get() as Meta;

/// Copy at most 64 old policy rows. The cursor and the copied rows commit with the triggers' concurrent changes.
export function archivePolicyIndexStep(db: DatabaseSync, limit = BATCH): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > BATCH) throw new RangeError("policy batch must be 1–64");
  if (!hasLegacyArchivePolicy(db)) return { done: true, visited: 0 };
  db.exec("BEGIN IMMEDIATE");
  try {
    const m = meta(db);
    if (m.version !== VERSION) throw new Error("unsupported archive policy preparation");
    if (m.complete === 1) { db.exec("COMMIT"); return { done: true, visited: 0 }; }
    const rows = m.end_id === null ? [] : (m.cursor === null
      ? db.prepare(`SELECT CAST(id AS TEXT) AS id FROM archive_policy WHERE id<=CAST(?1 AS INTEGER)
          ORDER BY archive_policy.id LIMIT ?2`).all(m.end_id, limit)
      : db.prepare(`SELECT CAST(id AS TEXT) AS id FROM archive_policy WHERE id>CAST(?1 AS INTEGER) AND id<=CAST(?2 AS INTEGER)
          ORDER BY archive_policy.id LIMIT ?3`).all(m.cursor, m.end_id, limit)) as { id: string }[];
    const put = db.prepare(`INSERT INTO archive_policy_lookup(id,ws) SELECT p.id,p.ws FROM archive_policy p
      WHERE p.id=CAST(?1 AS INTEGER) AND NOT EXISTS (SELECT 1 FROM archive_policy_lookup k WHERE k.id=p.id)`);
    for (const row of rows) put.run(row.id);
    const done = rows.length < limit;
    db.prepare("UPDATE archive_policy_lookup_meta SET cursor=CAST(? AS INTEGER),complete=? WHERE id=1")
      .run(rows.at(-1)?.id ?? m.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { done, visited: rows.length };
  } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
}

export function archivePolicyIndexNeedsWork(db: DatabaseSync): boolean {
  return hasLegacyArchivePolicy(db) && meta(db).complete === 0;
}
