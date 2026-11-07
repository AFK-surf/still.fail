import type { DatabaseSync, StatementSync } from "node:sqlite";

// Only a restatement in progress needs a guard. A later restatement in the same thread replaces its token; the older
// one detects that and rereads. A process that dies can leave at most one row per thread, reused on the next attempt.
const VERSION = 1;
const MARK = "restate_guard_v1";
const triggers = ["restate_guard_add", "restate_guard_change", "restate_guard_drop", "restate_guard_thread_drop"];
const cached = new WeakMap<DatabaseSync, number>();
const schemaQueries = new WeakMap<DatabaseSync, StatementSync>();

export function restateGuardSchema(db: DatabaseSync): number {
  let query = schemaQueries.get(db);
  if (!query) { query = db.prepare("PRAGMA schema_version"); schemaQueries.set(db, query); }
  return Number(query.get()!.schema_version);
}

/// Install without scanning old entries. The rowid lookup also catches a REPLACE displacing a different thread.
export function ensureRestateGuard(db: DatabaseSync): number {
  const installed = () => {
    const meta = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='restate_guard_meta'").get();
    if (!meta) return false;
    const version = db.prepare("SELECT version FROM restate_guard_meta WHERE id=1").get()?.version;
    if (version !== VERSION) throw new Error(`restate guard version ${version ?? "missing"} is incompatible with ${VERSION}`);
    if (!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='restate_guard'").get()) return false;
    const found = db.prepare(`SELECT name,tbl_name,sql FROM sqlite_master WHERE type='trigger' AND name IN
      ('restate_guard_add','restate_guard_change','restate_guard_drop','restate_guard_thread_drop')`).all();
    return triggers.every((name) => found.some((row) => row.name === name &&
      row.tbl_name === (name === "restate_guard_thread_drop" ? "threads" : "entries") &&
      typeof row.sql === "string" && row.sql.includes(MARK)));
  };
  // The schema cookie and the trigger check must describe one snapshot. Otherwise a trigger removed just after the
  // check could be cached under the newer cookie and a write would go unobserved.
  db.exec("SAVEPOINT restate_guard_schema");
  let schema: number, ready: boolean;
  try {
    schema = restateGuardSchema(db);
    ready = cached.get(db) === schema || installed();
  } finally { db.exec("RELEASE restate_guard_schema"); }
  if (!ready) {
    db.exec("BEGIN IMMEDIATE");
    try {
      if (!installed()) {
        db.exec(`CREATE TABLE IF NOT EXISTS restate_guard_meta(id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL) WITHOUT ROWID;
          INSERT OR IGNORE INTO restate_guard_meta VALUES(1,${VERSION});
          CREATE TABLE IF NOT EXISTS restate_guard(thread INTEGER PRIMARY KEY,token TEXT NOT NULL,dirty INTEGER NOT NULL) WITHOUT ROWID;`);
        for (const name of triggers) db.exec(`DROP TRIGGER IF EXISTS ${name}`);
        db.exec(`CREATE TRIGGER restate_guard_add BEFORE INSERT ON entries
          WHEN EXISTS (SELECT 1 FROM restate_guard WHERE thread=NEW.thread)
            OR EXISTS (SELECT 1 FROM entries e JOIN restate_guard g ON g.thread=e.thread WHERE e.rowid=NEW.rowid)
          BEGIN -- ${MARK}
            UPDATE restate_guard SET dirty=1 WHERE dirty=0 AND thread IN
            (NEW.thread,(SELECT e.thread FROM entries e WHERE e.rowid=NEW.rowid)); END;
        CREATE TRIGGER restate_guard_change BEFORE UPDATE ON entries
          WHEN EXISTS (SELECT 1 FROM restate_guard WHERE thread IN (OLD.thread,NEW.thread))
            OR EXISTS (SELECT 1 FROM entries e JOIN restate_guard g ON g.thread=e.thread WHERE e.rowid=NEW.rowid)
          BEGIN -- ${MARK}
            UPDATE restate_guard SET dirty=1 WHERE dirty=0 AND thread IN
            (OLD.thread,NEW.thread,(SELECT e.thread FROM entries e WHERE e.rowid=NEW.rowid)); END;
        CREATE TRIGGER restate_guard_drop BEFORE DELETE ON entries
          WHEN EXISTS (SELECT 1 FROM restate_guard WHERE thread=OLD.thread)
          BEGIN -- ${MARK}
            UPDATE restate_guard SET dirty=1 WHERE dirty=0 AND thread=OLD.thread; END;
        CREATE TRIGGER restate_guard_thread_drop AFTER DELETE ON threads
          BEGIN -- ${MARK}
            DELETE FROM restate_guard WHERE thread=OLD.id; END;`);
      }
      if (!installed()) throw new Error("restate guard installation did not finish");
      schema = restateGuardSchema(db);
      db.exec("COMMIT");
    } catch (error) { try { db.exec("ROLLBACK"); } catch {} throw error; }
  }
  cached.set(db, schema);
  return schema;
}
