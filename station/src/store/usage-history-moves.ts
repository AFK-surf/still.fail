// A workspace's history moves without rewriting its quarters in the session update. A move redirects new writes in
// that transaction; its old physical partition is then folded into the destination in bounded transactions.
import type { DatabaseSync } from "node:sqlite";

type Scope = string | Uint8Array;
type Group = { id: number; rank: number; pending: number; physical: Scope };

export const hasHistoryMoves = (db: DatabaseSync): boolean => db.prepare(
  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_history_move_scopes'",
).get() !== undefined;
const hasHistoryMoveEpoch = (db: DatabaseSync): boolean => db.prepare(
  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_history_move_epoch'",
).get() !== undefined;

/// A reader can discard a snapshot that crossed even a move with no quarters to transfer.
export function advanceHistoryMoveEpoch(db: DatabaseSync): void {
  if (!hasHistoryMoveEpoch(db)) db.exec(`CREATE TABLE usage_history_move_epoch (id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);
    INSERT INTO usage_history_move_epoch VALUES (1, 0)`);
  db.exec("UPDATE usage_history_move_epoch SET value = value + 1 WHERE id = 1");
}

/// The tables start empty. Existing history keeps its TEXT scope until that workspace first moves. New physical scopes
/// are BLOBs, so a reused workspace name can never collide with a partition still being moved.
export function createHistoryMoves(db: DatabaseSync): void {
  db.exec(`CREATE TABLE usage_history_move_groups (id INTEGER PRIMARY KEY, parent INTEGER, rank INTEGER NOT NULL DEFAULT 0,
      pending INTEGER NOT NULL DEFAULT 0, physical NOT NULL);
    CREATE TABLE usage_history_move_scopes (scope TEXT PRIMARY KEY, group_id INTEGER NOT NULL) WITHOUT ROWID;
    CREATE TABLE usage_history_moving (source BLOB PRIMARY KEY, group_id INTEGER NOT NULL) WITHOUT ROWID;`);
}

/// SQL expression for the physical partition of a logical workspace. Scope mappings always point directly to a root.
export const historyPhysical = (scope: string): string => `COALESCE((SELECT g.physical FROM usage_history_move_scopes s
  JOIN usage_history_move_groups g ON g.id = s.group_id WHERE s.scope = ${scope}), ${scope})`;

export const HISTORY_MOVE_SCOPE = `SELECT g.physical FROM usage_history_move_scopes s
  JOIN usage_history_move_groups g ON g.id = s.group_id WHERE s.scope = ?`;
export const HISTORY_MOVE_PENDING_SCOPE = `SELECT 1 FROM usage_history_move_scopes s
  JOIN usage_history_move_groups g ON g.id = s.group_id WHERE s.scope = ? AND g.pending > 0`;
export const HISTORY_MOVE_ROWS = "SELECT quarter, calls, tokens FROM usage_history WHERE scope = ? ORDER BY quarter LIMIT ?";

function group(db: DatabaseSync, scope: string): Group {
  const found = db.prepare(`SELECT g.id, g.rank, g.pending, g.physical FROM usage_history_move_scopes s
    JOIN usage_history_move_groups g ON g.id = s.group_id WHERE s.scope = ?`).get(scope) as Group | undefined;
  if (found !== undefined) return found;
  const id = Number(db.prepare("INSERT INTO usage_history_move_groups (physical) VALUES (?)").run(scope).lastInsertRowid);
  db.prepare("INSERT INTO usage_history_move_scopes VALUES (?, ?)").run(scope, id);
  return { id, rank: 0, pending: 0, physical: scope };
}

/// Must be called in the same transaction as the session and deleted-owner changes.
export function beginHistoryMove(db: DatabaseSync, from: string, to: string): void {
  if (from === to) return;
  advanceHistoryMoveEpoch(db);
  const a = group(db, from);
  const b = group(db, to);
  const hasRows = db.prepare("SELECT 1 FROM usage_history WHERE scope = ? LIMIT 1").get(a.physical) !== undefined;
  if (hasRows) db.prepare("INSERT INTO usage_history_moving VALUES (?, ?)").run(a.physical, a.id);
  const pending = a.pending + b.pending + (hasRows ? 1 : 0);
  const aWins = a.rank >= b.rank;
  const root = aWins ? a : b;
  const child = aWins ? b : a;
  db.prepare("UPDATE usage_history_move_groups SET parent = ? WHERE id = ?").run(root.id, child.id);
  db.prepare("UPDATE usage_history_move_groups SET rank = ?, pending = ?, physical = ? WHERE id = ?")
    .run(root.rank + (a.rank === b.rank ? 1 : 0), pending, b.physical, root.id);
  db.prepare("UPDATE usage_history_move_scopes SET group_id = ? WHERE scope = ?").run(root.id, to);
  // The source name may be used again while its old partition is still being moved. Its new partition has a BLOB key.
  const fresh = Number(db.prepare("INSERT INTO usage_history_move_groups (physical) VALUES (X'')").run().lastInsertRowid);
  db.prepare("UPDATE usage_history_move_groups SET physical = CAST(? AS BLOB) WHERE id = ?").run(fresh, fresh);
  db.prepare("UPDATE usage_history_move_scopes SET group_id = ? WHERE scope = ?").run(fresh, from);
  // Most moves have few quarters. Finish up to 128 here (at most 256 history-row writes), after routing new writes.
  if (hasRows) foldHistoryBatch(db, { source: a.physical, group_id: a.id }, 128);
}

/// Changes whenever logical ownership is redirected, including a move that finishes in the calling transaction.
export function historyMoveEpoch(db: DatabaseSync): number {
  if (!hasHistoryMoveEpoch(db)) return 0;
  return (db.prepare("SELECT value FROM usage_history_move_epoch WHERE id = 1").get() as { value: number }).value;
}

/// A page must not see an incomplete partition while its workspace's old rows are being folded in.
export function historyMovesPending(db: DatabaseSync, scopes: string[] | null = null): boolean {
  if (!hasHistoryMoves(db)) return false;
  if (scopes === null) return db.prepare("SELECT 1 FROM usage_history_moving LIMIT 1").get() !== undefined;
  const pending = db.prepare(HISTORY_MOVE_PENDING_SCOPE);
  return scopes.some((scope) => pending.get(scope) !== undefined);
}

export function physicalHistoryScope(db: DatabaseSync, scope: string): Scope {
  if (!hasHistoryMoves(db)) return scope;
  return (db.prepare(HISTORY_MOVE_SCOPE).get(scope) as { physical: Scope } | undefined)?.physical ?? scope;
}

/// Move at most `batch` old quarters, or finish one empty source, under a single write lock. Its owner can have moved
/// again since it was queued; union by rank keeps the path to its current root short.
type Move = { source: Scope; group_id: number };

/// The caller owns the write transaction. Rows are removed only after their contribution reaches the current root.
function foldHistoryBatch(db: DatabaseSync, move: Move, batch: number): boolean {
  const root = db.prepare(`WITH RECURSIVE owners(id) AS (SELECT ?1 UNION ALL
    SELECT g.parent FROM usage_history_move_groups g JOIN owners o ON g.id = o.id WHERE g.parent IS NOT NULL)
    SELECT g.id, g.physical, g.pending FROM owners o JOIN usage_history_move_groups g ON g.id = o.id WHERE g.parent IS NULL`)
    .get(move.group_id) as Group;
  const rows = db.prepare(HISTORY_MOVE_ROWS)
    .all(move.source, batch) as { quarter: number; calls: number; tokens: number }[];
  const add = db.prepare(`INSERT INTO usage_history (scope, quarter, calls, tokens) VALUES (?, ?, ?, ?)
    ON CONFLICT (scope, quarter) DO UPDATE SET calls = calls + excluded.calls, tokens = tokens + excluded.tokens`);
  const drop = db.prepare("DELETE FROM usage_history WHERE scope = ? AND quarter = ?");
  for (const row of rows) {
    add.run(root.physical, row.quarter, row.calls, row.tokens);
    drop.run(move.source, row.quarter);
  }
  if (rows.length === batch && db.prepare("SELECT 1 FROM usage_history WHERE scope = ? LIMIT 1").get(move.source) !== undefined) return false;
  db.prepare("DELETE FROM usage_history_total WHERE scope = ?").run(move.source);
  db.prepare("DELETE FROM usage_history_moving WHERE source = ?").run(move.source);
  db.prepare("UPDATE usage_history_move_groups SET pending = pending - 1 WHERE id = ?").run(root.id);
  return root.pending === 1;
}

export function moveHistoryStep(db: DatabaseSync, batch = 256): { done: boolean; ready?: boolean } {
  if (!hasHistoryMoves(db)) return { done: true };
  if (!Number.isSafeInteger(batch) || batch < 1) throw new RangeError("history move batch must be positive");
  batch = Math.min(batch, 256);
  db.exec("BEGIN IMMEDIATE");
  try {
    const move = db.prepare("SELECT source, group_id FROM usage_history_moving ORDER BY source LIMIT 1").get() as Move | undefined;
    if (move === undefined) { db.exec("COMMIT"); return { done: true }; }
    const ready = foldHistoryBatch(db, move, batch);
    db.exec("COMMIT");
    return { done: false, ready };
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
