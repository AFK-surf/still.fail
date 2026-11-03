// Fill old minute summaries on a separate connection. A workspace asking for its history takes priority in bounded
// batches; background work still gets a turn, and progress is kept in the database.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { BACKFILL_PAUSE_MS, REQUEST_BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import { backfillNextUsageSession, backfillUsageMinutes, PENDING_MINUTE_SESSION } from "../store/usage-minutes.ts";
import { backfillNextUsageDetail, backfillUsageDetail, backfillUsageDetailMove, PENDING_DETAIL_SESSION, usageDetailReady } from "../store/usage-detail.ts";
import { backfillRemoteRuns } from "../store/remote-runs.ts";
import { backfillUsageChatStats, usageChatStatsReady } from "../store/usage-chat-stats.ts";
import type { InWorkspace } from "../store/rows.ts";
import type { MinuteRequest, MinuteResponse } from "./minute-reader.ts";

type Waiting = { request: Extract<MinuteRequest, { viewer: unknown } | { detail: unknown }>; after: string | null; sessions: string[]; scanned: boolean };
const db = new DatabaseSync(workerData.path as string, { timeout: 100 });
db.exec("PRAGMA synchronous = NORMAL");
const waiting: Waiting[] = [];
const remoteWaiting: number[] = [];
const chatWaiting: { id: number; viewer: InWorkspace | null }[] = [];
const scanned = new Set<string>();
let complete = (db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number }).done === 1;
const detailInstalled = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_detail_all'").get() !== undefined;
const detailsReady = (viewer: InWorkspace | null = null) => !detailInstalled || usageDetailReady(db, viewer);
let detailComplete = detailsReady();
const remoteInstalled = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'remote_run_progress'").get() !== undefined;
let remoteComplete = !remoteInstalled || (db.prepare("SELECT done FROM remote_run_progress WHERE id = 1").get() as { done: number }).done === 1;
const chatInstalled = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_chat_progress'").get() !== undefined;
const chatsReady = (viewer: InWorkspace | null = null) => !chatInstalled || usageChatStatsReady(db, viewer);
let chatComplete = chatsReady();
let backgroundTurn = 0;
let scheduled = false;
let foreground = 0;
let backgroundFailed = false;
let backgroundError: string | null = null;
let foregroundWaiting = false;
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;

function signalComplete() {
  if (chatComplete) chatComplete = chatsReady();
  if (detailComplete) detailComplete = detailsReady();
  if (remoteComplete) for (const id of remoteWaiting.splice(0)) parentPort!.postMessage({ id } satisfies MinuteResponse);
  for (let i = chatWaiting.length - 1; i >= 0; i--) {
    const q = chatWaiting[i]!;
    if (chatsReady(q.viewer)) {
      chatWaiting.splice(i, 1);
      parentPort!.postMessage({ id: q.id } satisfies MinuteResponse);
    }
  }
  if (complete && detailComplete && remoteComplete && chatComplete) parentPort!.postMessage({ complete: true } satisfies MinuteResponse);
}

// A ready workspace can be checked with reads alone, even while a foreground writer is waiting. Return null only
// when the next step really has to take a write transaction.
function one(q: Waiting, mayWrite: boolean): boolean | null {
  const detail = "detail" in q.request;
  const viewer = "detail" in q.request ? q.request.detail : q.request.viewer;
  if (detail) {
    if (detailsReady(viewer)) return true;
    const dirty = (viewer === null
      ? db.prepare("SELECT session FROM usage_detail_dirty ORDER BY session LIMIT 1").get()
      : viewer.home === false
        ? db.prepare("SELECT session FROM usage_detail_dirty_scope INDEXED BY usage_detail_dirty_by_scope WHERE scope = ? LIMIT 1").get(`W${viewer.workspace}`)
        : db.prepare("SELECT session FROM usage_detail_dirty_scope INDEXED BY usage_detail_dirty_by_scope WHERE scope IN (?, 'H') LIMIT 1").get(`W${viewer.workspace}`)) as { session: string } | undefined;
    if (dirty) {
      if (!mayWrite) return null;
      backfillUsageDetailMove(db, 32, dirty.session);
      detailComplete = detailsReady();
      signalComplete();
      return detailsReady(viewer);
    }
  } else if (complete) return true;
  while (q.sessions.length) {
    const session = q.sessions[0]!;
    const state = db.prepare(`SELECT done FROM ${detail ? "usage_detail_sessions" : "usage_minute_sessions"} WHERE session = ?`).get(session) as { done: number } | undefined;
    if (state?.done || (state === undefined && !db.prepare("SELECT 1 FROM usage INDEXED BY usage_session WHERE session = ? LIMIT 1").get(session))) {
      q.sessions.shift();
      continue;
    }
    if (!mayWrite) return null;
    if ((detail ? backfillUsageDetail(db, session) : backfillUsageMinutes(db, session)).done) q.sessions.shift();
    return false;
  }
  if (!q.scanned) {
    const rows = (q.after === null
      ? db.prepare("SELECT key, ws FROM sessions INDEXED BY sessions_ws ORDER BY key LIMIT 32").all()
      : db.prepare("SELECT key, ws FROM sessions INDEXED BY sessions_ws WHERE key > ? ORDER BY key LIMIT 32").all(q.after)) as { key: string; ws: string | null }[];
    q.after = rows.at(-1)?.key ?? q.after;
    q.sessions = rows.filter((r) => viewer === null || r.ws === viewer.workspace || (r.ws === null && viewer.home !== false)).map((r) => r.key);
    q.scanned = rows.length < 32;
    return false;
  }
  if (viewer !== null && viewer.home === false) {
    // A session can have entered this workspace while it was being scanned. Its trigger records an unfinished state.
    const pending = db.prepare(detail ? PENDING_DETAIL_SESSION : PENDING_MINUTE_SESSION).get(viewer.workspace) as { session: string } | undefined;
    if (pending) {
      q.sessions.push(pending.session);
      return false;
    }
    if (detail) {
      if (!db.prepare("SELECT 1 FROM usage_detail_ready WHERE ws = ?").get(viewer.workspace)) {
        if (!mayWrite) return null;
        db.prepare("INSERT OR IGNORE INTO usage_detail_ready VALUES (?)").run(viewer.workspace);
      }
    } else scanned.add(viewer.workspace);
    return true;
  }
  // The home workspace also owns usage of sessions that no longer exist. Discover those in the background index.
  if (!mayWrite) return null;
  if (detail) {
    backfillNextUsageDetail(db);
    detailComplete = detailsReady();
    if (detailComplete) signalComplete();
    return detailComplete;
  }
  complete = backfillNextUsageSession(db).done;
  if (complete) signalComplete();
  return complete;
}

function schedule(delay = 0) {
  if (scheduled) return;
  scheduled = true;
  const step = () => {
    scheduled = false;
    const q = waiting.length && (foreground < 8 || backgroundFailed || (complete && detailComplete && remoteComplete && chatComplete) || (priority !== null && Atomics.load(priority, 0) !== 0))
      ? waiting.shift() : undefined;
    let held = false;
    const take = () => {
      if (takeBackfill(priority, threadId)) {
        held = true;
        foregroundWaiting = false;
        return true;
      }
      if (!foregroundWaiting && priority !== null && Atomics.load(priority, 0) !== 0) {
        foregroundWaiting = true;
        parentPort!.postMessage({ foreground: true, request: q?.request.id });
      }
      return false;
    };
    try {
      if (q) {
        let done = one(q, false);
        if (done === null) {
          if (!take()) {
            waiting.push(q);
            schedule(waiting.length > 1 ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
            return;
          }
          done = one(q, true);
        }
        foreground++;
        if (done) parentPort!.postMessage({ id: q.request.id } satisfies MinuteResponse);
        else waiting.push(q);
      } else if ((!complete || !detailComplete || !remoteComplete || !chatComplete) && !backgroundFailed) {
        if (!take()) {
          // The background turn cannot write now; let waiting requests try their read-only steps.
          if (waiting.length) foreground = 0;
          schedule(waiting.length || remoteWaiting.length || chatWaiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
          return;
        }
        foreground = 0;
        for (let i = 0; i < 4; i++) {
          const turn = backgroundTurn++ % 4;
          if (turn === 0 && !complete) { complete = backfillNextUsageSession(db).done; break; }
          if (turn === 1 && !remoteComplete) { remoteComplete = backfillRemoteRuns(db).done; break; }
          if (turn === 2 && !chatComplete) { chatComplete = backfillUsageChatStats(db).done; break; }
          if (turn === 3 && !detailComplete) {
            if (db.prepare("SELECT 1 FROM usage_detail_dirty LIMIT 1").get()) backfillUsageDetailMove(db);
            else backfillNextUsageDetail(db);
            detailComplete = detailsReady();
            break;
          }
        }
        signalComplete();
      }
    } catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code !== undefined && ((code & 0xff) === 5 || (code & 0xff) === 6)) {
        if (q) waiting.push(q);
        schedule(waiting.length > 1 ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
        return;
      }
      if (q) parentPort!.postMessage({ id: q.request.id, error: (error as Error).message } satisfies MinuteResponse);
      else {
        backgroundFailed = true;
        backgroundError = (error as Error).message;
        for (const id of remoteWaiting.splice(0)) parentPort!.postMessage({ id, error: backgroundError } satisfies MinuteResponse);
        for (const q of chatWaiting.splice(0)) parentPort!.postMessage({ id: q.id, error: backgroundError } satisfies MinuteResponse);
        log.error("usage", "the minute summary backfill stopped", { error: backgroundError });
      }
    } finally {
      if (held) giveBackfill(priority, threadId);
    }
    if (waiting.length || ((!complete || !detailComplete || !remoteComplete || !chatComplete) && !backgroundFailed))
      schedule(waiting.length || remoteWaiting.length || chatWaiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
  };
  if (delay > 0) wall.after(delay, step);
  else setImmediate(step);
}

parentPort!.on("message", (request: MinuteRequest) => {
  foregroundWaiting = false;
  if ("remote" in request) {
    if (remoteComplete || backgroundError !== null) parentPort!.postMessage({ id: request.id, ...(backgroundError !== null && !remoteComplete ? { error: backgroundError } : {}) } satisfies MinuteResponse);
    else remoteWaiting.push(request.id);
    return;
  }
  if ("chats" in request) {
    if (chatComplete) chatComplete = chatsReady();
    const ready = chatsReady(request.chats);
    if (ready || backgroundError !== null) parentPort!.postMessage({ id: request.id, ...(backgroundError !== null && !ready ? { error: backgroundError } : {}) } satisfies MinuteResponse);
    else { chatWaiting.push({ id: request.id, viewer: request.chats }); schedule(); }
    return;
  }
  const viewer = "detail" in request ? request.detail : request.viewer;
  if ("detail" in request && detailComplete) detailComplete = detailsReady();
  const scannedAlready = viewer !== null && viewer.home === false && ("detail" in request
    ? !!db.prepare("SELECT 1 FROM usage_detail_ready WHERE ws = ?").get(viewer.workspace) : scanned.has(viewer.workspace));
  waiting.push({ request, after: null, sessions: [], scanned: scannedAlready });
  schedule();
});
if (complete && detailComplete && remoteComplete && chatComplete) signalComplete();
else schedule();
