// Topics: their current values, who subscribes, and when a value goes out (store.rs).
//
// A topic comes alive with its first subscriber (the store calls the Source to start it) and is stopped a minute after
// its last one leaves; its value stays cached until then. `set` stores a value and schedules its emission; emissions
// are coalesced over COALESCE_MS, one window for all topics, so topics changed together go out together, in the order
// they changed; a topic's first value goes out on the next turn instead. A subscriber's first message is the whole
// value, the next ones only what changed (delta.ts), and an unchanged value sends nothing. Code inside the core can
// `watch` a topic; a derived topic is `invalidate`d and computed by its source when its emission goes out.
import { Effect } from "effect";
import { type AnyOp, diffKeyed, heavier, specOf } from "./collections.ts";
import { diff, largerThan, type Op } from "./delta.ts";
import { Output } from "./output.ts";
import { CoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import * as present from "./present.ts";
import { topicDebug, topicKey, type ClientId, type CoreMessage, type RequestId, type Topic } from "./protocol.ts";
import type { Runner } from "./runtime.ts";
import { equal } from "./util.ts";
import { holds } from "./data.ts";

export const COALESCE_MS = 50;
export const EVICT_AFTER_MS = 60_000;

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
  /// Nobody has subscribed for a while: stop streams and timers for it.
  stop(topic: Topic): void;
  /// The current value of a topic marked stale, as it goes out; undefined while it has none.
  compute?(topic: Topic): Value | undefined;
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
  /// The value last sent to the subscribers; the next emission is the difference to it.
  sent?: Value;
  /// Who subscribes, and whether it takes keyed ops (collections.ts).
  subscribers: [ClientId, RequestId, boolean][];
  watchers: [number, () => void][];
  stale: boolean;
  emitScheduled: boolean;
  idle: number | null;
  /// How its value goes out (output.ts).
  output?: Output;
};

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
  #source: Source | null = null;
  #idleCount = 0;
  #watchCount = 0;
  #pending: Topic[] = [];
  #windowOpen = false;
  #soon = false;
  #held: ((topic: Topic) => unknown) | null = null;
  #release_: ((topic: Topic) => void) | null = null;
  #clock = false;
  #clockOn = false;
  #shaped = false;

  constructor(host: Host, runner: Runner) {
    this.host = host;
    this.runner = runner;
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
    if (this.#heldValue(topic) !== undefined) this.invalidate(topic);
  }

  /// The data changed a topic's value: it goes out, and whatever watches it hears now.
  changed(topic: Topic): void {
    this.invalidate(topic);
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    for (const [, w] of [...entry.watchers]) w();
  }

  /// Adds a subscriber; sends the cached value at once if there is one, and starts the topic if it was not live.
  subscribe(client: ClientId, id: RequestId, topic: Topic, keyed = false): void {
    this.unsubscribe(client, id);
    const key = topicKey(topic);
    this.#subscriptions.set(`${client}/${id}`, topic);
    let entry = this.#topics.get(key);
    const started = entry === undefined;
    if (!entry) {
      entry = { topic, subscribers: [], watchers: [], stale: false, emitScheduled: false, idle: null };
      this.#topics.set(key, entry);
    }
    entry.subscribers.push([client, id, keyed]);
    entry.idle = null;
    const cached = entry.sent;
    if (cached !== undefined) this.host.emit(client, to(whole(cached), id));
    if (started) this.#start(topic);
    this.#tick();
  }

  /// Sends every value through its shape.
  setShaped(): void {
    this.#shaped = true;
  }

  /// Starts the minute clock: times in words go out fresh each minute while anything is shown.
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
      Effect.sleep(Math.max(next - now, 0)).pipe(
        Effect.andThen(
          Effect.sync(() => {
            this.#clock = false;
            const shown = [...this.#topics.values()].filter((e) => e.subscribers.length > 0 && present.ticks(e.topic)).map((e) => e.topic);
            if (shown.length === 0) return;
            for (const topic of shown) this.invalidate(topic);
            this.#tick();
          }),
        ),
      ),
    );
  }

  unsubscribe(client: ClientId, id: RequestId): void {
    const at = `${client}/${id}`;
    const topic = this.#subscriptions.get(at);
    if (!topic) return;
    this.#subscriptions.delete(at);
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    entry.subscribers = entry.subscribers.filter(([c, i]) => !(c === client && i === id));
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
      entry = { topic, subscribers: [], watchers: [], stale: false, emitScheduled: false, idle: null };
      this.#topics.set(key, entry);
    }
    entry.watchers.push([id, onChange]);
    entry.idle = null;
    if (started) this.#start(topic);
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
    if (!entry || entry.subscribers.length > 0 || entry.watchers.length > 0) return;
    entry.idle = idle;
    this.runner.fork(Effect.sleep(EVICT_AFTER_MS).pipe(Effect.andThen(Effect.sync(() => this.#evict(topic, idle)))));
  }

  /// A UI went away: drops all its subscriptions.
  dropClient(client: ClientId): void {
    const ids = [...this.#subscriptions.keys()].filter((k) => k.startsWith(`${client}/`)).map((k) => Number(k.slice(k.indexOf("/") + 1)));
    for (const id of ids) this.unsubscribe(client, id);
  }

  /// Stores a topic's new value (or its error) and schedules sending it. A topic that is not live is ignored.
  set(topic: Topic, value: Value): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    entry.value = value;
    const schedule = !entry.emitScheduled;
    entry.emitScheduled = true;
    const watchers = entry.watchers.map(([, w]) => w);
    if (schedule) this.#scheduleEmit(topic);
    for (const w of watchers) w();
  }

  /// Changes a topic's value in place, then schedules sending it. Does nothing if the topic has no value yet.
  update(topic: Topic, change: (value: unknown) => unknown): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry || !entry.value || !("ok" in entry.value)) return;
    const next = change(entry.value.ok);
    if (next !== undefined) entry.value = { ok: next };
    const schedule = !entry.emitScheduled;
    entry.emitScheduled = true;
    const watchers = entry.watchers.map(([, w]) => w);
    if (schedule) this.#scheduleEmit(topic);
    for (const w of watchers) w();
  }

  /// Marks a live topic's value out of date and schedules its emission.
  invalidate(topic: Topic): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    entry.stale = true;
    const schedule = !entry.emitScheduled;
    entry.emitScheduled = true;
    if (schedule) this.#scheduleEmit(topic);
  }

  /// Invalidates every live topic `pick` chooses.
  invalidateAll(pick: (topic: Topic) => boolean): void {
    for (const topic of this.liveTopics().filter(pick)) this.invalidate(topic);
  }

  /// The topic's value or error; undefined while it has neither.
  value(topic: Topic): Value | undefined {
    const held = this.#heldValue(topic);
    if (held !== undefined) return { ok: held };
    const entry = this.#topics.get(topicKey(topic));
    const value = entry?.value;
    if (value === undefined) return undefined;
    if ("err" in value) return value;
    // With a data center, a value of its topics here is only what was last sent.
    return this.#held !== null && holds(topic) ? undefined : value;
  }

  get(topic: Topic): unknown {
    const v = this.value(topic);
    return v && "ok" in v ? v.ok : undefined;
  }

  /// Whether a UI subscribes to the topic now.
  subscribed(topic: Topic): boolean {
    return (this.#topics.get(topicKey(topic))?.subscribers.length ?? 0) > 0;
  }

  /// Topics with at least one subscriber (or within their eviction grace).
  liveTopics(): Topic[] {
    return [...this.#topics.values()].map((e) => e.topic);
  }

  #scheduleEmit(topic: Topic): void {
    this.#pending.push(topic);
    const entry = this.#topics.get(topicKey(topic));
    const first = entry !== undefined && entry.sent === undefined && entry.subscribers.length > 0;
    if (first) {
      if (this.#soon) return;
      this.#soon = true;
    } else {
      if (this.#windowOpen) return;
      this.#windowOpen = true;
    }
    this.runner.fork((first ? Effect.yieldNow : Effect.sleep(COALESCE_MS)).pipe(Effect.andThen(Effect.sync(() => this.#flushPending()))));
  }

  #flushPending(): void {
    this.#windowOpen = false;
    this.#soon = false;
    const pending = this.#pending;
    this.#pending = [];
    for (const topic of pending) this.#flush(topic);
  }

  #flush(topic: Topic): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry) return;
    entry.emitScheduled = false;
    const stale = entry.stale;
    entry.stale = false;
    const isHeld = this.#held !== null && holds(topic);
    let computed: Value | undefined;
    if (stale) {
      if (isHeld && entry.subscribers.length === 0) {
        // Only watched: who watches it reads what is held (and heard of its changes as they were made); what is read
        // here is only what its source says when nothing is held (an error), so nothing is loaded for it.
        const said = this.#source?.compute?.(topic);
        const was = entry.value;
        if (said === undefined ? was === undefined || !("err" in was) : sameValue(was, said)) return;
        entry.value = said;
        for (const [, w] of [...entry.watchers]) w();
        return;
      }
      const held = this.#heldValue(topic);
      computed = held !== undefined ? { ok: held } : this.#source?.compute?.(topic);
    }
    const now = this.#topics.get(topicKey(topic));
    if (!now) return;
    let changed: (() => void)[] = [];
    if (computed !== undefined && !sameValue(now.value, computed)) {
      // What is held tells its watchers as it changes (changed): only an error is news to them here.
      const news = !isHeld || "err" in computed || (now.value !== undefined && "err" in now.value);
      now.value = computed;
      if (news) changed = now.watchers.map(([, w]) => w);
    }
    if (now.value === undefined) return;
    const c: present.Clock = { now: this.host.nowMs(), offsetMin: this.host.utcOffsetMin(this.host.nowMs()) };
    let value: Value = now.value;
    if ("ok" in value) {
      // What is decorated is a copy (output.ts): not what is kept.
      now.output ??= new Output();
      const out = now.output.shape(topic, value.ok, c, this.#shaped);
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
    for (const w of changed) w();
    for (const [client, id, keyed] of subscribers) {
      const o = keyed ? keyedOut : out;
      if (o) this.host.emit(client, to(o, id));
    }
  }

  #evict(topic: Topic, idle: number): void {
    const entry = this.#topics.get(topicKey(topic));
    if (!entry || entry.idle !== idle) return;
    // Gone before its source hears: what the source asks of the live topics then no longer has it.
    this.#topics.delete(topicKey(topic));
    this.#source?.stop(topic);
    if (holds(topic)) this.#release_?.(topic);
  }
}
