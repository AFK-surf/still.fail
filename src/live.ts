// Live view of sessions: what a running turn is doing as the runtime streams
// it, and the transcript's new entries as they are written. Nothing here is
// stored: the steps in flight live in memory until they end, and the
// transcript stays the record, read incrementally while someone watches.
import { watch, type FSWatcher } from "node:fs";
import type { RuntimeKind } from "./config.ts";
import type { LiveEvent, LiveStepKind } from "./runtime/types.ts";
import { readTimeline, TranscriptTail, type TimelineEntry, type TranscriptUsage } from "./transcript.ts";

/** A step in flight, as far as it has streamed. */
export interface LiveStep {
  id: string;
  step: LiveStepKind;
  tool?: string;
  subagent?: boolean;
  text: string;
  input: string;
  output: string;
  startedAt: number;
}

export type LiveMessage =
  | { type: "steps"; steps: LiveStep[] }
  | { type: "step"; event: LiveEvent }
  | { type: "timeline"; start: number; entries: TimelineEntry[]; usage: TranscriptUsage }
  | { type: "clear" };

type Listener = (message: LiveMessage) => void;

/** Caps what one step keeps, so a runaway command cannot grow memory without bound. */
const MAX_FIELD = 64 * 1024;
const keepTail = (text: string) => (text.length > MAX_FIELD ? text.slice(text.length - MAX_FIELD) : text);

interface Watched {
  tail: TranscriptTail;
  watcher: FSWatcher | null;
  timer: ReturnType<typeof setTimeout> | null;
}

export class LiveHub {
  readonly #steps = new Map<string, Map<string, LiveStep>>();
  readonly #listeners = new Map<string, Set<Listener>>();
  readonly #watched = new Map<string, Watched>();
  /** Where a session's transcript is, once its runtime has started one. */
  readonly #locate: (key: string) => { runtime: RuntimeKind; path: string } | undefined;

  constructor(locate: (key: string) => { runtime: RuntimeKind; path: string } | undefined) {
    this.#locate = locate;
  }

  /** A runtime's live event for a session. */
  event(key: string, event: LiveEvent): void {
    let steps = this.#steps.get(key);
    if (!steps) this.#steps.set(key, (steps = new Map()));
    if (event.kind === "start") {
      steps.set(event.id, {
        id: event.id, step: event.step, text: "", input: event.input ?? "", output: "", startedAt: Date.now(),
        ...(event.tool ? { tool: event.tool } : {}), ...(event.subagent ? { subagent: true } : {}),
      });
    } else if (event.kind === "delta") {
      const step = steps.get(event.id);
      if (!step) return;
      step[event.field] = keepTail(step[event.field] + event.text);
    } else {
      if (!steps.delete(event.id)) return;
      this.#soon(key);
    }
    this.#emit(key, { type: "step", event });
  }

  /** The turn is over: whatever was in flight is in the transcript now, or never will be. */
  turnEnded(key: string): void {
    this.#steps.delete(key);
    this.#emit(key, { type: "clear" });
    this.#soon(key);
  }

  /**
   * Follows a session: first the transcript entries from index `from` on and
   * the steps in flight, then everything new. Returns the way to stop.
   */
  subscribe(key: string, from: number, listener: Listener): () => void {
    let set = this.#listeners.get(key);
    if (!set) this.#listeners.set(key, (set = new Set()));
    set.add(listener);
    const watched = this.#watch(key);
    if (watched && from < watched.tail.count) {
      const entries = readTimeline(watched.tail.runtime, watched.tail.path).slice(from, watched.tail.count);
      listener({ type: "timeline", start: from, entries, usage: { ...watched.tail.usage } });
    }
    listener({ type: "steps", steps: [...(this.#steps.get(key)?.values() ?? [])] });
    return () => {
      set.delete(listener);
      if (set.size === 0) {
        this.#listeners.delete(key);
        this.#unwatch(key);
      }
    };
  }

  close(): void {
    for (const key of [...this.#watched.keys()]) this.#unwatch(key);
  }

  #emit(key: string, message: LiveMessage): void {
    for (const listener of this.#listeners.get(key) ?? []) listener(message);
  }

  /** Starts reading a watched session's transcript, once it exists. */
  #watch(key: string): Watched | undefined {
    const existing = this.#watched.get(key);
    if (existing) return existing;
    if (!this.#listeners.has(key)) return undefined;
    const where = this.#locate(key);
    if (!where) return undefined;
    const tail = new TranscriptTail(where.runtime, where.path);
    tail.read(); // what is already there counts as known; subscribers ask for what they lack
    const watched: Watched = { tail, watcher: null, timer: null };
    try {
      watched.watcher = watch(where.path, () => this.#soon(key));
      watched.watcher.on("error", () => { /* the file went away; the next turn's events reattach */ });
    } catch {
      // not watchable: reads still follow the runtime's own events
    }
    this.#watched.set(key, watched);
    return watched;
  }

  #unwatch(key: string): void {
    const watched = this.#watched.get(key);
    if (!watched) return;
    watched.watcher?.close();
    if (watched.timer) clearTimeout(watched.timer);
    this.#watched.delete(key);
  }

  /** Reads what the transcript gained, coalescing bursts of writes. */
  #soon(key: string): void {
    if (!this.#listeners.has(key)) return;
    const fresh = !this.#watched.has(key);
    const watched = this.#watch(key);
    if (!watched || watched.timer) return;
    watched.timer = setTimeout(() => {
      watched.timer = null;
      const { start, entries } = watched.tail.read();
      if (entries.length || fresh) this.#emit(key, { type: "timeline", start, entries, usage: { ...watched.tail.usage } });
    }, 40);
  }
}
