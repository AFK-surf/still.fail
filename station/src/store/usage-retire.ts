// Stop maintaining the per-call usage indexes after the previous station has exited. A durable marker makes the
// change atomic for readers and prevents a later startup from rebuilding them. Free their pages in bounded batches.
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

/// Seek the first batch by primary key. Every row deletion also releases its index entries; dropping a populated
/// index or table directly would visit its entire B-tree under one write lock.
export function usageIndexBatchSql(db: DatabaseSync, table: string): string {
  const columns = db.prepare(`PRAGMA table_info(${quote(table)})`).all() as { name: string; pk: number }[];
  const keys = columns.filter((column) => column.pk > 0).sort((a, b) => a.pk - b.pk).map((column) => quote(column.name));
  if (keys.length === 0) keys.push("rowid");
  const tuple = keys.length === 1 ? keys[0] : `(${keys.join(", ")})`;
  return `DELETE FROM ${quote(table)} WHERE ${tuple} IN (SELECT ${keys.join(", ")} FROM ${quote(table)} LIMIT ?)`;
}

/// One bounded delete is one transaction. Only drop a table and its indexes once every row has been removed.
export function dropUsageIndexStep(db: DatabaseSync, batch = 256): boolean {
  const row = db.prepare(`SELECT name FROM sqlite_master WHERE type = 'table' AND
    (name = 'usage_detail' OR name GLOB 'usage_detail_*' OR name = 'usage_main_calls')
    ORDER BY name LIMIT 1`).get() as { name: string } | undefined;
  if (row === undefined) return true;
  const removed = db.prepare(usageIndexBatchSql(db, row.name)).run(batch).changes;
  if (removed === 0) db.exec(`DROP TABLE IF EXISTS ${quote(row.name)}`);
  return false;
}

export function retireUsageIndexes(db: DatabaseSync): void {
  stopUsageIndexes(db);
  while (!dropUsageIndexStep(db)) { /* In-memory databases only; file databases use the background worker. */ }
}
