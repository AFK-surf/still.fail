// A working chat's workspace on each station has a soft size limit. Measurements are shared and queued so many active
// chats do not walk the disk at once; links are not followed and hard links count once (sessions/footprint.ts).
import { createHash } from "node:crypto";
import { mkdir, readFile, readdir, rm } from "node:fs/promises";
import { join } from "node:path";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { PrivateFile } from "../ops/files.ts";
import { log } from "../ops/log.ts";
import { measuredUpTo } from "../sessions/footprint.ts";
import type { DatabaseSync } from "node:sqlite";
import type { Store } from "../store/store.ts";

export const GIB = 1024 ** 3;
export const DEFAULT_LIMIT = 10 * GIB;
export const CHECK_MS = 5 * 60_000;
export const REMIND_MS = 60 * 60_000;

/// Recheck the chat when its workspace reading comes back: its turn or jobs may have ended meanwhile.
export function workspaceWorking(store: Pick<Store, "getSession" | "runningJobsAtLeast" | "lastTurn">,
  processState: (key: string) => string, key: string): boolean {
  const row = store.getSession(key);
  if (row === null) return false;
  return row.archivedAt === null && (row.running || processState(key) === "running"
    || store.runningJobsAtLeast(key, 1) || store.lastTurn(key)?.declared === "waiting");
}

/// The most of the sessions shown (the latest active first) a round looks at: what auto-archiving keeps shown, with room.
export const MEASURED_MOST = 1000;
const atWork = (jobs: string) => `SELECT s.key, s.workspace FROM (SELECT rowid AS rid, key, workspace, running, last_active_at
  FROM sessions INDEXED BY sessions_live WHERE archived_at IS NULL ORDER BY last_active_at DESC, rowid DESC LIMIT ?2) s
  WHERE s.running = 1 OR s.key IN (SELECT value FROM json_each(?1)) OR ${jobs}
    OR (SELECT declared FROM turns INDEXED BY turns_by_session WHERE session_key = s.key ORDER BY started_at DESC, rowid DESC LIMIT 1) = 'waiting'
  ORDER BY s.last_active_at DESC, s.rid DESC`;
/// The sessions shown that are at work (a turn running, its process running, a job of its running, or waiting on what
/// it started), each by its own index entries: a reader's (read/ops-sessions.ts), off the main thread, where it read
/// every session shown and each one's latest turn, held up to 18 s on a station short of memory (2026-11-06).
export const SESSIONS_AT_WORK = atWork(`EXISTS (SELECT 1 FROM active_watch_jobs INDEXED BY active_watch_jobs_session WHERE session = s.key)
    OR EXISTS (SELECT 1 FROM active_other_jobs WHERE session = s.key)`);
/// The same on a store whose running jobs' lookup is still being prepared (store/active-jobs-upgrade.ts).
export const SESSIONS_AT_WORK_BEFORE_UPGRADE = atWork("EXISTS (SELECT 1 FROM jobs INDEXED BY jobs_by_session WHERE session_key = s.key AND state = 'running')");

/// The sessions whose workspaces are measured this round: those at work (SESSIONS_AT_WORK); `processes`, those whose
/// process runs now.
export function workspaceSessionsToMeasure(db: DatabaseSync, processes: readonly string[], most = MEASURED_MOST): { key: string; workspace: string }[] {
  const args = [JSON.stringify(processes), most];
  let rows: unknown[];
  try { rows = db.prepare(SESSIONS_AT_WORK).all(...args); }
  catch (error) {
    if (!/no such table: active_(watch|other)_jobs/.test(error instanceof Error ? error.message : "")) throw error;
    rows = db.prepare(SESSIONS_AT_WORK_BEFORE_UPGRADE).all(...args);
  }
  return rows.map((r) => ({ key: (r as { key: string }).key, workspace: (r as { workspace: string }).workspace }));
}

export type WorkspaceSize = { bytes: number; complete: boolean };
type Measurement = { size: WorkspaceSize | null; at: number; pending: boolean; limit: number };

/// A single asynchronous disk walk at a time, shared by local and incoming remote requests. A caller never waits for
/// the walk on an RPC: it asks again for the completed result. A fresh result is reused for CHECK_MS.
export class WorkspaceReader {
  readonly #now: () => number;
  readonly #read: (path: string, limit: number, signal: AbortSignal) => Promise<WorkspaceSize>;
  readonly #abort = new AbortController();
  readonly #entries = new Map<string, Measurement>();
  readonly #queue: string[] = [];
  #running = false;

  constructor(now: () => number, read: (path: string, limit: number, signal: AbortSignal) => Promise<WorkspaceSize> = measuredUpTo) {
    this.#now = now;
    this.#read = read;
  }

  size(path: string, limit = DEFAULT_LIMIT): WorkspaceSize | null {
    if (this.#abort.signal.aborted) return null;
    let entry = this.#entries.get(path);
    if (entry?.size && this.#now() - entry.at < CHECK_MS && (entry.size.complete || entry.size.bytes > limit)) return entry.size;
    if (!entry) {
      entry = { size: null, at: 0, pending: false, limit };
      this.#entries.set(path, entry);
    }
    if (!entry.pending) {
      entry.pending = true;
      entry.limit = limit;
      this.#queue.push(path);
      void this.#next();
    }
    return null;
  }

  async #next(): Promise<void> {
    if (this.#running) return;
    this.#running = true;
    try {
      while (!this.#abort.signal.aborted && this.#queue.length > 0) {
        const path = this.#queue.shift()!;
        const entry = this.#entries.get(path)!;
        try {
          entry.size = await this.#read(path, entry.limit, this.#abort.signal);
          entry.at = this.#now();
        } catch (error) {
          entry.size = null;
          if (!this.#abort.signal.aborted) log.warn("workspace-size", "workspace not measured", { path, error: (error as Error).message });
        } finally {
          entry.pending = false;
        }
      }
    } finally {
      this.#running = false;
    }
  }

  close(): void {
    this.#abort.abort();
    this.#queue.length = 0;
  }
}

/// `station` is empty for the session's own station, otherwise the target station's id.
export type WorkspaceReading = { session: string; station: string; name: string; path: string; bytes: number; complete: boolean };
type Limit = { bytes: number; over: boolean; told: number | null };
type Limits = Record<string, Limit>;

export type WorkspaceWatchOptions = {
  data: string;
  clock?: Clock.Clock;
  /// Ready measurements of working sessions. Missing or still-running measurements are omitted, not treated as zero.
  readings(): Promise<WorkspaceReading[]>;
  working(session: string): boolean;
  notify(session: string, text: string): void | Promise<void>;
};

export class WorkspaceWatch {
  readonly #o: WorkspaceWatchOptions;
  readonly #fibers: Fibers;
  readonly #directory: string;
  readonly #limits = new Map<string, Limits>();
  readonly #files = new Map<string, PrivateFile>();
  readonly #ready: Promise<void>;

  constructor(options: WorkspaceWatchOptions) {
    this.#o = options;
    this.#fibers = new Fibers("workspace-size", options.clock);
    this.#directory = join(options.data, "workspace-limits");
    this.#ready = this.#readAll();
  }

  /// Once every chat's limit is read (off the station's thread, as it starts): what is said of one before is the default.
  ready(): Promise<void> {
    return this.#ready;
  }

  start(): void {
    const tick = async () => {
      try { await this.look(); } finally { this.#fibers.after(CHECK_MS, tick); }
    };
    this.#fibers.after(60_000, tick);
  }

  async close(): Promise<void> {
    await this.#fibers.close();
    await Promise.all([...this.#files.values()].map((file) => file.written()));
  }

  /// An archived chat can be restored with its limit; a deleted chat has no settings left behind.
  forget(session: string): void {
    this.#limits.delete(session);
    this.#read.delete(this.#file(session).slice(this.#directory.length + 1));
    void rm(this.#file(session), { force: true }).catch((error) =>
      log.warn("workspace-size", "deleted chat's limit not removed", { session, error: (error as Error).message }));
  }

  #file(session: string): string {
    return join(this.#directory, `${createHash("sha256").update(session).digest("hex")}.json`);
  }

  /// What each chat's file says, read off the station's thread as it starts: read on it at the first look after every
  /// update, these reads can hold up its other work. By file name; null: none could be read.
  readonly #read = new Map<string, string | null>();

  async #readAll(): Promise<void> {
    await mkdir(this.#directory, { recursive: true }).catch(() => undefined);
    for (const name of await readdir(this.#directory).catch(() => [] as string[])) {
      if (!name.endsWith(".json") || this.#read.has(name)) continue;
      this.#read.set(name, await readFile(join(this.#directory, name), "utf8").catch(() => null));
    }
  }

  #of(session: string): Limits {
    let all = this.#limits.get(session);
    if (all) return all;
    all = Object.create(null) as Limits;
    try {
      const file = this.#file(session);
      const name = file.slice(this.#directory.length + 1);
      const text = this.#read.get(name);
      this.#read.delete(name);
      // None read: none written (they are all read as it starts).
      if (text === undefined || text === null) throw new Error("none");
      const parsed: unknown = JSON.parse(text);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        for (const [station, value] of Object.entries(parsed)) {
          if (!value || typeof value !== "object") continue;
          const limit = value as Partial<Limit>;
          if (!Number.isSafeInteger(limit.bytes) || limit.bytes! < GIB) continue;
          all[station] = { bytes: limit.bytes!, over: limit.over === true, told: typeof limit.told === "number" ? limit.told : null };
        }
      }
    } catch {}
    this.#limits.set(session, all);
    return all;
  }

  /// Written whole, off the station's thread, the latest only (ops/files.ts PrivateFile).
  #save(session: string): Promise<void> {
    const file = this.#file(session);
    let kept = this.#files.get(file);
    if (kept === undefined) this.#files.set(file, (kept = new PrivateFile(file)));
    return kept.write(JSON.stringify(this.#of(session)));
  }

  limit(session: string, station: string): number {
    return this.#of(session)[station || "local"]?.bytes ?? DEFAULT_LIMIT;
  }

  async setLimit(session: string, station: string, gib: number): Promise<number> {
    if (!Number.isSafeInteger(gib) || gib < 1 || gib > Math.floor(Number.MAX_SAFE_INTEGER / GIB)) {
      throw new Error("limit_gib must be a positive whole number of GiB");
    }
    await this.#ready;
    const bytes = gib * GIB;
    this.#of(session)[station || "local"] = { bytes, over: false, told: null };
    await this.#save(session);
    return bytes;
  }

  async look(): Promise<void> {
    await this.#ready;
    const readings = await this.#o.readings();
    for (const reading of readings) {
      try {
        await this.#consider(reading);
      } catch (error) {
        log.warn("workspace-size", "workspace notice not given", { session: reading.session, error: (error as Error).message });
      }
    }
  }

  async #consider(reading: WorkspaceReading): Promise<void> {
    if (!this.#o.working(reading.session)) return;
    const all = this.#of(reading.session);
    const key = reading.station || "local";
    const existing = all[key];
    const previous = existing ?? { bytes: DEFAULT_LIMIT, over: false, told: null };
    if (reading.bytes <= previous.bytes) {
      if (previous.over && reading.complete) {
        all[key] = { ...previous, over: false, told: null };
        await this.#save(reading.session);
      }
      return;
    }
    const now = this.#fibers.now();
    if (previous.over && previous.told !== null && now - previous.told < REMIND_MS) return;
    const station = reading.station ? `, station: ${JSON.stringify(reading.station)}` : "";
    const place = reading.station ? `on ${reading.name}` : "on this station";
    const gib = reading.bytes / GIB;
    const current = (reading.complete ? gib : Math.floor(gib * 10) / 10).toFixed(1);
    const limit = (previous.bytes / GIB).toFixed(0);
    const atLeast = reading.complete ? "" : "at least ";
    await this.#o.notify(reading.session, `Your workspace ${place} (${reading.path}) uses ${atLeast}${current} GiB, above its ${limit} GiB limit. Inspect it and clean what you are authorized to remove, or raise this workspace's limit with workspace_limit {limit_gib: <new whole GiB>${station}}. The station will remind you hourly while it remains over the limit; it does not delete files or stop work for this.`);
    // An agent may have raised the limit while the notice was being delivered; keep its newer choice.
    if (all[key] !== existing) return;
    all[key] = { ...previous, over: true, told: now };
    await this.#save(reading.session);
  }
}
