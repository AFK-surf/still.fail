// Live view of sessions: what a running turn is doing, told at its turning
// points — the phase (asking the model, thinking, working), each step starting
// (thinking, writing, a tool with its input) and ending — and the transcript's
// entries as each is written whole. What a step writes as it goes (the
// runtime's deltas) is not sent: a step's words come with its entry. It goes
// over the relay when a link cannot be direct, where every frame counts.
// Nothing here is
// stored: the steps in flight live in memory until they end, and the
// transcript stays the record, parsed incrementally and kept in memory while
// someone watches, so a watcher asking from entry N is served without
// reading the file again.
import { watch, type FSWatcher } from "node:fs";
import type { RuntimeKind } from "./config.ts";
import type { LiveEvent, LivePhase, LiveStepKind } from "./runtime/types.ts";
import { TranscriptTail, type TimelineEntry, type TranscriptUsage } from "./transcript.ts";

/** A step in flight: what it is, not what it has written so far. */
export interface LiveStep {
  id: string;
  step: LiveStepKind;
  tool?: string;
  subagent?: boolean;
  /** For a sub-agent's step: the tool call that started the sub-agent. */
  parent?: string;
  /** A tool's input as it started (a command), cut short. */
  input: string;
  startedAt: number;
}

/** Where the turn stands with the model, and for how long (ms) at the time it is sent. */
export interface LivePhaseView { phase: LivePhase; elapsedMs: number }

export type LiveMessage =
  | { type: "steps"; steps: LiveStep[]; phase: LivePhaseView | null }
  | { type: "step"; event: LiveEvent }
  | { type: "timeline"; start: number; entries: TimelineEntry[]; usage: TranscriptUsage }
  /** How fast the model is writing now (≈ tokens a second, from bytes), at most once a second; 0 once it stops. */
  | { type: "rate"; tokensPerSecond: number }
  | { type: "clear" };

type Listener = (message: LiveMessage) => void;

/** How much of a tool's input a step carries: enough to say what it runs. */
const INPUT_CHARS = 300;
/** The output rate is told at most this often, over this window (bytes / 4 ≈ tokens, as Zork estimates). */
const RATE_EVERY_MS = 1_000;
const RATE_WINDOW_MS = 2_000;

/** A session's recent output, in 250 ms buckets, and when its rate was last told. */
interface Rate { buckets: [number, number][]; toldAt: number; told: number }

interface Watched {
  tail: TranscriptTail;
  watcher: FSWatcher | null;
  timer: ReturnType<typeof setTimeout> | null;
}

export class LiveHub {
  readonly #steps = new Map<string, Map<string, LiveStep>>();
  readonly #phase = new Map<string, { phase: LivePhase; at: number }>();
  readonly #rates = new Map<string, Rate>();
  readonly #listeners = new Map<string, Set<Listener>>();
  readonly #watched = new Map<string, Watched>();
  /** Where a session's transcript is, once its runtime has started one. */
  readonly #locate: (key: string) => { runtime: RuntimeKind; path: string } | undefined;

  constructor(locate: (key: string) => { runtime: RuntimeKind; path: string } | undefined) {
    this.#locate = locate;
  }

  /** A runtime's live event for a session. */
  event(key: string, event: LiveEvent): void {
    if (event.kind === "phase") {
      this.#phase.set(key, { phase: event.phase, at: Date.now() });
      this.#emit(key, { type: "step", event });
      return;
    }
    let steps = this.#steps.get(key);
    if (!steps) this.#steps.set(key, (steps = new Map()));
    // What a step writes as it goes is not told (see the top): its words come with its transcript entry. How fast it
    // writes is, now and then.
    if (event.kind === "delta") return this.#counted(key, Buffer.byteLength(event.text));
    if (event.kind === "start") {
      const input = (event.input ?? "").slice(0, INPUT_CHARS);
      steps.set(event.id, {
        id: event.id, step: event.step, input, startedAt: Date.now(),
        ...(event.tool ? { tool: event.tool } : {}), ...(event.subagent ? { subagent: true } : {}), ...(event.parent ? { parent: event.parent } : {}),
      });
      this.#emit(key, { type: "step", event: { ...event, input } });
      return;
    }
    if (!steps.delete(event.id)) return;
    this.#soon(key);
    this.#emit(key, { type: "step", event });
    this.#stopped(key);
  }

  /** The turn is over: whatever was in flight is in the transcript now, or never will be. */
  turnEnded(key: string): void {
    this.#steps.delete(key);
    this.#phase.delete(key);
    this.#rates.delete(key);
    this.#emit(key, { type: "clear" });
    this.#soon(key);
  }

  /**
   * Follows a session: first the transcript entries from index `from` on (and
   * the usage so far, even when a watcher kept every entry already), the steps
   * in flight, then everything new. Returns the way to stop.
   */
  subscribe(key: string, from: number, listener: Listener): () => void {
    let set = this.#listeners.get(key);
    if (!set) this.#listeners.set(key, (set = new Set()));
    set.add(listener);
    const watched = this.#watch(key);
    if (watched) {
      // A watcher that has more than the transcript (it was written anew) is told where it ends.
      const start = Math.min(from, watched.tail.entries.length);
      listener({ type: "timeline", start, entries: watched.tail.entries.slice(start), usage: { ...watched.tail.usage } });
    }
    const phase = this.#phase.get(key);
    listener({ type: "steps", steps: [...(this.#steps.get(key)?.values() ?? [])], phase: phase ? { phase: phase.phase, elapsedMs: Date.now() - phase.at } : null });
    return () => {
      set.delete(listener);
      if (set.size === 0) {
        this.#listeners.delete(key);
        this.#unwatch(key);
      }
    };
  }

  /** A deleted session: nothing of it is watched or kept any more. */
  forget(key: string): void {
    this.#steps.delete(key);
    this.#phase.delete(key);
    this.#rates.delete(key);
    this.#emit(key, { type: "clear" });
    this.#listeners.delete(key);
    this.#unwatch(key);
  }

  close(): void {
    for (const key of [...this.#watched.keys()]) this.#unwatch(key);
  }

  /** Output written: its rate is told when a second has passed since it last was (the first output at once). */
  #counted(key: string, bytes: number): void {
    const now = Date.now();
    let rate = this.#rates.get(key);
    if (!rate) this.#rates.set(key, (rate = { buckets: [], toldAt: 0, told: 0 }));
    const bucket = Math.floor(now / 250) * 250;
    const last = rate.buckets.at(-1);
    if (last && last[0] === bucket) last[1] += bytes;
    else rate.buckets.push([bucket, bytes]);
    while (rate.buckets.length && rate.buckets[0]![0] < now - RATE_WINDOW_MS) rate.buckets.shift();
    if (now - rate.toldAt < RATE_EVERY_MS) return;
    const first = rate.buckets[0]![0];
    const span = Math.min(RATE_WINDOW_MS, Math.max(250, now - first));
    const total = rate.buckets.reduce((sum, [, b]) => sum + b, 0);
    const tokensPerSecond = Math.max(1, Math.round((total * 1000) / (4 * span)));
    rate.toldAt = now;
    rate.told = tokensPerSecond;
    this.#emit(key, { type: "rate", tokensPerSecond });
  }

  /** A step ended: the model is not writing (until its next output). */
  #stopped(key: string): void {
    const rate = this.#rates.get(key);
    if (!rate) return;
    this.#rates.delete(key);
    if (rate.told > 0) this.#emit(key, { type: "rate", tokensPerSecond: 0 });
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
