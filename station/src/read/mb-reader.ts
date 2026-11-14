// A reader in MoonBit (station/mb, src/reader): a process of its own instead of a worker thread, asked and answering as
// a worker is, a line of JSON each way on its stdin and stdout. The pool (read/pool.ts) gives it the reads that have
// been moved to it, so far the store's checkpoints (`log`: read/worker.ts `Ask`, `Answer`, `Ready`); with `--builder`
// it is a builder of old state, asked by read/requested-builder.ts or, for a backfill the station drives itself, through
// `MbBackfill`. Where the program is not there (a checkout that has not built it), the worker is kept.
import { type ChildProcess, spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { sep } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import type { Worker } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { giveBackfill, releaseStoppedBackfill, takeBackfill } from "../store/backfill.ts";
import type { Answer, Ask, Ready } from "./worker.ts";

/// The program: STILLFAIL_MB_READER, else beside the station's code in a release, else where `moon build` puts it in
/// a checkout (station/mb/build.sh, for the Mac). None: not built here.
export function mbReaderBinary(): string | null {
  const candidates = [
    process.env.STILLFAIL_MB_READER,
    fileURLToPath(new URL(`./${platform.exe("stillfail-reader")}`, import.meta.url)),
    // (from the source only: bundled, this is main.js, beside which the release puts the program)
    import.meta.url.endsWith(".ts") ? fileURLToPath(new URL("../../mb/_build/stillfail-reader-darwin-arm64", import.meta.url)) : undefined,
  ];
  return candidates.find((p) => p !== undefined && p !== "" && existsSync(p)) ?? null;
}

/// What the pool asks of a reader, a worker thread's or this process's.
export interface ReaderLike {
  on(event: "message", f: (answer: Answer | Ready) => void): this;
  on(event: "error", f: (error: Error) => void): this;
  on(event: "exit", f: (code: number) => void): this;
  postMessage(ask: Ask): void;
  terminate(): Promise<number>;
  getHeapStatistics(): Promise<{ used_heap_size: number }>;
}

/// The program's process, a line of JSON each way: told its lines as "message"s, its end as "exit".
export class MbProcess extends EventEmitter {
  readonly #child: ChildProcess;
  #exited = false;

  constructor(binary: string, args: string[]) {
    super();
    this.#child = spawn(binary, args, { stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
    createInterface({ input: this.#child.stdout! }).on("line", (line) => {
      let answer: unknown;
      try { answer = JSON.parse(line); }
      catch { return void log.warn("readers", "a MoonBit reader said what is not JSON", { line: line.slice(0, 200) }); }
      this.emit("message", answer);
    });
    createInterface({ input: this.#child.stderr! }).on("line", (line) => log.warn("readers", "a MoonBit reader said", { line }));
    // (a failed write is the process gone, told by its exit)
    this.#child.stdin!.on("error", () => {});
    this.#child.on("error", (error) => this.emit("error", error));
    // Its end once its output is read whole (`close`: after `exit` and its streams' ends): what it said last, then that it
    // ended. On `exit` a line it wrote just before could still be on its way, its answer taken for none.
    this.#child.on("close", (code, signal) => {
      this.#exited = true;
      this.emit("exit", code ?? (signal !== null ? 1 : 0));
    });
  }

  /// (a bigint, as a worker would have been posted it, said as its digits)
  postMessage(message: unknown) {
    this.#child.stdin!.write(`${JSON.stringify(message, (_, v) => typeof v === "bigint" ? v.toString() : v)}\n`);
  }

  terminate(): Promise<number> {
    if (this.#exited) return Promise.resolve(this.#child.exitCode ?? 1);
    return new Promise((resolve) => {
      this.#child.once("close", (code) => resolve(code ?? 1));
      this.#child.kill();
    });
  }

  /// No JS heap: what it holds is not the station's to count (the memory log counts V8's).
  getHeapStatistics(): Promise<{ used_heap_size: number }> {
    return Promise.resolve({ used_heap_size: 0 });
  }
}

/// The reader, started on the station's data directory `data`.
export class MbReader extends MbProcess implements ReaderLike {
  constructor(binary: string, data: string) { super(binary, ["--data", data, "--sep", sep]); }
  override postMessage(ask: Ask) { super.postMessage(ask); }
}

/// What stands for a MoonBit backfill in the permit (a worker's thread id there): never a thread's.
let nextOwner = 0x60000000;

/// A backfill the station drives itself (a worker posted `{}` for each batch, answering `{done, error?}`), by the
/// MoonBit builder `args` instead: in a worker's place for its builder (`threadId`: its owner in the permit, released
/// on its exit as a worker's). It knows nothing of the backfill permit, which this takes for each batch and gives back
/// when it is answered, as the worker took it; a batch the permit is not had for, and one that did not finish
/// everything, are answered after the pause the worker makes (`pauseMs`). A batch it answers `{"fallback": true}`
/// (a kind not moved to it yet) is asked of the worker `fallback` makes, which answers from then on.
export class MbBackfill extends EventEmitter {
  readonly threadId = nextOwner++;
  readonly #process: MbProcess;
  readonly #buffer: SharedArrayBuffer | undefined;
  readonly #priority: Int32Array | null;
  readonly #pauseMs: number;
  readonly #fallback: (() => Worker) | undefined;
  #worker: Worker | null = null;
  #asked: unknown = null;
  #holding = false;
  #exited = false;

  constructor(binary: string, args: string[], priority: SharedArrayBuffer | undefined, pauseMs: number, fallback?: () => Worker) {
    super();
    this.#buffer = priority;
    this.#priority = priority instanceof SharedArrayBuffer ? new Int32Array(priority) : null;
    this.#pauseMs = pauseMs;
    this.#fallback = fallback;
    this.#process = new MbProcess(binary, args);
    this.#process.on("message", (result: { done: boolean; error?: string; fallback?: boolean }) => {
      if (this.#worker !== null) return;
      this.#give();
      if (result.fallback === true && this.#fallback !== undefined) return this.#toWorker(this.#fallback);
      if (!result.done && !result.error) this.#later(result);
      else this.emit("message", result);
    });
    this.#process.on("error", (error) => this.emit("error", error));
    this.#process.on("exit", (code) => {
      this.#give();
      if (this.#worker !== null) return;
      this.#exited = true;
      this.emit("exit", code);
    });
  }

  /// The worker in the program's place, asked what the program left to it.
  #toWorker(make: () => Worker) {
    const worker = this.#worker = make();
    void this.#process.terminate();
    worker.on("message", (result) => this.emit("message", result));
    worker.on("error", (error) => this.emit("error", error));
    worker.once("exit", (code) => {
      releaseStoppedBackfill(this.#buffer, worker.threadId);
      this.#exited = true;
      this.emit("exit", code);
    });
    worker.postMessage(this.#asked);
  }

  #give() {
    if (this.#holding) { this.#holding = false; giveBackfill(this.#priority, this.threadId); }
  }

  #later(result: { done: boolean }) {
    wall.after(this.#pauseMs, () => { if (!this.#exited && this.#worker === null) this.emit("message", result); });
  }

  postMessage(message: unknown) {
    this.#asked = message;
    if (this.#worker !== null) return void this.#worker.postMessage(message);
    if (!takeBackfill(this.#priority, this.threadId)) return void this.#later({ done: false });
    this.#holding = true;
    this.#process.postMessage(message);
  }

  /// (a process keeps the station's event loop no more than a worker it stands for)
  unref() { this.#worker?.unref(); }

  terminate(): Promise<number> { return this.#worker !== null ? this.#worker.terminate() : this.#process.terminate(); }
}
