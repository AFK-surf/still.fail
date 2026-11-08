// A reader in MoonBit (station/mb, src/reader): a process of its own instead of a worker thread, asked and answering as
// a worker is (read/worker.ts `Ask`, `Answer`, `Ready`), a line of JSON each way on its stdin and stdout. The pool
// (read/pool.ts) gives it the reads that have been moved to it, so far the store's checkpoints (`log`). Where the
// program is not there (a checkout that has not built it), the pool keeps the worker.
import { type ChildProcess, spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import type { Answer, Ask, Ready } from "./worker.ts";

/// The program: STILLFAIL_MB_READER, else beside the station's code in a release, else where `moon build` puts it in
/// a checkout (station/mb/build.sh). None: not built here.
export function mbReaderBinary(): string | null {
  const candidates = [
    process.env.STILLFAIL_MB_READER,
    fileURLToPath(new URL(`./${platform.exe("stillfail-reader")}`, import.meta.url)),
    // (from the source only: bundled, this is main.js, beside which the release puts the program)
    import.meta.url.endsWith(".ts") ? fileURLToPath(new URL("../../mb/_build/native/release/build/station/reader/reader.exe", import.meta.url)) : undefined,
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

export class MbReader extends EventEmitter implements ReaderLike {
  readonly #child: ChildProcess;
  #exited = false;

  /// Started on the station's data directory `data`.
  constructor(binary: string, data: string) {
    super();
    this.#child = spawn(binary, ["--data", data], { stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
    createInterface({ input: this.#child.stdout! }).on("line", (line) => {
      let answer: Answer | Ready;
      try { answer = JSON.parse(line) as Answer | Ready; }
      catch { return void log.warn("readers", "a MoonBit reader said what is not JSON", { line: line.slice(0, 200) }); }
      this.emit("message", answer);
    });
    createInterface({ input: this.#child.stderr! }).on("line", (line) => log.warn("readers", "a MoonBit reader said", { line }));
    // (a failed write is the process gone, told by its exit)
    this.#child.stdin!.on("error", () => {});
    this.#child.on("error", (error) => this.emit("error", error));
    this.#child.on("exit", (code, signal) => {
      this.#exited = true;
      this.emit("exit", code ?? (signal !== null ? 1 : 0));
    });
  }

  postMessage(ask: Ask) {
    this.#child.stdin!.write(`${JSON.stringify(ask)}\n`);
  }

  terminate(): Promise<number> {
    if (this.#exited) return Promise.resolve(this.#child.exitCode ?? 1);
    return new Promise((resolve) => {
      this.#child.once("exit", (code) => resolve(code ?? 1));
      this.#child.kill();
    });
  }

  /// No JS heap: what it holds is not the station's to count (the memory log counts V8's).
  getHeapStatistics(): Promise<{ used_heap_size: number }> {
    return Promise.resolve({ used_heap_size: 0 });
  }
}
