// Read one bounded range for legacy lookup preparation, inside the caller's transaction.
// Keys stay decimal strings in JS and are compared as integers by SQLite.
import type { DatabaseSync } from "node:sqlite";

type Cursor = { cursor_thread: string | null; cursor_n: string | null; end_thread: string | null; end_n: string | null };

export function legacyEntryBatch<T>(db: DatabaseSync, m: Cursor, columns: string, limit: number): T[] {
  const rows: T[] = [];
  if (m.end_thread !== null) {
    if (m.cursor_thread !== null) {
      const same = m.cursor_thread === m.end_thread;
      const sql = `SELECT ${columns} FROM entries e WHERE e.thread=CAST(?1 AS INTEGER) AND e.n>CAST(?2 AS INTEGER)
        ${same ? "AND e.n<=CAST(?3 AS INTEGER) ORDER BY e.n LIMIT ?4" : "ORDER BY e.n LIMIT ?3"}`;
      rows.push(...(same ? db.prepare(sql).all(m.cursor_thread,m.cursor_n,m.end_n,limit)
        : db.prepare(sql).all(m.cursor_thread,m.cursor_n,limit)) as T[]);
    }
    if (rows.length < limit && m.cursor_thread !== m.end_thread) {
      const sql = `SELECT ${columns} FROM entries e WHERE e.thread<CAST(?1 AS INTEGER)
        ${m.cursor_thread === null ? "" : "AND e.thread>CAST(?2 AS INTEGER)"}
        ORDER BY e.thread,e.n LIMIT ?${m.cursor_thread === null ? 2 : 3}`;
      rows.push(...(m.cursor_thread === null ? db.prepare(sql).all(m.end_thread,limit-rows.length)
        : db.prepare(sql).all(m.end_thread,m.cursor_thread,limit-rows.length)) as T[]);
      if (rows.length < limit) rows.push(...db.prepare(`SELECT ${columns} FROM entries e
        WHERE e.thread=CAST(?1 AS INTEGER) AND e.n<=CAST(?2 AS INTEGER) ORDER BY e.n LIMIT ?3`)
        .all(m.end_thread,m.end_n,limit-rows.length) as T[]);
    }
  }
  return rows;
}
