// Live view of sessions (the Rust station's live.rs): what a running turn is doing, told at its turning points — the phase
// (asking the model, thinking, working), each step starting (thinking, writing, a tool with its input) and ending — and
// the transcript's entries as each is written whole. What a step writes as it goes (the runtime's deltas) is not sent:
// a step's words come with its entry; how fast it writes is, now and then. Nothing here is stored: the steps in flight
// live in memory until they end, and the transcript stays the record, read as it grows and kept in memory while someone
// watches. Redesigned on one point (docs/station-ts.md, push not poll): a watched transcript is followed by the file
// system's change events (fs.watch), not looked at every 250 ms.
import type { Clock } from "effect";
import { existsSync, type FSWatcher, watch } from "node:fs";
import type { LiveEvent } from "../agents/runtime.ts";
import { Fibers } from "../ops/fibers.ts";
import { ChainTail, type TailState } from "../read/tail.ts";
import { type TimelineEntry, brief } from "../read/transcript.ts";
import { type SessionUsage, noUsage } from "../read/usage.ts";
import type { RuntimeKind } from "../agents/runtime.ts";

export { ChainTail, TranscriptTail } from "../read/tail.ts";

type Phase = Extract<LiveEvent, { kind: "phase" }>["phase"];

/// A step in flight: what it is, not what it has written so far.
export type LiveStep = { id: string; step: "text" | "thinking" | "tool"; tool?: string; subagent?: boolean; parent?: string; input: string; startedAt: number };

export type LiveMessage =
  | { type: "steps"; steps: LiveStep[]; phase: { phase: Phase; elapsedMs: number } | null }
  | { type: "step"; event: LiveEvent }
  | { type: "timeline"; start: number; entries: TimelineEntry[]; usage: SessionUsage }
  /// How fast the model is writing now (≈ tokens a second, from bytes), at most once a second; 0 once it stops.
  | { type: "rate"; tokensPerSecond: number }
  | { type: "clear" };

export type Listener = (message: LiveMessage) => void;

/// A listener told the transcript's entries in brief (read/transcript.ts `brief`): what an execution history shows before
/// a step is opened, the rest read whole as it is.
export const inBrief = (listener: Listener): Listener => (m) => listener(m.type === "timeline" ? { ...m, entries: m.entries.map(brief) } : m);

/// How much of a tool's input a step carries: enough to say what it runs.
const INPUT_CHARS = 300;
/// The fields of a call's input that say what it runs. A client core before 0.1.2301 says what a running call does by
/// them (its activity.ts callText); a newer one says it by the call's transcript entry alone and reads none of them, but
/// a step without them showed only 处理中 in an older one: they stay until no client that old is about.
const SAYING = ["description", "command", "cmd", "file_path", "path", "pattern", "url", "query", "prompt"];
/// The output rate is told at most this often, over this window (bytes / 4 ≈ tokens).
const RATE_EVERY_MS = 1_000;
const RATE_WINDOW_MS = 2_000;
const RATE_FIRST_MS = 500;
/// How long a session is still followed once its turn is over (`running`): a person who answers within it is answered
/// without its transcript read again from the start.
export const HELD_AFTER_MS = 2 * 60_000;

const takeChars = (text: string, n: number) => Array.from(text).slice(0, n).join("");
/**
 * A call's input as a step carries it: of a JSON object, only the fields that say what it runs, each cut short, so a
 * long command before it does not cut its description off (it showed as "Run the tests 3 times with new m"); anything
 * else cut short as it is.
 */
export function briefInput(input: string): string {
  let args: unknown;
  try {
    args = JSON.parse(input);
  } catch {
    return takeChars(input, INPUT_CHARS);
  }
  if (typeof args !== "object" || args === null || Array.isArray(args)) return takeChars(input, INPUT_CHARS);
  const kept: Record<string, string | string[]> = {};
  for (const name of SAYING) {
    const v = (args as Record<string, unknown>)[name];
    if (typeof v === "string") kept[name] = takeChars(v, INPUT_CHARS);
    else if (Array.isArray(v)) kept[name] = v.filter((p): p is string => typeof p === "string").map((p) => takeChars(p, INPUT_CHARS));
  }
  return JSON.stringify(kept);
}

type Rate = { buckets: [number, number][]; toldAt: number; told: number };
/// `behind`: the transcript of the runtime session it runs in now is not written yet (a runtime writes it once its
/// conversation has begun), so where its history goes on is looked for again on each read. `tail` null while where its
/// transcripts stand is read off the main thread (`ready`).
type Watched = { tail: ChainTail | null; ready: Promise<void> | null; watcher: FSWatcher | null; reading: boolean; behind: boolean; arm(): void };
/// A listener of a session: whether it is told the entries in brief, and what is said while it joins (what it lacks of
/// the transcript read off the main thread first), held until it has joined.
type Sub = { id: number; listener: Listener; brief: boolean; queue: LiveMessage[] | null };

/// Where a session's history is read off the main thread (the readers: sessions/agents.ts), so the live view reads none
/// of a transcript's past here: where the reading of its transcripts stands there (read/tail.ts `snapshot`; null: none
/// found), to go on from; and up to `limit` entries just before `before`, in brief or whole, with the index of the
/// first and how many there are (`end`).
export type History = {
  state(key: string): Promise<TailState[] | null>;
  page(key: string, before: number, limit: number, brief: boolean): Promise<{ start: number; entries: TimelineEntry[]; end: number }>;
};

/// Where a session's transcripts are: of the runtime sessions it ran in, the first first, ending with its current one
/// (`current`: whether that one's is among them; when not given, it is).
export type Locate = (key: string) => { runtime: RuntimeKind; paths: string[]; current?: boolean } | null;

export class LiveHub {
  private steps = new Map<string, LiveStep[]>();
  private phase = new Map<string, [Phase, number]>();
  private rates = new Map<string, Rate>();
  private listeners = new Map<string, Sub[]>();
  private watched = new Map<string, Watched>();
  /// Its time and its waits (a read put off to gather a burst of writes).
  private time: Fibers;
  private nextId = 0;
  /// Where a session's transcript is, once its runtime has started one.
  private locate: Locate;
  /// What the usage counter recorded of a session's calls (usage/module.ts `usageNow`), and asking it to count what a
  /// session at work wrote since (agents.ts, once it runs).
  private count: { of: (key: string) => SessionUsage | null; ask: (key: string) => void } | null = null;
  /// Each watched session's usage as last told.
  private told = new Map<string, string>();
  /// The sessions at work, followed by the station itself (`running`): what each says goes to `heldTold`, whoever
  /// watches; and, of those whose turn is over, the end of the while they are still followed.
  private holds = new Map<string, number>();
  private releases = new Map<string, () => void>();
  /// Where what the sessions at work say goes (api/events.ts: every stream whose viewer sees them).
  heldTold: ((key: string, message: LiveMessage) => void) | null = null;
  /// Where each watched transcript's length goes as it changes (the store: its session's summary says it).
  lengths: ((key: string, n: number) => void) | null = null;
  private lengthTold = new Map<string, number>();
  /// Where a transcript's past is read (agents.ts: the readers); none (tests): here, and kept in memory.
  history: History | null = null;

  constructor(locate: Locate, clock?: Clock.Clock) {
    this.locate = locate;
    this.time = new Fibers("live", clock);
  }

  countWith(count: { of: (key: string) => SessionUsage | null; ask: (key: string) => void }) {
    this.count = count;
  }

  /// A session's usage: its calls as the usage counter recorded them, the one count of them (the usage page's too). The
  /// live view counts none itself: what a transcript gains, the counter is asked to count (`soon`).
  private usageOf(key: string): SessionUsage {
    let usage: SessionUsage | null = null;
    try {
      usage = this.count?.of(key) ?? null;
    } catch {}
    usage ??= noUsage();
    this.told.set(key, JSON.stringify(usage));
    return usage;
  }

  /// The usage counter counted more: each watched session whose usage changed is told it.
  usageCounted() {
    for (const [key, watched] of this.watched) {
      if (watched.tail === null) continue;
      const before = this.told.get(key);
      const usage = this.usageOf(key);
      if (JSON.stringify(usage) !== before) this.emit(key, { type: "timeline", start: watched.tail.length, entries: [], usage });
    }
  }

  private emit(key: string, message: LiveMessage) {
    for (const sub of this.listeners.get(key) ?? []) {
      if (sub.queue !== null) sub.queue.push(message);
      else this.tell(sub, message);
    }
  }

  /// A message to one listener, its entries in brief for one that has them so (`briefed`: they are already).
  private tell(sub: Sub, message: LiveMessage, briefed = false) {
    try {
      sub.listener(sub.brief && !briefed && message.type === "timeline" ? { ...message, entries: message.entries.map(brief) } : message);
    } catch {}
  }

  /// The steps in flight, and the phase.
  private stepsNow(key: string): LiveMessage {
    const phase = this.phase.get(key);
    return { type: "steps", steps: [...(this.steps.get(key) ?? [])], phase: phase ? { phase: phase[0], elapsedMs: this.time.now() - phase[1] } : null };
  }

  /// A runtime's live event for a session.
  event(key: string, event: LiveEvent) {
    switch (event.kind) {
      case "phase":
        this.phase.set(key, [event.phase, this.time.now()]);
        this.emit(key, { type: "step", event });
        break;
      // What a step writes as it goes is not told: its words come with its transcript entry. How fast it writes is.
      case "delta":
        this.counted(key, Buffer.byteLength(event.text));
        break;
      case "start": {
        const input = briefInput(event.input ?? "");
        const steps = this.steps.get(key) ?? [];
        // Started again with its input (Claude Code streams it after the start): it keeps when it started.
        const startedAt = steps.find((s) => s.id === event.id)?.startedAt ?? this.time.now();
        const kept = steps.filter((s) => s.id !== event.id);
        const step = { id: event.id, step: event.step } as LiveStep;
        if (event.tool !== undefined) step.tool = event.tool;
        if (event.subagent === true) step.subagent = true;
        if (event.parent !== undefined) step.parent = event.parent;
        step.input = input;
        step.startedAt = startedAt;
        kept.push(step);
        this.steps.set(key, kept);
        const told: LiveEvent = { kind: "start", id: event.id, step: event.step };
        if (event.tool !== undefined) told.tool = event.tool;
        told.input = input;
        if (event.subagent !== undefined) told.subagent = event.subagent;
        if (event.parent !== undefined) told.parent = event.parent;
        this.emit(key, { type: "step", event: told });
        break;
      }
      case "end": {
        const steps = this.steps.get(key);
        if (!steps) return;
        const kept = steps.filter((s) => s.id !== event.id);
        if (kept.length === steps.length) return;
        this.steps.set(key, kept);
        this.emit(key, { type: "step", event });
        // A step ended: the model is not writing (until its next output).
        const rate = this.rates.get(key);
        this.rates.delete(key);
        if (rate && rate.told > 0) this.emit(key, { type: "rate", tokensPerSecond: 0 });
        this.soon(key);
        break;
      }
    }
  }

  /// The turn is over: whatever was in flight is in the transcript now, or never will be. What it wrote last is read
  /// now, so it is told (and its length kept) before the session is told to be done, not after the next write.
  turnEnded(key: string) {
    this.steps.delete(key);
    this.phase.delete(key);
    this.rates.delete(key);
    this.readNow(key);
    this.emit(key, { type: "clear" });
    this.soon(key);
  }

  /// Whether a session is at work (its `running` as the store has it): from when it starts until HELD_AFTER_MS after it
  /// stops, the station follows it itself, whoever watches, and tells what it does as it does it (`heldTold`). A stream
  /// asks for nothing to be told of it; and an answer given within the while finds it still read.
  running(key: string, on: boolean) {
    if (on) {
      this.releases.get(key)?.();
      this.releases.delete(key);
      if (this.holds.has(key)) return;
      // From where it ends now, in brief: what it said before is read by whoever lacks it, not told.
      this.holds.set(key, this.subscribe(key, Number.MAX_SAFE_INTEGER, null, (message) => this.heldTold?.(key, message), true));
      return;
    }
    if (!this.holds.has(key) || this.releases.has(key)) return;
    this.releases.set(
      key,
      this.time.after(HELD_AFTER_MS, () => {
        this.releases.delete(key);
        const id = this.holds.get(key);
        this.holds.delete(key);
        if (id !== undefined) this.unsubscribe(key, id);
      }),
    );
  }

  /// The sessions the station follows now (`running`).
  held(): string[] {
    return [...this.holds.keys()];
  }

  /// A followed session as it is now, for a stream that opens: where its transcript ends (no entry of it) with its
  /// usage, and the steps in flight.
  now(key: string): LiveMessage[] {
    const out: LiveMessage[] = [];
    const tail = this.watched.get(key)?.tail ?? null;
    if (tail !== null) out.push({ type: "timeline", start: tail.length, entries: [], usage: this.usageOf(key) });
    out.push(this.stepsNow(key));
    return out;
  }

  /// Reads a watched transcript's new entries now and tells them.
  private readNow(key: string) {
    const watched = this.watched.get(key);
    if (!watched || watched.tail === null) return;
    if (watched.behind) this.follow(watched, key);
    const [start, entries] = watched.tail.read();
    this.noteLength(key, watched.tail);
    this.gained(key, start, entries);
  }

  /// What a watched transcript gained, told; the usage counter is asked to count it (what it spent comes after).
  private gained(key: string, start: number, entries: TimelineEntry[]) {
    if (entries.length === 0) return;
    this.emit(key, { type: "timeline", start, entries, usage: this.usageOf(key) });
    this.count?.ask(key);
  }

  /// A watched transcript's length, kept where its summary reads it, as it changes.
  private noteLength(key: string, tail: ChainTail) {
    const n = tail.length;
    if (this.lengthTold.get(key) === n) return;
    this.lengthTold.set(key, n);
    try {
      this.lengths?.(key, n);
    } catch {}
  }

  /// Follows a session: first the transcript entries from index `from` on (only the `last` of them, when given: a long
  /// transcript is not sent whole; the ones before come by `before`), in brief for a listener that has them so, and the
  /// usage so far, the steps in flight, then everything new. What it lacks of the transcript is read off the main
  /// thread where the readers keep it (`history`), what comes meanwhile told after it. Gives the id to unsubscribe with.
  subscribe(key: string, from: number, last: number | null, listener: Listener, brief = false): number {
    const id = ++this.nextId;
    const sub: Sub = { id, listener, brief, queue: [] };
    this.listeners.set(key, [...(this.listeners.get(key) ?? []), sub]);
    this.watch(key);
    const ready = this.watched.get(key)?.ready ?? null;
    if (ready !== null) void ready.then(() => this.join(key, sub, from, last));
    else this.join(key, sub, from, last);
    return id;
  }

  /// A listener told what it lacks (`subscribe`), then what was said while it joined.
  private join(key: string, sub: Sub, from: number, last: number | null) {
    const listening = () => (this.listeners.get(key) ?? []).includes(sub);
    const joined = (first: LiveMessage[], briefed: boolean) => {
      if (!listening()) return;
      for (const m of first) this.tell(sub, m, briefed);
      const queued = sub.queue ?? [];
      sub.queue = null;
      for (const m of queued) this.tell(sub, m);
    };
    if (!listening()) return;
    const tail = this.watched.get(key)?.tail ?? null;
    if (tail === null) return joined([this.stepsNow(key)], false);
    // A watcher that has more than the transcript (it was written anew) is told where it ends.
    const len = tail.length;
    const start = Math.max(Math.min(from, len), last === null ? 0 : Math.max(0, len - last));
    const usage = this.usageOf(key);
    if (start >= len || tail.keeps) return joined([{ type: "timeline", start, entries: tail.keeps ? tail.entries.slice(start) : [], usage }, this.stepsNow(key)], false);
    void this.past(key, start, len, sub.brief).then(
      (entries) => joined([{ type: "timeline", start, entries, usage }, this.stepsNow(key)], true),
      // Not read: told where it ends; it reads what it lacks as it would anything.
      () => joined([{ type: "timeline", start: len, entries: [], usage }, this.stepsNow(key)], false),
    );
  }

  /// Entries `from ..< to` of a session's transcripts, read where its history is (`history`), in brief or whole.
  private async past(key: string, from: number, to: number, brief: boolean): Promise<TimelineEntry[]> {
    const pages: TimelineEntry[][] = [];
    for (let upto = to; upto > from; ) {
      const page = await this.history!.page(key, upto, Math.min(1000, upto - from), brief);
      const got = page.entries.slice(0, Math.max(0, upto - page.start));
      if (got.length === 0) break;
      pages.unshift(got);
      upto = page.start;
    }
    return pages.flat();
  }

  /// Up to `limit` transcript entries just before index `before`, and the index of the first: from what is watched and
  /// kept, else read now, here. Null when the session has no transcript.
  before(key: string, before: number, limit: number): [number, TimelineEntry[]] | null {
    const all = this.readHere(key);
    if (all === null) return null;
    const end = Math.min(before, all.length);
    const start = Math.max(0, end - limit);
    return [start, all.slice(start, end)];
  }

  /// As `before`, with how many entries there are (`end`): read off the main thread where the history is read so
  /// (`history`), else here. Null when the session has no transcript (here; the readers say none as no entries).
  async page(key: string, before: number, limit: number): Promise<{ start: number; entries: TimelineEntry[]; end: number } | null> {
    if (this.history !== null) return this.history.page(key, before, limit, false);
    const all = this.readHere(key);
    if (all === null) return null;
    const end = Math.min(before, all.length);
    const start = Math.max(0, end - limit);
    return { start, entries: all.slice(start, end), end: all.length };
  }

  /// A session's transcripts' entries as written now: those watched and kept (read up to now: the transcript it went on
  /// in included, what this reads told as it would be), else read now.
  private readHere(key: string): TimelineEntry[] | null {
    const watched = this.watched.get(key);
    if (watched?.tail?.keeps) {
      this.readNow(key);
      return watched.tail.entries;
    }
    const at = this.locate(key);
    if (!at) return null;
    const tail = new ChainTail(at.runtime, at.paths);
    tail.read();
    return tail.entries;
  }

  /// The session went on in a new runtime session: a watched history reads on in its transcript.
  moved(key: string) {
    const watched = this.watched.get(key);
    if (!watched) return;
    // Where it stands not read yet: it goes on into the new one once it is.
    if (watched.tail === null) {
      watched.behind = true;
      return;
    }
    // What the transcript left has is read first: its entries come before the new one's.
    const [start, entries] = watched.tail.read();
    this.gained(key, start, entries);
    // The new one is usually not written yet: it is looked for on each read until it is.
    watched.behind = true;
    this.follow(watched, key);
    this.soon(key);
  }

  /// Goes on into the transcripts a session that moved on has now, watching the one written to.
  private follow(watched: Watched, key: string) {
    if (watched.tail === null) return;
    const at = this.locate(key);
    if (!at) return;
    watched.behind = at.current === false;
    const path = watched.tail.path;
    watched.tail.extend(at.paths);
    if (watched.tail.path !== path) watched.arm();
  }

  unsubscribe(key: string, id: number) {
    const listeners = this.listeners.get(key);
    if (!listeners) return;
    const kept = listeners.filter((sub) => sub.id !== id);
    if (kept.length > 0) {
      this.listeners.set(key, kept);
      return;
    }
    this.listeners.delete(key);
    this.unwatch(key);
  }

  /// A deleted session: nothing of it is watched or kept any more.
  forget(key: string) {
    this.steps.delete(key);
    this.phase.delete(key);
    this.rates.delete(key);
    this.emit(key, { type: "clear" });
    this.releases.get(key)?.();
    this.releases.delete(key);
    this.holds.delete(key);
    this.lengthTold.delete(key);
    this.listeners.delete(key);
    this.unwatch(key);
  }

  close() {
    for (const key of [...this.watched.keys()]) this.unwatch(key);
    void this.time.close();
  }

  /// Output written: its rate is told once half a second of it has come (a first few bytes say nothing of the pace),
  /// then when a second has passed since it last was.
  private counted(key: string, bytes: number) {
    const now = this.time.now();
    let rate = this.rates.get(key);
    if (!rate) this.rates.set(key, (rate = { buckets: [], toldAt: 0, told: 0 }));
    const bucket = Math.floor(now / 250) * 250;
    const last = rate.buckets.at(-1);
    if (last && last[0] === bucket) last[1] += bytes;
    else rate.buckets.push([bucket, bytes]);
    rate.buckets = rate.buckets.filter(([at]) => at >= now - RATE_WINDOW_MS);
    if (now - rate.toldAt < RATE_EVERY_MS) return;
    const first = rate.buckets[0]![0];
    if (rate.toldAt === 0 && now - first < RATE_FIRST_MS) return;
    const span = Math.min(RATE_WINDOW_MS, Math.max(250, now - first));
    const total = rate.buckets.reduce((sum, [, b]) => sum + b, 0);
    const tokensPerSecond = Math.max(1, Math.round((total * 1000) / (4 * span)));
    rate.toldAt = now;
    rate.told = tokensPerSecond;
    this.emit(key, { type: "rate", tokensPerSecond });
  }

  /// Starts reading a watched session's transcript, once it exists. Whether it is watched now. Where its history is read
  /// off the main thread (`history`), it goes on from where the reading stands there (no read of its past here, nor any
  /// of it kept: listeners that lack some of it are given it from there); else it is read here, and kept.
  private watch(key: string): boolean {
    if (this.watched.has(key)) return true;
    if (!this.listeners.has(key)) return false;
    const at = this.locate(key);
    if (!at) return false;
    // The transcript written to now is watched: its file, or its `.zst` while packed (sessions/cold.ts): packed or
    // restored, it is another file, watched from then on (live.rs looks at whichever is there).
    const arm = () => {
      watched.watcher?.close();
      watched.watcher = null;
      if (this.watched.get(key) !== watched || watched.tail === null) return;
      const path = watched.tail.path;
      try {
        const watcher: FSWatcher = watch(existsSync(path) ? path : `${path}.zst`, { persistent: false }, (event) => {
          if (event === "rename") arm();
          this.soon(key);
        });
        watcher.on("error", () => {});
        watched.watcher = watcher;
      } catch {}
    };
    const watched: Watched = { tail: null, ready: null, watcher: null, reading: false, behind: at.current === false, arm };
    this.watched.set(key, watched);
    const begin = (tail: ChainTail) => {
      watched.tail = tail;
      watched.ready = null;
      this.noteLength(key, tail);
      arm();
    };
    if (this.history === null) {
      const tail = new ChainTail(at.runtime, at.paths);
      tail.read(); // what is already there counts as known; subscribers ask for what they lack
      begin(tail);
      return true;
    }
    const same = (states: TailState[] | null): states is TailState[] => states !== null && states.length === at.paths.length && states.every((st, i) => st.path === at.paths[i]);
    watched.ready = this.history
      .state(key)
      .then(
        (states) => states,
        () => null,
      )
      .then((states) => {
        if (this.watched.get(key) !== watched) return;
        if (same(states)) begin(ChainTail.from(at.runtime, states));
        else {
          // Its transcripts are not where the readers found them (or they could not say): read here, kept nowhere.
          const tail = new ChainTail(at.runtime, at.paths, null, false);
          tail.read();
          begin(tail);
        }
        // What was written since the readers read it.
        this.soon(key);
      });
    return true;
  }

  private unwatch(key: string) {
    const watched = this.watched.get(key);
    this.watched.delete(key);
    this.told.delete(key);
    watched?.watcher?.close();
  }

  /// Reads what the transcript gained, coalescing bursts of writes.
  private soon(key: string) {
    if (!this.listeners.has(key)) return;
    const fresh = !this.watched.has(key);
    if (!this.watch(key)) return;
    const watched = this.watched.get(key)!;
    if (watched.reading) return;
    watched.reading = true;
    this.time.after(40, () => {
      const now = this.watched.get(key);
      if (!now) return;
      now.reading = false;
      // Where it stands still being read off the main thread: read on once it is.
      if (now.tail === null) return;
      if (now.behind) this.follow(now, key);
      const [start, entries] = now.tail.read();
      this.noteLength(key, now.tail);
      if (entries.length > 0) this.gained(key, start, entries);
      else if (fresh) this.emit(key, { type: "timeline", start, entries, usage: this.usageOf(key) });
    });
  }
}
