// The station topics (docs/client-core.md, Topics), read from what the sync holds (rule 6): the data center's records,
// a thread's or a transcript's items, and what a link holds beyond them (its state, the sessions at work, host samples,
// jobs' logs). A topic subscribed makes what it shows more urgent in the sync; it never asks for anything itself. A
// thread's window and a transcript's page are the topic's own state: where the reader is.
import { Deferred, Effect, type Fiber } from "effect";
import type { Inner } from "../core.ts";
import { membersOf } from "../db/account.ts";
import { CoreError } from "../error.ts";
import { nOf } from "../entries.ts";
import { t } from "../i18n.ts";
import { topicKey, topicStation, type Topic } from "../protocol.ts";
import { terms } from "../refs.ts";
import type { Owner } from "../core/routing.ts";
import type { Value } from "../store.ts";
import { Priority } from "../sync/scheduler.ts";
import { equal, get, isObject, parseJson } from "../util.ts";
import { ofAddress } from "../workspace.ts";
import { StationAddr } from "./addr.ts";
import { PAGE, TRANSCRIPT_PAGE, entriesOf, transcriptOf } from "./channel-kinds.ts";
import type { StationsSync } from "./sync.ts";
import type { LinkNet } from "./wire.ts";
import { screenCard, screensChanged, screensView } from "../screens.ts";
import { down, downWords, isLetter, members } from "../views/views.ts";
import { type Link, MEMORY, OUTFLOW, filePeekKey, linkPreviewKey, logKey } from "./link.ts";
import { grantsShown } from "./outflow.ts";
import * as logins from "./machine-logins.ts";
import { laterSleep } from "../runtime.ts";
import * as looks from "../looks.ts";

/// A chat shows a window of its thread's entries: at most this many of what it shows (shownTo).
export const WINDOW = 3 * PAGE;
/// How many entries a message found is to have on either side of it in the window, for the window to be left as it is.
const AROUND = 10;
/// How often a station's connection is sampled while its card shows it, and how many samples are kept.
export const NET_EVERY_MS = 2_000;
const NET_KEPT = 30;

/// Packets sent and lost between two samples, on the way in use: none counted across a change of way (or of
/// connection), whose counts are another way's.
export function packetsSince(was: LinkNet["packets"], now: LinkNet["packets"]): { sent: number; lost: number } {
  if (was === null || now === null || was.path !== now.path || now.sent < was.sent || now.lost < was.lost) return { sent: 0, lost: 0 };
  return { sent: now.sent - was.sent, lost: now.lost - was.lost };
}

const STATION_TOPICS = new Set(["link", "overview", "sessions", "host", "footprint", "net", "way", "threads", "chatRows", "jobs", "archivedRows", "stationUsage", "stationResources", "session", "live", "thread", "letters", "slackApp", "jobLog", "job", "drive", "screens", "screenCard", "machineLogins", "machineLogin", "machineLoginScreen", "stationSearch", "memory", "outflowGrants", "linkPreview", "filePeek"]);

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
  /// Each open `letters` topic: how far its chat went when all of it was last asked for.
  readonly #wholes = new Map<string, number>();
  /// Where chats were left (`chat.place`), as told this run or read from the database.
  readonly #places = new Map<string, LeftAt | null>();
  /// The chats whose place cores before kept in the host's storage was looked for this run.
  readonly #oldPlaces = new Set<string>();
  /// Entries told as they were said (an event), by thread: they come in with a motion; the rest is caught up on.
  readonly told = new Map<string, Set<number>>();
  /// What runs for a topic while it is started (a drive folder kept as it is), by topic.
  readonly #samplers = new Map<string, Fiber.Fiber<void, never>>();
  /// Each station's connection sampler, while its `net` or `way` is started (which of the two are).
  readonly #sampling = new Map<string, { fiber: Fiber.Fiber<void, never>; by: Set<string> }>();
  /// The stations sampled this run (a reading of each is in its link's memory: its `net`), and how each is reached by
  /// its reading (its `way`).
  readonly #sampled = new Set<string>();
  readonly #ways = new Map<string, unknown>();

  constructor(core: Inner, sync: StationsSync) {
    this.#core = core;
    this.#sync = sync;
    sync.wanted = (address) => this.#wanted(address);
    sync.onChange = (address, what, key) => this.#changed(address, what, key);
    sync.onTold = (address, id, entries) => this.tell(address, id, entries);
    // A screen says the chat that opened it as the viewer's chats have it: those read again, it is said again.
    core.data.onChange((topic) => {
      if (topic.topic === "chatRows" || topic.topic === "*") core.store.invalidateAll((t) => (t.topic === "screens" || t.topic === "screenCard") && (topic.topic === "*" || t.station === topic.station));
    });
    core.data.onLogChange((table, station, id) => {
      const topics = core.store.liveTopics().filter((t) => t.station === station && ((table === "entry" && (t.topic === "thread" || t.topic === "letters") && String(t.thread) === id) || (table === "transcript" && t.topic === "live" && t.key === id)));
      for (const topic of topics) core.store.changed(topic);
    });
  }

  owns(topic: Topic): boolean {
    return STATION_TOPICS.has(topic.topic);
  }

  /// What the station topics shown want of each station's stream: host samples, the sessions shown, the logs shown.
  #wanted(address: string): { host: boolean; live: string[]; logs: [string, number][]; logins: string[] } {
    const topics = this.#core.store.liveTopics().filter((t) => t.station === address);
    return {
      host: topics.some((t) => t.topic === "host"),
      live: topics.filter((t) => t.topic === "live").map((t) => t.key as string),
      logs: topics.filter((t) => t.topic === "jobLog").map((t) => [t.job as string, t.lines as number] as [string, number]),
      logins: [...new Set(topics.filter((t) => t.topic === "machineLoginScreen").map((t) => t.id as string))],
    };
  }

  #changed(address: string, what: string, key?: string): void {
    const store = this.#core.store;
    const of = (pick: (t: Topic) => boolean) => store.invalidateAll((t) => t.station === address && pick(t));
    if (what === "link") {
      of((t) => t.topic === "link" || t.topic === "live" || t.topic === "screens" || t.topic === "screenCard" || t.topic === "drive");
      // 添加 station's list says which of another workspace's stations are online, as their links find them.
      store.invalidateAll((t) => t.topic === "joinable");
    }
    else if (what === "live") of((t) => t.topic === "live" && (key === undefined || t.key === key));
    else if (what === "host") of((t) => t.topic === "host");
    else if (what === "screens") {
      of((t) => t.topic === "screens" || t.topic === "screenCard");
      screensChanged(this.#core, address);
    }
    else if (what === "log" || what === "errors") of((t) => key === undefined || topicKey(t) === key);
    else if (what === "logins") of((t) => t.topic === "machineLogins" || t.topic === "machineLogin");
    else if (what === "loginScreen") of((t) => t.topic === "machineLoginScreen" && (key === undefined || t.id === key));
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
    // What a UI has open (a chat's messages, its agent, a history): ahead of what is kept current around it, and in the
    // room a station's lane keeps for the urgent (scheduler.ts URGENT_ROOM), so a slow read of a list never holds it up.
    const urgent = this.#urgent(topic);
    if (urgent) this.#core.scheduler.prioritize(topicKey(topic), urgent, Priority.focused);
    if (topic.topic === "thread") {
      const id = topic.thread as number;
      // Opened: the most recently used, kept while shown. Let go for room before, or a chat no list has (opened from an
      // old notification's link): the sync brings it.
      const evicted = this.#core.data.opened("entry", station, String(id), true);
      const entries = entriesOf(station, id);
      if (evicted || this.summary(station, id) === null) this.#sync.channels.bring(entries, Priority.shown);
      // Its latest not on the device yet: that page alone, at once. What is before it comes with the station's history,
      // in batches behind (sync.ts #history), or as it is scrolled back to.
      else if (this.#sync.channels.latestMissing(entries)) this.#sync.channels.bring(entries, Priority.shown, "latest");
      this.#moveOldPlace(station, id);
      // Used now: its agents' histories are brought whole, behind the rest (channel-kinds.ts `whole`).
      for (const key of membersOf(this.summary(station, id))) this.#wholeHistory(station, key);
    }
    // Shown: what the sync would bring of it next (its latest page, what came after what is held, a hole) comes first,
    // nothing it would not read anyway; let go for room before, it is the sync's again from now on. A station whose
    // stream does not follow the sessions at work itself is told it on the stream instead (`live` named there).
    if (topic.topic === "live") {
      const evicted = this.#core.data.opened("transcript", station, topic.key as string, true);
      const shown = evicted || this.#sync.link(station)?.followsRunning === true ? this.#sync.channels.bring(transcriptOf(station, topic.key as string), Priority.shown, "latest") : null;
      this.#wholeHistory(station, topic.key as string, shown);
    }
    if (topic.topic === "net" || topic.topic === "way") this.#sampleNet(station, topic.topic);
    // A folder of the drive: kept as it is on the station's disk while shown.
    if (topic.topic === "drive") this.#samplers.set(topicKey(topic), this.#core.runner.fork(this.#sync.driveWatch(station, topic.root as string, topic.path as string)));
    // What still.fail uses of the station's machine: told as the station looks, while shown.
    if (topic.topic === "stationResources") this.#samplers.set(topicKey(topic), this.#core.runner.fork(this.#sync.resourcesWatch(station)));
    this.resume(topic);
    // A job's log: what it is now read once; from then on the station says how it grows, on its stream.
    if (topic.topic === "jobLog") this.#sync.readLog(station, topic.job as string, topic.lines as number);
    if (["host", "live", "jobLog", "machineLoginScreen"].includes(topic.topic)) this.#sync.openEvents(station, false);
  }

  /// Shown, as it starts or again while kept after the last showed it: what is read only while shown is brought up to
  /// date.
  resume(topic: Topic): void {
    const station = topicStation(topic);
    if (station === null) return;
    // What the agents spent, and the archive: read as a page shows them, not with each change while none does.
    if (topic.topic === "stationUsage") this.#sync.usageShown(station);
    if (topic.topic === "archivedRows") this.#sync.archivedShown(station);
    // A folder of the drive: read again each time it is shown (what is held is shown meanwhile); while shown, the station
    // says when something in it changes (sync.ts `driveWatch`).
    if (topic.topic === "drive") this.#sync.driveShown(station, topic.root as string, topic.path as string);
    // What a search finds there: asked once its words settle, while shown (sync.ts `searchShown`).
    if (topic.topic === "stationSearch") this.#sync.searchShown(topic);
    // The agents' memory: read each time it is shown (agents write it as they work), what was read last shown meanwhile.
    if (topic.topic === "memory") this.#sync.memoryShown(station);
    // The programs granted the station's data: read each time shown, then as the station tells.
    if (topic.topic === "outflowGrants") this.#sync.outflowShown(station);
    // What a web link in a message is: read each time its card shows (a pull request's state moves), what was read
    // last shown meanwhile.
    if (topic.topic === "linkPreview") this.#sync.linkPreviewShown(station, topic.url as string);
    // What a file a message names is: read each time its card shows (it is written as agents work), the same.
    if (topic.topic === "filePeek") this.#sync.filePeekShown(station, topic.key as string, topic.path as string, typeof topic.line === "number" ? topic.line : null);
  }

  stop(topic: Topic): void {
    const station = topicStation(topic);
    if (station === null) return;
    const key = topicKey(topic);
    if (topic.topic === "thread") this.#core.data.opened("entry", station, String(topic.thread), false);
    this.#wholes.delete(key);
    if (topic.topic === "live") this.#core.data.opened("transcript", station, topic.key as string, false);
    if (topic.topic === "stationSearch") this.#sync.searchHidden(topic);
    if (topic.topic === "net" || topic.topic === "way") this.#unsampleNet(station, topic.topic);
    this.#core.scheduler.prioritize(key, null);
    this.#windows.delete(key);
    this.#firsts.delete(key);
    const sampler = this.#samplers.get(key);
    if (sampler) {
      this.#core.runner.interrupt(sampler as Fiber.Fiber<unknown, unknown>);
      this.#samplers.delete(key);
    }
    if (["host", "live", "jobLog", "machineLoginScreen"].includes(topic.topic)) this.#sync.openEvents(station, false);
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
        if (!link) return { ok: { state: "offline", message: t("core-views.station.not_listed") } };
        // While catching up on what was missed: how many chats are left to (-1 while that is not known yet).
        return { ok: link.catching === null ? link.state : { ...link.state, catching: link.catching.tallied ? link.catching.behind.size : -1 } };
      case "host": {
        const v = link?.memory.get("host");
        return v === undefined ? undefined : { ok: v };
      }
      case "screens":
        // As the station said them last (kept: there as the app opens again, while it is reached anew); none while it
        // is down.
        return { ok: screensView(this.#core, station, this.#sync.screens(station), link !== undefined && !down(link.state)) };
      case "screenCard": {
        if (typeof topic.screen !== "string" || topic.screen === "") return { err: CoreError.invalid(t("core-misc.params.missing", { field: "screen" })) };
        return { ok: screenCard(this.#core, station, topic.screen, this.#sync.screens(station), link?.state.state === "online") };
      }
      case "jobLog": {
        const v = link?.memory.get(logKey(topic.job as string, topic.lines as number));
        return v === undefined ? undefined : { ok: v };
      }
      case "stationResources":
      case "stationSearch": {
        if (error) return { err: error };
        const v = link?.memory.get(topicKey(topic));
        return v === undefined ? undefined : { ok: v };
      }
      case "net": {
        // As it was last sampled (this run, or before it: kept in the link's memory); null once sampled with none.
        const v = link?.memory.get("net");
        return v !== undefined ? { ok: v } : this.#sampled.has(station) ? { ok: null } : undefined;
      }
      case "way":
        return this.#ways.has(station) ? { ok: this.#ways.get(station) } : undefined;
      case "live":
        return this.#live(topic);
      case "machineLogins":
      case "machineLogin":
        return this.#logins(topic, link);
      case "machineLoginScreen": {
        const held = logins.held(link);
        const screen = link?.memory.get(logins.screenKey(topic.id as string));
        if (screen !== undefined) return { ok: screen };
        return held.supported === null ? undefined : { ok: null };
      }
      case "thread":
        if (error) return { err: error };
        return this.#thread(topic);
      case "letters":
        if (error) return { err: error };
        return this.#letters(topic);
      case "drive":
        // Nothing held (what is goes out first): a station down says so, not a wait until it is back; else why it was
        // not read, once known.
        if (link && down(link.state)) return { err: new CoreError("offline", downWords(link.state, this.#core.views.stationName(station))) };
        return error ? { err: error } : undefined;
      case "memory": {
        // As the station said it last (kept: there as the app opens again), with what the clients show of it; nothing
        // read yet, as `drive`.
        const v = link?.memory.get(MEMORY);
        if (v !== undefined) {
          const shown = structuredClone(v);
          looks.answer("GET", "/memory", shown);
          return { ok: shown };
        }
        if (link && down(link.state)) return { err: new CoreError("offline", downWords(link.state, this.#core.views.stationName(station))) };
        return error ? { err: error } : undefined;
      }
      case "outflowGrants": {
        // As the station said it last (kept), the times in words; nothing read yet, as `memory`.
        const v = link?.memory.get(OUTFLOW);
        if (v !== undefined) {
          const now = this.#core.host.nowMs();
          return { ok: grantsShown(v, now, this.#core.host.utcOffsetMin(now)) };
        }
        if (link && down(link.state)) return { err: new CoreError("offline", downWords(link.state, this.#core.views.stationName(station))) };
        return error ? { err: error } : undefined;
      }
      case "linkPreview":
      case "filePeek": {
        // As the station said it last (kept: there as the app opens again; its times in words: present.ts); nothing read
        // yet, as `memory`.
        const kept = topic.topic === "linkPreview"
          ? linkPreviewKey(topic.url as string)
          : filePeekKey(topic.key as string, topic.path as string, typeof topic.line === "number" ? topic.line : null);
        const v = link?.memory.get(kept);
        if (v !== undefined) return { ok: v };
        if (link && down(link.state)) return { err: new CoreError("offline", downWords(link.state, this.#core.views.stationName(station))) };
        return error ? { err: error } : undefined;
      }
      default:
        // Held: what is held goes out (the store reads it); with nothing held, why not, once known.
        return error ? { err: error } : undefined;
    }
  }

  // ── logins ──

  /// A station's logins (`machineLogins`), or one of them (`machineLogin`), as shown: none while never read.
  #logins(topic: Topic, link: Link | undefined): Value | undefined {
    const station = topic.station as string;
    const held = logins.held(link);
    const now = this.#core.host.nowMs();
    const offset = this.#core.host.utcOffsetMin(now);
    const name = this.#core.views.stationName(station);
    const shown = (l: unknown) => {
      const id = String(get(l, "id"));
      return logins.loginShown(l, station, name, now, offset, this.#sync.relays.listening(station, id), this.#sync.relays.refused(station, id));
    };
    if (topic.topic === "machineLogin") {
      const found = held.logins.find((l) => l.id === topic.id);
      if (found !== undefined) return { ok: shown(found) };
      return held.supported === null ? undefined : { ok: null };
    }
    const ws = station.slice(0, Math.max(0, station.indexOf("/")));
    const role = get(this.#core.data.shared({ topic: "workspace", workspace: ws }), "role");
    const active = (l: unknown) => (typeof get(l, "endedAt") === "number" ? 1 : 0);
    const started = (l: unknown) => (typeof get(l, "startedAt") === "number" ? (get(l, "startedAt") as number) : 0);
    return {
      ok: {
        supported: held.supported !== false,
        loaded: held.supported !== null,
        canLogin: role !== "viewer",
        canRelay: this.#core.host.listen !== undefined,
        logins: [...held.logins].sort((a, b) => active(a) - active(b) || started(b) - started(a)).map(shown),
      },
    };
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
    if (view?.tasks) value.tasks = view.tasks;
    if (view?.plan) value.plan = view.plan;
    if (view) value.activity = this.#sync.activity(value, this.#core.views.stationNames(ofAddress(station)));
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
      // Read now unless held, while its station is reached (else what is held is all there is).
      if (this.#sync.link(station) && this.#sync.reachable(station)) yield* this.#sync.channels.older(transcriptOf(station, key), before, { quiet: false });
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
  /// A session used now: its history brought whole in the background, down to its first entry, as the sync keeps it so
  /// while it is used lately (a station whose stream follows its sessions at work: it says how far each goes).
  /// `after`: what is shown of it is brought first (one task a channel: asked for while that one waits, this would be it).
  #wholeHistory(station: string, key: string, after: Deferred.Deferred<void, CoreError> | null = null): void {
    if (this.#sync.link(station)?.followsRunning !== true) return;
    const whole = () => void this.#sync.channels.bring(transcriptOf(station, key), Priority.background, "whole");
    if (after === null) whole();
    else this.#core.runner.fork(Effect.ignore(Deferred.await(after)).pipe(Effect.andThen(Effect.sync(whole))));
  }

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
        { log: "Unhandled", message: "former place moved" },
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
          // Not all on the device yet: brought. What is held of it opens it now, what is not joining it as it comes: from
          // where it opens, or, that not held (what came since it was read, the app away meanwhile), from what is held
          // just before it, with what runs unbroken before that. Only with nothing of it held up to there does it wait.
          this.#core.runner.fork(Effect.ignore(this.#sync.ask(station, `range/${id}/${from}`, this.#sync.channels.range(entriesOf(station, id), from, to, { quiet: false })), { log: "Unhandled", message: "range read" }));
          const held = data.logRange("entry", station, String(id), from, to);
          first = at;
          while (first >= from && !held.has(first)) first--;
          if (first < from) return undefined;
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

  /// What two chats' agents wrote each other in a chat (`letters`): all of its entries held, from its first; those not
  /// held yet asked for once each time it goes further (a chat's page holds only a window of it). `whole` once all are
  /// here.
  #letters(topic: Topic): Value | undefined {
    const station = topic.station as string;
    const id = topic.thread as number;
    const data = this.#core.data;
    if (this.summary(station, id) === null) return undefined;
    const latest = this.#latest(station, id);
    const held = data.logRange("entry", station, String(id), 1, latest);
    const tk = topicKey(topic);
    if (held.size < latest && (this.#wholes.get(tk) ?? 0) < latest) {
      this.#wholes.set(tk, latest);
      this.#core.runner.fork(Effect.ignore(this.#sync.ask(station, `range/${id}/1`, this.#sync.channels.range(entriesOf(station, id), 1, latest, { quiet: false })), { log: "Unhandled", message: "range read" }));
    }
    const entries = [...held.keys()].sort((a, b) => a - b).map((n) => held.get(n));
    return { ok: { entries, whole: held.size >= latest, thread: this.summary(station, id) } };
  }

  /// Where a window kept from entry `from` on toward `to` (either way) ends to hold WINDOW of what its chat shows (its
  /// messages, not what agents wrote each other nor edits: views.ts `#chat`), the last entry it keeps; null when all of
  /// it fits. Counted by entries, a chat that is mostly letters showed less than a screen of a whole window: its page
  /// before then dropped what was in view at its end, which asked for the page after, which dropped the start, on and on.
  #shownTo(station: string, id: number, from: number, to: number): number | null {
    const keys = new Set(members(this.summary(station, id)));
    const held = this.#core.data.logRange("entry", station, String(id), Math.min(from, to), Math.max(from, to));
    const step = to >= from ? 1 : -1;
    let shown = 0;
    for (let n = from; n !== to + step; n += step) {
      const e = held.get(n);
      if (!isObject(e) || e.kind !== "message" || isLetter(e, keys)) continue;
      if (++shown > WINDOW) return n - step;
    }
    return null;
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
      yield* this.#sync.channels.older(entriesOf(station, id), before, { quiet: false });
      const held = this.#core.data.logRange("entry", station, String(id), Math.max(1, before - PAGE), before - 1);
      let first = before;
      while (first > Math.max(1, before - PAGE) && held.has(first - 1)) first--;
      if (first === before) return false;
      window.first = first;
      // What shows past WINDOW goes at the other end: the window is short of its end from then on.
      const end = this.#shownTo(station, id, first, window.last ?? this.#latest(station, id));
      if (end !== null) window.last = end;
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
      yield* this.#sync.channels.range(entriesOf(station, id), after + 1, to, { quiet: false });
      const held = this.#core.data.logRange("entry", station, String(id), after + 1, to);
      let last = after;
      while (last < to && held.has(last + 1)) last++;
      window.last = last >= latest ? null : last;
      window.caught = Math.max(window.caught, last);
      // What shows before WINDOW of it goes at its start.
      const start = this.#shownTo(station, id, last, window.first);
      if (start !== null) window.first = start;
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
      yield* this.#sync.channels.range(entriesOf(station, id), Math.max(1, latest - PAGE + 1), latest, { quiet: false });
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

  /// The window of a chat about its entry `seq` (`chat.around`: a message found in it, to be shown): a page before it
  /// and one after, read now where not held. The chat's list goes to it by itself (the UI's to do).
  around(station: string, id: number, seq: number): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const found = this.#window(station, id);
      const latest = this.#latest(station, id);
      if (!found || seq < 1 || seq > latest) return;
      const window = found[1];
      // Already in it, and not at its edge: left as it is (what is around it is on the page).
      const end = window.last ?? latest;
      if (seq >= window.first && seq <= end && (seq - window.first >= AROUND || window.first === 1) && (end - seq >= AROUND || window.last === null)) return;
      const from = Math.max(seq - PAGE, 1);
      const to = Math.min(seq + PAGE - 1, latest);
      yield* this.#sync.channels.range(entriesOf(station, id), from, to, { quiet: false });
      const held = this.#core.data.logRange("entry", station, String(id), from, to);
      if (!held.has(seq)) return;
      let first = seq;
      while (first > from && held.has(first - 1)) first--;
      let last = seq;
      while (last < to && held.has(last + 1)) last++;
      window.first = first;
      window.last = last >= latest ? null : last;
      window.at = null;
      window.atOffset = null;
      window.caught = Math.max(window.caught, last);
      this.#core.store.invalidate({ topic: "thread", station, thread: id });
    });
  }

  /// The messages of a chat that have every word of `query` (`chat.find`), oldest first, each with how many times the
  /// words are in its text; and whether all the chat was looked in (`whole`: all of it is on the device), with how
  /// many of its entries were (`held` of `of`). `bring`: what is not on the device is read first, while its station
  /// answers.
  find(station: string, id: number, query: string, bring: boolean): Effect.Effect<{ words: string[]; hits: { seq: number; count: number }[]; held: number; of: number; whole: boolean }, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const channel = entriesOf(station, id);
      const data = this.#core.data;
      const whole = () => !data.evicted("entry", station, String(id)) && this.#sync.channels.next(channel) === null;
      if (bring && this.#sync.link(station) && this.#sync.reachable(station)) {
        for (let read = this.#sync.channels.next(channel); read !== null; read = this.#sync.channels.next(channel)) {
          const came = yield* Effect.result(this.#sync.channels.read(channel, read, { quiet: true }));
          if (came._tag === "Failure" || came.success === 0) break;
        }
      }
      const words = terms(query);
      const hits = data.findInThread(station, id, words).map(({ seq, text }) => {
        const lower = text.toLowerCase();
        let count = 0;
        for (const w of words) for (let i = lower.indexOf(w); i >= 0; i = lower.indexOf(w, i + w.length)) count++;
        return { seq, count };
      });
      return { words, hits, held: data.logSpan("entry", station, String(id))?.count ?? 0, of: this.#latest(station, id), whole: whole() };
    });
  }

  /// Whether a thread topic's window reaches its end.
  atEnd(station: string, id: number): boolean {
    return this.#window(station, id)?.[1].last === null;
  }

  // ── a station's connection, sampled while shown ──

  /// Samples the station's connection for its `net` (every figure) or its `way` (how it is reached), one sampler for
  /// both: `way` goes out only when that changes, so what shows only how a station is reached (the stations' list) is
  /// not put out again with each reading.
  #sampleNet(station: string, by: string): void {
    const running = this.#sampling.get(station);
    if (running) {
      running.by.add(by);
      return;
    }
    const core = this.#core;
    const net: Topic = { topic: "net", station };
    const way: Topic = { topic: "way", station };
    let last: [number, NonNullable<ReturnType<NonNullable<StationsSync["wire"]["net"]>>>] | null = null;
    let samples: unknown[] = [];
    const sample = Effect.sync(() => {
      const link = this.#sync.link(station);
      const reading = link ? (this.#sync.wire.net?.(link.addr) ?? null) : null;
      const now = core.host.nowMs();
      const was = link?.memory.get("net") ?? null;
      let value: unknown = null;
      if (reading === null) {
        // No connection now (coming back, or the app just opened): how it went last is kept, the station's card saying
        // it is reconnecting.
        last = null;
        samples = [];
        value = was;
      } else {
        const since = last !== null && reading.rxBytes >= last[1].rxBytes && reading.txBytes >= last[1].txBytes ? last : null;
        if (since) {
          const secs = Math.max((now - since[0]) / 1000, 0.001);
          samples.push({ at: Math.round(now), rttMs: reading.rttMs, rxBps: Math.round((reading.rxBytes - since[1].rxBytes) / secs), txBps: Math.round((reading.txBytes - since[1].txBytes) / secs), ...packetsSince(since[1].packets, reading.packets) });
        } else samples = [];
        while (samples.length > NET_KEPT) samples.shift();
        const measured = reading.measured ? { measuring: reading.measured.measuring, relays: reading.measured.relays.map(([relay, ms]) => ({ relay, rttMs: ms })), moved: reading.measured.moved } : null;
        value = { path: reading.path, relay: reading.relay, rttMs: reading.rttMs, rxBytes: reading.rxBytes, txBytes: reading.txBytes, samples: [...samples], measured, todayRxBytes: reading.today?.[0] ?? null, todayTxBytes: reading.today?.[1] ?? null, lan: reading.lan ?? [] };
        last = [now, reading];
      }
      if (!this.#sampled.has(station) || !equal(was, value)) {
        this.#sampled.add(station);
        if (link && value !== null) link.memory.set("net", value);
        core.store.invalidate(net);
      }
      // How it is reached: what changes seldom, apart from its figures.
      const reached = isObject(value) ? { path: value.path ?? null, relay: value.relay ?? null } : null;
      if (!this.#ways.has(station) || !equal(this.#ways.get(station), reached)) {
        this.#ways.set(station, reached);
        core.store.invalidate(way);
      }
    });
    // A measurement shown on screen: sampled while it is shown, the last reading kept to show from as the app opens
    // again (the station's card dimmed while it is reached anew). Not while the app is out of view: a phone
    // in a pocket samples nothing (it was most of what the core did there, 2026-10-19).
    const inView = Effect.suspend(() => core.attention?.attend.untilShown() ?? Effect.void);
    const fiber = core.runner.fork(Effect.forever(Effect.andThen(inView, Effect.andThen(sample, laterSleep(NET_EVERY_MS)))));
    this.#sampling.set(station, { fiber, by: new Set([by]) });
  }

  /// The station's `net` or `way` stopped: its sampler goes once neither is started.
  #unsampleNet(station: string, by: string): void {
    const running = this.#sampling.get(station);
    if (!running) return;
    running.by.delete(by);
    if (running.by.size > 0) return;
    this.#core.runner.interrupt(running.fiber as Fiber.Fiber<unknown, unknown>);
    this.#sampling.delete(station);
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
