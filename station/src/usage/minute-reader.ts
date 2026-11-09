import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import { MbProcess, mbReaderBinary } from "../read/mb-reader.ts";
import type { InWorkspace } from "../store/rows.ts";

export type MinuteRequest = { id: number; viewer: InWorkspace | null } | { id: number; detail: InWorkspace | null }
  | { id: number; remote: true } | { id: number; chats: InWorkspace | null };
export type MinuteResponse = { id?: number; error?: string; complete?: boolean; foreground?: boolean };

/// Check whether previously maintained summaries are complete without writing or filling old history. By the MoonBit
/// checker (station/mb, src/usage: `--builder usage-check`) where its program is there, else by the worker.
export class MinuteReader {
  readonly #path: string;
  readonly #mb: string | null;
  #worker: Worker | MbProcess | null = null;
  #next = 0;
  #closed = false;
  #complete = false;
  #termination: Promise<number> | null = null;
  #waiting = new Map<number, { resolve: () => void; reject: (error: Error) => void; request: MinuteRequest; sent: boolean }>();
  constructor(path: string, _options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, mb = mbReaderBinary()) {
    this.#path = path;
    this.#mb = mb;
  }

  start(): void {
    if (this.#closed || this.#complete || this.#worker !== null) return;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./minute-worker.ts" : "./usage/minute-worker.js", import.meta.url);
    const worker = this.#mb !== null ? new MbProcess(this.#mb, ["--builder", "usage-check", "--db", this.#path])
      : new Worker(file, { workerData: { path: this.#path }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    this.#worker = worker;
    if (worker instanceof Worker) worker.unref();
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
    worker.on("error", (error: Error) => {
      failure = error;
      log.error("usage", "the minute summary worker stopped", { error: error.message });
    });
    worker.on("exit", (code: number) => {
      const current = this.#worker === worker;
      if (current) this.#worker = null;
      if (current && !this.#complete && !this.#closed) {
        for (const waiting of this.#waiting.values()) waiting.reject(failure ?? new Error(`the minute summary worker stopped (exit ${code})`));
        this.#waiting.clear();
      }
    });
    this.#sendWaiting();
  }

  #sendWaiting(): void {
    if (this.#worker === null) return;
    for (const waiting of this.#waiting.values()) if (!waiting.sent) {
      this.#worker.postMessage(waiting.request);
      waiting.sent = true;
    }
  }

  ready(viewer: InWorkspace | null): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (this.#complete) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const id = ++this.#next;
      try {
        this.#waiting.set(id, { resolve, reject, request: { id, viewer }, sent: false });
        this.start();
        this.#sendWaiting();
      } catch (error) {
        this.#waiting.delete(id);
        reject(error);
      }
    });
  }

  /// A moved session can make only its workspace's detail statistics incomplete.
  readyDetail(viewer: InWorkspace | null): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    // A session can move after the original fill finished; the requesting reader has seen pending work.
    this.#complete = false;
    return new Promise((resolve, reject) => {
      const id = ++this.#next;
      try {
        this.#waiting.set(id, { resolve, reject, request: { id, detail: viewer }, sent: false });
        this.start();
        this.#sendWaiting();
      } catch (error) {
        this.#waiting.delete(id);
        reject(error);
      }
    });
  }

  /// Remote-task statistics may already be complete even when another statistic is incomplete.
  readyRemote(): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    if (this.#complete) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const id = ++this.#next;
      try {
        this.#waiting.set(id, { resolve, reject, request: { id, remote: true }, sent: false });
        this.start();
        this.#sendWaiting();
      } catch (error) {
        this.#waiting.delete(id);
        reject(error);
      }
    });
  }

  /// Check only the asking workspace's chat and card totals.
  readyChats(viewer: InWorkspace | null = null): Promise<void> {
    if (this.#closed) return Promise.reject(new Error("station stopping"));
    // A session can move after an earlier fill finished. The calling reader saw pending work in its own snapshot.
    this.#complete = false;
    return new Promise((resolve, reject) => {
      const id = ++this.#next;
      try {
        this.#waiting.set(id, { resolve, reject, request: { id, chats: viewer }, sent: false });
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
