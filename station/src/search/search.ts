// What the station finds for a search (docs/search.md): looked for by a thread of its own (search/worker.ts) in the
// station's data as it is then; nothing indexed. The thread is started with the station and stays; one that dies is
// started again when next asked.
import { Worker } from "node:worker_threads";
import { rmSync } from "node:fs";
import { join } from "node:path";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import type { Asker, Group } from "./match.ts";
import type { Answered, Told } from "./worker.ts";

/// How long a search may take before it is answered with nothing.
const QUERY_MS = 30_000;

/// `building`: always false (said to the clients that showed an index still being built).
export type Found = { groups: Group[]; building: boolean };

export class Search {
  #data: string;
  #worker: Worker | null = null;
  #next = 0;
  #waiting = new Map<number, { resolve: (found: Found) => void; reject: (error: Error) => void; timer: () => void }>();
  #closed = false;

  constructor(options: { data: string }) {
    this.#data = options.data;
  }

  start(): void {
    // The index an earlier station kept: there is none now.
    for (const f of ["search.db", "search.db-wal", "search.db-shm"]) rmSync(join(this.#data, f), { force: true });
    this.#spawn();
  }

  #spawn(): Worker | null {
    if (this.#closed) return null;
    // From source: worker.ts beside this; bundled (this inside dist/main.js): dist/search/worker.js.
    const file = new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./search/worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { data: this.#data }, resourceLimits: { maxOldGenerationSizeMb: 384 } });
    this.#worker = worker;
    worker.on("message", (answer: Answered) => {
      const waiter = this.#waiting.get(answer.id);
      if (!waiter) return;
      this.#waiting.delete(answer.id);
      waiter.timer();
      if (answer.error !== undefined) waiter.reject(new Error(answer.error));
      else waiter.resolve({ groups: answer.groups ?? [], building: false });
    });
    worker.on("error", (error) => log.error("search", "the search's thread stopped", { error: error.message }));
    worker.on("exit", () => {
      if (this.#worker === worker) this.#worker = null;
      for (const [id, waiter] of this.#waiting) {
        waiter.timer();
        waiter.reject(new Error("the search stopped"));
        this.#waiting.delete(id);
      }
    });
    return worker;
  }

  /// What `query` finds for `asker`: by kind, at most `limit` of each (those of `kinds` only, when given; the execution
  /// history only when asked for by name).
  query(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number } = {}): Promise<Found> {
    const worker = this.#worker ?? this.#spawn();
    if (!worker) return Promise.reject(new Error("the search is stopped"));
    const id = this.#next++;
    return new Promise<Found>((resolve, reject) => {
      const timer = wall.after(QUERY_MS, () => {
        this.#waiting.delete(id);
        reject(new Error("the search took too long"));
      });
      this.#waiting.set(id, { resolve, reject, timer });
      worker.postMessage({ type: "query", id, query, asker, ...options } satisfies Told);
    });
  }

  async stop(): Promise<void> {
    this.#closed = true;
    await this.#worker?.terminate();
    this.#worker = null;
  }
}
