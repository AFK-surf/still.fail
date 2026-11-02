import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import type { InWorkspace } from "../store/rows.ts";
import { releaseStoppedBackfill } from "../store/backfill.ts";

export type MinuteRequest = { id: number; viewer: InWorkspace | null };
export type MinuteResponse = { id?: number; error?: string; complete?: boolean; foreground?: boolean };

/// A history waits here, away from all of the readers, while its old minute summaries are filled.
export class MinuteReader {
  readonly #path: string;
  #worker: Worker | null = null;
  #next = 0;
  #closed = false;
  #complete = false;
  #termination: Promise<number> | null = null;
  #waiting = new Map<number, { resolve: () => void; reject: (error: Error) => void; viewer: InWorkspace | null; sent: boolean }>();
  #previousGone: Promise<void> | null;
  #starting = false;
  readonly #priority: SharedArrayBuffer | undefined;

  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}) {
    this.#path = path;
    this.#previousGone = options.previousGone ?? null;
    this.#priority = options.priority;
  }

  start(): void {
    if (this.#closed || this.#complete || this.#worker !== null || this.#starting) return;
    if (this.#previousGone !== null) {
      this.#starting = true;
      const previous = this.#previousGone;
      this.#previousGone = null;
      void previous.then(() => {
        this.#starting = false;
        try { this.start(); } catch (error) { this.#fail(error as Error); }
      }, (error) => { this.#starting = false; this.#fail(error as Error); });
      return;
    }
    const file = new URL(import.meta.url.endsWith(".ts") ? "./minute-worker.ts" : "./usage/minute-worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { path: this.#path, priority: this.#priority }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    const owner = worker.threadId;
    worker.once("exit", () => releaseStoppedBackfill(this.#priority, owner));
    this.#worker = worker;
    worker.unref();
    worker.on("message", (answer: MinuteResponse) => {
      if (answer.complete) {
        this.#complete = true;
        for (const waiting of this.#waiting.values()) waiting.resolve();
        this.#waiting.clear();
        if (this.#worker === worker) this.#worker = null;
        this.#termination = worker.terminate();
        return;
      }
      if (answer.id === undefined) return;
      const waiting = this.#waiting.get(answer.id);
      if (!waiting) return;
      this.#waiting.delete(answer.id);
      if (answer.error) waiting.reject(new Error(answer.error));
      else waiting.resolve();
    });
    let failure: Error | null = null;
    worker.on("error", (error) => {
      failure = error;
      log.error("usage", "the minute summary worker stopped", { error: error.message });
    });
    worker.on("exit", (code) => {
      if (this.#worker === worker) this.#worker = null;
      if (!this.#complete && !this.#closed) {
        for (const waiting of this.#waiting.values()) waiting.reject(failure ?? new Error(`the minute summary worker stopped (exit ${code})`));
        this.#waiting.clear();
      }
    });
    this.#sendWaiting();
  }

  #fail(error: Error): void {
    for (const waiting of this.#waiting.values()) waiting.reject(error);
    this.#waiting.clear();
  }

  #sendWaiting(): void {
    if (this.#worker === null) return;
    for (const [id, waiting] of this.#waiting) if (!waiting.sent) {
      this.#worker.postMessage({ id, viewer: waiting.viewer } satisfies MinuteRequest);
      waiting.sent = true;
    }
  }

  ready(viewer: InWorkspace | null): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (this.#complete) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const id = ++this.#next;
      try {
        this.#waiting.set(id, { resolve, reject, viewer, sent: false });
        this.start();
        this.#sendWaiting();
      } catch (error) {
        this.#waiting.delete(id);
        reject(error);
      }
    });
  }

  async close(): Promise<void> {
    this.#closed = true;
    for (const waiting of this.#waiting.values()) waiting.reject(new Error("station stopping"));
    this.#waiting.clear();
    if (this.#worker !== null) this.#termination = this.#worker.terminate();
    this.#worker = null;
    if (this.#termination !== null) await this.#termination;
  }
}
