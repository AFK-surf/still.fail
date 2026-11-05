import type { DatabaseSync } from "node:sqlite";

type RecentIndexPart = "global" | "scope" | "home" | "overlap";
const tables: Record<RecentIndexPart, string> = {
  global: "recent_chat_meta", scope: "recent_scope_tracked", home: "recent_home_meta", overlap: "recent_home_overlap_meta",
};
export const RECENT_CHAT_SCHEMA_TABLES = `SELECT
  EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1) AS component,
  EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_chat_versions') AS versions`;
export const RECENT_CHAT_SCHEMA_VERSION = `SELECT (SELECT version = 1 FROM recent_chat_versions WHERE part = ?1) AS current,
  EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?2) AS component`;

/// A version and its component's tables and triggers are installed in the same transaction. Future changes that
/// cannot use this version must migrate or rebuild it after handover; they must not silently read a partial index.
export function recentChatIndexInstalled(db: DatabaseSync, part: RecentIndexPart): boolean {
  const found = db.prepare(RECENT_CHAT_SCHEMA_TABLES)
    .get(tables[part]) as { component: number; versions: number };
  if (!found.versions) {
    if (!found.component) return false;
    throw new Error(`recent chat ${part} index has an incompatible or missing version`);
  }
  // Installation can finish on another connection between the two statements. Read its marker and component on
  // the same snapshot, rather than comparing the marker with the earlier snapshot's table list.
  const marker = db.prepare(RECENT_CHAT_SCHEMA_VERSION).get(part, tables[part]) as { current: number | null; component: number };
  if (!marker.component && marker.current === null) return false;
  if (!marker.component || marker.current !== 1) throw new Error(`recent chat ${part} index has an incompatible or missing version`);
  return true;
}

/// Called only inside the transaction that creates the corresponding component.
export function markRecentChatIndexInstalled(db: DatabaseSync, part: RecentIndexPart): void {
  db.exec("CREATE TABLE IF NOT EXISTS recent_chat_versions (part TEXT PRIMARY KEY, version INTEGER NOT NULL) WITHOUT ROWID");
  db.prepare("INSERT INTO recent_chat_versions(part, version) VALUES (?, 1)").run(part);
}
