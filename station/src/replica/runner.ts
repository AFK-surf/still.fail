// Where the export's work runs (work.ts): its own worker thread as the station runs, so none of its reads, hashing,
// compressing or writing is on the main thread; in the test's thread in tests.
import { Worker } from "node:worker_threads";
import type { Places, Told } from "./export.ts";
import { ExportWork, type WorkPassed } from "./work.ts";

export type Asked =
  | { type: "places"; places: Places }
  | { type: "pass"; told: Told }
  | { type: "newGenerations"; after: number }
  | { type: "sources"; hashes: string[] }
  | { type: "close" };

export interface Runner {
  places(places: Places): Promise<void>;
  pass(told: Told): Promise<WorkPassed>;
  newGenerations(after: number): Promise<void>;
  sources(hashes: string[]): Promise<Record<string, string>>;
  close(): Promise<void>;
}

export type RunnerOptions = { db: string; replica: string; dataDir: string; origin: string };

/// The work in a worker thread of its own, started again (told the workspaces again) at the next thing asked once it
/// ended: what asked meanwhile failed, and its caller tries again with a backoff (copies.ts `#pass`).
export class WorkerRunner implements Runner {
  readonly #o: RunnerOptions;
  readonly #file: URL;
  #worker: Worker | null = null;
  readonly #waiting = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
  #next = 0;
  #places: Places | null = null;
  #closed = false;

  constructor(o: RunnerOptions, file = new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./replica/worker.js", import.meta.url)) {
    this.#o = o;
    this.#file = file;
  }

  #start(): Worker {
    const worker = new Worker(this.#file, { workerData: this.#o, resourceLimits: { maxOldGenerationSizeMb: 256 } });
    worker.unref();
    worker.on("message", (m: { id: number; answer?: unknown; error?: string }) => {
      const w = this.#waiting.get(m.id);
      this.#waiting.delete(m.id);
      if (m.error !== undefined) w?.reject(new Error(m.error));
      else w?.resolve(m.answer);
    });
    const fail = (e: Error) => {
      if (this.#worker !== worker) return;
      this.#worker = null;
      for (const w of this.#waiting.values()) w.reject(e);
      this.#waiting.clear();
    };
    worker.on("error", (e) => fail(new Error(`the copies' thread failed: ${e.message}`)));
    worker.on("exit", (code) => fail(new Error(`the copies' thread ended (${code})`)));
    this.#worker = worker;
    if (this.#places !== null) worker.postMessage({ type: "places", places: this.#places, id: ++this.#next });
    return worker;
  }

  #ask<T>(m: Asked): Promise<T> {
    if (this.#closed) return Promise.reject(new Error("the copies' thread is closed"));
    const worker = this.#worker ?? this.#start();
    const id = ++this.#next;
    return new Promise<T>((resolve, reject) => {
      this.#waiting.set(id, { resolve, reject });
      worker.postMessage({ ...m, id });
    });
  }

  places(places: Places) {
    this.#places = places;
    return this.#ask<void>({ type: "places", places });
  }
  pass(told: Told) {
    return this.#ask<WorkPassed>({ type: "pass", told });
  }
  newGenerations(after: number) {
    return this.#ask<void>({ type: "newGenerations", after });
  }
  sources(hashes: string[]) {
    return this.#ask<Record<string, string>>({ type: "sources", hashes });
  }
  async close() {
    if (this.#worker === null) {
      this.#closed = true;
      return;
    }
    await this.#ask<void>({ type: "close" }).catch(() => {});
    this.#closed = true;
  }
}

/// The work in this thread, one thing at a time as in the worker (a test's: its clock).
export class InlineRunner implements Runner {
  readonly work: ExportWork;
  #queue: Promise<unknown> = Promise.resolve();

  constructor(o: RunnerOptions & { now: () => number }) {
    this.work = new ExportWork(o);
  }

  #one<T>(f: () => T | Promise<T>): Promise<T> {
    const p = this.#queue.then(f);
    this.#queue = p.catch(() => {});
    return p;
  }

  places(places: Places) {
    return this.#one(() => this.work.setPlaces(places));
  }
  pass(told: Told) {
    return this.#one(() => this.work.pass(told));
  }
  newGenerations(after: number) {
    return this.#one(() => this.work.newGenerations(after));
  }
  sources(hashes: string[]) {
    return this.#one(() => this.work.sources(hashes));
  }
  close() {
    return this.#one(() => this.work.close());
  }
}
