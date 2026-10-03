// The station topics (docs/client-core.md, Topics), read from what the sync holds (rule 6): the data center's records,
// a thread's or a transcript's items, and what a link holds beyond them (its state, the sessions at work, host samples,
// jobs' logs). A topic subscribed makes what it shows more urgent in the sync; it never asks for anything itself. A
// thread's window and a transcript's page are the topic's own state: where the reader is.
import { Effect, type Fiber } from "effect";
import type { Inner } from "../core.ts";
import { CoreError } from "../error.ts";
import { nOf } from "../entries.ts";
import { t } from "../i18n.ts";
import { topicKey, topicStation, type Topic } from "../protocol.ts";
import type { Owner } from "../core/routing.ts";
import type { Value } from "../store.ts";
import { Priority } from "../sync/scheduler.ts";
import { equal, get, isObject, parseJson, toJsonBytes } from "../util.ts";
import { StationAddr } from "./addr.ts";
import { PAGE, TRANSCRIPT_PAGE, type StationsSync } from "./sync.ts";

/// A chat shows a window of its thread's entries: at most this many.
export const WINDOW = 3 * PAGE;
/// How often a station's connection is sampled while its card shows it, and how many samples are kept.
export const NET_EVERY_MS = 2_000;
const NET_KEPT = 30;

const STATION_TOPICS = new Set(["link", "overview", "sessions", "host", "footprint", "net", "threads", "chatRows", "jobs", "archivedRows", "stationUsage", "session", "live", "thread", "slackApp", "jobLog", "job"]);

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);

/// Where a chat was left short of its end (`chat.place`).
export type LeftAt = { at: number; offset: number | null };

/// A thread topic's window: entries `first ..= last` (`last` null: up to the end as it grows), opened `at` an entry.
type Window = { first: number; last: number | null; at: number | null; atOffset: number | null; caught: number };

export function placeKey(station: string, thread: number): string {
  return `place/${station}/${thread}`;
}

export class StationTopics implements Owner {
  readonly #core: Inner;
  readonly #sync: StationsSync;
  /// Each open thread topic's window.
  readonly #windows = new Map<string, Window>();
  /// Each live topic's first item shown (history.older moves it back).
  readonly #firsts = new Map<string, number>();
  /// Where chats were left (`chat.place`), as told this run or read from the device.
  readonly #places = new Map<string, LeftAt | null>();
  /// Entries told as they were said (an event), by thread: they come in with a motion; the rest is caught up on.
  readonly told = new Map<string, Set<number>>();
  /// Connection samplers, by topic.
  readonly #samplers = new Map<string, Fiber.Fiber<void, never>>();
  /// The net topics' readings.
  readonly #nets = new Map<string, unknown>();

  constructor(core: Inner, sync: StationsSync) {
    this.#core = core;
    this.#sync = sync;
    sync.wanted = (address) => this.#wanted(address);
    sync.onChange = (address, what, key) => this.#changed(address, what, key);
    sync.onTold = (address, id, entries) => this.tell(address, id, entries);
    core.data.onLogChange((table, station, id) => {
      const topics = core.store.liveTopics().filter((t) => t.station === station && ((table === "entry" && t.topic === "thread" && String(t.thread) === id) || (table === "transcript" && t.topic === "live" && t.key === id)));
      for (const topic of topics) core.store.changed(topic);
    });
  }

  owns(topic: Topic): boolean {
    return STATION_TOPICS.has(topic.topic);
  }

  /// What the station topics shown want of each station's stream: host samples, the sessions shown, the logs shown.
  #wanted(address: string): { host: boolean; live: string[]; logs: [string, number][] } {
    const topics = this.#core.store.liveTopics().filter((t) => t.station === address);
    return {
      host: topics.some((t) => t.topic === "host"),
      live: topics.filter((t) => t.topic === "live").map((t) => t.key as string),
      logs: topics.filter((t) => t.topic === "jobLog").map((t) => [t.job as string, t.lines as number] as [string, number]),
    };
  }

  #changed(address: string, what: string, key?: string): void {
    const store = this.#core.store;
    const of = (pick: (t: Topic) => boolean) => store.invalidateAll((t) => t.station === address && pick(t));
    if (what === "link") of((t) => t.topic === "link" || t.topic === "live");
    else if (what === "live") of((t) => t.topic === "live" && (key === undefined || t.key === key));
    else if (what === "host") of((t) => t.topic === "host");
    else if (what === "log" || what === "errors") of((t) => key === undefined || topicKey(t) === key);
  }

  /// What a topic shown makes urgent in the sync.
  #urgent(topic: Topic): string | null {
    const station = topic.station as string;
    switch (topic.topic) {
      case "thread":
        return `${station} entries/${topic.thread}`;
      case "session":
        return `${station} session/${topic.key}`;
      case "live":
        return `${station} transcript/${topic.key}`;
      default:
        return null;
    }
  }

  start(topic: Topic): void {
    const station = topicStation(topic);
    if (station === null) return;
    try {
      StationAddr.parse(station);
    } catch {
      return;
    }
    const urgent = this.#urgent(topic);
    if (urgent) this.#core.scheduler.prioritize(topicKey(topic), urgent, Priority.shown);
    if (topic.topic === "thread") {
      const id = topic.thread as number;
      this.#core.runner.fork(
        Effect.gen({ self: this }, function* () {
          yield* this.#core.data.log("entry", station, String(id));
          yield* this.#place(station, id);
          this.#core.store.invalidate(topic);
        }),
      );
    }
    if (topic.topic === "live") this.#core.runner.fork(Effect.andThen(this.#core.data.log("transcript", station, topic.key as string), Effect.sync(() => this.#core.store.invalidate(topic))));
    if (topic.topic === "net") this.#sampleNet(topic);
    if (["host", "live", "jobLog"].includes(topic.topic)) this.#sync.openEvents(station, false);
  }

  stop(topic: Topic): void {
    const station = topicStation(topic);
    if (station === null) return;
    const key = topicKey(topic);
    this.#core.scheduler.prioritize(key, null);
    this.#windows.delete(key);
    this.#firsts.delete(key);
    const sampler = this.#samplers.get(key);
    if (sampler) {
      this.#core.runner.interrupt(sampler as Fiber.Fiber<unknown, unknown>);
      this.#samplers.delete(key);
    }
    if (["host", "live", "jobLog"].includes(topic.topic)) this.#sync.openEvents(station, false);
  }

  compute(topic: Topic): Value | undefined {
    const station = topicStation(topic)!;
    try {
      StationAddr.parse(station);
    } catch (e) {
      return { err: e as CoreError };
    }
    const link = this.#sync.link(station);
    const error = link?.errors.get(topicKey(topic));
    switch (topic.topic) {
      case "link":
        return { ok: link ? link.state : { state: "offline", message: t("core-views.station.not_listed") } };
      case "host": {
        const v = link?.memory.get("host");
        return v === undefined ? undefined : { ok: v };
      }
      case "jobLog": {
        const v = link?.memory.get(topicKey(topic));
        return v === undefined ? undefined : { ok: v };
      }
      case "net":
        return this.#nets.has(topicKey(topic)) ? { ok: this.#nets.get(topicKey(topic)) } : undefined;
      case "live":
        return this.#live(topic);
      case "thread":
        if (error) return { err: error };
        return this.#thread(topic);
      default:
        // Held: what is held goes out (the store reads it); with nothing held, why not, once known.
        return error ? { err: error } : undefined;
    }
  }

  // ── live ──

  #live(topic: Topic): Value | undefined {
    const station = topic.station as string;
    const key = topic.key as string;
    const items = this.#core.data.loaded("transcript", station, key);
    if (!items) return undefined;
    const link = this.#sync.link(station);
    const view = link?.lives.get(key);
    const ns = [...items.keys()].sort((a, b) => a - b);
    const end = ns.length > 0 ? ns[ns.length - 1] + 1 : 0;
    // Its latest page; `history.older` brings the pages before (and keeps them in view).
    const tk = topicKey(topic);
    let first = this.#firsts.get(tk);
    if (first === undefined) {
      first = Math.max(end - TRANSCRIPT_PAGE, ns.length > 0 ? ns[0] : 0);
      this.#firsts.set(tk, first);
    }
    // The run held from `first` to the end.
    let from = first;
    while (from < end && !items.has(from)) from++;
    const timeline: unknown[] = [];
    for (let n = from; n < end && items.has(n); n++) timeline.push(items.get(n));
    const value: Record<string, unknown> = {
      loaded: view?.loaded ?? false,
      first: from,
      timeline,
      usage: view?.usage ?? null,
      steps: view?.steps ?? [],
      phase: view?.phase ?? null,
    };
    if (view?.rate !== null && view?.rate !== undefined) value.rate = view.rate;
    if (view) value.activity = this.#sync.activity(value);
    // Offline, what is held is all there is: it is loaded, and says why it ends there.
    if (!this.#sync.reachable(station) || !link || link.state.state !== "online") {
      if (!view?.loaded) {
        value.loaded = true;
        value.offline = true;
      }
    }
    return { ok: value };
  }

  /// The page of a transcript before what a `live` topic shows, into it: from what is held, else read now.
  historyOlder(station: string, key: string): Effect.Effect<boolean, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const topic: Topic = { topic: "live", station, key };
      const tk = topicKey(topic);
      const before = this.#firsts.get(tk);
      if (before === undefined || before === 0) return false;
      const items = yield* this.#core.data.log("transcript", station, key);
      const from = Math.max(0, before - TRANSCRIPT_PAGE);
      let all = true;
      for (let n = from; n < before; n++) if (!items.has(n)) all = false;
      if (!all) yield* this.#sync.transcript(station, key, before);
      if (!items.has(before - 1)) return false;
      let first = before;
      while (first > from && items.has(first - 1)) first--;
      this.#firsts.set(tk, first);
      this.#core.store.invalidate(topic);
      return first > 0;
    });
  }

  // ── threads ──

  /// The thread's summary as the station's lists say.
  summary(station: string, id: number): unknown {
    const listed = (this.#core.data.get({ topic: "threads", station }) as unknown[] | undefined)?.find((t) => u64(get(t, "id")) === id);
    if (listed !== undefined) return listed;
    for (const [key, detail] of this.#core.data.records("session")) {
      if (!key.startsWith(`${station}\u0001`)) continue;
      const found = ((get(detail, "threads") as unknown[] | undefined) ?? []).find((t) => u64(get(t, "id")) === id);
      if (found !== undefined) return found;
    }
    return null;
  }

  /// Where a chat was left (`chat.place`): as told this run, else as kept on the device.
  #place(station: string, thread: number): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const key = `${station}\u0001${thread}`;
      if (this.#places.has(key)) return;
      const kept = parseJson(yield* Effect.orElseSucceed(this.#core.host.storageGet(placeKey(station, thread)), () => null));
      const at = u64(get(kept, "at"));
      const offset = get(kept, "offset");
      if (!this.#places.has(key)) this.#places.set(key, at === null ? null : { at, offset: typeof offset === "number" ? offset : null });
    });
  }

  /// Where the reader leaves a chat: at entry `at` short of its end, or at its end (null). Kept on the device too.
  place(station: string, thread: number, at: number | null, offset: number | null): void {
    const key = `${station}\u0001${thread}`;
    const place: LeftAt | null = at === null ? null : { at, offset: offset !== null && Number.isFinite(offset) ? offset : null };
    if (this.#places.has(key) && equal(this.#places.get(key), place)) return;
    this.#places.set(key, place);
    const storage = placeKey(station, thread);
    this.#core.runner.fork(Effect.ignore(place ? this.#core.host.storageSet(storage, toJsonBytes({ at: place.at, offset: place.offset })) : this.#core.host.storageDelete(storage)));
  }

  /// How far a thread is known to go: its summary's last, or what is held past it.
  #latest(station: string, id: number, held: Map<number, unknown>): number {
    let latest = u64(get(this.summary(station, id), "last")) ?? 0;
    for (const n of held.keys()) latest = Math.max(latest, n);
    return latest;
  }

  #thread(topic: Topic): Value | undefined {
    const station = topic.station as string;
    const id = topic.thread as number;
    const held = this.#core.data.loaded("entry", station, String(id));
    if (!held) return undefined;
    const tk = topicKey(topic);
    const summary = this.summary(station, id);
    const latest = this.#latest(station, id, held);
    let window = this.#windows.get(tk);
    if (!window) {
      const placeKeyOf = `${station}\u0001${id}`;
      if (!this.#places.has(placeKeyOf)) return undefined;
      // Where the chat is to be read: the first entry not read while something is unread, else where it was left, else
      // its end.
      const unread = u64(get(summary, "unread")) ?? 0;
      const read = u64(get(summary, "read"));
      const place = this.#places.get(placeKeyOf) ?? null;
      const at = read !== null && unread > 0 ? read + 1 : (place?.at ?? null);
      const atOffset = read !== null && unread > 0 ? null : (place?.offset ?? null);
      if (at !== null && at <= latest) {
        const from = Math.max(at - PAGE, 1);
        const to = Math.min(at + PAGE - 1, latest);
        for (let n = from; n <= to; n++) {
          if (!held.has(n)) {
            // Not on the device yet: brought first.
            this.#core.runner.fork(Effect.ignore(this.#sync.ask(station, `range/${id}/${from}`, this.#sync.range(station, id, from, to, null))));
            return undefined;
          }
        }
        window = { first: from, last: to >= latest ? null : to, at, atOffset, caught: to };
      } else {
        if (held.size === 0) {
          // Nothing of it yet: it opens once its latest page is here (an empty thread opens empty).
          if (latest === 0 && summary !== null) window = { first: 1, last: null, at: null, atOffset: null, caught: 0 };
          else return undefined;
        } else {
          // The latest page held, as far back as it runs unbroken.
          let first = Math.max(...held.keys());
          while (first > 1 && held.has(first - 1) && first > latest - PAGE + 1) first--;
          window = { first, last: null, at: null, atOffset: null, caught: Math.max(...held.keys()) };
        }
      }
      this.#windows.set(tk, window);
    }
    const entries: unknown[] = [];
    let last = window.first - 1;
    const stop = window.last ?? Infinity;
    for (let n = window.first; n <= stop && held.has(n); n++) {
      entries.push(held.get(n));
      last = n;
    }
    // What came as it was said comes in with a motion; what was read is caught up on.
    const told = this.told.get(`${station}\u0001${id}`);
    let caught = window.caught;
    for (let n = caught + 1; n <= last; n++) {
      if (told?.has(n)) break;
      caught = n;
    }
    window.caught = Math.max(window.caught, caught);
    const end = window.last === null && last >= latest;
    const rows = this.#core.data.get({ topic: "chatRows", station }) as unknown[] | undefined;
    const title = rows?.find((r) => u64(get(r, "thread")) === id);
    const value: Record<string, unknown> = { first: window.first, last, caught: Math.min(window.caught, last), entries, thread: summary, title: title === undefined ? null : (get(title, "title") ?? null), end: window.last === null ? end || last >= latest : false };
    if (window.at !== null) value.at = window.at;
    if (window.atOffset !== null) value.atOffset = window.atOffset;
    return { ok: value };
  }

  #window(station: string, id: number): [string, Window] | null {
    const tk = topicKey({ topic: "thread", station, thread: id });
    const w = this.#windows.get(tk);
    return w ? [tk, w] : null;
  }

  /// The page before a chat's window into it (`chat.older`): from the device, else read now. Answers whether still
  /// older ones exist.
  older(station: string, id: number): Effect.Effect<boolean, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const found = this.#window(station, id);
      if (!found) return false;
      const [, window] = found;
      const before = window.first;
      if (before <= 1) return false;
      yield* this.#sync.older(station, id, before, null);
      const held = yield* this.#core.data.log("entry", station, String(id));
      let first = before;
      while (first > Math.max(1, before - PAGE) && held.has(first - 1)) first--;
      if (first === before) return false;
      window.first = first;
      // As many go at the other end: the window is short of its end from then on.
      const top = window.last ?? this.#latest(station, id, held);
      if (top - first + 1 > WINDOW) window.last = first + WINDOW - 1;
      this.#core.store.invalidate({ topic: "thread", station, thread: id });
      return first > 1;
    });
  }

  /// The page after a window short of its end (`chat.newer`): as many go at its start. Answers whether still newer
  /// ones exist.
  newer(station: string, id: number): Effect.Effect<boolean, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const found = this.#window(station, id);
      if (!found || found[1].last === null) return false;
      const window = found[1];
      const after = window.last!;
      const held = yield* this.#core.data.log("entry", station, String(id));
      const latest = this.#latest(station, id, held);
      const to = Math.min(after + PAGE, latest);
      yield* this.#sync.range(station, id, after + 1, to, null);
      let last = after;
      while (last < to && held.has(last + 1)) last++;
      window.last = last >= latest ? null : last;
      window.caught = Math.max(window.caught, last);
      const over = last - window.first + 1 - WINDOW;
      if (over > 0) window.first += over;
      this.#core.store.invalidate({ topic: "thread", station, thread: id });
      return last < latest;
    });
  }

  /// The thread's latest page in place of its window (`chat.latest`).
  latest(station: string, id: number): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const found = this.#window(station, id);
      if (!found || found[1].last === null) return;
      const held = yield* this.#core.data.log("entry", station, String(id));
      const latest = this.#latest(station, id, held);
      yield* this.#sync.range(station, id, Math.max(1, latest - PAGE + 1), latest, null);
      let first = latest;
      while (first > 1 && held.has(first - 1) && first > latest - PAGE + 1) first--;
      found[1].first = first;
      found[1].last = null;
      found[1].at = null;
      found[1].atOffset = null;
      found[1].caught = latest;
      this.#core.store.invalidate({ topic: "thread", station, thread: id });
    });
  }

  /// Whether a thread topic's window reaches its end.
  atEnd(station: string, id: number): boolean {
    return this.#window(station, id)?.[1].last === null;
  }

  // ── a station's connection, sampled while shown ──

  #sampleNet(topic: Topic): void {
    const station = topic.station as string;
    const key = topicKey(topic);
    const core = this.#core;
    let last: [number, NonNullable<ReturnType<NonNullable<StationsSync["wire"]["net"]>>>] | null = null;
    let samples: unknown[] = [];
    const sample = Effect.sync(() => {
      const link = this.#sync.link(station);
      const net = link ? (this.#sync.wire.net?.(link.addr) ?? null) : null;
      const now = core.host.nowMs();
      let value: unknown = null;
      if (net === null) {
        last = null;
        samples = [];
      } else {
        const since = last !== null && net.rxBytes >= last[1].rxBytes && net.txBytes >= last[1].txBytes ? last : null;
        if (since) {
          const secs = Math.max((now - since[0]) / 1000, 0.001);
          samples.push({ at: Math.round(now), rttMs: net.rttMs, rxBps: Math.round((net.rxBytes - since[1].rxBytes) / secs), txBps: Math.round((net.txBytes - since[1].txBytes) / secs), sent: Math.max(net.txPackets - since[1].txPackets, 0), lost: Math.max(net.lostPackets - since[1].lostPackets, 0) });
        } else samples = [];
        while (samples.length > NET_KEPT) samples.shift();
        const measured = net.measured ? { measuring: net.measured.measuring, relays: net.measured.relays.map(([relay, ms]) => ({ relay, rttMs: ms })), moved: net.measured.moved } : null;
        value = { path: net.path, relay: net.relay, rttMs: net.rttMs, rxBytes: net.rxBytes, txBytes: net.txBytes, samples: [...samples], measured, todayRxBytes: net.today?.[0] ?? null, todayTxBytes: net.today?.[1] ?? null };
        last = [now, net];
      }
      if (!this.#nets.has(key) || !equal(this.#nets.get(key), value)) {
        this.#nets.set(key, value);
        core.store.invalidate(topic);
      }
    });
    // A measurement shown on screen: sampled while it is shown, never kept.
    this.#samplers.set(key, core.runner.fork(Effect.forever(Effect.andThen(sample, Effect.sleep(NET_EVERY_MS)))));
  }

  /// Told entries (an event) of a thread: they come in with a motion.
  tell(station: string, id: number, entries: unknown[]): void {
    const k = `${station}\u0001${id}`;
    let set = this.told.get(k);
    if (!set) {
      set = new Set();
      this.told.set(k, set);
    }
    for (const e of entries) {
      const n = nOf(e);
      if (n !== null) set.add(n);
    }
  }

  static isObject = isObject;
}
