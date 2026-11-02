import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import type { InWorkspace } from "../store/rows.ts";

export type MinuteRequest = { id: number; viewer: InWorkspace | null };
export type MinuteResponse = { id?: number; error?: string; complete?: boolean };

/// A history waits here, away from all of the readers, while its old minute summaries are filled.
export class MinuteReader {
  readonly #path: string;
  #worker: Worker | null = null;
  #next = 0;
  #closed = false;
  #complete = false;
  #termination: Promise<number> | null = null;
  #waiting = new Map<number, { resolve: () => void; reject: (error: Error) => void }>();

  constructor(path: string) { this.#path = path; }

  start(): void {
    if (this.#closed || this.#complete || this.#worker !== null) return;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./minute-worker.ts" : "./usage/minute-worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { path: this.#path }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
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
  }

  ready(viewer: InWorkspace | null): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (this.#complete) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const id = ++this.#next;
      try {
        this.start();
        this.#waiting.set(id, { resolve, reject });
        this.#worker!.postMessage({ id, viewer } satisfies MinuteRequest);
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
