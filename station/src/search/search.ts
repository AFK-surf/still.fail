// What the station finds for a search: looked for by the MoonBit program (station/mb, src/search; `--builder search`)
// where it is built, else by a thread of its own (search/worker.ts), in the station's data as it is then. A prepared candidate scope avoids unrelated chats; their contents are read as asked.
// The thread is started with the station and stays; one that dies is started again when next asked. The machine's
// files are asked beside it (search/files.ts).
import { Worker } from "node:worker_threads";
import { rmSync } from "node:fs";
import { join, sep } from "node:path";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { type Asker, type Group, terms } from "./match.ts";
import type { FileSearch } from "./files.ts";
import type { Answered, Told } from "./worker.ts";
import { SearchScopeBuilder } from "./scope-builder.ts";
import { SessionListBuilder } from "../read/session-list-builder.ts";
import { MbProcess, mbReaderBinary } from "../read/mb-reader.ts";

/// How long a search may take before it is answered with nothing.
const QUERY_MS = 30_000;

/// `building`: always false (said to the clients that showed an index still being built).
export type Found = { groups: Group[]; building: boolean };

type Looker = Worker | MbProcess;

export class Search {
  #data: string;
  /// The program (none: not built here; the worker looks through everything).
  readonly #mb: string | null;
  #program: MbProcess | null = null;
  #worker: Worker | null = null;
  #next = 0;
  #waiting = new Map<number, { resolve: (found: Found) => void; reject: (error: Error) => void; timer: () => void }>();
  #closed = false;
  readonly #scope: SearchScopeBuilder;
  #preparingScope: Promise<void> | null = null;
  readonly #sessionList: SessionListBuilder;
  #preparingSessions: Promise<void> | null = null;
  /// The machine's files (none: not searched here).
  #files: FileSearch | null;

  constructor(options: { data: string; files?: FileSearch | null; backfill?: { previousGone?: Promise<void>; priority?: SharedArrayBuffer }; mb?: string | null }) {
    this.#data = options.data;
    this.#mb = options.mb === undefined ? mbReaderBinary() : options.mb;
    this.#files = options.files ?? null;
    this.#scope = new SearchScopeBuilder(join(options.data, "stillfail.db"), options.backfill);
    this.#sessionList = new SessionListBuilder(join(options.data, "stillfail.db"), options.backfill);
  }

  start(): void {
    // The index an earlier station kept: there is none now.
    for (const f of ["search.db", "search.db-wal", "search.db-shm"]) rmSync(join(this.#data, f), { force: true });
    if (this.#mb !== null) this.#spawnProgram();
    else this.#spawn();
  }

  #spawnProgram(): MbProcess | null {
    if (this.#closed || this.#mb === null) return null;
    const program = new MbProcess(this.#mb, ["--builder", "search", "--db", join(this.#data, "stillfail.db"), "--data", this.#data, "--sep", sep]);
    this.#program = program;
    this.#listen(program, () => { if (this.#program === program) this.#program = null; });
    return program;
  }

  #spawn(): Worker | null {
    if (this.#closed) return null;
    // From source: worker.ts beside this; bundled (this inside dist/main.js): dist/search/worker.js.
    const file = new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./search/worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { data: this.#data }, resourceLimits: { maxOldGenerationSizeMb: 384 } });
    this.#worker = worker;
    this.#listen(worker, () => { if (this.#worker === worker) this.#worker = null; });
    return worker;
  }

  /// A looker's answers: each to the search it is for; its end ends the searches waiting on it.
  #listen(looker: Looker, gone: () => void): void {
    const mine = new Set<number>();
    (looker as Worker).on("message", (answer: Answered) => {
      if ("scopePending" in answer) { if (!this.#closed) this.#prepareScope(); return; }
      if ("sessionListPending" in answer) { if (!this.#closed) this.#prepareSessions(); return; }
      mine.delete(answer.id);
      const waiter = this.#waiting.get(answer.id);
      if (!waiter) return;
      this.#waiting.delete(answer.id);
      waiter.timer();
      if (answer.error !== undefined) waiter.reject(new Error(answer.error));
      else waiter.resolve({ groups: answer.groups ?? [], building: false });
    });
    (looker as Worker).on("error", (error: Error) => log.error("search", "the search's thread stopped", { error: error.message }));
    (looker as Worker).on("exit", () => {
      gone();
      for (const [id, waiter] of this.#waiting) {
        if (!mine.has(id)) continue;
        waiter.timer();
        waiter.reject(new Error("the search stopped"));
        this.#waiting.delete(id);
      }
    });
    this.#asked.set(looker, mine);
  }

  readonly #asked = new WeakMap<Looker, Set<number>>();

  /// What `query` finds for `asker`: by kind, at most `limit` of each (those of `kinds` only, when given; the execution
  /// history only when asked for by name), the machine's files beside the rest.
  async query(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number; archived?: boolean } = {}): Promise<Found> {
    const files = this.#files;
    const wantsFiles = files !== null && (!options.kinds || options.kinds.length === 0 || options.kinds.includes("file")) && (options.offset ?? 0) === 0;
    const rest = options.kinds?.filter((k) => k !== "file");
    const [looked, found] = await Promise.all([
      options.kinds && options.kinds.length > 0 && rest!.length === 0 ? Promise.resolve({ groups: [], building: false }) : this.#looked(query, asker, options),
      wantsFiles ? files.query(terms(query), asker, Math.max(1, Math.min(options.limit ?? 8, 200))).catch(() => null) : Promise.resolve(null),
    ]);
    return found === null ? looked : { ...looked, groups: [...looked.groups, found] };
  }

  // Preparation is shared and never holds up the current search. A later query retries after a failure or change.
  #prepareScope(): void {
    if (this.#preparingScope !== null) return;
    const pending = this.#scope.prepare();
    this.#preparingScope = pending;
    void pending.catch((error: unknown) => {
      if (!this.#closed) log.warn("search", "the candidate scope could not be prepared", { error: (error as Error).message });
    }).finally(() => { if (this.#preparingScope === pending) this.#preparingScope = null; });
  }

  #prepareSessions(): void {
    if (this.#preparingSessions !== null) return;
    const pending = this.#sessionList.readySearch();
    this.#preparingSessions = pending;
    void pending.catch((error: unknown) => {
      if (!this.#closed) log.warn("search", "the session list could not be prepared", { error: (error as Error).message });
    }).finally(() => { if (this.#preparingSessions === pending) this.#preparingSessions = null; });
  }

  #looked(query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number; archived?: boolean }): Promise<Found> {
    return this.#ask(this.#mb === null ? this.#worker ?? this.#spawn() : this.#program ?? this.#spawnProgram(), query, asker, options);
  }

  #ask(looker: Looker | null, query: string, asker: Asker, options: { kinds?: string[]; limit?: number; offset?: number; archived?: boolean }): Promise<Found> {
    if (!looker) return Promise.reject(new Error("the search is stopped"));
    const id = this.#next++;
    const program = looker instanceof MbProcess;
    const cancel = program ? undefined : new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT);
    return new Promise<Found>((resolve, reject) => {
      const timer = wall.after(QUERY_MS, () => {
        if (cancel) Atomics.store(new Int32Array(cancel), 0, 1);
        else looker.postMessage({ type: "cancel", id });
        this.#waiting.delete(id);
        reject(new Error("the search took too long"));
      });
      this.#waiting.set(id, { resolve, reject, timer });
      this.#asked.get(looker)?.add(id);
      looker.postMessage({ type: "query", id, query, asker, ...options, ...(cancel ? { cancel } : {}) } satisfies Told);
    });
  }

  async stop(): Promise<void> {
    this.#closed = true;
    await Promise.all([this.#worker?.terminate(), this.#program?.terminate(), this.#scope.close(), this.#sessionList.close()]);
    this.#worker = null;
    this.#program = null;
  }
}
