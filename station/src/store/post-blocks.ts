import type { DatabaseSync } from "node:sqlite";

// A marker covers only one author's messages in a small range of entry numbers. Most consecutive messages from the
// same agent share it, while a lookup can skip every range in which that agent said nothing.
export const POST_BLOCK_SIZE = 64;
export type PostPosition = { thread: number; n: number };

/// A lookup needs an older suffix before it can answer without walking the thread's history.
export class PostBlocksUnavailable extends Error {
  readonly positions: readonly PostPosition[];
  constructor(positions: readonly PostPosition[]) {
    super("post block history not ready");
    this.positions = positions;
  }
}

const block = (n: string) => `(${n} / ${POST_BLOCK_SIZE} - CASE WHEN ${n} < 0 AND ${n} % ${POST_BLOCK_SIZE} != 0 THEN 1 ELSE 0 END)`;
const isPost = (row: string) => `${row}.kind = 'message' AND ${row}.author_kind = 'agent'`;

// REPLACE may silently remove two different rows, one for (thread,n) and one for (thread,ts), without DELETE triggers.
// SQLite serializes writers, so this small staging table belongs to the current write. IGNORE may leave it populated;
// the next write clears it, without changing any markers for the ignored write.
const stage = `
  DELETE FROM post_blocks_replaced WHERE thread IS NOT NULL;
  INSERT INTO post_blocks_replaced (thread, author, bucket)
    SELECT e.thread, e.author, ${block("e.n")} FROM entries e
      WHERE e.thread = NEW.thread AND e.n = NEW.n AND ${isPost("e")}
    UNION
    SELECT e.thread, e.author, ${block("e.n")} FROM entries e
      WHERE NEW.ts IS NOT NULL AND e.thread = NEW.thread AND e.ts = NEW.ts AND ${isPost("e")};`;
const noPost = (marker: string) => `NOT EXISTS (SELECT 1 FROM entries e WHERE e.thread = ${marker}.thread
  AND e.n >= ${marker}.bucket * ${POST_BLOCK_SIZE} AND e.n <= ${marker}.bucket * ${POST_BLOCK_SIZE} + ${POST_BLOCK_SIZE - 1}
  AND ${isPost("e")} AND e.author = ${marker}.author)`;
const cleanReplaced = `
  DELETE FROM post_blocks WHERE (thread, author, bucket) IN (SELECT thread, author, bucket FROM post_blocks_replaced)
    AND ${noPost("post_blocks")};
  DELETE FROM post_blocks_replaced WHERE thread IS NOT NULL;`;
const cleanOld = `
  DELETE FROM post_blocks WHERE thread = OLD.thread AND author = OLD.author AND bucket = ${block("OLD.n")}
    AND OLD.kind = 'message' AND OLD.author_kind = 'agent' AND ${noPost("post_blocks")};`;
// Do not rely on INSERT OR IGNORE in a trigger: an older writer's conflict policy can override it.
const addNew = `
  INSERT INTO post_blocks (thread, author, bucket)
    SELECT NEW.thread, NEW.author, ${block("NEW.n")}
    WHERE NEW.kind = 'message' AND NEW.author_kind = 'agent'
      AND NOT EXISTS (SELECT 1 FROM post_blocks b WHERE b.thread = NEW.thread AND b.author = NEW.author AND b.bucket = ${block("NEW.n")});`;
const changed = "OLD.thread IS NOT NEW.thread OR OLD.n IS NOT NEW.n OR OLD.kind IS NOT NEW.kind OR OLD.author_kind IS NOT NEW.author_kind OR OLD.author IS NOT NEW.author OR OLD.ts IS NOT NEW.ts";

/// Install the markers and their triggers without scanning old messages. An empty store is covered from its first write;
/// an older store records only the requested suffix of each thread in bounded steps.
export function installPostBlocks(db: DatabaseSync): void {
  const installed = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'post_blocks_meta'").get() !== undefined;
  if (installed()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!installed()) db.exec(`
      CREATE TABLE post_blocks(thread INTEGER NOT NULL, author TEXT NOT NULL, bucket INTEGER NOT NULL,
        PRIMARY KEY(thread,author,bucket)) WITHOUT ROWID;
      CREATE TABLE post_blocks_replaced(thread INTEGER NOT NULL, author TEXT NOT NULL, bucket INTEGER NOT NULL,
        PRIMARY KEY(thread,author,bucket)) WITHOUT ROWID;
      CREATE TABLE post_blocks_meta(id INTEGER PRIMARY KEY CHECK (id = 1), fresh INTEGER NOT NULL) WITHOUT ROWID;
      CREATE TABLE post_blocks_coverage(thread INTEGER PRIMARY KEY, cursor INTEGER, complete INTEGER NOT NULL) WITHOUT ROWID;
      INSERT INTO post_blocks_meta SELECT 1, NOT EXISTS (SELECT 1 FROM entries LIMIT 1);
      CREATE TRIGGER post_blocks_before_insert BEFORE INSERT ON entries BEGIN ${stage} END;
      CREATE TRIGGER post_blocks_after_insert AFTER INSERT ON entries BEGIN ${cleanReplaced} ${addNew} END;
      CREATE TRIGGER post_blocks_before_update BEFORE UPDATE OF thread,n,kind,author_kind,author,ts ON entries
        WHEN ${changed} BEGIN ${stage} END;
      CREATE TRIGGER post_blocks_after_update AFTER UPDATE OF thread,n,kind,author_kind,author,ts ON entries
        WHEN ${changed} BEGIN ${cleanOld} ${cleanReplaced} ${addNew} END;
      CREATE TRIGGER post_blocks_after_delete AFTER DELETE ON entries BEGIN ${cleanOld} END;
    `);
    db.exec("COMMIT");
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}

type Coverage = { cursor: number | null; complete: number };
const coverage = (db: DatabaseSync, thread: number): Coverage | undefined =>
  db.prepare("SELECT cursor, complete FROM post_blocks_coverage WHERE thread = ?").get(thread) as Coverage | undefined;
const fresh = (db: DatabaseSync): boolean =>
  (db.prepare("SELECT fresh FROM post_blocks_meta WHERE id = 1").get() as { fresh: number }).fresh === 1;
const covers = (row: Coverage | undefined, after: number): boolean =>
  row !== undefined && (row.complete === 1 || (row.cursor !== null && row.cursor <= after + 1));

export function postBlocksReady(db: DatabaseSync, thread: number, after: number): boolean {
  return fresh(db) || covers(coverage(db, thread), after);
}

/// One coverage read can release all of a thread's waiting deliveries after a batch.
export function postBlocksCoverage(db: DatabaseSync, thread: number): { complete: boolean; cursor: number | null } {
  if (fresh(db)) return { complete: true, cursor: null };
  const row = coverage(db, thread);
  return { complete: row?.complete === 1, cursor: row?.cursor ?? null };
}

type Entry = { n: number; kind: string; author_kind: string; author: string };

/// Index one requested suffix, newest first. The potentially cold history is read outside the write transaction. Once
/// the write lock is held, only the selected posts are rechecked by primary key; intervening writes have their own
/// triggers, so neither a concurrent change nor an interrupted batch can make coverage claim a missing marker.
export function postBlocksStep(db: DatabaseSync, thread: number, after: number, limit = POST_BLOCK_SIZE, mayWrite?: () => boolean): { done: boolean; visited: number } {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > POST_BLOCK_SIZE) throw new RangeError("post block batch must be between 1 and 64");
  if (fresh(db)) return { done: true, visited: 0 };
  const before = coverage(db, thread);
  if (covers(before, after)) return { done: true, visited: 0 };
  const rows = (before?.cursor === null || before?.cursor === undefined
    ? db.prepare("SELECT n, kind, author_kind, author FROM entries WHERE thread = ? AND n >= ? ORDER BY n DESC LIMIT ?").all(thread, after, limit)
    : db.prepare("SELECT n, kind, author_kind, author FROM entries WHERE thread = ? AND n < ? AND n >= ? ORDER BY n DESC LIMIT ?").all(thread, before.cursor, after, limit)) as Entry[];
  const older = rows.length < limit && db.prepare("SELECT 1 FROM entries WHERE thread = ? AND n < ? LIMIT 1").get(thread, after) !== undefined;
  // A foreground writer may have arrived while those pages were read. Do not try to take SQLite's writer then.
  if (mayWrite && !mayWrite()) return { done: false, visited: rows.length };
  db.exec("BEGIN IMMEDIATE");
  try {
    const current = coverage(db, thread);
    if ((current?.cursor ?? null) !== (before?.cursor ?? null) || (current?.complete ?? 0) !== (before?.complete ?? 0)) {
      const done = covers(current, after);
      db.exec("COMMIT");
      return { done, visited: 0 };
    }
    const add = db.prepare(`INSERT INTO post_blocks (thread, author, bucket)
      SELECT e.thread, e.author, ${block("e.n")} FROM entries e
      WHERE e.thread = ? AND e.n = ? AND e.author = ? AND ${isPost("e")}
        AND NOT EXISTS (SELECT 1 FROM post_blocks b WHERE b.thread = e.thread AND b.author = e.author AND b.bucket = ${block("e.n")})`);
    for (const row of rows) if (row.kind === "message" && row.author_kind === "agent") add.run(thread, row.n, row.author);
    const cursor = rows.length < limit ? after : rows.at(-1)!.n;
    const complete = rows.length < limit && !older ? 1 : 0;
    db.prepare(`INSERT INTO post_blocks_coverage(thread, cursor, complete) VALUES (?, ?, ?)
      ON CONFLICT(thread) DO UPDATE SET cursor = excluded.cursor, complete = excluded.complete`).run(thread, cursor, complete);
    db.exec("COMMIT");
    return { done: complete === 1 || cursor <= after + 1, visited: rows.length };
  } catch (error) {
    try { db.exec("ROLLBACK"); } catch {}
    throw error;
  }
}
