import type { DatabaseSync } from "node:sqlite";
import { restateGuardSchema } from "./restate-guard.ts";

const VERSION = 1, MARK = "card_scan_guard_v1";
const triggers = ["card_scan_add", "card_scan_change", "card_scan_drop", "card_scan_thread_drop"];
const cached = new WeakMap<DatabaseSync, number>();

// Include rows that INSERT OR REPLACE / UPDATE OR REPLACE may silently displace, even with recursive triggers off.
// If the timestamp index is absent it cannot enforce a conflicting timestamp; do not scan the chat to look for one.
const conflicts = `SELECT e.thread,e.n,e.target FROM entries e WHERE e.thread=NEW.thread AND e.n=NEW.n
  UNION SELECT e.thread,e.n,e.target FROM (SELECT 1 FROM card_scan_meta WHERE id=1 AND has_ts_index=1) present
    CROSS JOIN entries e WHERE NEW.ts IS NOT NULL AND e.thread=NEW.thread AND e.ts=NEW.ts
  UNION SELECT e.thread,e.n,e.target FROM entries e WHERE e.rowid=NEW.rowid`;
const keys = (update: boolean) => `SELECT NEW.thread AS thread,NEW.n AS target
  UNION SELECT NEW.thread,NEW.target WHERE NEW.target IS NOT NULL
  ${update ? "UNION SELECT OLD.thread,OLD.n UNION SELECT OLD.thread,OLD.target WHERE OLD.target IS NOT NULL" : ""}
  UNION SELECT e.thread,e.n FROM (${conflicts}) e
  UNION SELECT e.thread,e.target FROM (${conflicts}) e WHERE e.target IS NOT NULL`;
const guarded = (side: "NEW" | "OLD" | "e") => `EXISTS (SELECT 1 FROM card_scan_guard g
  WHERE g.thread=${side}.thread AND g.target IN (${side}.n,${side}.target))`;
// First check indexed candidates. The more expensive conflict set below runs only when some guarded message can
// actually be affected; unrelated writes in this or another conversation do not enumerate every guard or entry.
const displaces = `EXISTS (SELECT 1 FROM entries e WHERE e.thread=NEW.thread AND e.n=NEW.n AND ${guarded("e")})
  OR EXISTS (SELECT 1 FROM (SELECT 1 FROM card_scan_meta WHERE id=1 AND has_ts_index=1) present
    CROSS JOIN entries e WHERE NEW.ts IS NOT NULL AND e.thread=NEW.thread AND e.ts=NEW.ts AND ${guarded("e")})
  OR EXISTS (SELECT 1 FROM entries e WHERE e.rowid=NEW.rowid AND ${guarded("e")})`;
// A schema change invalidates every existing scan; while it is stale, skip probes that depended on the old indexes.
const currentSchema = "(SELECT schema_version FROM pragma_schema_version)=(SELECT schema_version FROM card_scan_meta WHERE id=1)";

/// Install only empty guard state. Schema validation and the schema cookie are read from the same snapshot.
export function ensureCardScanGuard(db: DatabaseSync): number {
  const installed = () => {
    const meta = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='card_scan_meta'").get();
    if (!meta) return false;
    const version = db.prepare("SELECT version FROM card_scan_meta WHERE id=1").get()?.version;
    if (version !== VERSION) throw new Error(`card scan guard version ${version ?? "missing"} is incompatible with ${VERSION}`);
    if (!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='card_scan_guard'").get()) return false;
    const found = db.prepare(`SELECT name,tbl_name,sql FROM sqlite_master WHERE type='trigger' AND name IN
      ('card_scan_add','card_scan_change','card_scan_drop','card_scan_thread_drop')`).all();
    return triggers.every((name) => found.some((row) => row.name === name &&
      row.tbl_name === (name === "card_scan_thread_drop" ? "threads" : "entries") &&
      typeof row.sql === "string" && row.sql.includes(MARK)));
  };
  db.exec("SAVEPOINT card_scan_schema");
  let schema: number, ready: boolean;
  try { schema = restateGuardSchema(db); ready = cached.get(db) === schema || installed(); }
  finally { db.exec("RELEASE card_scan_schema"); }
  if (!ready) {
    db.exec("BEGIN IMMEDIATE");
    try {
      if (!installed()) {
        db.exec(`CREATE TABLE IF NOT EXISTS card_scan_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
            schema_version INTEGER NOT NULL,has_ts_index INTEGER NOT NULL) WITHOUT ROWID;
          INSERT OR IGNORE INTO card_scan_meta VALUES(1,${VERSION},0,0);
          CREATE TABLE IF NOT EXISTS card_scan_guard(thread INTEGER NOT NULL,target INTEGER NOT NULL,token TEXT NOT NULL,dirty INTEGER NOT NULL,
            PRIMARY KEY(thread,target)) WITHOUT ROWID;`);
        for (const name of triggers) db.exec(`DROP TRIGGER IF EXISTS ${name}`);
        db.exec(`CREATE TRIGGER card_scan_add BEFORE INSERT ON entries WHEN EXISTS (SELECT 1 FROM card_scan_guard LIMIT 1) AND ${currentSchema}
          AND (${guarded("NEW")} OR ${displaces})
          BEGIN -- ${MARK}
            UPDATE card_scan_guard SET dirty=1 WHERE dirty=0 AND (thread,target) IN (${keys(false)}); END;
          CREATE TRIGGER card_scan_change BEFORE UPDATE ON entries WHEN EXISTS (SELECT 1 FROM card_scan_guard LIMIT 1) AND ${currentSchema}
          AND (${guarded("OLD")} OR ${guarded("NEW")} OR ${displaces})
          BEGIN -- ${MARK}
            UPDATE card_scan_guard SET dirty=1 WHERE dirty=0 AND (thread,target) IN (${keys(true)}); END;
          CREATE TRIGGER card_scan_drop BEFORE DELETE ON entries WHEN ${currentSchema} AND ${guarded("OLD")}
          BEGIN -- ${MARK}
            UPDATE card_scan_guard SET dirty=1 WHERE thread=OLD.thread AND target IN (OLD.n,OLD.target) AND dirty=0; END;
          CREATE TRIGGER card_scan_thread_drop AFTER DELETE ON threads
          BEGIN -- ${MARK}
            DELETE FROM card_scan_guard WHERE thread=OLD.id; END;`);
      }
      if (!installed()) throw new Error("card scan guard installation did not finish");
      schema = restateGuardSchema(db);
      db.exec("COMMIT");
    } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
  }
  cached.set(db, schema);
  return schema;
}
