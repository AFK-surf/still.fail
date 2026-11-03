// Stop maintaining the per-call usage indexes after the previous station has exited. A durable marker makes the
// change atomic for readers and prevents a later startup from rebuilding them. Free their pages in separate steps.
import type { DatabaseSync } from "node:sqlite";

const quote = (name: string) => `"${name.replaceAll('"', '""')}"`;
export const retiredUsage = (db: DatabaseSync): boolean => db.prepare(
  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_retired_detail'",
).get() !== undefined;

export function stopUsageIndexes(db: DatabaseSync): void {
  if (retiredUsage(db)) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!retiredUsage(db)) {
      const triggers = db.prepare(`SELECT name FROM sqlite_master WHERE type = 'trigger' AND
        (name GLOB 'usage_detail_*' OR name GLOB 'usage_daily_detail_*' OR name GLOB 'usage_main_calls_*'
          OR name = 'usage_compactions_add')`).all() as { name: string }[];
      for (const { name } of triggers) db.exec(`DROP TRIGGER ${quote(name)}`);
      db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY CHECK (id = 1)); INSERT INTO usage_retired_detail VALUES (1)");
    }
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Drop one object at a time, so foreground writes can run between them. This can resume after a restart.
export function dropUsageIndexStep(db: DatabaseSync): boolean {
  const row = db.prepare(`SELECT type, name FROM sqlite_master WHERE
    ((type = 'index' AND sql IS NOT NULL) OR type = 'table') AND
    (tbl_name = 'usage_detail' OR tbl_name GLOB 'usage_detail_*' OR tbl_name = 'usage_main_calls')
    ORDER BY CASE type WHEN 'index' THEN 0 ELSE 1 END, name LIMIT 1`).get() as { type: string; name: string } | undefined;
  if (row === undefined) return true;
  db.exec(`DROP ${row.type === "index" ? "INDEX" : "TABLE"} IF EXISTS ${quote(row.name)}`);
  return false;
}

export function retireUsageIndexes(db: DatabaseSync): void {
  stopUsageIndexes(db);
  while (!dropUsageIndexStep(db)) { /* In-memory databases only; file databases use the background worker. */ }
}
