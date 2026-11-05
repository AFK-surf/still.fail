// A single bounded piece of requested recent-chat preparation. This coordinator is not yet connected to readers.
import type { DatabaseSync } from "node:sqlite";
import { installRecentHomeIndex, scanRecentHomeChatsStep, settleRecentHomeChatStep,
  settleRecentHomeOrderStep, settleRecentHomeSessionStep } from "./chat-list-home-index.ts";
import { installRecentHomeOverlap, readPreparedRecentHome, scanRecentHomeOverlapStep, settleRecentHomeOverlapStep } from "./chat-list-home-overlap.ts";
import { installRecentChatIndex, readGlobalRecentChatIndex, stepRecentChatIndex } from "./chat-list-index.ts";
import { scanRecentWorkspaceStep, settleRecentWorkspaceMemberStep, settleRecentWorkspaceSessionStep } from "./chat-list-scope-build.ts";
import { installRecentScopeJournal, trackRecentScope } from "./chat-list-scope-journal.ts";
import { dispatchRecentScopeOrderStep, settleRecentWorkspaceOrderStep } from "./chat-list-scope-order.ts";
import { readPreparedRecentWorkspace } from "./chat-list-scope-rows.ts";
import { settleRecentScopeVisibilityStep } from "./chat-list-scope-visibility.ts";

export type RecentChatScope = { ws: string | null; home: string | null };
type Lane = { pending: () => boolean; step: () => number };

/// One worker can interleave requests by calling step once per scope and putting unfinished scopes back in line.
/// The caller must wait for a previous station process to leave, stop on cancellation, and release write priority
/// between steps. A returned `done` is only a hint: the reader must check the journals again in its own snapshot.
export class RecentChatPreparation {
  readonly #db: DatabaseSync;
  readonly #limit: number;
  readonly #turns = new Map<string, number>();
  #globalInstalled = false;
  #scopeInstalled = false;
  #homeInstalled = false;
  readonly #tracked = new Set<string>();

  constructor(db: DatabaseSync, limit = 64) {
    if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent chat preparation batch must be positive");
    this.#db = db;
    this.#limit = limit;
  }

  step({ ws, home }: RecentChatScope): { done: boolean; visited: number } {
    const db = this.#db, limit = this.#limit;
    if (ws === null) {
      if (!this.#globalInstalled) { installRecentChatIndex(db); this.#globalInstalled = true; }
      if (readGlobalRecentChatIndex(db, 1) !== null) return { done: true, visited: 0 };
      const result = stepRecentChatIndex(db, limit);
      return { done: result.done, visited: result.processed };
    }
    if (!this.#scopeInstalled) { installRecentScopeJournal(db); this.#scopeInstalled = true; }
    if (!this.#tracked.has(ws)) { trackRecentScope(db, { kind: "workspace", workspace: ws }); this.#tracked.add(ws); }
    const isHome = ws === home;
    if (isHome && !this.#homeInstalled) {
      installRecentHomeIndex(db);
      installRecentHomeOverlap(db);
      this.#homeInstalled = true;
    }
    const ready = () => isHome ? readPreparedRecentHome(db, ws, 1) !== null : readPreparedRecentWorkspace(db, ws, 1) !== null;
    if (ready()) return { done: true, visited: 0 };
    const scope = db.prepare("SELECT scan_done, scan_session, complete FROM recent_scope_tracked WHERE kind = 1 AND ws = ?")
      .get(ws) as { scan_done: number; scan_session: string | null; complete: number };
    const scanned = scope.scan_done === 1 && scope.scan_session === null;
    const exists = (sql: string) => db.prepare(sql).get() !== undefined;
    const scoped = (sql: string) => db.prepare(sql).get(ws) !== undefined;
    const lanes: Lane[] = [
      { pending: () => !scanned, step: () => scanRecentWorkspaceStep(db, ws, limit).visited },
      { pending: () => scanned && scope.complete !== 1, step: () => {
        db.prepare("UPDATE recent_scope_tracked SET complete = 1 WHERE kind = 1 AND ws = ? AND scan_done = 1 AND scan_session IS NULL").run(ws);
        return 0;
      } },
      { pending: () => scanned && scoped("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 1 AND ws = ? LIMIT 1"),
        step: () => settleRecentWorkspaceSessionStep(db, ws, limit).visited },
      { pending: () => scanned && scoped("SELECT 1 FROM recent_scope_member_dirty WHERE ws = ? LIMIT 1"),
        step: () => settleRecentWorkspaceMemberStep(db, ws, limit).visited },
      { pending: () => scoped("SELECT 1 FROM recent_scope_order_dirty WHERE ws = ? LIMIT 1"),
        step: () => settleRecentWorkspaceOrderStep(db, ws, limit).visited },
      { pending: () => exists("SELECT 1 FROM recent_scope_visibility_dirty LIMIT 1"),
        step: () => settleRecentScopeVisibilityStep(db, limit).visited },
      { pending: () => exists("SELECT 1 FROM recent_scope_order_dispatch LIMIT 1"),
        step: () => dispatchRecentScopeOrderStep(db, limit).visited },
    ];
    if (isHome) lanes.push(
      { pending: () => exists("SELECT 1 FROM recent_home_meta WHERE id = 1 AND scan_done = 0"),
        step: () => scanRecentHomeChatsStep(db, limit).visited },
      { pending: () => exists("SELECT 1 FROM recent_scope_session_dirty WHERE kind = 0 AND ws = '' LIMIT 1"),
        step: () => settleRecentHomeSessionStep(db, limit).visited },
      { pending: () => exists("SELECT 1 FROM recent_home_dirty LIMIT 1"), step: () => settleRecentHomeChatStep(db, limit).visited },
      { pending: () => exists("SELECT 1 FROM recent_home_order_dirty LIMIT 1"), step: () => settleRecentHomeOrderStep(db, limit).visited },
      { pending: () => exists("SELECT 1 FROM recent_home_overlap_meta WHERE id = 1 AND scan_done = 0"),
        step: () => scanRecentHomeOverlapStep(db, limit).visited },
      { pending: () => exists("SELECT 1 FROM recent_home_overlap_dirty LIMIT 1"), step: () => settleRecentHomeOverlapStep(db, limit).visited },
    );
    // Each requested scope has different lanes. Sharing a turn between them can repeatedly skip one scope's
    // home-only work when another busy scope is interleaved with it.
    const key = JSON.stringify([ws, isHome]), turn = this.#turns.get(key) ?? 0;
    for (let n = 0; n < lanes.length; n++) {
      const at = (turn + n) % lanes.length, lane = lanes[at]!;
      if (!lane.pending()) continue;
      this.#turns.set(key, (at + 1) % lanes.length);
      return { done: false, visited: lane.step() };
    }
    // Another connection can have completed work after the earlier readiness check.
    if (ready()) return { done: true, visited: 0 };
    throw new Error("recent chat preparation has no runnable work");
  }
}
