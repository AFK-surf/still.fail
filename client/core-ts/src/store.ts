// Topics: their current values, who subscribes, and when a value goes out (store.rs).
//
// A topic comes alive with its first subscriber (the store calls the Source to start it) and is stopped a minute after
// its last one leaves; its value stays cached until then. `set` stores a value and schedules its emission; emissions
// are coalesced over COALESCE_MS, one window for all topics, so topics changed together go out together, in the order
// they changed; a topic's first value goes out on the next turn instead. A subscriber's first message is the whole
// value, the next ones only what changed (delta.ts), and an unchanged value sends nothing; one subscribed `from` another
// of its subscriptions to the same topic (a list's first rows, more of them asked now) gets its first value as what
// changed from that one's, not the whole of it again (#firstFrom); one asked again by a client that kept what it was
// sent as it let go of the topic (`have`) gets `same` where it is that still, else what changed from that (#first).
// Code inside the core can
// `watch` a topic; a derived topic is `invalidate`d and computed by its source when its emission goes out. While no page
// is in view (`inView`), what changed is kept from the subscribers and goes out as one difference per topic once one is.
import { Effect } from "effect";
import { computed, observe, signal, tracking, untracked, type Derived, type Source as ReactiveSource } from "./reactive.ts";
import { type AnyOp, diffKeyed, heavier, share, specOf } from "./collections.ts";
import { diff, largerThan, type Op } from "./delta.ts";
import { Output } from "./output.ts";
import { CoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import * as present from "./present.ts";
import { topicDebug, topicKey, type ClientId, type CoreMessage, type RequestId, type Topic } from "./protocol.ts";
import { laterSleep, type Runner } from "./runtime.ts";
import { Kind, type Span, type Tracer } from "./trace.ts";
import { readAfresh } from "./markdown.ts";
import { spent, spentSince, timed } from "./spent.ts";
import { equal, sharedValue } from "./util.ts";
import { holds } from "./data.ts";
import { version } from "./digest.ts";

export const COALESCE_MS = 50;
export const EVICT_AFTER_MS = 60_000;
/// How many values let go of keeping them (`keep`) are remembered for a client (#kept), the least recently let go of
/// forgotten first: the app keeps the lists its places open on, a workspace's eight or so, and its last 4 chats
/// (apps/mbui/src/sfbase/source.mbt `topic_kept`). One it keeps past these, asked again, is still answered `same`
/// where it has not changed (a version needs nothing remembered), and whole where it has.
export const KEPT_PER_CLIENT = 24;
/// The topics a page opens with, each first subscriber's wait for its first value a trace of its own (`<topic>.open`,
///): how long a chat took to show, and how much of that the core spent making it.
const OPENED = new Set(["chat"]);
/// Rounds of emissions that held the core this long are told (`core.flush`): what made the core busy as a page waited
/// for it. At most one a minute, saying how many there were and the worst of them: one a round was 1375 spans a phone
/// sent in two hours, more than anything else it sent (2026-10-31).
const FLUSH_HELD_MS = 50;
const FLUSH_TOLD_EVERY_MS = 60_000;
/// What an app acts on while none of its pages is in view (its notices, its icon's badge, a download ready saved, a
/// copy between stations: the topics it watches whatever page shows): these go out then too.
const UNSEEN = new Set(["notify", "workspaceMarks", "downloads", "driveTransfers"]);

/// A value or the error a topic shows.
export type Value = { ok: unknown } | { err: CoreError };

export function sameValue(a: Value | undefined, b: Value | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  if ("ok" in a) return "ok" in b && equal(a.ok, b.ok);
  return "err" in b && a.err.equals(b.err);
}

/// Whoever produces a kind of topic (the station module, the accounts module).
export interface Source {
  /// The topic got its first subscriber: fetch it and keep it current.
  start(topic: Topic): void;
  /// The topic is subscribed to or watched again in the while it is kept after the last went (not started anew).
  resume?(topic: Topic): void;
  /// Nobody has subscribed for a while: stop streams and timers for it.
  stop(topic: Topic): void;
  /// The current value of a topic marked stale, as it goes out; undefined while it has none.
  compute?(topic: Topic): Value | undefined;
  /// Whether a topic with no value yet waits on a station for it (nothing it shows is on the device), not only on what
  /// it is computed from being computed: its subscribers are told so (`waiting`).
  waits?(topic: Topic): boolean;
}

/// Keeps a watched topic subscribed; `drop` lets the topic go like a UI unsubscribing.
export class Watch {
  #store: Store;
  #topic: Topic;
  #id: number;
  #dropped = false;
  constructor(store: Store, topic: Topic, id: number) {
    this.#store = store;
    this.#topic = topic;
    this.#id = id;
  }
  drop(): void {
    if (this.#dropped) return;
    this.#dropped = true;
    this.#store.unwatch(this.#topic, this.#id);
  }
}

type Entry = {
  topic: Topic;
  value?: Value;
  usage: ReactiveSource<number>;
  input: ReactiveSource<ReactiveInput>;
  read: Derived<Value | undefined>;
  selections: WeakMap<(value: Value | undefined) => unknown, WeakMap<object, Derived<unknown>>>;
  stop?: () => void;
  job?: () => void;
  /// The value last sent to the subscribers; the next emission is the difference to it.
  sent?: Value;
  /// What would go out of it changed without a subscriber (#sentHolds no longer): it needs output when a page next asks
  /// for it, not `sent`.
  outputDirty?: boolean;
  /// Its value changed while no page was in view: what changed goes out once one is (`inView`).
  unseen?: boolean;
  /// Who subscribes, and whether it takes keyed ops (collections.ts).
  subscribers: [ClientId, RequestId, boolean][];
  watchers: [number, () => void][];
  stale: boolean;
  emitScheduled: boolean;
  idle: number | null;
  /// How its value goes out (output.ts).
  output?: Output;
  /// A page's first subscriber waiting for its first value (OPENED): its trace, and what the core spent making it.
  opening?: { span: Span; workMs: number; computes: number; mdFrom: number; spentFrom: Record<string, number> };
  /// Its subscribers told it waits on a station (Source.waits), while it has no value.
  waiting?: boolean;
};

type ReactiveInput = { mode: "direct"; value?: Value } | { mode: "derived" };

type Out = { value: unknown } | { delta: AnyOp[] } | { error: CoreError };

function whole(v: Value): Out {
  return "ok" in v ? { value: v.ok } : { error: v.err };
}

function to(out: Out, id: RequestId): CoreMessage {
  if ("value" in out) return { id, value: out.value };
  if ("delta" in out) return { id, delta: out.delta };
  return { id, error: out.error };
}

export class Store {
  readonly host: Host;
  readonly runner: Runner;
  readonly #topics = new Map<string, Entry>();
  readonly #subscriptions = new Map<string, Topic>();
  /// A keyed subscriber's `from` (`client/id` to the id of the client's other subscription), till its first value goes.
  readonly #from = new Map<string, RequestId>();
  /// A subscriber's `have` (`client/id` to the version of what it holds), till its first value goes (#first).
  readonly #have = new Map<string, string>();
  /// What each client holds of the topics it let go of keeping them (`keep`), by topic key: the value it was last sent,
  /// whose version its `{id, v}` said, and that version; at most KEPT_PER_CLIENT, the least recently let go of first.
  /// A subscription asked again with that version gets what changed from it (#first), not the value whole. It is
  /// cheap: the value is the object that went out (shared, read-only: never a copy, never changed), the one the topic's
  /// entry holds as `sent` while it lives, so it costs memory only once the topic is evicted or has moved on; and a
  /// version is made only as a client lets go of a topic it keeps. One is forgotten as a subscription of that client to
  /// that topic gets its first message (whatever it is: the client takes what it kept out with it too), and all of a
  /// client's as it goes (dropClient).
  readonly #kept = new Map<ClientId, Map<string, { ok: unknown; v: string }>>();
  #source: Source | null = null;
  #idleCount = 0;
  #watchCount = 0;
  #firstPending = new Map<string, Entry>();
  #updatesPending = new Map<string, Entry>();
  #pumping = false;
  #windowOpen = false;
  #soon = false;
  #held: ((topic: Topic) => unknown) | null = null;
  #release_: ((topic: Topic) => void) | null = null;
  #clock = false;
  #clockOn = false;
  #shaped = false;
  #inView = true;
  /// The rounds that held the core since `core.flush` last went out: how many, for how long, and the worst.
  #heldRounds: { from: number; rounds: number; ms: number; worst: { ms: number; topics: number; slowest: string; slowestMs: number; parts: [string, number][] } | null } | null = null;

  readonly #tracer: Tracer | null;

  constructor(host: Host, runner: Runner, tracer: Tracer | null = null) {
    this.host = host;
    this.runner = runner;
    this.#tracer = tracer;
  }

  setSource(source: Source): void {
    this.#source = source;
  }

  /// Where the values of the data's topics are read (data.ts): they have no value of their own here. `release` is told
  /// when such a topic goes (what was loaded for it can go).
  setHeld(held: (topic: Topic) => unknown, release?: (topic: Topic) => void): void {
    this.#held = held;
    this.#release_ = release ?? null;
  }

  #heldValue(topic: Topic): unknown {
    return this.#held ? this.#held(topic) : undefined;
  }

  #start(topic: Topic): void {
    this.#source?.start(topic);
    // A held topic goes out as it is read when its emission goes (not read now: a list only watched is not loaded).
    if (this.#held !== null && holds(topic)) this.invalidate(topic);
  }

  /// A topic owns its signal nodes for precisely as long as the store owns the topic.
  #newEntry(topic: Topic): Entry {
    let entry: Entry;
    const usage = signal(0, () => this.#release(topic));
    const input = signal<ReactiveInput>({ mode: "direct" });
    const read = computed(() => {
      const state = input.get();
      if (state.mode === "direct") return state.value;
      return this.#compute(topic) ?? entry.value;
    });
    entry = { topic, usage, input, read, selections: new WeakMap(), subscribers: [], watchers: [], stale: false, emitScheduled: false, idle: null };
    return entry;
  }

  /// The data changed a topic's value: it goes out, and whatever watches it hears now.
  changed(topic: Topic): void {
    this.invalidate(topic);
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    for (const [, w] of [...entry.watchers]) w();
  }

  /// Adds a subscriber; sends the cached value at once if there is one, and starts the topic if it was not live.
  subscribe(client: ClientId, id: RequestId, topic: Topic, keyed = false, from?: RequestId, have?: string): void {
    this.unsubscribe(client, id);
    const key = topicKey(topic);
    this.#subscriptions.set(`${client}/${id}`, topic);
    if (keyed && from !== undefined) this.#from.set(`${client}/${id}`, from);
    if (have !== undefined) this.#have.set(`${client}/${id}`, have);
    let entry = this.#topics.get(key);
    const started = entry === undefined;
    if (!entry) {
      entry = this.#newEntry(topic);
      this.#topics.set(key, entry);
    }
    const resumed = entry.idle !== null;
    // Its last client output predates changes made while the page was closed. A new subscriber must receive the
    // current value whole, rather than that old value followed by a delta.
    if (entry.outputDirty && entry.subscribers.length === 0) entry.sent = undefined;
    entry.subscribers.push([client, id, keyed]);
    entry.idle = null;
    const cached = entry.sent;
    if (cached === undefined && this.#updatesPending.get(key) === entry) {
      this.#updatesPending.delete(key);
      this.#firstPending.set(key, entry);
      this.#wakePending(true);
    }
    if (cached !== undefined) this.host.emit(client, this.#first(client, id, topic, keyed, cached) ?? to(whole(cached), id));
    else {
      if (entry.waiting === true) this.host.emit(client, { id, waiting: true });
      if (entry.opening === undefined && this.#tracer !== null && OPENED.has(topic.topic)) {
        const span = this.#tracer.root(`${topic.topic}.open`, Kind.Internal);
        // (made anew, or kept from a page shown a moment ago and let go: its view made again either way)
        span.set("stillfail.anew", started);
        entry.opening = { span, workMs: 0, computes: 0, mdFrom: readAfresh.chars, spentFrom: { ...spent } };
      }
    }
    if (started) this.#start(topic);
    else {
      if (resumed) this.#source?.resume?.(topic);
      // A held topic only watched in the core so far (by a view) has never gone out: it does now, not when it next
      // changes (#flush sends nothing of one that has no subscriber).
      if (cached === undefined && this.#held !== null && holds(topic)) this.invalidate(topic);
    }
    if (entry.outputDirty && this.#held !== null && holds(topic)) {
      // Held values are read from Data, not kept in the entry while only watched.
      this.invalidate(topic);
    } else if (entry.outputDirty && !entry.emitScheduled) {
      entry.emitScheduled = true;
      this.#scheduleEmit(topic);
    }
    this.#tick();
  }

  /// Whether any page is in view (Attend.shown). While none is, what changes is not sent: an app behind draws nothing,
  /// and a phone's keeps every message for its first frame back, all of them handed on in it (a few minutes behind was
  /// a hundred differences of the same few topics; hours behind, a first frame the system gave up waiting for,
  /// 2026-11-02). In view
  /// again, each topic changed meanwhile sends one difference, to its value now.
  inView(on: boolean): void {
    if (on === this.#inView) return;
    this.#inView = on;
    if (!on) return;
    for (const entry of this.#topics.values()) {
      if (!entry.unseen) continue;
      entry.unseen = false;
      if (entry.emitScheduled) continue;
      entry.emitScheduled = true;
      this.#scheduleEmit(entry.topic);
    }
  }

  /// Sends every value through its shape.
  setShaped(): void {
    this.#shaped = true;
  }

  /// Starts the minute clock: times in words go out fresh each minute while anything is shown. The clock's signals
  /// move on (present.ts `clockAt`); only what read a grain that changed is made again.
  setClock(): void {
    this.#clockOn = true;
    this.#tick();
  }

  #tick(): void {
    if (!this.#clockOn || this.#clock) return;
    this.#clock = true;
    const now = this.host.nowMs();
    const next = (Math.floor(now / 60_000) + 1) * 60_000 + 1000;
    this.runner.fork(
      laterSleep(Math.max(next - now, 0)).pipe(
        Effect.andThen(
          Effect.sync(() => {
            this.#clock = false;
            if (![...this.#topics.values()].some((e) => e.subscribers.length > 0 && present.ticks(e.topic))) return;
            const at = this.host.nowMs();
            present.clockAt({ now: at, offsetMin: this.host.utcOffsetMin(at) });
            this.#tick();
          }),
        ),
      ),
    );
  }

  /// What went out of a topic is out of date though its value is not (output.ts): it goes out again, shaped anew.
  #again(entry: Entry): void {
    if (this.#topics.get(topicKey(entry.topic)) !== entry || entry.emitScheduled) return;
    entry.emitScheduled = true;
    this.#scheduleEmit(entry.topic);
  }

  /// `keep`: the client keeps what it holds of the topic (protocol.ts): answered `{id, v}`, the version of that, the
  /// last message for `id`: what went to it before (a difference already on its way) it has applied by then. That value
  /// is remembered for the client (#kept), to send what changed from it as it asks again.
  unsubscribe(client: ClientId, id: RequestId, keep = false): void {
    const at = `${client}/${id}`;
    const topic = this.#subscriptions.get(at);
    if (!topic) {
      if (keep) this.host.emit(client, { id, v: null });
      return;
    }
    this.#subscriptions.delete(at);
    this.#from.delete(at);
    this.#have.delete(at);
    const entry = this.#topics.get(topicKey(topic));
    if (keep) {
      // (what went to it last: the value it holds, every message to it going out in order; none, where none went)
      const had = entry?.subscribers.some(([c, i]) => c === client && i === id) ? entry.sent : undefined;
      const v = had !== undefined && "ok" in had ? version(had.ok) : null;
      if (had !== undefined && "ok" in had && v !== null) this.#keep(client, topicKey(topic), had.ok, v);
      this.host.emit(client, { id, v });
    }
    if (!entry) return;
    entry.subscribers = entry.subscribers.filter(([c, i]) => !(c === client && i === id));
    if (entry.subscribers.length === 0 && entry.sent === undefined && this.#firstPending.get(topicKey(topic)) === entry) {
      const key = topicKey(topic);
      this.#firstPending.delete(key);
      this.#updatesPending.set(key, entry);
    }
    if (entry.subscribers.length === 0 && entry.opening) {
      entry.opening.span.cancel();
      entry.opening = undefined;
    }
    this.#release(topic);
  }

  /// Subscribes from inside the core: starts the topic if it was not live and calls `onChange` after each change of
  /// it, until the watch is dropped.
  watch(topic: Topic, onChange: () => void): Watch {
    const key = topicKey(topic);
    const id = ++this.#watchCount;
    let entry = this.#topics.get(key);
    const started = entry === undefined;
    if (!entry) {
      entry = this.#newEntry(topic);
      this.#topics.set(key, entry);
    }
    const resumed = entry.idle !== null;
    entry.watchers.push([id, onChange]);
    entry.idle = null;
    if (started) this.#start(topic);
    else if (resumed) this.#source?.resume?.(topic);
    return new Watch(this, topic, id);
  }

  unwatch(topic: Topic, id: number): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    entry.watchers = entry.watchers.filter(([w]) => w !== id);
    this.#release(topic);
  }

  /// Starts the eviction grace if nobody subscribes to or watches the topic any more.
  #release(topic: Topic): void {
    const idle = ++this.#idleCount;
    const entry = this.#topics.get(topicKey(topic));
    if (!entry || entry.subscribers.length > 0 || entry.watchers.length > 0 || entry.usage.hasSubscribers()) return;
    entry.idle = idle;
    this.runner.fork(laterSleep(EVICT_AFTER_MS).pipe(Effect.andThen(Effect.sync(() => this.#evict(topic, idle)))));
  }

  /// A UI went away: drops all its subscriptions, and what it kept of those it let go of.
  dropClient(client: ClientId): void {
    const ids = [...this.#subscriptions.keys()].filter((k) => k.startsWith(`${client}/`)).map((k) => Number(k.slice(k.indexOf("/") + 1)));
    for (const id of ids) this.unsubscribe(client, id);
    this.#kept.delete(client);
  }

  /// Client `client` let go of topic `key` keeping `ok`, of version `v`: remembered for it (#kept), the least recently
  /// let go of forgotten past KEPT_PER_CLIENT.
  #keep(client: ClientId, key: string, ok: unknown, v: string): void {
    let kept = this.#kept.get(client);
    if (kept === undefined) this.#kept.set(client, (kept = new Map()));
    kept.delete(key);
    kept.set(key, { ok, v });
    if (kept.size > KEPT_PER_CLIENT) kept.delete(kept.keys().next().value!);
  }

  /// How many values are remembered for `client` (#kept), for tests.
  keptOf(client: ClientId): number {
    return this.#kept.get(client)?.size ?? 0;
  }

  /// Stores a topic's new value (or its error) and schedules sending it. A topic that is not live is ignored.
  set(topic: Topic, value: Value): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    if ("ok" in value) sharedValue(value.ok);
    entry.value = value;
    const schedule = !entry.emitScheduled;
    entry.emitScheduled = true;
    const watchers = entry.watchers.map(([, w]) => w);
    if (schedule) this.#scheduleEmit(topic);
    entry.input.set({ mode: "direct", value });
    for (const w of watchers) w();
  }

  /// Replaces a topic's value by what `change` makes of it (a new value: the one kept is shared, and never changed in
  /// place), then schedules sending it. Does nothing if the topic has no value yet.
  update(topic: Topic, change: (value: unknown) => unknown): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry || !entry.value || !("ok" in entry.value)) return;
    entry.value = { ok: sharedValue(change(entry.value.ok)) };
    const schedule = !entry.emitScheduled;
    entry.emitScheduled = true;
    const watchers = entry.watchers.map(([, w]) => w);
    if (schedule) this.#scheduleEmit(topic);
    entry.input.set({ mode: "direct", value: entry.value });
    for (const w of watchers) w();
  }

  /// Marks a live topic's value out of date and schedules its emission.
  invalidate(topic: Topic): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    entry.stale = true;
    entry.input.set({ mode: "derived" });
    const schedule = !entry.emitScheduled;
    entry.emitScheduled = true;
    if (schedule) this.#scheduleEmit(topic);
  }

  /// Invalidates every live topic `pick` chooses.
  invalidateAll(pick: (topic: Topic) => boolean): void {
    for (const topic of this.liveTopics().filter(pick)) this.invalidate(topic);
  }

  #entryForRead(topic: Topic): Entry | undefined {
    const key = topicKey(topic);
    let entry = this.#topics.get(key);
    if (tracking()) {
      const started = entry === undefined;
      if (!entry) {
        entry = this.#newEntry(topic);
        this.#topics.set(key, entry);
      }
      entry.usage.get();
      const resumed = entry.idle !== null;
      entry.idle = null;
      if (started) untracked(() => this.#start(topic));
      else if (resumed) untracked(() => this.#source?.resume?.(topic));
    }
    return entry;
  }

  /// The topic's value or error; undefined while it has neither.
  value(topic: Topic): Value | undefined {
    const entry = this.#entryForRead(topic);
    // Held values come straight from Data, but changes to their topics must still invalidate their readers.
    const held = this.#heldValue(topic);
    if (entry && (held !== undefined || (this.#held !== null && holds(topic)))) void entry.input.get();
    if (held !== undefined) {
      return { ok: held };
    }
    const value = entry?.read.get();
    if (value === undefined) return undefined;
    if ("err" in value) return value;
    // With a data center, a value of its topics here is only what was last sent.
    return this.#held !== null && holds(topic) ? undefined : value;
  }

  /// Reads one part of a topic. A reader is only made again if the selected part changes.
  select<T>(topic: Topic, pick: (value: Value | undefined) => T, same: (a: T, b: T) => boolean = equal): T {
    const entry = this.#entryForRead(topic);
    if (!entry) return pick(this.value(topic));
    let selections = entry.selections.get(pick);
    if (!selections) {
      selections = new WeakMap();
      entry.selections.set(pick, selections);
    }
    let selected = selections.get(same) as Derived<T> | undefined;
    if (!selected) {
      let made = false;
      let previous: T;
      selected = computed(() => {
        const next = pick(this.value(topic));
        if (made && same(previous, next)) return previous;
        made = true;
        return (previous = next);
      });
      selections.set(same, selected as Derived<unknown>);
    }
    return selected.get();
  }

  get(topic: Topic): unknown {
    const v = this.value(topic);
    return v && "ok" in v ? v.ok : undefined;
  }

  /// Whether a UI subscribes to the topic now.
  subscribed(topic: Topic): boolean {
    return (this.#topics.get(topicKey(topic))?.subscribers.length ?? 0) > 0;
  }

  /// Whether anything shows the topic now: a UI subscribes to it, or a view built from it is watched (a page open).
  inUse(topic: Topic): boolean {
    const entry = this.#topics.get(topicKey(topic));
    return entry !== undefined && (entry.subscribers.length > 0 || entry.watchers.length > 0 || entry.usage.hasSubscribers());
  }

  /// Whether a newly opened view is waiting for its first value to be made.
  firstValuesPending(): boolean {
    return this.#firstPending.size > 0;
  }

  /// Topics with at least one subscriber (or within their eviction grace).
  liveTopics(): Topic[] {
    return [...this.#topics.values()].map((e) => e.topic);
  }

  #scheduleEmit(topic: Topic): void {
    const key = topicKey(topic);
    const entry = this.#topics.get(key);
    if (!entry) return;
    const first = entry.sent === undefined && entry.subscribers.length > 0;
    this.#firstPending.delete(key);
    this.#updatesPending.delete(key);
    (first ? this.#firstPending : this.#updatesPending).set(key, entry);
    this.#wakePending(first);
  }

  #wakePending(first: boolean): void {
    if (this.#pumping) return;
    if (first) {
      if (this.#soon) return;
      this.#soon = true;
    } else {
      if (this.#windowOpen) return;
      this.#windowOpen = true;
    }
    this.runner.fork((first ? Effect.yieldNow : Effect.sleep(COALESCE_MS)).pipe(Effect.andThen(this.#flushPending())));
  }

  #flushPending(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (this.#pumping) return;
      this.#pumping = true;
      this.#windowOpen = false;
      this.#soon = false;
      let wasFirst = false;
      try {
        while (this.#firstPending.size > 0 || this.#updatesPending.size > 0) {
          // A new page takes its turn immediately after background work; alternating while both queues have work
          // also gives already queued updates a turn if pages keep opening.
          const first: boolean = this.#firstPending.size > 0 && (this.#updatesPending.size === 0 || !wasFirst);
          const queue = first ? this.#firstPending : this.#updatesPending;
          const [key, entry] = queue.entries().next().value!;
          queue.delete(key);
          if (this.#topics.get(key) !== entry || !entry.emitScheduled) continue;
          wasFirst = first;
          const topic = entry.topic;
          const t0 = this.host.monotonicMs();
          const spentFrom = this.#tracer !== null ? { ...spent } : null;
          this.#flush(topic);
          this.#heldFor(topic, t0, spentFrom);
          if (this.#firstPending.size > 0 || this.#updatesPending.size > 0) yield* Effect.yieldNow;
        }
      } finally {
        this.#pumping = false;
        if (!this.runner.closed) {
          if (this.#firstPending.size > 0) this.#wakePending(true);
          else if (this.#updatesPending.size > 0) this.#wakePending(false);
        }
      }
    });
  }

  #heldFor(topic: Topic, t0: number, spentFrom: Record<string, number> | null): void {
    const now = this.host.monotonicMs();
    const held = now - t0;
    if (held < FLUSH_HELD_MS || this.#tracer === null) return;
    // (the first told at once; then each a minute after the one before)
    const first = this.#heldRounds === null;
    const h = (this.#heldRounds ??= { from: now, rounds: 0, ms: 0, worst: null });
    h.rounds++;
    h.ms += held;
    if (h.worst === null || held > h.worst.ms) h.worst = { ms: held, topics: 1, slowest: topic.topic, slowestMs: held, parts: spentFrom ? spentSince(spentFrom) : [] };
    if (!first && now - h.from < FLUSH_TOLD_EVERY_MS) return;
    const span = this.#tracer.root("core.flush", Kind.Internal);
    span.set("stillfail.rounds", h.rounds);
    span.set("stillfail.rounds_ms", Math.round(h.ms));
    const w = h.worst!;
    span.set("stillfail.held_ms", Math.round(w.ms));
    span.set("stillfail.topics", w.topics);
    span.set("stillfail.slowest", w.slowest);
    span.set("stillfail.slowest_ms", Math.round(w.slowestMs));
    for (const [part, ms] of w.parts) span.set(`stillfail.ms.${part}`, Math.round(ms));
    span.end();
    this.#heldRounds = { from: now, rounds: 0, ms: 0, worst: null };
  }

  /// What the source makes of a topic now, kept shared (frozen when that is checked). A source that throws making it
  /// fails this topic, which says why, not the core and every other topic with it (a chat's view writing on a frozen
  /// message took the whole core down once, and the page stayed on 正在读取对话).
  #compute(topic: Topic): Value | undefined {
    let value: Value | undefined;
    try {
      value = this.#source?.compute?.(topic);
    } catch (error) {
      console.error(`computing ${topicDebug(topic)} failed`, error);
      return { err: new CoreError("internal", t("core-misc.compute", { topic: topicDebug(topic), reason: error instanceof Error ? error.message : String(error) })) };
    }
    if (value !== undefined && "ok" in value) sharedValue(value.ok);
    return value;
  }

  #flush(topic: Topic): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    entry.emitScheduled = false;
    const stale = entry.stale;
    entry.stale = false;
    const job = entry.job;
    entry.job = undefined;
    job?.();
    const isHeld = this.#held !== null && holds(topic);
    let computed: Value | undefined;
    const workFrom = entry.opening ? this.host.monotonicMs() : 0;
    if (stale) {
      if (isHeld && entry.subscribers.length === 0) {
        // Only watched: who watches it reads what is held (and heard of its changes as they were made); what is read
        // here is only what its source says when nothing is held (an error), so nothing is loaded for it.
        entry.outputDirty = true;
        const said = this.#compute(topic);
        const was = entry.value;
        if (said === undefined ? was === undefined || !("err" in was) : sameValue(was, said)) return;
        entry.value = said;
        for (const [, w] of [...entry.watchers]) w();
        return;
      }
      const held = this.#heldValue(topic);
      // A direct set after an invalidation is visible immediately; the queued recomputation still follows it.
      if (held === undefined && entry.input.get().mode !== "derived") entry.input.set({ mode: "derived" });
      if (held !== undefined) computed = { ok: held };
      else {
        entry.stop ??= observe(() => { entry.read.get(); }, (next) => {
          entry.job = next;
          // A direct write already schedules this entry; it only needs its observer refreshed.
          if (entry.input.get().mode === "direct" && !entry.stale) return;
          entry.stale = true;
          const schedule = !entry.emitScheduled;
          entry.emitScheduled = true;
          if (schedule) this.#scheduleEmit(topic);
        });
        computed = entry.read.get();
      }
    }
    const now = this.#topics.get(topicKey(topic));
    if (!now) return;
    let changed: (() => void)[] = [];
    // What equals the last value is the last value's (collections.ts share): what did not change goes on as the same
    // objects, which the diff and the items' shaping step over.
    // (only what goes out: what reads a topic in the core reads what its source made)
    if (now.subscribers.length > 0 && computed !== undefined && "ok" in computed && now.value !== undefined && "ok" in now.value && now.value.ok !== computed.ok) {
      const kept = share(now.value.ok, computed.ok, specOf(topic));
      computed = kept === now.value.ok ? now.value : { ok: sharedValue(kept) };
    }
    if (computed !== undefined && computed !== now.value && !sameValue(now.value, computed)) {
      // What is held tells its watchers as it changes (changed): only an error is news to them here.
      const news = !isHeld || "err" in computed || (now.value !== undefined && "err" in now.value);
      now.value = computed;
      if (news) changed = now.watchers.map(([, w]) => w);
    }
    if (now.value === undefined) {
      if (now.opening) {
        now.opening.workMs += this.host.monotonicMs() - workFrom;
        now.opening.computes++;
      }
      // Nothing to show yet: whoever shows it told once if that waits on a station, not on the core (a page opening
      // then shows what is to come at once, and otherwise waits for what the device holds).
      if (now.waiting !== true && now.subscribers.length > 0 && this.#source?.waits?.(topic) === true) {
        now.waiting = true;
        for (const [client, id] of now.subscribers) this.host.emit(client, { id, waiting: true });
        now.opening?.span.set("stillfail.waiting", true);
      }
      return;
    }
    now.waiting = false;
    if (now.subscribers.length === 0) {
      // Internal readers use the value above, not its client representation. Keep the last output for a reopening
      // page, and make the new one only when there is a subscriber to receive it. Out of date only where it is: a
      // value made again the same (a pref written at every switch of workspace, read whole by several views) left the
      // chat list it went into sent whole again as its page came back (69 KB, parsed on the app's frame thread), and
      // `profiles` shaped again (5 ms in Hermes, 2026-11-11). What is held is read from Data, not here: out of date.
      if (isHeld || !this.#sentHolds(now)) now.outputDirty = true;
      for (const w of changed) w();
      return;
    }
    if (!this.#inView && now.sent !== undefined && !UNSEEN.has(topic.topic)) {
      // No page in view: what changed goes out once one is (inView), not shaped till then.
      now.unseen = true;
      for (const w of changed) w();
      return;
    }
    now.outputDirty = false;
    const c: present.Clock = { now: this.host.nowMs(), offsetMin: this.host.utcOffsetMin(this.host.nowMs()) };
    let value: Value = now.value;
    if ("ok" in value) {
      // What is decorated is a copy (output.ts): not what is kept.
      now.output ??= new Output(() => this.#again(now));
      const output = now.output;
      const ok = value.ok;
      const out = timed(`${topic.topic}.shape`, () => output.shape(topic, ok, c, this.#shaped));
      value = "ok" in out ? { ok: out.ok } : { err: new CoreError("shape", t("core-misc.shape", { topic: topicDebug(topic), at: out.error })) };
    }
    // What goes out: to a subscriber taking keyed ops, its lists changed item by item; to the others, the old ops.
    let out: Out | null;
    let keyedOut: Out | null;
    const sent = now.sent;
    const subscribers = [...now.subscribers];
    if (sent !== undefined && "ok" in sent && "ok" in value) {
      const next = value.ok;
      const delta = (ops: Op[]): Out | null => (ops.length === 0 ? null : largerThan(ops, next) ? { value: next } : { delta: ops });
      const spec = specOf(topic);
      out = subscribers.some(([, , k]) => !k || !spec) ? delta(diff(sent.ok, next)) : null;
      if (spec && subscribers.some(([, , k]) => k)) {
        const ops = diffKeyed(sent.ok, next, spec);
        keyedOut = ops.length === 0 ? null : heavier(ops, next) ? { value: next } : { delta: ops };
      } else keyedOut = out;
    } else if (sent !== undefined && sameValue(sent, value)) out = keyedOut = null;
    else out = keyedOut = whole(value);
    now.sent = value;
    if (now.opening) {
      // Its first value going out: how long it took, and how much of it was the core making it (the rest it waited:
      // for what it is made from, or for the core busy with something else)
      const { span } = now.opening;
      const work = now.opening.workMs + this.host.monotonicMs() - workFrom;
      span.set("stillfail.work_ms", Math.round(work));
      span.set("stillfail.computes", now.opening.computes + 1);
      // (Markdown read afresh meanwhile, by it or by whatever else the core did: words not kept here nor on the device)
      span.set("stillfail.md_chars", readAfresh.chars - now.opening.mdFrom);
      // where the core's time went meanwhile, by part (spent.ts): this chat's making and whatever else ran
      for (const [part, ms] of spentSince(now.opening.spentFrom)) span.set(`stillfail.ms.${part}`, Math.round(ms));
      if ("err" in value) span.fail();
      span.end();
      now.opening = undefined;
    }
    for (const w of changed) w();
    for (const [client, id, keyed] of subscribers) {
      const o = keyed ? keyedOut : out;
      // (its first value: `same`, or what changed from what the client holds, where it says so)
      const first = sent === undefined ? this.#first(client, id, topic, keyed, value) : null;
      if (first) this.host.emit(client, first);
      else if (o) this.host.emit(client, to(o, id));
    }
  }

  /// Whether what went out of the topic last (`sent`) is what would go out of it now: an error that went out as it is,
  /// or what its output made of the very value it holds, said in the same words, nothing that making read changed
  /// since (output.ts `kept`). What makes it otherwise while nobody subscribes: a value made again that differs, or
  /// one `set` or `update`d (a new object, equal or not); a change kept from the subscribers while no page was in view
  /// (`unseen`, not shaped); what went out told out of date (#again: the clock moved on past its words, an item's
  /// computed); the language, the product's name, the minute where it says times in words; the last shaping failed.
  #sentHolds(entry: Entry): boolean {
    const { sent, value, output } = entry;
    if (sent === undefined || value === undefined) return false;
    if ("err" in value) return sent === value;
    if (!("ok" in sent) || output === undefined) return false;
    const at = this.host.nowMs();
    const kept = output.kept(entry.topic, value.ok, { now: at, offsetMin: this.host.utcOffsetMin(at) }, this.#shaped);
    return kept !== null && kept.ok === sent.ok;
  }

  /// The first message of subscriber `id` of `client` (`keyed`: it takes keyed ops) to topic `topic`, whose value going
  /// out is `value`, where it need not be the value whole; none where it goes whole. In this order:
  /// - `{id, same: true}` where it was asked with `have` and `value` is the one of that version: nothing of it sent;
  /// - its `from`'s (#firstFrom): what changed from another of its subscriptions held now (a list's first rows, more
  ///   of them asked), which differs from it by the rows asked and what changed this moment; what was kept is as old as
  ///   the while the topic was let go of, all that changed meanwhile in what changed from it: the lighter as a rule;
  /// - `{id, delta, kept: true}` where it was asked with `have` and that is the version of what the client was
  ///   remembered to keep of this topic (#kept): what changed from that, as a held subscriber's change goes (keyed ops
  ///   for a keyed one of a topic with keyed lists, plain else), unless it weighs more than the value (`heavier`,
  ///   `largerThan`, as #flush decides).
  /// An error, nothing remembered, another version: none. Its `from` and `have` are forgotten either way, and what was
  /// remembered of the topic for the client: its first message gone, the client keeps none of it after.
  #first(client: ClientId, id: RequestId, topic: Topic, keyed: boolean, value: Value): CoreMessage | null {
    const at = `${client}/${id}`;
    const have = this.#have.get(at);
    this.#have.delete(at);
    const kept = this.#kept.get(client);
    const had = kept?.get(topicKey(topic));
    if (had !== undefined) kept!.delete(topicKey(topic));
    if (have !== undefined && "ok" in value && version(value.ok) === have) {
      this.#from.delete(at);
      return { id, same: true };
    }
    const from = keyed ? this.#firstFrom(client, id, topic, value) : null;
    this.#from.delete(at);
    if (from !== null) return from;
    if (have === undefined || had === undefined || had.v !== have || !("ok" in value)) return null;
    const spec = keyed ? specOf(topic) : null;
    if (spec) {
      const ops = diffKeyed(had.ok, value.ok, spec);
      return heavier(ops, value.ok) ? null : { id, delta: ops, kept: true };
    }
    const ops = diff(had.ok, value.ok);
    return largerThan(ops, value.ok) ? null : { id, delta: ops, kept: true };
  }

  /// The first value `value` of topic `topic` going to subscriber `id` of `client` as what changed from what its
  /// `from` has: that subscription's topic's value as last sent, which the client holds, the messages to it going in
  /// order. None when it has no `from`, or that one is gone, has another topic's name, has no value, or the difference
  /// would be heavier than the value: it goes whole then. Its `from` is forgotten either way, its first value gone.
  #firstFrom(client: ClientId, id: RequestId, topic: Topic, value: Value): CoreMessage | null {
    const at = `${client}/${id}`;
    const from = this.#from.get(at);
    if (from === undefined) return null;
    this.#from.delete(at);
    const other = this.#subscriptions.get(`${client}/${from}`);
    if (!other || other.topic !== topic.topic || !("ok" in value)) return null;
    const entry = this.#topics.get(topicKey(other));
    const base = entry?.sent;
    if (!entry || !base || !("ok" in base) || !entry.subscribers.some(([c, i, k]) => c === client && i === from && k)) return null;
    const spec = specOf(topic);
    if (!spec) return null;
    const ops = diffKeyed(base.ok, value.ok, spec);
    return heavier(ops, value.ok) ? null : { id, delta: ops, from };
  }

  #evict(topic: Topic, idle: number): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry || entry.idle !== idle) return;
    // Gone before its source hears: what the source asks of the live topics then no longer has it.
    this.#topics.delete(topicKey(topic));
    entry.stop?.();
    entry.output?.stop();
    if (this.#firstPending.get(topicKey(topic)) === entry) this.#firstPending.delete(topicKey(topic));
    if (this.#updatesPending.get(topicKey(topic)) === entry) this.#updatesPending.delete(topicKey(topic));
    this.#source?.stop(topic);
    if (holds(topic)) this.#release_?.(topic);
  }
}
