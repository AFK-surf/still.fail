import { setMaxListeners } from "node:events";
import { Worker } from "node:worker_threads";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { REQUEST_BACKFILL_PAUSE_MS, giveBackfill, releaseStoppedBackfill, takeBackfill } from "../store/backfill.ts";
import { MbProcess } from "./mb-reader.ts";

/// A builder in MoonBit (read/mb-reader.ts): its program and arguments. It knows nothing of the backfill permit, which
/// the builder here takes for it around each batch it asks, and gives back when the batch is answered; or (`lazy`) it
/// asks for the permit itself when it is about to write, as a worker that reads without it takes it: a line
/// `{"take": true}` answered `{"permit": …}`, `{"give": true}` when it is done with it before its answer. A lazy one
/// is told of what is let go (`cancel`), as a worker is. One that answers `{"fallback": true}` (a store in a state it
/// does not build for, such as a legacy lookup) is let go, and the worker asked instead from then on.
export type MbBuilder = { binary: string; args: string[]; lazy?: boolean };
/// What stands for a MoonBit builder in the permit (a worker's thread id there): never a thread's.
let nextOwner = 0x40000000;

type Waiter = { resolve: () => void; reject: (error: Error) => void; done: () => void };
const IDLE_MS = 5_000;

/// Requested old state alone; readers share progress, each slice gives other work a turn, and abandoned work stops.
export class RequestedBuilder<K extends number | string> {
  readonly #path: string;
  readonly #options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  readonly #workerFile: URL | undefined;
  readonly #timers: Fibers;
  readonly #field: "thread" | "session" | "scope";
  readonly #message: ((item: K, cancel: boolean) => Record<string, unknown>) | undefined;
  readonly #waiting = new Map<K, Set<Waiter>>();
  #worker: Worker | MbProcess | null = null;
  #mb: MbBuilder | null;
  /// The MoonBit builder's own in the permit, and whether it holds it for the batch it was asked.
  #owner = 0;
  #holding = false;
  #current: K | null = null;
  #previousReady = false;
  #previousWaiting = false;
  #closed = false;
  #retry: (() => void) | null = null;
  #idle: (() => void) | null = null;
  #retryMs = 250;

  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer }, workerFile: URL | undefined,
    field: "thread" | "session" | "scope", name: string, message?: (item: K, cancel: boolean) => Record<string, unknown>, mb: MbBuilder | null = null) {
    this.#path = path; this.#options = options; this.#workerFile = workerFile; this.#field = field; this.#timers = new Fibers(name);
    this.#message = message; this.#mb = mb;
  }

  #priority(): Int32Array | null {
    return this.#options.priority instanceof SharedArrayBuffer ? new Int32Array(this.#options.priority) : null;
  }

  /// A batch asked of the MoonBit builder, once it holds the permit (as a worker takes it itself: store/backfill.ts);
  /// without it, the batch is not done, after the pause a worker makes.
  #askMb(process: MbProcess, message: Record<string, unknown>): void {
    if (this.#mb?.lazy) return void process.postMessage(message);
    if (!takeBackfill(this.#priority(), this.#owner)) {
      this.#timers.after(REQUEST_BACKFILL_PAUSE_MS, () => { if (this.#worker === process) this.#answer({ done: false }); });
      return;
    }
    this.#holding = true;
    process.postMessage(message);
  }

  /// The MoonBit builder's answer: the permit given back, and a batch that did not finish everything followed by the
  /// pause a worker makes before it answers.
  #answeredMb(process: MbProcess, result: { done: boolean; error?: string; take?: boolean; give?: boolean; fallback?: boolean }): void {
    if (result.fallback === true) {
      if (this.#holding) { this.#holding = false; giveBackfill(this.#priority(), this.#owner); }
      log.info("readers", "a MoonBit builder left this store to the worker", { args: this.#mb?.args.slice(0, 2) ?? [] });
      this.#mb = null;
      this.#worker = null;
      this.#current = null;
      void process.terminate();
      return void this.#pump();
    }
    if (result.take === true) {
      if (!this.#holding) this.#holding = takeBackfill(this.#priority(), this.#owner);
      return void process.postMessage({ permit: this.#holding });
    }
    if (result.give === true) {
      if (this.#holding) { this.#holding = false; giveBackfill(this.#priority(), this.#owner); }
      return;
    }
    if (this.#holding) { this.#holding = false; giveBackfill(this.#priority(), this.#owner); }
    if (!result.done && !result.error) this.#timers.after(REQUEST_BACKFILL_PAUSE_MS, () => { if (this.#worker === process) this.#answer(result); });
    else this.#answer(result);
  }

  ready(items: readonly K[], signal?: AbortSignal): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (signal?.aborted) return Promise.reject(new Error("read cancelled"));
    const cancel = new AbortController();
    setMaxListeners(0, cancel.signal);
    const abort = () => cancel.abort();
    signal?.addEventListener("abort", abort, { once: true });
    return Promise.all([...new Set(items)].map((item) => this.#readyItem(item, cancel.signal)))
      .then(() => {})
      .catch((error: unknown) => { cancel.abort(); throw error; })
      .finally(() => signal?.removeEventListener("abort", abort));
  }

  #readyItem(item: K, signal: AbortSignal): Promise<void> {
    return new Promise((resolve, reject) => {
      let waiters = this.#waiting.get(item);
      if (!waiters) { waiters = new Set(); this.#waiting.set(item, waiters); }
      const group = waiters;
      const abort = () => { waiter.done(); reject(new Error("read cancelled")); this.#pump(); };
      const waiter: Waiter = { resolve, reject, done: () => {
        signal.removeEventListener("abort", abort);
        group.delete(waiter);
        if (group.size === 0 && this.#waiting.get(item) === group) this.#waiting.delete(item);
      } };
      group.add(waiter);
      signal.addEventListener("abort", abort, { once: true });
      this.#pump();
    });
  }

  #fail(item: K, error: Error): void {
    const waiters = this.#waiting.get(item);
    this.#waiting.delete(item);
    if (waiters) for (const waiter of [...waiters]) { waiter.done(); waiter.reject(error); }
  }

  #answer(result: { done: boolean; error?: string }): void {
    const item = this.#current;
    this.#current = null;
    if (this.#closed || item === null) return;
    if (result.error) this.#fail(item, new Error(result.error));
    else {
      const waiters = this.#waiting.get(item);
      if (waiters && result.done) for (const waiter of [...waiters]) { waiter.done(); waiter.resolve(); }
      else if (waiters) { this.#waiting.delete(item); this.#waiting.set(item, waiters); }
      this.#retryMs = 250;
    }
    if (!this.#waiting.has(item) && !result.done && (!(this.#worker instanceof MbProcess) || this.#mb?.lazy)) this.#worker?.postMessage(this.#message?.(item, true) ?? { [this.#field]: item, cancel: true });
    this.#pump();
  }

  #pump(): void {
    if (this.#closed || this.#current !== null || this.#retry !== null) return;
    if (this.#waiting.size === 0) {
      if (this.#worker !== null && this.#idle === null) {
        const worker = this.#worker;
        this.#idle = this.#timers.after(IDLE_MS, () => {
          this.#idle = null;
          if (this.#worker === worker && this.#current === null && this.#waiting.size === 0) {
            this.#worker = null; void worker.terminate();
          }
        });
      }
      return;
    }
    if (this.#idle !== null) { this.#idle(); this.#idle = null; }
    if (!this.#previousReady) {
      if (this.#previousWaiting) return;
      this.#previousWaiting = true;
      void (this.#options.previousGone ?? Promise.resolve()).then(() => {
        this.#previousReady = true; this.#previousWaiting = false; this.#pump();
      }, (error) => {
        this.#previousWaiting = false;
        for (const item of [...this.#waiting.keys()]) this.#fail(item, error instanceof Error ? error : new Error(String(error)));
      });
      return;
    }
    if (this.#worker === null && this.#mb !== null) {
      const mb = new MbProcess(this.#mb.binary, this.#mb.args);
      const owner = this.#owner = nextOwner++;
      this.#worker = mb;
      mb.on("message", (result: { done: boolean; error?: string }) => { if (this.#worker === mb) this.#answeredMb(mb, result); });
      mb.once("error", (error: Error) => log.warn("readers", "an old-state builder failed", { error: error.message }));
      mb.once("exit", () => {
        releaseStoppedBackfill(this.#options.priority, owner);
        this.#holding = false;
        this.#gone(mb);
      });
    }
    if (this.#worker === null) {
      const file = this.#workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./said-worker.ts" : "./read/said-worker.js", import.meta.url);
      let worker: Worker;
      try { worker = new Worker(file, { workerData: { path: this.#path, priority: this.#options.priority }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } }); }
      catch (error) { for (const item of [...this.#waiting.keys()]) this.#fail(item, error instanceof Error ? error : new Error(String(error))); return; }
      const owner = worker.threadId;
      this.#worker = worker;
      worker.unref();
      worker.on("message", (result: { done: boolean; error?: string }) => { if (this.#worker === worker) this.#answer(result); });
      worker.once("error", (error) => log.warn("readers", "an old-state worker failed", { error: error.message }));
      worker.once("exit", () => {
        releaseStoppedBackfill(this.#options.priority, owner);
        this.#gone(worker);
      });
    }
    const item = this.#waiting.keys().next().value as K | undefined;
    if (item === undefined) return;
    this.#current = item;
    const message = this.#message?.(item, false) ?? { [this.#field]: item };
    if (this.#worker instanceof MbProcess) this.#askMb(this.#worker, message);
    else this.#worker.postMessage(message);
  }

  /// The worker or builder process ended: what it held is asked again of another, after a growing wait.
  #gone(worker: Worker | MbProcess): void {
    if (this.#worker !== worker) return;
    this.#worker = null; this.#current = null;
    if (this.#idle !== null) { this.#idle(); this.#idle = null; }
    if (this.#closed || this.#waiting.size === 0) return;
    const ms = this.#retryMs;
    this.#retryMs = Math.min(ms * 2, 30_000);
    this.#retry = this.#timers.after(ms, () => { this.#retry = null; this.#pump(); });
  }

  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    this.#retry?.(); this.#retry = null;
    this.#idle?.(); this.#idle = null;
    for (const item of [...this.#waiting.keys()]) this.#fail(item, new Error("station stopping"));
    const worker = this.#worker; this.#worker = null;
    if (worker !== null) await worker.terminate();
    await this.#timers.close();
  }
}
