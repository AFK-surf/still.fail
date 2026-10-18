// What the station finds for a search (docs/search.md): looked for by a thread of its own (search/worker.ts) in the
// station's data as it is then; nothing indexed. The thread is started with the station and stays; one that dies is
// started again when next asked. The machine's files are asked beside it (search/files.ts).
import { Worker } from "node:worker_threads";
import { rmSync } from "node:fs";
import { join } from "node:path";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { type Asker, type Group, terms } from "./match.ts";
import type { FileSearch } from "./files.ts";
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
  /// The machine's files (none: not searched here).
  #files: FileSearch | null;

  constructor(options: { data: string; files?: FileSearch | null }) {
    this.#data = options.data;
    this.#files = options.files ?? null;
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
  /// history only when asked for by name), the machine's files beside the rest.
  async query(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number } = {}): Promise<Found> {
    const files = this.#files;
    const wantsFiles = files !== null && (!options.kinds || options.kinds.length === 0 || options.kinds.includes("file")) && (options.offset ?? 0) === 0;
    const rest = options.kinds?.filter((k) => k !== "file");
    const [looked, found] = await Promise.all([
      options.kinds && options.kinds.length > 0 && rest!.length === 0 ? Promise.resolve({ groups: [], building: false }) : this.#looked(query, asker, options),
      wantsFiles ? files.query(terms(query), asker, Math.max(1, Math.min(options.limit ?? 8, 200))).catch(() => null) : Promise.resolve(null),
    ]);
    return found === null ? looked : { ...looked, groups: [...looked.groups, found] };
  }

  #looked(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number }): Promise<Found> {
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
