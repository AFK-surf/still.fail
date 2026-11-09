import { Worker } from "node:worker_threads";
import { MbBackfill, mbReaderBinary } from "../read/mb-reader.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { installSessionDirectories, sessionDirectoriesReady, sessionDirectoriesStep, sessionDirectory, sessionDirectoryArguments, SESSION_DIR_LIVE_MANY, type DirectorySession } from "../store/session-directory.ts";
import type { Store } from "../store/store.ts";

/// A memory check answers immediately while one shared worker prepares the directory lookup after handover.
export class SessionDirectoryBuilder {
  private pending: Promise<boolean> | null = null;
  private worker: Worker | MbBackfill | null = null;
  private stopped = false;
  private readonly cancelled = Promise.withResolvers<boolean>();
  private readonly previous: Promise<boolean>;

  constructor(privateStore: Store, previous: Promise<void>, privateWorkerFile?: URL) {
    this.store = privateStore;
    this.workerFile = privateWorkerFile;
    this.previous = previous.then(() => true, (error) => {
      log.warn("memory", "could not wait for the previous station before preparing directories", { error: (error as Error).message });
      return false;
    });
  }

  private readonly store: Store;
  private readonly workerFile: URL | undefined;

  find(dir: string): DirectorySession | null {
    if (this.stopped) return null;
    try {
      const found = sessionDirectory(this.store.db, dir);
      if (found !== null) {
        if (!sessionDirectoriesReady(this.store.db)) void this.prepare();
        return found;
      }
    } catch (error) {
      log.warn("memory", "the session directory lookup could not be read", { error: (error as Error).message });
    }
    void this.prepare();
    return null;
  }

  /// The resource page attributes independent processes by directories mentioned in their arguments.
  findArguments(lines: readonly string[], home: string): Map<string, string> | null {
    if (this.stopped) return null;
    if (!lines.some((line) => line.includes("/"))) return new Map();
    try {
      const found = sessionDirectoryArguments(this.store.db, lines, home);
      if (!sessionDirectoriesReady(this.store.db) && this.store.db.prepare(SESSION_DIR_LIVE_MANY).get() !== undefined) void this.prepare();
      return found;
    } catch (error) {
      log.warn("resources", "the session directory lookup could not be read", { error: (error as Error).message });
      void this.prepare();
      return null;
    }
  }

  async settled(): Promise<void> { await this.pending; }

  private prepare(): Promise<boolean> {
    if (this.pending !== null) return this.pending;
    const work = (async () => {
      const previous = await Promise.race([this.previous, this.cancelled.promise]);
      if (!previous || this.stopped) return false;
      if (this.store.db.location() === null) {
        installSessionDirectories(this.store.db);
        while (!this.stopped && !sessionDirectoriesReady(this.store.db)) {
          sessionDirectoriesStep(this.store.db);
          await new Promise<void>((resolve) => setImmediate(resolve));
        }
        return !this.stopped;
      }
      return this.runWorker();
    })().catch((error) => {
      log.warn("memory", "the session directory lookup could not be prepared", { error: (error as Error).message });
      return false;
    }).finally(() => { if (this.pending === work) this.pending = null; });
    this.pending = work;
    return work;
  }

  private runWorker(): Promise<boolean> {
    const path = this.store.db.location();
    if (path === null) return Promise.resolve(false);
    const file = this.workerFile ?? new URL(import.meta.url.endsWith(".ts")
      ? "./workspace-activity-worker.ts" : "./sessions/workspace-activity-worker.js", import.meta.url);
    return new Promise<boolean>((resolve) => {
      // (by the MoonBit builder, station/mb's src/activity, directory.mbt, where its program is there: `MbBackfill`)
      let current: Worker | MbBackfill;
      const mb = this.workerFile === undefined ? mbReaderBinary() : null;
      const thread = () => new Worker(file, { workerData: { path, priority: this.store.backfillPriority } });
      try { current = mb !== null ? new MbBackfill(mb, ["--builder", "session-backfill", "--db", path], this.store.backfillPriority, 20, thread) : thread(); }
      catch (error) {
        log.warn("memory", "the session directory worker could not start", { error: (error as Error).message });
        resolve(false);
        return;
      }
      const owner = current.threadId;
      let done = false;
      this.worker = current;
      current.unref();
      current.on("message", (result: { done: boolean; error?: string }) => {
        if (result.error) {
          log.warn("memory", "a session directory batch stopped", { error: result.error });
          void current.terminate();
        } else if (result.done || this.stopped) {
          done = result.done && !this.stopped;
          void current.terminate();
        } else current.postMessage({ kind: "directory" });
      });
      current.once("error", (error) => log.warn("memory", "the session directory worker failed", { error: error.message }));
      current.once("exit", (code) => {
        releaseStoppedBackfill(this.store.backfillPriority, owner);
        if (this.worker === current) this.worker = null;
        if (!done && !this.stopped) log.warn("memory", "the session directory worker stopped before finishing", { code });
        resolve(done);
      });
      current.postMessage({ kind: "directory" });
    });
  }

  async close(): Promise<void> {
    if (this.stopped) return;
    this.stopped = true;
    this.cancelled.resolve(false);
    if (this.worker !== null) await this.worker.terminate();
    await this.pending;
  }
}
