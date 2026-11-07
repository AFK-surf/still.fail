import type { DatabaseSync } from "node:sqlite";
import { hasLegacyEdits, hasOldEditIndex } from "./legacy-edits-build.ts";

// A current edit in this bounded tail is newer than every unvisited entry. A short tail is the whole chat.
export const LAST_MESSAGE_RECENT_EDIT = `WITH tail AS MATERIALIZED (
    SELECT n,target FROM entries WHERE thread=?1 ORDER BY n DESC LIMIT 65
  ) SELECT (SELECT CAST(n AS TEXT) FROM tail WHERE target=CAST(?2 AS INTEGER) ORDER BY n DESC LIMIT 1) AS n,
    (SELECT COUNT(*) FROM tail) AS count`;
export const LAST_MESSAGE_OLD_EDITS = `WITH edits AS MATERIALIZED (
    SELECT x.n FROM entries x INDEXED BY entries_target WHERE x.thread=?1 AND x.target=CAST(?2 AS INTEGER)
      ORDER BY x.rowid DESC LIMIT 65
  ) SELECT CAST(MAX(n) AS TEXT) AS n,COUNT(*) AS count FROM edits`;
export const LAST_MESSAGE_WITH_EDIT = `SELECT m.thread,m.n,m.ts,m.author_kind,m.author,
    CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS text,
    CASE WHEN e.n IS NULL THEN m.attachments ELSE e.attachments END AS attachments,
    CASE WHEN e.n IS NULL THEN m.quotes ELSE e.quotes END AS quotes,
    m.declared,m.client,m.agent_identity,m.at AS created_at,e.at AS edited_at,m.letter
  FROM entries m LEFT JOIN entries e ON e.thread=m.thread AND e.n=CAST(?3 AS INTEGER)
  WHERE m.thread=?1 AND m.n=CAST(?2 AS INTEGER) AND m.kind='message'`;

/// The latest edit, null when there is none, or undefined when old edits need preparation. The caller holds a snapshot.
export function boundedEditKey(db: DatabaseSync, thread: number, n: string): string | null | undefined {
  let edit = db.prepare(LAST_MESSAGE_RECENT_EDIT).get(thread, n) as { n: string | null; count: number };
  if (edit.n === null && edit.count === 65) {
    const meta = hasLegacyEdits(db) ? db.prepare("SELECT scanned,old_index FROM legacy_edit_meta WHERE id=1").get() : undefined;
    if (meta?.scanned === 0 && meta.old_index === 1 && hasOldEditIndex(db))
      edit = db.prepare(LAST_MESSAGE_OLD_EDITS).get(thread, n) as { n: string | null; count: number };
    if (edit.count === 65) return undefined;
  }
  return edit.n;
}
