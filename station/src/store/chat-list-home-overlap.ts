// A default-home chat can also be in a named workspace. These rows/counts let the home reader count that intersection
// exactly; it waits for both the old-row scan and every pending overlap batch before using them.
import type { DatabaseSync } from "node:sqlite";
import { installRecentHomeIndex, preparedDefaultHomeTotal } from "./chat-list-home-index.ts";
import type { RecentChatPage } from "./chat-list-index.ts";
import { preparedRecentWorkspaceTotal } from "./chat-list-scope-rows.ts";

const mark = (thread: string) => `
  UPDATE recent_home_overlap_dirty SET revision = revision + 1 WHERE thread = ${thread};
  INSERT INTO recent_home_overlap_dirty(thread, revision) SELECT ${thread}, 1 WHERE ${thread} IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM recent_home_overlap_dirty WHERE thread = ${thread});`;

/// Install the intersection writers without walking old chats. The old default-home rows are scheduled separately.
export function installRecentHomeOverlap(db: DatabaseSync): void {
  installRecentHomeIndex(db);
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recent_home_overlap_meta'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE recent_home_overlap_meta (id INTEGER PRIMARY KEY CHECK (id = 1), cursor INTEGER, through INTEGER, scan_done INTEGER NOT NULL);
      INSERT INTO recent_home_overlap_meta SELECT 1, NULL, (SELECT MAX(thread) FROM recent_home_rows),
        NOT EXISTS (SELECT 1 FROM recent_home_rows LIMIT 1);
      CREATE TABLE recent_home_overlap_dirty (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL);
      CREATE TABLE recent_home_overlap_work (thread INTEGER PRIMARY KEY, revision INTEGER NOT NULL, after_ws TEXT);
      CREATE TABLE recent_home_overlap_rows (ws TEXT NOT NULL, thread INTEGER NOT NULL, PRIMARY KEY(ws, thread)) WITHOUT ROWID;
      CREATE INDEX recent_home_overlap_by_thread ON recent_home_overlap_rows(thread, ws);
      CREATE TABLE recent_home_overlap_totals (ws TEXT PRIMARY KEY, total INTEGER NOT NULL) WITHOUT ROWID;
      CREATE TRIGGER recent_home_overlap_add AFTER INSERT ON recent_home_overlap_rows BEGIN
        INSERT INTO recent_home_overlap_totals(ws, total) SELECT NEW.ws, 0
          WHERE NOT EXISTS (SELECT 1 FROM recent_home_overlap_totals WHERE ws = NEW.ws);
        UPDATE recent_home_overlap_totals SET total = total + 1 WHERE ws = NEW.ws;
      END;
      CREATE TRIGGER recent_home_overlap_drop AFTER DELETE ON recent_home_overlap_rows BEGIN
        UPDATE recent_home_overlap_totals SET total = total - 1 WHERE ws = OLD.ws;
      END;
      CREATE TRIGGER recent_home_overlap_scope_add AFTER INSERT ON recent_scope_rows BEGIN
        INSERT INTO recent_home_overlap_rows(ws, thread) SELECT NEW.ws, NEW.thread
          WHERE EXISTS (SELECT 1 FROM recent_home_rows WHERE thread = NEW.thread)
            AND NOT EXISTS (SELECT 1 FROM recent_home_overlap_rows WHERE ws = NEW.ws AND thread = NEW.thread);
      END;
      CREATE TRIGGER recent_home_overlap_scope_drop AFTER DELETE ON recent_scope_rows BEGIN
        DELETE FROM recent_home_overlap_rows WHERE ws = OLD.ws AND thread = OLD.thread;
      END;
      CREATE TRIGGER recent_home_overlap_home_add AFTER INSERT ON recent_home_rows BEGIN ${mark("NEW.thread")} END;
      CREATE TRIGGER recent_home_overlap_home_drop AFTER DELETE ON recent_home_rows BEGIN ${mark("OLD.thread")} END;
    `);
    db.exec("COMMIT");
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Schedule at most `limit` already indexed default chats. Concurrent new rows are scheduled by the trigger.
export function scanRecentHomeOverlapStep(db: DatabaseSync, limit = 64): { scanDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent home overlap scan batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const get = db.prepare("SELECT cursor, through, scan_done FROM recent_home_overlap_meta WHERE id = 1");
    get.setReadBigInts(true);
    const meta = get.get() as { cursor: bigint | null; through: bigint | null; scan_done: bigint };
    if (meta.scan_done === 1n || meta.through === null) { db.exec("COMMIT"); return { scanDone: true, visited: 0 }; }
    const query = db.prepare(meta.cursor === null
      ? "SELECT thread FROM recent_home_rows WHERE thread <= ?1 ORDER BY thread LIMIT ?2"
      : "SELECT thread FROM recent_home_rows WHERE thread > ?1 AND thread <= ?2 ORDER BY thread LIMIT ?3");
    query.setReadBigInts(true);
    const rows = (meta.cursor === null ? query.all(meta.through, limit) : query.all(meta.cursor, meta.through, limit)) as { thread: bigint }[];
    const add = db.prepare(`INSERT INTO recent_home_overlap_dirty(thread, revision) SELECT ?1, 1
      WHERE NOT EXISTS (SELECT 1 FROM recent_home_overlap_dirty WHERE thread = ?1)`);
    for (const row of rows) add.run(row.thread);
    const done = rows.length < limit;
    db.prepare("UPDATE recent_home_overlap_meta SET cursor = ?, scan_done = ? WHERE id = 1")
      .run(rows.at(-1)?.thread ?? meta.cursor, done ? 1 : 0);
    db.exec("COMMIT");
    return { scanDone: done, visited: rows.length };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

/// Bring default chats' workspace intersections up to date in bounded batches. Even a chat with no workspaces costs
/// one unit. A default-row flip restarts the cursor; workspace row changes behind it are applied by the row triggers.
export function settleRecentHomeOverlapStep(db: DatabaseSync, limit = 64): { overlapsDone: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent home overlap batch must be positive");
  db.exec("BEGIN IMMEDIATE");
  try {
    const next = db.prepare("SELECT thread, revision FROM recent_home_overlap_dirty ORDER BY thread LIMIT 1");
    next.setReadBigInts(true);
    const getWork = db.prepare("SELECT revision, after_ws FROM recent_home_overlap_work WHERE thread = ?");
    getWork.setReadBigInts(true);
    const add = db.prepare(`INSERT INTO recent_home_overlap_rows(ws, thread) SELECT ?1, ?2
      WHERE NOT EXISTS (SELECT 1 FROM recent_home_overlap_rows WHERE ws = ?1 AND thread = ?2)`);
    const remove = db.prepare("DELETE FROM recent_home_overlap_rows WHERE ws = ? AND thread = ?");
    let visited = 0;
    while (visited < limit) {
      const pending = next.get() as { thread: bigint; revision: bigint } | undefined;
      if (!pending) break;
      let work = getWork.get(pending.thread) as { revision: bigint; after_ws: string | null } | undefined;
      if (!work || work.revision !== pending.revision) {
        db.prepare(`INSERT INTO recent_home_overlap_work(thread, revision, after_ws) VALUES (?, ?, NULL)
          ON CONFLICT(thread) DO UPDATE SET revision = excluded.revision, after_ws = NULL`).run(pending.thread, pending.revision);
        work = { revision: pending.revision, after_ws: null };
      }
      const included = db.prepare("SELECT 1 FROM recent_home_rows WHERE thread = ?").get(pending.thread) !== undefined;
      const table = included ? "recent_scope_rows INDEXED BY recent_scope_rows_thread" : "recent_home_overlap_rows INDEXED BY recent_home_overlap_by_thread";
      const query = db.prepare(work.after_ws === null
        ? `SELECT ws FROM ${table} WHERE thread = ?1 ORDER BY ws LIMIT ?2`
        : `SELECT ws FROM ${table} WHERE thread = ?1 AND ws > ?2 ORDER BY ws LIMIT ?3`);
      const remaining = limit - visited;
      const rows = (work.after_ws === null ? query.all(pending.thread, remaining)
        : query.all(pending.thread, work.after_ws, remaining)) as { ws: string }[];
      for (const row of rows) if (included) add.run(row.ws, pending.thread); else remove.run(row.ws, pending.thread);
      visited += Math.max(1, rows.length);
      if (rows.length === remaining) {
        db.prepare("UPDATE recent_home_overlap_work SET after_ws = ? WHERE thread = ?").run(rows.at(-1)!.ws, pending.thread);
        break;
      }
      db.prepare("DELETE FROM recent_home_overlap_work WHERE thread = ?").run(pending.thread);
      db.prepare("DELETE FROM recent_home_overlap_dirty WHERE thread = ? AND revision = ?").run(pending.thread, pending.revision);
    }
    const done = db.prepare("SELECT 1 FROM recent_home_overlap_dirty LIMIT 1").get() === undefined;
    db.exec("COMMIT");
    return { overlapsDone: done, visited };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}

type Ordered = { thread: bigint; at: bigint; said_at: bigint; created_at: bigint };
const before = (a: Ordered, b: Ordered) => a.at !== b.at ? a.at > b.at : a.said_at !== b.said_at ? a.said_at > b.said_at
  : a.created_at !== b.created_at ? a.created_at > b.created_at : a.thread >= b.thread;

export const RECENT_HOME_ORDER_PAGE = `SELECT thread, at, said_at, created_at FROM recent_home_rows INDEXED BY recent_home_order
  ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?`;
export const RECENT_HOME_WORKSPACE_ORDER_PAGE = `SELECT thread, at, said_at, created_at FROM recent_scope_rows INDEXED BY recent_scope_order
  WHERE ws = ? ORDER BY at DESC, said_at DESC, created_at DESC, thread DESC LIMIT ?`;

/// Both inputs and the exact overlap count are read on one snapshot.
export function readPreparedRecentHome(db: DatabaseSync, home: string, limit: number): RecentChatPage | null {
  if (!Number.isSafeInteger(limit) || limit < 0) throw new RangeError("recent home page size must be nonnegative");
  if (limit === 0) return { ids: [], total: 0 };
  db.exec("SAVEPOINT recent_home_union");
  try {
    const meta = db.prepare("SELECT scan_done FROM recent_home_overlap_meta WHERE id = 1").get() as { scan_done: number };
    if (meta.scan_done !== 1 || db.prepare("SELECT 1 FROM recent_home_overlap_dirty LIMIT 1").get() !== undefined) return null;
    const defaults = preparedDefaultHomeTotal(db), workspace = preparedRecentWorkspaceTotal(db, home);
    if (defaults === null || workspace === null) return null;
    const count = db.prepare("SELECT total FROM recent_home_overlap_totals WHERE ws = ?").get(home) as { total: number } | undefined;
    const defaultQuery = db.prepare(RECENT_HOME_ORDER_PAGE);
    const workspaceQuery = db.prepare(RECENT_HOME_WORKSPACE_ORDER_PAGE);
    defaultQuery.setReadBigInts(true);
    workspaceQuery.setReadBigInts(true);
    const left = defaultQuery.all(limit) as Ordered[], right = workspaceQuery.all(home, limit) as Ordered[];
    const ids: number[] = [], seen = new Set<bigint>();
    let i = 0, j = 0;
    while (ids.length < limit && (i < left.length || j < right.length)) {
      const item = j >= right.length || (i < left.length && before(left[i]!, right[j]!)) ? left[i++]! : right[j++]!;
      if (seen.has(item.thread)) continue;
      const id = Number(item.thread);
      if (!Number.isSafeInteger(id)) throw new RangeError("recent chat id exceeds JavaScript's safe integer range");
      seen.add(item.thread);
      ids.push(id);
    }
    return { ids, total: defaults + workspace - (count?.total ?? 0) };
  } finally { db.exec("RELEASE recent_home_union"); }
}
