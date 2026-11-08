import type { DatabaseSync } from "node:sqlite";
import { Worker } from "node:worker_threads";
import { MbBackfill, mbReaderBinary } from "../read/mb-reader.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";
import { forgetSigninSave, installSigninSaveIndex, nextPendingSigninSave, queueSigninSave, signinForSave, signinSaveComplete, stepSigninSaveIndex, type PendingSigninSave } from "./signin-save-index.ts";

/// Older undecided saves are indexed only when needed. The queue survives a restart while an old session is indexed.
export class SigninSaveBuilder {
  readonly #db: DatabaseSync;
  readonly #path: string | null;
  readonly #options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  readonly #answer: (pending: PendingSigninSave, body: string | null) => void;
  readonly #workerFile: URL | undefined;
  readonly #timers = new Fibers("signin save index");
  #worker: Worker | MbBackfill | null = null;
  #current: string | null = null;
  #last: string | null = null;
  #closed = false;
  #previousReady = false;
  #previousWaiting = false;
  #timer: (() => void) | null = null;
  #retryMs = 250;

  constructor(db: DatabaseSync, answer: (pending: PendingSigninSave, body: string | null) => void,
    options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    this.#db = db; this.#path = db.location(); this.#answer = answer; this.#options = options; this.#workerFile = workerFile;
    installSigninSaveIndex(db);
    this.#pump();
  }

  lookup(session: string, save: string): string | null { return signinForSave(this.#db, session, save); }

  /// An already covered session cannot contain an older matching ask. No work for ordinary non-sign-in saves.
  wait(session: string, save: string, status: string): void {
    if (this.#closed || signinSaveComplete(this.#db, session)) return;
    queueSigninSave(this.#db, session, save, status);
    this.#pump();
  }

  forget(session: string, save: string, status: string): void { forgetSigninSave(this.#db, session, save, status); }

  #schedule(ms: number): void {
    if (this.#closed || this.#timer !== null) return;
    this.#timer = this.#timers.after(ms, () => { this.#timer = null; this.#pump(); });
  }

  #pump(): void {
    if (this.#closed || this.#current !== null || this.#timer !== null) return;
    const pending = nextPendingSigninSave(this.#db, this.#last);
    if (pending === null) {
      if (this.#worker !== null) { const worker = this.#worker; this.#worker = null; void worker.terminate(); }
      return;
    }
    if (!this.#previousReady) {
      if (this.#previousWaiting) return;
      this.#previousWaiting = true;
      void (this.#options.previousGone ?? Promise.resolve()).then(() => {
        this.#previousReady = true; this.#previousWaiting = false; this.#pump();
      }, (error) => {
        this.#previousWaiting = false;
        log.warn("signin", "the previous station did not finish", { error: (error as Error).message });
        this.#schedule(this.#retryMs);
      });
      return;
    }
    this.#last = pending.session;
    if (signinSaveComplete(this.#db, pending.session)) {
      try {
        this.#answer(pending, this.lookup(pending.session, pending.save));
        // Do not drop a newer decision if one arrived while the answer was being told.
        forgetSigninSave(this.#db, pending.session, pending.save, pending.status);
        this.#retryMs = 250;
        this.#schedule(0);
      } catch (error) {
        log.warn("signin", "an older sign-in decision could not be told", { error: (error as Error).message });
        this.#schedule(this.#retryMs);
        this.#retryMs = Math.min(this.#retryMs * 2, 30_000);
      }
      return;
    }
    if (this.#path === null) {
      try { stepSigninSaveIndex(this.#db, pending.session); this.#retryMs = 250; this.#schedule(0); }
      catch (error) {
        log.warn("signin", "an older sign-in index batch stopped", { error: (error as Error).message });
        this.#schedule(this.#retryMs);
        this.#retryMs = Math.min(this.#retryMs * 2, 30_000);
      }
      return;
    }
    if (this.#worker === null) {
      const file = this.#workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./signin-save-worker.ts" : "./vault/signin-save-worker.js", import.meta.url);
      // (by the MoonBit builder, station/mb's src/signin, where its program is there: `MbBackfill`)
      const mb = this.#workerFile === undefined ? mbReaderBinary() : null;
      let worker: Worker | MbBackfill;
      try {
        worker = mb !== null ? new MbBackfill(mb, ["--builder", "signin-save", "--db", this.#path], this.#options.priority, 20)
          : new Worker(file, { workerData: { path: this.#path, priority: this.#options.priority } });
      }
      catch (error) {
        log.warn("signin", "the sign-in index worker could not start", { error: (error as Error).message });
        this.#schedule(this.#retryMs); this.#retryMs = Math.min(this.#retryMs * 2, 30_000); return;
      }
      const owner = worker.threadId;
      this.#worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => {
        if (this.#closed || this.#worker !== worker) return;
        this.#current = null;
        if (result.error) {
          log.warn("signin", "an older sign-in index batch stopped", { error: result.error });
          void worker.terminate();
        } else { this.#retryMs = 250; this.#pump(); }
      });
      worker.once("error", (error) => log.warn("signin", "the sign-in index worker failed", { error: error.message }));
      worker.once("exit", () => {
        releaseStoppedBackfill(this.#options.priority, owner);
        if (this.#worker !== worker) return;
        this.#worker = null; this.#current = null;
        if (!this.#closed && nextPendingSigninSave(this.#db, null) !== null) {
          this.#schedule(this.#retryMs);
          this.#retryMs = Math.min(this.#retryMs * 2, 30_000);
        }
      });
    }
    this.#current = pending.session;
    this.#worker.postMessage(pending.session);
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#timer?.(); this.#timer = null;
    const worker = this.#worker; this.#worker = null;
    if (worker !== null) await worker.terminate();
    await this.#timers.close();
  }
}
