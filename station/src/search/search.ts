// What the station finds for a search (docs/search.md): its index's thread (search/worker.ts) kept as the station's data
// is, by the store's changes, and asked what a query finds. The thread is started with the station and stays: it holds
// the index current. One that dies is started again a little later, and looks everything over then.
import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import type { Store } from "../store/store.ts";
import type { StoreChange } from "../store/rows.ts";
import { type Asker, type Group, terms } from "./index.ts";
import type { FileSearch } from "./files.ts";
import type { Answered, Told } from "./worker.ts";

/// How often everything is looked over for what the station did not say (memory an agent wrote, the profiles).
const SWEEP_MS = 10 * 60_000;
/// How long after a thread failed it is started again.
const AGAIN_MS = 30_000;
/// How long a query may take before it is answered with nothing (the thread busy with a large source).
const QUERY_MS = 10_000;

export type Found = { groups: Group[]; building: boolean };

export class Search {
  #data: string;
  #store: Store;
  #worker: Worker | null = null;
  #next = 0;
  #waiting = new Map<number, { resolve: (found: Found) => void; reject: (error: Error) => void; timer: () => void }>();
  #unsubscribe: (() => void) | null = null;
  #sweeping: (() => void) | null = null;
  #again: (() => void) | null = null;
  #closed = false;

  /// The machine's files, where Spotlight finds them (macOS); elsewhere they are in the index.
  #files: FileSearch | null;

  constructor(options: { data: string; store: Store; files?: FileSearch | null }) {
    this.#data = options.data;
    this.#store = options.store;
    this.#files = options.files ?? null;
  }

  start(): void {
    this.#unsubscribe = this.#store.subscribe((change) => this.#changed(change));
    this.#spawn();
    const sweep = () => {
      this.#tell({ type: "sweep" });
      this.#sweeping = wall.after(SWEEP_MS, sweep);
    };
    this.#sweeping = wall.after(SWEEP_MS, sweep);
  }

  #spawn(): void {
    if (this.#closed) return;
    // From source: worker.ts beside this; bundled (this inside dist/main.js): dist/search/worker.js.
    const file = new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./search/worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { data: this.#data }, resourceLimits: { maxOldGenerationSizeMb: 384 } });
    this.#worker = worker;
    worker.on("message", (answer: Answered) => {
      if (answer.id < 0) {
        log.warn("search", "indexing failed", { error: answer.error });
        return;
      }
      const waiter = this.#waiting.get(answer.id);
      if (!waiter) return;
      this.#waiting.delete(answer.id);
      waiter.timer();
      if (answer.error !== undefined) waiter.reject(new Error(answer.error));
      else waiter.resolve({ groups: (answer.groups as Group[]) ?? [], building: answer.building === true });
    });
    worker.on("error", (error) => log.error("search", "the search index stopped", { error: error.message }));
    worker.on("exit", () => {
      if (this.#worker === worker) this.#worker = null;
      for (const [id, waiter] of this.#waiting) {
        waiter.timer();
        waiter.reject(new Error("the search index stopped"));
        this.#waiting.delete(id);
      }
      if (!this.#closed) this.#again = wall.after(AGAIN_MS, () => this.#spawn());
    });
    worker.postMessage({ type: "sweep" } satisfies Told);
  }

  #tell(told: Told): void {
    this.#worker?.postMessage(told);
  }

  #changed(change: StoreChange): void {
    switch (change.type) {
      case "thread":
        this.#tell({ type: "thread", id: change.id });
        break;
      case "threadRemoved":
        this.#tell({ type: "threadRemoved", id: change.id });
        break;
      case "session":
        this.#tell({ type: "session", key: change.key });
        break;
      case "sessionRemoved":
        this.#tell({ type: "sessionRemoved", key: change.key });
        break;
      case "job":
        this.#tell({ type: "job", id: change.id });
        break;
      case "jobRemoved":
        this.#tell({ type: "session", key: change.session });
        break;
    }
  }

  /// What `query` finds for `asker`: by kind, at most `limit` of each (those of `kinds` only, when given); the machine's
  /// files beside what the index has, where Spotlight finds them.
  async query(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number } = {}): Promise<Found> {
    const files = this.#files;
    const wantsFiles = files !== null && (!options.kinds || options.kinds.length === 0 || options.kinds.includes("file")) && (options.offset ?? 0) === 0;
    const [indexed, found] = await Promise.all([
      this.#indexed(query, asker, options),
      wantsFiles ? files.query(terms(query), asker, Math.max(1, Math.min(options.limit ?? 8, 200))).catch(() => null) : Promise.resolve(null),
    ]);
    return found === null ? indexed : { ...indexed, groups: [...indexed.groups.filter((g) => g.kind !== "file"), found] };
  }

  #indexed(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number }): Promise<Found> {
    const worker = this.#worker;
    if (!worker) return Promise.reject(new Error("the search index is starting"));
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

  /// Once what the index was told so far is in it (for tests: the store's changes are indexed in the background).
  flushed(): Promise<Found> {
    const worker = this.#worker;
    if (!worker) return Promise.reject(new Error("the search index is starting"));
    const id = this.#next++;
    return new Promise<Found>((resolve, reject) => {
      this.#waiting.set(id, { resolve, reject, timer: () => {} });
      worker.postMessage({ type: "flush", id } satisfies Told);
    });
  }

  async stop(): Promise<void> {
    this.#closed = true;
    this.#unsubscribe?.();
    this.#sweeping?.();
    this.#again?.();
    await this.#worker?.terminate();
    this.#worker = null;
  }
}
