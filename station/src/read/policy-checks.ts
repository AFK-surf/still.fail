// The checks a workspace's archive policy view counts (sessions/archive-policy.ts `policyChecks`), counted in a reader:
// a week's checks, each chat's latest, by the time index (and, for another workspace's viewer, by its chats' own).
import type { DatabaseSync } from "node:sqlite";
import { type PolicyChecks, policyChecks } from "../sessions/archive-policy.ts";
import { hasLegacyDecisionTime } from "../store/legacy-decision-time.ts";
import type { InWorkspace } from "../store/rows.ts";
import { LATEST_DECISIONS_SCOPED, LATEST_DECISIONS_SCOPED_FALLBACK } from "../store/store.ts";

const hasIndex = (db: DatabaseSync, name: string) => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?").get(name) !== undefined;

/// What the checks since `since` say of `viewer`'s workspace's chats; null on a store whose lookups of them are still
/// being prepared (the main thread's store reads it then, as it knows how far that has come).
export function policyChecksRead(db: DatabaseSync, since: number, viewer: InWorkspace): PolicyChecks | null {
  if (hasLegacyDecisionTime(db) || !hasIndex(db, "decision_checks_lately") || !hasIndex(db, "decision_checks_session")) return null;
  const home = viewer.home !== false;
  let rows: Record<string, unknown>[];
  try {
    rows = db.prepare(home ? LATEST_DECISIONS_SCOPED_FALLBACK : LATEST_DECISIONS_SCOPED).all(since, viewer.workspace, home ? 1 : 0) as Record<string, unknown>[];
  } catch (error) {
    if (/no such (index|table)/.test(error instanceof Error ? error.message : "")) return null;
    throw error;
  }
  return policyChecks(rows.map((r) => ({ session: r.session, at: r.created_at as number, detail: parsed(r.result) })));
}

const parsed = (v: unknown): unknown => {
  if (typeof v !== "string") return null;
  try {
    return JSON.parse(v);
  } catch {
    return null;
  }
};
