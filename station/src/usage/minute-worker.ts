// Fill old minute summaries on a separate connection. A workspace asking for its history takes priority in bounded
// batches; background work still gets a turn, and progress is kept in the database.
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
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

function signalComplete() {
  parentPort!.postMessage({ complete: true } satisfies MinuteResponse);
}

function one(q: Waiting): boolean {
  if (complete) return true;
  const viewer = q.request.viewer;
  const session = q.sessions[0];
  if (session !== undefined) {
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
  const step = backfillNextUsageSession(db);
  complete = step.done;
  if (complete) signalComplete();
  return complete;
}

function schedule() {
  if (scheduled) return;
  scheduled = true;
  setImmediate(() => {
    scheduled = false;
    const q = waiting.length && (foreground < 8 || backgroundFailed || complete) ? waiting.shift() : undefined;
    try {
      if (q) {
        foreground++;
        if (one(q)) parentPort!.postMessage({ id: q.request.id } satisfies MinuteResponse);
        else waiting.push(q);
      } else if (!complete && !backgroundFailed) {
        foreground = 0;
        complete = backfillNextUsageSession(db).done;
        if (complete) signalComplete();
      }
    } catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code !== undefined && ((code & 0xff) === 5 || (code & 0xff) === 6)) {
        if (q) waiting.unshift(q);
        wall.after(50, schedule);
        return;
      }
      if (q) parentPort!.postMessage({ id: q.request.id, error: (error as Error).message } satisfies MinuteResponse);
      else {
        backgroundFailed = true;
        log.error("usage", "the minute summary backfill stopped", { error: (error as Error).message });
      }
    }
    if (waiting.length || (!complete && !backgroundFailed)) schedule();
  });
}

parentPort!.on("message", (request: MinuteRequest) => {
  const viewer = request.viewer;
  waiting.push({ request, after: null, sessions: [], scanned: viewer !== null && viewer.home === false && scanned.has(viewer.workspace) });
  schedule();
});
if (complete) signalComplete();
else schedule();
