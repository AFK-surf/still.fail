// The calls recorded before the compact statistics began: the detail (the usage page's days, GET /v1/usage of data
// outflow) holds none of them, and the year (usage_history) none on a station whose old statistics never held every
// call. The calls themselves are all kept, so a worker takes them in, newest first, a few at a time.
//
// The two `since` are the only cursor: each batch counts a run of whole quarters and moves them to its start in one
// transaction, so a read always knows which days are complete and a stopped fill goes on from there.
import type { DatabaseSync } from "node:sqlite";
import { compactCoverageSince, hasCompactUsage, keepContextOnFill, setCompactCoverageSince } from "./usage-compact.ts";
import { hasUsageHistory, setUsageHistorySince, setUsageHistoryQuarters, usageHistorySince } from "./usage-history.ts";

const QUARTER_MS = 900_000;
const FILL_BATCH = 256;

/// One batch of at least `batch` calls, or those left, and whole quarters: true when no call is left before the two
/// `since`. A quarter is counted again from its calls, so calls written meanwhile (they count by the triggers either
/// way) are neither missed nor counted twice.
export function fillUsageStep(db: DatabaseSync, batch = FILL_BATCH): boolean {
  if (!hasCompactUsage(db) || !hasUsageHistory(db)) return true;
  db.exec("BEGIN IMMEDIATE");
  try {
    keepContextOnFill(db);
    const history = usageHistorySince(db);
    const coverage = compactCoverageSince(db);
    const end = Math.ceil(Math.max(coverage, history ?? coverage) / QUARTER_MS);
    const before = end * QUARTER_MS;
    const next = (db.prepare("SELECT at FROM usage INDEXED BY usage_at WHERE at < ? ORDER BY at DESC LIMIT 1 OFFSET ?").get(before, batch - 1)
      ?? db.prepare("SELECT at FROM usage INDEXED BY usage_at WHERE at < ? ORDER BY at LIMIT 1").get(before)) as { at: number } | undefined;
    if (next === undefined) {
      if (history !== null) setUsageHistorySince(db, null);
      db.exec("COMMIT");
      return true;
    }
    const start = Math.floor(next.at / QUARTER_MS);
    const from = start * QUARTER_MS;
    db.prepare("UPDATE usage INDEXED BY usage_at SET compact_counted = 1 WHERE at >= ? AND at < ? AND compact_counted = 0").run(from, before);
    if (from < coverage) setCompactCoverageSince(db, from);
    if (history !== null) {
      setUsageHistoryQuarters(db, start, end);
      setUsageHistorySince(db, from);
    }
    db.exec("COMMIT");
    return false;
  } catch (error) { db.exec("ROLLBACK"); throw error; }
}
