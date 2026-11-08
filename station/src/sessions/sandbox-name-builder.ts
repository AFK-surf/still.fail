import { Worker } from "node:worker_threads";
import { MbBackfill, mbReaderBinary } from "../read/mb-reader.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { disableSandboxIndex, enableSandboxIndex, runnerNameSessions, runnerTakeUpSessions, sandboxIndexEnabled, sandboxIndexReady, sandboxIndexStep, sandboxSessions } from "../store/sandbox-index.ts";
import type { SessionRow, Store } from "../store/store.ts";

/// Prepare the session-name lookup only when an idle sandbox or a runner needs it. Old sessions and old writers'
/// journalled keys are handled after handover in short transactions. Concurrent callers share the same preparation.
export class SandboxNameBuilder {
  private pending: Promise<boolean> | null = null;
  private disabling: Promise<boolean> | null = null;
  private worker: Worker | MbBackfill | null = null;
  private stopped = false;
  private forRunners = false;
  private readonly cancelled = Promise.withResolvers<boolean>();
  private readonly store: Store;
  private readonly previous: Promise<boolean>;
  private readonly workerFile: URL | undefined;
  private readonly enabled: () => boolean;
  private previousReady = false;

  constructor(store: Store, previous: Promise<void>, enabled: () => boolean = () => true, workerFile?: URL) {
    this.store = store;
    this.previous = previous.then(() => { this.previousReady = true; return true; }, (error) => {
      log.warn("hub", "could not wait for the previous station before preparing sandbox names", { error: (error as Error).message });
      return false;
    });
    this.enabled = enabled;
    this.workerFile = workerFile;
  }

  async sessions(names: readonly string[]): Promise<Map<string, string> | "fallback" | null> {
    // Let an already-settled predecessor promise take effect before deciding whether the old path is needed.
    await Promise.resolve();
    try {
      while (!this.stopped && this.enabled()) {
        if (sandboxIndexEnabled(this.store.db)) {
          const sessions = sandboxSessions(this.store.db, names);
          if (sessions !== null) return sessions;
        }
        const preparing = this.prepare();
        // The old station may take a long time to leave. The caller can keep the existing immediate sweep meanwhile;
        // one shared preparation starts after it leaves.
        if (!this.previousReady) return "fallback";
        if (!(await preparing)) return this.stopped || !this.enabled() ? null : "fallback";
      }
    } catch (error) {
      log.warn("hub", "the sandbox name lookup could not be read", { error: (error as Error).message });
      return this.stopped || !this.enabled() ? null : "fallback";
    }
    return null;
  }

  /// Memory protection must not wait for an old store to be prepared. It can use the old answer immediately while one
  /// shared preparation runs; later looks use the same name lookup as sandbox sweeps, even without sandbox mode.
  runners(runners: readonly { id: string; part: string }[]): Map<string, string> | "fallback" {
    if (runners.length === 0) {
      // Runners can disappear briefly between turns. Keep the lookup current so their return does not repeatedly
      // rebuild all historical names; no lookup is installed on a station that has never needed it.
      if (this.forRunners && !this.stopped) {
        try {
          if (!sandboxIndexEnabled(this.store.db) || !sandboxIndexReady(this.store.db)) void this.prepare();
        } catch (error) {
          log.warn("hub", "the runner name lookup could not be checked", { error: (error as Error).message });
        }
      }
      return new Map();
    }
    if (this.stopped) return "fallback";
    this.forRunners = true;
    try {
      if (sandboxIndexEnabled(this.store.db)) {
        const sessions = runnerNameSessions(this.store.db, runners);
        if (sessions !== null) {
          // The answer may include a bounded overlay of keys the worker still needs to save.
          if (!sandboxIndexReady(this.store.db)) void this.prepare();
          return sessions;
        }
      }
    } catch (error) {
      log.warn("hub", "the runner name lookup could not be read", { error: (error as Error).message });
    }
    void this.prepare();
    return "fallback";
  }

  /// Startup cannot wait for old names to be prepared; keep the old answer until the shared worker catches up.
  takeUp(parts: readonly string[]): SessionRow[] | "fallback" {
    if (this.stopped) return "fallback";
    if (parts.length !== 0) this.forRunners = true;
    try {
      if (parts.length === 0 || sandboxIndexEnabled(this.store.db)) {
        const sessions = runnerTakeUpSessions(this.store.db, parts);
        if (sessions !== null) {
          if (parts.length !== 0 && !sandboxIndexReady(this.store.db)) void this.prepare();
          return sessions;
        }
      }
    } catch (error) {
      log.warn("hub", "the runner takeup lookup could not be read", { error: (error as Error).message });
    }
    if (parts.length !== 0) void this.prepare();
    return "fallback";
  }

  /// Let callers that need to know when a requested preparation settled wait without starting another one.
  async settled(): Promise<void> { await this.pending; await this.disabling; }

  private needed(): boolean { return this.enabled() || this.forRunners; }

  /// Stop recording keys after sandbox mode is disabled. A busy writer delays this small change on the worker, never
  /// on the station's thread.
  async disable(): Promise<void> {
    if (this.needed()) return;
    if (this.pending !== null && this.previousReady) await this.pending;
    if (this.stopped || this.needed() || !sandboxIndexEnabled(this.store.db)) return;
    if (this.store.db.location() === null) disableSandboxIndex(this.store.db);
    else {
      const work = this.disabling ??= this.runWorker("sandbox-off");
      try { await work; } finally { if (this.disabling === work) this.disabling = null; }
      // A runner or sandbox may have appeared while the worker turned journalling off.
      if (!this.stopped && this.needed()) void this.prepare();
    }
  }

  private prepare(): Promise<boolean> {
    if (this.pending !== null) return this.pending;
    const work = (async () => {
      const previous = await Promise.race([this.previous, this.cancelled.promise]);
      if (this.disabling !== null) await this.disabling;
      if (!previous || this.stopped || !this.needed()) return false;
      return this.build();
    })().catch((error) => {
      log.warn("hub", "the sandbox name lookup could not be prepared", { error: (error as Error).message });
      return false;
    }).finally(() => { if (this.pending === work) this.pending = null; });
    this.pending = work;
    return work;
  }

  private async build(): Promise<boolean> {
    const path = this.store.db.location();
    if (path === null) {
      enableSandboxIndex(this.store.db);
      while (!this.stopped && this.needed() && !sandboxIndexReady(this.store.db)) {
        sandboxIndexStep(this.store.db);
        await new Promise<void>((resolve) => setImmediate(resolve));
      }
      return !this.stopped && this.needed();
    }
    return this.runWorker("sandbox");
  }

  private runWorker(kind: "sandbox" | "sandbox-off"): Promise<boolean> {
    const path = this.store.db.location();
    if (path === null) return Promise.resolve(false);
    const file = this.workerFile ?? new URL(import.meta.url.endsWith(".ts")
      ? "./workspace-activity-worker.ts" : "./sessions/workspace-activity-worker.js", import.meta.url);
    return new Promise<boolean>((resolve) => {
      // (by the MoonBit builder, station/mb's src/activity sandbox.mbt, where its program is there: `MbBackfill`)
      let current: Worker | MbBackfill;
      const mb = this.workerFile === undefined ? mbReaderBinary() : null;
      const thread = () => new Worker(file, { workerData: { path, priority: this.store.backfillPriority } });
      try { current = mb !== null ? new MbBackfill(mb, ["--builder", "session-backfill", "--db", path], this.store.backfillPriority, 20, thread) : thread(); }
      catch (error) {
        log.warn("hub", "the sandbox name worker could not start", { error: (error as Error).message });
        resolve(false);
        return;
      }
      const owner = current.threadId;
      let done = false;
      this.worker = current;
      current.unref();
      current.on("message", (result: { done: boolean; error?: string }) => {
        if (result.error) {
          log.warn("hub", "a sandbox name batch stopped", { error: result.error });
          void current.terminate();
        } else if (result.done || this.stopped || (kind === "sandbox" && !this.needed())) {
          done = result.done && !this.stopped && (kind !== "sandbox" || this.needed());
          void current.terminate();
        } else current.postMessage({ kind });
      });
      current.once("error", (error) => log.warn("hub", "the sandbox name worker failed", { error: error.message }));
      current.once("exit", (code) => {
        releaseStoppedBackfill(this.store.backfillPriority, owner);
        if (this.worker === current) this.worker = null;
        if (!done && !this.stopped && (kind !== "sandbox" || this.needed()))
          log.warn("hub", "the sandbox name worker stopped before finishing", { code });
        resolve(done);
      });
      current.postMessage({ kind });
    });
  }

  async close(): Promise<void> {
    if (this.stopped) return;
    this.stopped = true;
    this.cancelled.resolve(false);
    if (this.worker !== null) await this.worker.terminate();
    await this.pending;
    await this.disabling;
  }
}
