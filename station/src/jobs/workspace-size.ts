// A working chat's workspace on each station has a soft size limit. Measurements are shared and queued so many active
// chats do not walk the disk at once; links are not followed and hard links count once (sessions/footprint.ts).
import { createHash, randomBytes } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { measuredUpTo } from "../sessions/footprint.ts";

export const GIB = 1024 ** 3;
export const DEFAULT_LIMIT = 10 * GIB;
export const CHECK_MS = 5 * 60_000;
export const REMIND_MS = 60 * 60_000;

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

  constructor(options: WorkspaceWatchOptions) {
    this.#o = options;
    this.#fibers = new Fibers("workspace-size", options.clock);
    this.#directory = join(options.data, "workspace-limits");
    mkdirSync(this.#directory, { recursive: true });
  }

  start(): void {
    const tick = async () => {
      try { await this.look(); } finally { this.#fibers.after(CHECK_MS, tick); }
    };
    this.#fibers.after(60_000, tick);
  }

  close(): Promise<void> { return this.#fibers.close(); }

  /// An archived chat can be restored with its limit; a deleted chat has no settings left behind.
  forget(session: string): void {
    this.#limits.delete(session);
    try {
      rmSync(this.#file(session), { force: true });
    } catch (error) {
      log.warn("workspace-size", "deleted chat's limit not removed", { session, error: (error as Error).message });
    }
  }

  #file(session: string): string {
    return join(this.#directory, `${createHash("sha256").update(session).digest("hex")}.json`);
  }

  #of(session: string): Limits {
    let all = this.#limits.get(session);
    if (all) return all;
    all = Object.create(null) as Limits;
    try {
      const parsed: unknown = JSON.parse(readFileSync(this.#file(session), "utf8"));
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

  #save(session: string): void {
    const file = this.#file(session);
    const temp = `${file}.${randomBytes(8).toString("hex")}.tmp`;
    try {
      writeFileSync(temp, JSON.stringify(this.#of(session)), { mode: 0o600 });
      renameSync(temp, file);
    } catch (error) {
      try { rmSync(temp, { force: true }); } catch {}
      throw error;
    }
  }

  limit(session: string, station: string): number {
    return this.#of(session)[station || "local"]?.bytes ?? DEFAULT_LIMIT;
  }

  setLimit(session: string, station: string, gib: number): number {
    if (!Number.isSafeInteger(gib) || gib < 1 || gib > Math.floor(Number.MAX_SAFE_INTEGER / GIB)) {
      throw new Error("limit_gib must be a positive whole number of GiB");
    }
    const bytes = gib * GIB;
    this.#of(session)[station || "local"] = { bytes, over: false, told: null };
    this.#save(session);
    return bytes;
  }

  async look(): Promise<void> {
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
        this.#save(reading.session);
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
    this.#save(reading.session);
  }
}
