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
import { equal, get, isObject, parseJson } from "../util.ts";
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
  /// Where chats were left (`chat.place`), as told this run or read from the database.
  readonly #places = new Map<string, LeftAt | null>();
  /// The chats whose place cores before kept in the host's storage was looked for this run.
  readonly #oldPlaces = new Set<string>();
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
      // Opened: the most recently used, kept while shown. Let go for room before, or a chat no list has (opened from an
      // old notification's link): the sync brings it.
      const evicted = this.#core.data.opened("entry", station, String(id), true);
      if (evicted || this.summary(station, id) === null) this.#sync.syncEntries(station, id, Priority.shown);
      this.#moveOldPlace(station, id);
    }
    if (topic.topic === "live" && this.#core.data.opened("transcript", station, topic.key as string, true)) this.#sync.syncTranscript(station, topic.key as string, Priority.shown);
    if (topic.topic === "net") this.#sampleNet(topic);
    // What the agents spent: read as a page shows it, not with each model call while none does.
    if (topic.topic === "stationUsage") this.#sync.usageShown(station);
    // A job's log: what it is now read once; from then on the station says how it grows, on its stream.
    if (topic.topic === "jobLog") this.#sync.readLog(station, topic.job as string, topic.lines as number);
    if (["host", "live", "jobLog"].includes(topic.topic)) this.#sync.openEvents(station, false);
  }

  stop(topic: Topic): void {
    const station = topicStation(topic);
    if (station === null) return;
    const key = topicKey(topic);
    if (topic.topic === "thread") this.#core.data.opened("entry", station, String(topic.thread), false);
    if (topic.topic === "live") this.#core.data.opened("transcript", station, topic.key as string, false);
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
    const data = this.#core.data;
    const span = data.logSpan("transcript", station, key);
    const link = this.#sync.link(station);
    const view = link?.lives.get(key);
    const end = span ? span.max + 1 : 0;
    // Its latest page; `history.older` brings the pages before (and keeps them in view).
    const tk = topicKey(topic);
    let first = this.#firsts.get(tk);
    if (first === undefined) {
      first = Math.max(end - TRANSCRIPT_PAGE, span ? span.min : 0);
      this.#firsts.set(tk, first);
    }
    // The unbroken run that ends the transcript, back as far as `first`.
    const items = data.logRange("transcript", station, key, first, end - 1);
    let from = end;
    while (from > first && items.has(from - 1)) from--;
    this.#firsts.set(tk, from);
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
      const data = this.#core.data;
      const from = Math.max(0, before - TRANSCRIPT_PAGE);
      if (data.logCount("transcript", station, key, from, before - 1) !== before - from) yield* this.#sync.transcript(station, key, before);
      const items = data.logRange("transcript", station, key, from, before - 1);
      if (!items.has(before - 1)) return false;
      let first = before;
      while (first > from && items.has(first - 1)) first--;
      this.#firsts.set(tk, first);
      this.#core.store.invalidate(topic);
      return first > 0;
    });
  }

  /// A history's entries `from` to `to` whole (`history.detail`), for what it shows of them in brief: read behind what is
  /// shown in brief, and in their place, the topic showing them as they come.
  historyDetail(station: string, key: string, from: number, to: number): Effect.Effect<void, CoreError> {
    return this.#sync.detail(station, key, from, to);
  }

  // ── threads ──

  /// The thread's summary as the station's lists say.
  summary(station: string, id: number): unknown {
    return this.#core.data.thread(station, id) ?? null;
  }

  /// Where a chat was left (`chat.place`), as told this run or kept in its account's database: there as the chat opens, not read from
  /// anywhere on the way (an empty first frame is a page swapped for another).
  #placeOf(station: string, thread: number): LeftAt | null {
    const key = `${station}\u0001${thread}`;
    if (this.#places.has(key)) return this.#places.get(key) ?? null;
    const kept = this.#core.data.record("place", `${station}/${thread}`);
    const at = u64(get(kept, "at"));
    const offset = get(kept, "offset");
    const place = at === null ? null : { at, offset: typeof offset === "number" ? offset : null };
    this.#places.set(key, place);
    return place;
  }

  /// Where a chat was left as cores before kept it, in the host's storage (a file of its own): moved into the
  /// database once, the file let go. Read on the way, it is for the next time the chat opens.
  #moveOldPlace(station: string, thread: number): void {
    const storage = placeKey(station, thread);
    const moved = `${station}\u0001${thread}`;
    if (this.#oldPlaces.has(moved)) return;
    this.#oldPlaces.add(moved);
    const host = this.#core.host;
    this.#core.runner.fork(
      Effect.ignore(
        Effect.gen({ self: this }, function* () {
          const kept = parseJson(yield* host.storageGet(storage));
          if (kept === null || kept === undefined) return;
          const at = u64(get(kept, "at"));
          if (at !== null && this.#core.data.record("place", `${station}/${thread}`) === undefined) {
            const offset = get(kept, "offset");
            this.#places.set(moved, { at, offset: typeof offset === "number" ? offset : null });
            this.#core.data.put("place", `${station}/${thread}`, { at, offset: typeof offset === "number" ? offset : null });
          }
          yield* host.storageDelete(storage);
        }),
      ),
    );
  }

  /// Where the reader leaves a chat: at entry `at` short of its end, or at its end (null). Kept in its account's database.
  place(station: string, thread: number, at: number | null, offset: number | null): void {
    const key = `${station}\u0001${thread}`;
    const place: LeftAt | null = at === null ? null : { at, offset: offset !== null && Number.isFinite(offset) ? offset : null };
    if (equal(this.#placeOf(station, thread), place)) return;
    this.#places.set(key, place);
    if (place) this.#core.data.put("place", `${station}/${thread}`, { at: place.at, offset: place.offset });
    else this.#core.data.forgetRecord("place", `${station}/${thread}`);
  }

  /// How far a thread is known to go: its summary's last, or what is held past it.
  #latest(station: string, id: number): number {
    const held = this.#core.data.logSpan("entry", station, String(id));
    return Math.max(u64(get(this.summary(station, id), "last")) ?? 0, held ? held.max : 0);
  }

  #thread(topic: Topic): Value | undefined {
    const station = topic.station as string;
    const id = topic.thread as number;
    const data = this.#core.data;
    const tk = topicKey(topic);
    const summary = this.summary(station, id);
    const span = data.logSpan("entry", station, String(id));
    const latest = this.#latest(station, id);
    let window = this.#windows.get(tk);
    if (!window) {
      // Where the chat is to be read: the first entry not read while something is unread, else where it was left, else
      // its end.
      const unread = u64(get(summary, "unread")) ?? 0;
      const read = u64(get(summary, "read"));
      const place = this.#placeOf(station, id);
      const at = read !== null && unread > 0 ? read + 1 : (place?.at ?? null);
      const atOffset = read !== null && unread > 0 ? null : (place?.offset ?? null);
      if (at !== null && at <= latest) {
        const from = Math.max(at - PAGE, 1);
        const to = Math.min(at + PAGE - 1, latest);
        let first = from;
        if (data.logCount("entry", station, String(id), from, to) !== to - from + 1) {
          // Not all on the device yet: brought. What is held from where it opens on (the sync brings the latest first)
          // opens it now, what is before it coming in as it does when read back; only with that not held either does
          // it wait.
          this.#core.runner.fork(Effect.ignore(this.#sync.ask(station, `range/${id}/${from}`, this.#sync.range(station, id, from, to, null))));
          const held = data.logRange("entry", station, String(id), from, to);
          for (let n = at; n <= to; n++) if (!held.has(n)) return undefined;
          first = at;
          while (first > from && held.has(first - 1)) first--;
        }
        window = { first, last: to >= latest ? null : to, at, atOffset, caught: to };
      } else {
        if (span === null) {
          // Nothing of it yet: it opens once its latest page is here (an empty thread opens empty).
          if (latest === 0 && summary !== null) window = { first: 1, last: null, at: null, atOffset: null, caught: 0 };
          else return undefined;
        } else {
          // The latest page held, as far back as it runs unbroken.
          const page = data.logRange("entry", station, String(id), Math.max(1, latest - PAGE + 1), span.max);
          let first = span.max;
          while (first > 1 && page.has(first - 1) && first > latest - PAGE + 1) first--;
          window = { first, last: null, at: null, atOffset: null, caught: span.max };
        }
      }
      this.#windows.set(tk, window);
    }
    const stop = window.last ?? Math.max(latest, span?.max ?? 0);
    const held = data.logRange("entry", station, String(id), window.first, stop);
    const entries: unknown[] = [];
    let last = window.first - 1;
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
    const row = data.chatOfThread(station, id);
    // A window kept to the chat's end is at its end even while the summary is ahead of what is held (a message just
    // said, its entry on its way): what comes joins it as it does, not a page to load after it.
    const value: Record<string, unknown> = { first: window.first, last, caught: Math.min(window.caught, last), entries, thread: summary, title: row === undefined ? null : (get(row, "title") ?? null), end: window.last === null };
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
      const held = this.#core.data.logRange("entry", station, String(id), Math.max(1, before - PAGE), before - 1);
      let first = before;
      while (first > Math.max(1, before - PAGE) && held.has(first - 1)) first--;
      if (first === before) return false;
      window.first = first;
      // As many go at the other end: the window is short of its end from then on.
      const top = window.last ?? this.#latest(station, id);
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
      const latest = this.#latest(station, id);
      const to = Math.min(after + PAGE, latest);
      yield* this.#sync.range(station, id, after + 1, to, null);
      const held = this.#core.data.logRange("entry", station, String(id), after + 1, to);
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
      const latest = this.#latest(station, id);
      yield* this.#sync.range(station, id, Math.max(1, latest - PAGE + 1), latest, null);
      const held = this.#core.data.logRange("entry", station, String(id), Math.max(1, latest - PAGE), latest);
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
        // No connection now (coming back): how it went last is kept, the station's card saying it is reconnecting.
        last = null;
        samples = [];
        value = this.#nets.get(key) ?? null;
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
