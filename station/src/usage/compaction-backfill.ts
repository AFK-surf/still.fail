import { Worker } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";

/// The backfill is needed only for an old database and stops itself once it has caught up.
export class CompactionBackfill {
  #worker: Worker | null = null;
  #retry: (() => void) | null = null;
  #closed = false;
  #complete = false;
  readonly #path: string;

  constructor(path: string) { this.#path = path; }

  start(): void {
    if (this.#closed || this.#complete || this.#worker !== null) return;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./compaction-worker.ts" : "./usage/compaction-worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { path: this.#path }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    this.#worker = worker;
    worker.unref();
    worker.on("message", (answer: { complete?: boolean }) => { if (answer.complete) this.#complete = true; });
    worker.on("error", (error) => log.error("usage", "the compaction history worker stopped", { error: error.message }));
    worker.on("exit", () => {
      if (this.#worker !== worker) return;
      this.#worker = null;
      if (!this.#complete && !this.#closed) this.#retry = wall.after(5_000, () => { this.#retry = null; this.start(); });
    });
  }

  async stop(): Promise<void> {
    this.#closed = true;
    this.#retry?.();
    this.#retry = null;
    const worker = this.#worker;
    this.#worker = null;
    if (worker !== null) await worker.terminate();
  }
}
