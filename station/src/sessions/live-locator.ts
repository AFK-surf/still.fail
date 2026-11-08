// The live view's source and path lookup, off the main thread. Only a bounded batch of source ids and path hints crosses
// back at a time; the worker's source snapshot is taken before it starts touching the filesystem.
import { Worker } from "node:worker_threads";
import { onTranscriptHintsChanged, transcriptLocationHints } from "../read/transcript.ts";
import { locationIdentity, type LiveLocation, type LiveLocationIdentity, type LiveLocationProfile, type LiveSession, type LiveSource, type LocateMessage, type LocateReply, type LocateRequest } from "./live-location-protocol.ts";

type HintSnapshot = ReturnType<typeof transcriptLocationHints>;
type Pending = {
  id: number; key: string; signal?: AbortSignal; abort?: () => void; profiles: LiveLocationProfile[]; attempts: number;
  paths: NonNullable<LiveLocation>["paths"]; ids: Set<string>; stale: boolean; hints: HintSnapshot | null; batch: LiveSource[];
  resolve(value: LiveLocation): void; reject(error: Error): void;
};
const IDLE_MS = 60_000;
const RESTARTS = 3;
// A long history yields between batches so a small one can finish without waiting behind it. Limit simultaneous
// snapshots and messages; the worker itself still runs on just one thread.
const IN_FLIGHT = 4;
const cancelled = () => new Error("live transcript location cancelled");
const sameIdentity = (a: LiveLocationIdentity | null, b: LiveSession | null) =>
  JSON.stringify(a) === JSON.stringify(b === null ? null : locationIdentity(b, b.token));
const sameProfiles = (a: LiveLocationProfile[], b: readonly LiveLocationProfile[]) => a.length === b.length
  && a.every((p, i) => p.id === b[i]?.id && p.home === b[i]?.home);

export class LiveLocator {
  private worker: Worker | null = null;
  private active = new Map<number, Pending>();
  private waiting: Pending[] = [];
  private idle: ReturnType<typeof setTimeout> | null = null;
  private retiring: Promise<void> | null = null;
  private closed = false;
  private next = 0;
  private merging: Pending | null = null;
  private readonly unlisten: () => void;
  private readonly data: string;
  private readonly session: (key: string) => LiveSession | null;
  private readonly profiles: () => readonly LiveLocationProfile[];
  private readonly workerFile: URL | undefined;

  constructor(data: string, session: (key: string) => LiveSession | null,
    profiles: () => readonly LiveLocationProfile[], workerFile?: URL) {
    this.data = data; this.session = session; this.profiles = profiles; this.workerFile = workerFile;
    this.unlisten = onTranscriptHintsChanged((id) => {
      for (const request of this.active.values()) {
        if (request !== this.merging && request.ids.has(id)) request.stale = true;
      }
    });
  }

  locate(key: string, signal?: AbortSignal): Promise<LiveLocation> {
    if (this.closed) return Promise.reject(new Error("live locator stopped"));
    if (signal?.aborted) return Promise.reject(cancelled());
    return new Promise((resolve, reject) => {
      const request: Pending = { id: ++this.next, key, signal, profiles: [], attempts: 0, paths: [], ids: new Set(), stale: false, hints: null, batch: [], resolve, reject };
      request.abort = () => {
        if (this.active.delete(request.id)) {
          this.finish(request, cancelled());
          try { this.worker?.postMessage({ type: "cancel", id: request.id } satisfies LocateReply); }
          catch (error) { this.retire(error instanceof Error ? error : new Error(String(error))); }
          this.pump();
        } else {
          const at = this.waiting.indexOf(request);
          if (at >= 0) { this.waiting.splice(at, 1); this.finish(request, cancelled()); }
        }
      };
      signal?.addEventListener("abort", request.abort, { once: true });
      this.waiting.push(request);
      this.pump();
    });
  }

  private finish(request: Pending, error?: Error, value: LiveLocation = null) {
    if (request.abort) request.signal?.removeEventListener("abort", request.abort);
    if (error) request.reject(error);
    else request.resolve(value);
  }

  private start(): Worker {
    const file = this.workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./live-locator-worker.ts" : "./sessions/live-locator-worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { data: this.data }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    this.worker = worker;
    worker.on("message", (message: LocateMessage) => { if (this.worker === worker) this.heard(message); });
    worker.on("error", (error) => { if (this.worker === worker) this.retire(error); });
    worker.on("exit", (code) => { if (this.worker === worker) this.retire(new Error(`live locator exited (${code})`)); });
    return worker;
  }

  private pump() {
    if (this.closed || this.retiring !== null) return;
    while (this.active.size < IN_FLIGHT) {
      const request = this.waiting.shift();
      if (request === undefined) break;
      if (this.idle !== null) { clearTimeout(this.idle); this.idle = null; }
      this.active.set(request.id, request);
      if (!this.ask(request)) return;
    }
    if (this.active.size === 0 && this.waiting.length === 0) {
      if (this.worker !== null && this.idle === null) {
        const worker = this.worker;
        this.idle = setTimeout(() => {
          this.idle = null;
          if (this.worker === worker && this.active.size === 0) { this.worker = null; void worker.terminate(); }
        }, IDLE_MS);
        this.idle.unref();
      }
    }
  }

  private ask(request: Pending): boolean {
    try {
      request.profiles = this.profiles().map(({ id, home }) => ({ id, home }));
      request.paths = []; request.ids.clear(); request.stale = false; request.hints = null; request.batch = [];
      (this.worker ?? this.start()).postMessage({ type: "locate", id: request.id, key: request.key, profiles: request.profiles } satisfies LocateRequest);
      return true;
    } catch (error) { this.retire(error instanceof Error ? error : new Error(String(error))); return false; }
  }

  private heard(message: LocateMessage) {
    const request = this.active.get(message.id), worker = this.worker;
    if (request === undefined || worker === null) return;
    try {
      if (message.type === "error") return this.retire(new Error(message.error));
      if (message.type === "hints") {
        request.batch = message.sources;
        request.hints = transcriptLocationHints(this.data, request.profiles, request.batch);
        worker.postMessage({ type: "hints", id: request.id, hints: request.hints.value } satisfies LocateReply);
        return;
      }
      if (message.type === "batch") {
        if (request.hints === null) throw new Error("live locator sent a batch without hints");
        let accepted: boolean;
        this.merging = request;
        try { accepted = request.hints.merge(message.hints); } finally { this.merging = null; }
        if (accepted) {
          request.paths.push(...message.paths);
          for (const source of request.batch) request.ids.add(source.id);
        }
        request.hints = null;
        worker.postMessage({ type: "accepted", id: request.id, accepted } satisfies LocateReply);
        return;
      }
      const changed = request.stale || !sameIdentity(message.identity, this.session(request.key)) || !sameProfiles(request.profiles, this.profiles());
      if (changed) {
        if (++request.attempts > RESTARTS) throw new Error("live transcript location kept changing");
        this.ask(request);
        return;
      }
      this.active.delete(request.id);
      this.finish(request, undefined, message.runtime === null || request.paths.length === 0 ? null
        : { runtime: message.runtime, paths: request.paths, current: message.current });
      this.pump();
    } catch (error) { this.retire(error instanceof Error ? error : new Error(String(error))); }
  }

  private retire(error: Error) {
    const worker = this.worker, requests = [...this.active.values()];
    this.worker = null; this.active.clear();
    for (const request of requests) this.finish(request, error);
    if (worker === null) return this.pump();
    const stopped = worker.terminate().then(() => undefined, () => undefined);
    this.retiring = stopped;
    void stopped.then(() => { if (this.retiring === stopped) this.retiring = null; this.pump(); });
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    this.unlisten();
    if (this.idle !== null) clearTimeout(this.idle);
    const active = [...this.active.values()], worker = this.worker;
    this.active.clear(); this.worker = null;
    for (const request of active) this.finish(request, cancelled());
    for (const request of this.waiting.splice(0)) this.finish(request, cancelled());
    if (worker !== null) await worker.terminate();
    await this.retiring;
  }
}
