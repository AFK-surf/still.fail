// Fill old minute summaries on a separate connection. A workspace asking for its history takes priority in bounded
// batches; background work still gets a turn, and progress is kept in the database.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { BACKFILL_PAUSE_MS, REQUEST_BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import { backfillNextUsageSession, backfillUsageMinutes, PENDING_MINUTE_SESSION } from "../store/usage-minutes.ts";
import type { MinuteRequest, MinuteResponse } from "./minute-reader.ts";

type Waiting = { request: MinuteRequest; after: string | null; sessions: string[]; scanned: boolean };
const db = new DatabaseSync(workerData.path as string, { timeout: 100 });
db.exec("PRAGMA synchronous = NORMAL");
const waiting: Waiting[] = [];
const scanned = new Set<string>();
let complete = (db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number }).done === 1;
let scheduled = false;
let foreground = 0;
let backgroundFailed = false;
let foregroundWaiting = false;
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;

function signalComplete() {
  parentPort!.postMessage({ complete: true } satisfies MinuteResponse);
}

// A ready workspace can be checked with reads alone, even while a foreground writer is waiting. Return null only
// when the next step really has to take a write transaction.
function one(q: Waiting, mayWrite: boolean): boolean | null {
  if (complete) return true;
  const viewer = q.request.viewer;
  while (q.sessions.length) {
    const session = q.sessions[0]!;
    const state = db.prepare("SELECT done FROM usage_minute_sessions WHERE session = ?").get(session) as { done: number } | undefined;
    if (state?.done || (state === undefined && !db.prepare("SELECT 1 FROM usage INDEXED BY usage_session WHERE session = ? LIMIT 1").get(session))) {
      q.sessions.shift();
      continue;
    }
    if (!mayWrite) return null;
    if (backfillUsageMinutes(db, session).done) q.sessions.shift();
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
    const pending = db.prepare(PENDING_MINUTE_SESSION).get(viewer.workspace) as { session: string } | undefined;
    if (pending) {
      q.sessions.push(pending.session);
      return false;
    }
    scanned.add(viewer.workspace);
    return true;
  }
  // The home workspace also owns usage of sessions that no longer exist. Discover those in the background index.
  if (!mayWrite) return null;
  const step = backfillNextUsageSession(db);
  complete = step.done;
  if (complete) signalComplete();
  return complete;
}

function schedule(delay = 0) {
  if (scheduled) return;
  scheduled = true;
  const step = () => {
    scheduled = false;
    const q = waiting.length && (foreground < 8 || backgroundFailed || complete || (priority !== null && Atomics.load(priority, 0) !== 0))
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
      } else if (!complete && !backgroundFailed) {
        if (!take()) {
          // The background turn cannot write now; let waiting requests try their read-only steps.
          if (waiting.length) foreground = 0;
          schedule(waiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
          return;
        }
        foreground = 0;
        complete = backfillNextUsageSession(db).done;
        if (complete) signalComplete();
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
        log.error("usage", "the minute summary backfill stopped", { error: (error as Error).message });
      }
    } finally {
      if (held) giveBackfill(priority, threadId);
    }
    if (waiting.length || (!complete && !backgroundFailed)) schedule(waiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
  };
  if (delay > 0) wall.after(delay, step);
  else setImmediate(step);
}

parentPort!.on("message", (request: MinuteRequest) => {
  foregroundWaiting = false;
  const viewer = request.viewer;
  waiting.push({ request, after: null, sessions: [], scanned: viewer !== null && viewer.home === false && scanned.has(viewer.workspace) });
  schedule();
});
if (complete) signalComplete();
else schedule();
