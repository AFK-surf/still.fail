// What the core keeps in sync with the stations, by itself, whatever the UI shows (docs/core-ts.md, rule 6; station.rs
// and sync.rs for what a station says and how). Every station of every workspace an account reaches has a link
// (link.ts): its events stream, held open while the station is reached. What a station holds is of two sorts, kept in
// sync each its own way:
//
// - what is only added to (a thread's entries, a session's transcript): channels (channels/channels.ts, a part of its
//   own). The stream says what is added (`thread`, `live`), and what the device lacks of one it reads by number: where
//   it is in a channel is the numbers it holds. Nothing of it depends on a stream having told all there was.
// - what changes (the lists and their rows, a thread's summary, the overview, jobs, how far one has read): only how it
//   is now matters. The stream says how it is as it changes; one that comes back is told first how what changed
//   meanwhile is now (from where the device is in the station's log of events, cursor.ts), and where that cannot be
//   told the station is read again (`snapshot`: the lists, as what changed of them where some is held). That is here,
//   with what a write brings up to date.
//
// Then the rest is brought onto the device in the background, the most urgent first (`#history`): every session's
// detail, and every channel. The UI makes some of it more urgent (`prioritize`), never more or less.
import { Deferred, Effect, Exit, Scope } from "effect";
import type { Inner } from "../core.ts";
import { join } from "../data.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { encode, type Effect as OpEffect, type Request } from "../ops.ts";
import { topicKey, type Topic } from "../protocol.ts";
import { Kind, type SpanContext } from "../trace.ts";
import { equal, get, isObject, parseJson } from "../util.ts";
import { Priority } from "../sync/scheduler.ts";
import { activity as historyActivity } from "../history.ts";
import { StationAddr } from "./addr.ts";
import { IDEMPOTENCY_KEY, READS, Requests, httpError } from "./requests.ts";
import { digest } from "../digest.ts";
import { type Channel, Channels } from "../channels/channels.ts";
import { ENTRIES, PAGE, TRANSCRIPT, TRANSCRIPT_PAGE, entriesOf, heldIn, transcriptOf } from "./channel-kinds.ts";
import { type HistoryRead, type Link, Links, type LiveView, MEMORY, OUTFLOW, filePeekKey, linkPreviewKey, logKey } from "./link.ts";
import { readAll, replyHeader, type StationWire } from "./wire.ts";
import { SseParser } from "./sse.ts";
import * as logins from "./machine-logins.ts";
import { Relays } from "./machine-logins.ts";
import { Retold } from "./retold.ts";

export { HOST_KEY, LINK_KEY, LONG_MISSES, MISSES, OFFLINE_RETRY_MS, RECONNECT_MAX_MS, RECONNECT_MS, STREAM_IDLE_MS, STREAM_QUIET_MS, Link } from "./link.ts";
export type { EventsFor, LiveView } from "./link.ts";

/// A burst of `thread` events becomes one read of each thread's summary.
export const EVENTS_COALESCE_MS = 400;
export { PAGE, TRANSCRIPT_PAGE };
export const RECHECK_MS = 5 * 60 * 1000;
/// A read that failed in passing (a 5xx, the link dropping) is tried again after this, doubling, this many times.
export const READ_RETRY_MS = 2_000;
export const READ_RETRIES = 5;
/// The field naming a row of each list read whole that may be asked as what changed of it (POST /changed/<list>).
const LIST_ID: Record<string, string> = { chatRows: "id", archivedRows: "id", threads: "id", sessions: "key" };
/// A station from before POST /changed/<list> reads its lists whole, and is tried again after this.
export const CHANGES_RETRY_MS = 3_600_000;
/// How much of a station's history one batch asks (POST /batch, #history): a page of entries or a session's detail is
/// one, a page of a transcript (200 steps in brief) five (each channel's kind says, channel-kinds.ts).
export const HISTORY_BATCH = 40;

export const RECHECKING = "等它回来确认";
/// The station's events that change what a search of it finds.
const SEARCHED = new Set(["session", "session-removed", "thread", "thread-removed", "chat", "chat-removed", "job", "job-removed"]);
/// The station's events that say what its reads bring too: told again on top of what a read asked before them brought
/// (retold.ts).
const RETOLD = new Set(["session", "session-removed", "thread-view", "thread-removed", "read", "chat", "chat-removed", "job", "job-removed", "overview", "footprint"]);
/// How long the words of a search stay as they are before the stations are asked what they find.
export const SEARCH_SETTLE_MS = 150;
/// A station's changes ask the searches of it shown again at most this often: a busy station tells of its chats many
/// times a second, each search asked again a search of the machine's files there (docs/search.md).
export const SEARCH_STALE_MS = 2_000;
/// How often a shown resources page asks a station from before telling them again (the station, asked, looks as often
/// itself); and how long one that tells them is waited on after its last before the stream is taken for gone.
export const RESOURCES_EVERY_MS = 5_000;
const RESOURCES_SILENT_MS = 4 * RESOURCES_EVERY_MS;

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
/// A row's id as text (sessions' and chats' are strings, threads' numbers).
const idText = (v: unknown): string | null => (typeof v === "string" ? v : typeof v === "number" ? String(v) : null);

/// One `step` event, as useLiveSession applies it.
export function applyStep(view: LiveView, event: unknown, now: number): void {
  const kind = str(get(event, "kind")) ?? "";
  const id = get(event, "id") ?? null;
  if (kind === "phase") view.phase = { phase: get(event, "phase") ?? null, since: Math.round(now) };
  else if (kind === "start") {
    const before = view.steps.find((s) => equal(get(s, "id"), id));
    const startedAt = get(before, "startedAt");
    view.steps = view.steps.filter((s) => !equal(get(s, "id"), id));
    const input = get(event, "input");
    const step: Record<string, unknown> = { id, step: get(event, "step") ?? null, input: typeof input === "string" ? input : "", startedAt: typeof startedAt === "number" ? startedAt : Math.round(now) };
    const tool = get(event, "tool");
    if (typeof tool === "string" && tool !== "") step.tool = tool;
    if (get(event, "subagent") === true) step.subagent = true;
    const parent = get(event, "parent");
    if (typeof parent === "string" && parent !== "") step.parent = parent;
    view.steps.push(step);
  } else if (kind === "end") {
    // On new steps: the ones there are in the live topic's value as it was made (shared, docs/core-ts.md).
    view.steps = view.steps.map((s) => (equal(get(s, "id"), id) && isObject(s) ? { ...s, ended: true } : s));
  }
}

/// How long a folder's watch waits before asking again, the station not reached or its asking failed.
const WATCH_AGAIN_MS = 5_000;

export class StationsSync {
  readonly #core: Inner;
  readonly requests: Requests;
  /// What its stations hold that is only added to (threads' entries, sessions' transcripts), kept in sync by number.
  readonly channels: Channels;
  /// Its stations' links: their streams, opened and tried again (link.ts).
  readonly #links: Links;
  /// What their streams told while a read was out, to tell again on top of what it brings.
  readonly #retold = new Retold();
  /// The stations whose searches shown are to be asked again once SEARCH_STALE_MS is up.
  readonly #staleSearches = new Set<string>();
  /// What the station topics want of a stream beyond what the sync wants (host samples, logs, sessions shown).
  wanted: (address: string) => { host: boolean; live: string[]; logs: [string, number][]; logins?: string[] } = () => ({ host: false, live: [], logs: [] });
  /// Told when what a station holds beyond the records changed (link, live views, host, logs).
  onChange: (address: string, what: "link" | "live" | "host" | "log" | "errors" | "screens" | "logins" | "loginScreen", key?: string) => void = () => {};
  /// The loopback relays of logins this device takes the callback of (docs/remote-login.md).
  readonly relays: Relays;
  /// Told of entries that came as they were said (an event): they come in with a motion.
  onTold: (address: string, id: number, entries: unknown[]) => void = () => {};
  /// What other parts read of a station whenever it is read again (its stream opened afresh), each a task of its own
  /// (the vault's: views/vault.ts); and hear of its events they know.
  readonly also: { read(address: string): Effect.Effect<void, CoreError>; event(address: string, name: string, data: unknown): void }[] = [];

  constructor(core: Inner, wire: StationWire) {
    this.#core = core;
    this.requests = new Requests(core, wire);
    this.#links = new Links(core, this.requests, {
      wanted: (address) => this.wanted(address),
      afresh: (address, ctx) => this.snapshot(address, ctx),
      goesOn: (address, how) => this.#goesOn(address, how),
      event: (address, name, raw) => this.onEvent(address, name, raw),
      toldMissed: (address) => this.#tally(address),
      changed: (address, what) => this.onChange(address, what),
      gone: (address) => this.channels.forget(address),
    });
    // A thread caught up on brought its latest: one less to catch up on.
    core.data.onLogChange((table, station, id) => {
      if (table === "entry") this.#caughtUp(station, Number(id));
    });
    // Nothing left to bring of a station: what is still behind is not coming now (read again later, as the sync goes).
    core.scheduler.onIdle = (lane) => this.#lull(lane);
    this.requests.onAnswered = (station) => this.#links.answered(station.toString());
    this.relays = new Relays(core);
    this.relays.onChange = (station) => this.onChange(station, "logins");
    this.channels = new Channels(heldIn(core.data, (station) => this.#links.get(station)?.followsRunning === true), {
      read: (station, path, options) => Effect.suspend(() => this.requests.call(this.#links.get(station)?.addr ?? StationAddr.parse(station), "GET", path, null, options)),
      reached: (station) => this.#links.has(station) && this.reachable(station),
      enqueue: (station, task, priority, work) => this.#enqueue(station, task, priority, work),
      later: (station, work) => {
        const link = this.#links.get(station);
        if (link) core.runner.fork(Effect.sleep(EVENTS_COALESCE_MS).pipe(Effect.andThen(Effect.sync(work))), link.scoped);
        else work();
      },
      answered: (channel, error, nothing) => this.#channelAnswered(channel, error, nothing),
    });
  }

  get wire(): StationWire {
    return this.requests.wire;
  }

  // ── its links ──

  link(address: string): Link | undefined {
    return this.#links.get(address);
  }

  /// Whether the station is worth asking now: not while its link has found it down.
  reachable(address: string): boolean {
    return this.#links.reachable(address);
  }

  /// Whether its link is up now (link.ts `online`).
  online(address: string): boolean {
    return this.#links.online(address);
  }

  /// Every station of every workspace an account reaches is linked, those no longer listed let go (link.ts).
  reconcile(): void {
    this.#links.reconcile();
  }

  /// still.fail cloud says the station came online: one waiting to reconnect tries now.
  cameOnline(address: string): void {
    this.#links.cameOnline(address);
  }

  /// still.fail cloud is reached again after it was not: the device's network is back, and every station waiting to
  /// reconnect tries now.
  networkBack(): void {
    this.#links.networkBack();
  }

  /// Why each station down is not reached is said anew (link.ts `recause`).
  recause(): void {
    this.#links.recause();
  }

  /// Opens the station's stream for what it is wanted for now, unless the one open gives that (or `anew`).
  openEvents(address: string, anew: boolean): void {
    this.#links.openEvents(address, anew);
  }

  /// A stream opened going on from where the device was in its station's events: nothing is read again but the
  /// channels a UI shows where the stream was away, asked what came after what is held of them (what is shown does not
  /// hang on all of it having been told). Taken up from where a core before this one was, the station's history is
  /// swept as a reading of everything would.
  #goesOn(address: string, how: { away: boolean; restored: boolean }): void {
    if (how.away || how.restored) this.#catchingFrom(address);
    if (how.away) this.#catchUpShown(address);
    // Its screens and its logins are held in its link's memory, not its log of events (what was kept of them shows
    // meanwhile): its screens read again whenever the stream was not there to hear them change, both once a run.
    const memory = this.#links.get(address)?.memory;
    if (how.away || how.restored || memory?.fresh("screens") !== true) this.#enqueue(address, "screens", Priority.background, this.#screens(address));
    if (memory?.fresh(logins.HELD) !== true) this.#enqueue(address, "machineLogins", Priority.background, this.#machineLogins(address));
    if (how.restored) this.#historyStart(address);
  }

  // ── reading what a station holds ──

  /// Everything the station holds, read again (its stream opened): the lists, then what they name. One span
  /// (`station.read`, under `parent` where given) has each read under it, and ends once they all have.
  snapshot(address: string, parent: SpanContext | null = null): void {
    const p = Priority.shown;
    const span = this.#core.tracer.span("station.read", Kind.Internal, parent);
    span.set("stillfail.station", address);
    const ctx = span.context;
    // Where the device is in the station's events is written down again once all of this is read (cursor.ts).
    const link = this.#links.get(address);
    if (link) {
      link.cursor.reading();
      this.#core.data.forgetRecord("heard", address);
    }
    this.#catchingFrom(address);
    const unread = () => link?.cursor.unread();
    const read = (topic: Topic, path: string) => this.#read(address, topic, path, undefined, ctx, 0, unread);
    // The chats a UI has open, first: what was said in them after what is held, in the room kept for what is open. The
    // lists and the history behind them take a slow link a minute, and what an agent said while the stream was away
    // waited on them.
    this.#catchUpShown(address);
    const done = [
      this.#enqueue(address, "overview", p, read({ topic: "overview", station: address }, "/overview")),
      this.#enqueue(address, "sessions", p, Effect.andThen(read({ topic: "sessions", station: address }, "/sessions"), Effect.sync(() => this.#historyStart(address)))),
      this.#enqueue(address, "threads", p, Effect.andThen(read({ topic: "threads", station: address }, "/threads"), Effect.sync(() => this.#historyStart(address)))),
      this.#enqueue(address, "chats", p, Effect.andThen(read({ topic: "chatRows", station: address }, "/chats"), Effect.sync(() => this.openEvents(address, false)))),
      ...this.#archivedChanged(address, ctx),
      this.#enqueue(address, "jobs", p, read({ topic: "jobs", station: address }, "/jobs")),
      this.#enqueue(address, "footprint", Priority.background, read({ topic: "footprint", station: address }, "/footprint")),
      this.#enqueue(address, "screens", Priority.background, this.#screens(address, ctx)),
      this.#enqueue(address, "machineLogins", Priority.background, this.#machineLogins(address, ctx)),
      ...this.#usageChanged(address, ctx),
      ...this.#slackConnects(address).map((id) => this.#enqueue(address, `slackApp/${id}`, Priority.background, read({ topic: "slackApp", station: address, connect: id }, `/connects/${encode(id)}/slack-app`))),
      ...this.also.map((part, i) => this.#enqueue(address, `also/${i}`, Priority.background, part.read(address))),
    ];
    // All read (what the events keep current: the lists' reads say where they could not be), where the device is.
    const kept = Effect.sync(() => {
      const keep = link?.cursor.read() ?? null;
      if (keep !== null && this.#links.get(address) === link) this.#core.data.put("heard", address, keep);
      if (link?.cursor.busy === false && this.#links.get(address) === link) this.#tally(address);
    });
    this.#core.runner.fork(Effect.ensuring(Effect.andThen(Effect.ignore(Effect.all(done.map((d) => Deferred.await(d)), { mode: "result" })), kept), Effect.sync(() => span.end())));
  }

  // ── catching up ──

  /// The station's stream opened after the device was away from it (read afresh, or going on from where it was): what
  /// changed meanwhile is being caught up on, not yet known (link.ts `catching`).
  #catchingFrom(address: string): void {
    const link = this.#links.get(address);
    if (!link) return;
    link.catching = { tallied: false, behind: new Set() };
    this.onChange(address, "link");
  }

  /// What was missed is known (the station read, or what a stream that went on was told first): the threads it left
  /// behind, each until its latest is on the device. None: caught up.
  #tally(address: string): void {
    const link = this.#links.get(address);
    if (!link?.catching || link.catching.tallied) return;
    const data = this.#core.data;
    const behind = data.threadsBehind(address).filter((id) => !data.evicted("entry", address, String(id)));
    link.catching = behind.length === 0 || !this.#core.scheduler.busy(address) ? null : { tallied: true, behind: new Set(behind) };
    this.onChange(address, "link");
  }

  /// A station's lane with nothing left to run: done catching up, whatever is still behind.
  #lull(address: string): void {
    const link = this.#links.get(address);
    if (!link?.catching?.tallied) return;
    link.catching = null;
    this.onChange(address, "link");
  }

  /// Whether a thread's summary goes further than what is held of it (and it is to be brought: not let go for room).
  #behind(address: string, id: number): boolean {
    const data = this.#core.data;
    return data.threadLast(address, id) > (data.logSpan("entry", address, String(id))?.max ?? 0) && !data.evicted("entry", address, String(id));
  }

  /// A thread caught up on that has its latest now (or will not have it while catching up: `gone`), let go of.
  #caughtUp(address: string, id: number, gone = false): void {
    const catching = this.#links.get(address)?.catching;
    if (!catching?.tallied || !catching.behind.has(id) || (!gone && this.#behind(address, id))) return;
    catching.behind.delete(id);
    if (catching.behind.size === 0) this.#links.get(address)!.catching = null;
    this.onChange(address, "link");
  }

  /// A push came of a chat (`notice.bring`, `seq` the message it is about): what it says is brought onto the device now,
  /// whether the station's stream is there or not, so its notification opens on what is held. A chat the device does
  /// not hold yet is found in the station's chats; of a station not linked, nothing is read. Done once it is held, or
  /// could not be read.
  bringPushed(address: string, session: string, seq: number | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const bound = () => {
        const thread = get(this.#core.data.chatOfSession(address, session), "thread");
        return typeof thread === "number" ? thread : this.#core.data.threadOf(address, session);
      };
      let thread = bound();
      if (thread === null) {
        yield* this.ask(address, "chats", this.#read(address, { topic: "chatRows", station: address }, "/chats"));
        thread = bound();
      }
      if (thread !== null) yield* this.channels.pushed(entriesOf(address, thread), seq, Priority.focused);
    });
  }

  /// The station's stream was away: the threads a UI shows are asked what was said in them after what is held, and the
  /// drive's folders shown are read again (one never read while the station was down is read now).
  #catchUpShown(address: string): void {
    for (const topic of this.#core.store.liveTopics()) {
      if (topic.station !== address) continue;
      if (topic.topic === "thread" && typeof topic.thread === "number") this.channels.catchUp(entriesOf(address, topic.thread), Priority.shown);
      else if (topic.topic === "drive" && this.#core.store.inUse(topic)) this.driveShown(address, String(topic.root), String(topic.path));
    }
  }

  /// The station's screens as it has them now (docs/remote-screens.md), in its link's memory (kept: what was said last
  /// shows as the app opens again, until they are read). A station from before screens has none (404): it is held so,
  /// and said (`outdated`).
  #screens(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/screens", null, { quiet: true, ctx }));
      if (answer._tag === "Success") this.#heldScreens(address, { screens: Array.isArray(get(answer.success, "screens")) ? (get(answer.success, "screens") as unknown[]) : [], outdated: false });
      else if (answer.failure.status === 404) this.#heldScreens(address, { screens: [], outdated: true });
      else return yield* Effect.fail(answer.failure);
    });
  }

  #heldScreens(address: string, held: { screens: unknown[]; outdated: boolean }): void {
    const link = this.#links.get(address);
    if (!link) return;
    link.memory.set("screens", held);
    this.onChange(address, "screens");
  }

  /// What is held of the station's screens; undefined while it has not said.
  screens(address: string): { screens: unknown[]; outdated: boolean } | undefined {
    return this.#links.get(address)?.memory.get("screens") as { screens: unknown[]; outdated: boolean } | undefined;
  }

  /// The station's screens read now, for a person waiting on them (a view of one opened before they were known).
  readScreens(address: string): Effect.Effect<void, CoreError> {
    return this.ask(address, "screens", this.#screens(address));
  }

  /// The agents' memory on the station (GET /memory, the `memory` topic), read as a page shows it: each time, as agents
  /// write it while they work and nothing on the stream says so; what was read last (kept in the link's memory) shows
  /// meanwhile. Not read, why: once nothing is held.
  memoryShown(address: string): void {
    this.#enqueue(address, "memory", Priority.shown, this.#memory(address));
  }

  #memory(address: string): Effect.Effect<void, CoreError> {
    const key = topicKey({ topic: "memory", station: address });
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/memory", null, { quiet: true }));
      if (answer._tag === "Success") {
        link.errors.delete(key);
        link.memory.set(MEMORY, answer.success);
        this.onChange(address, "log", key);
      } else if (answer.failure.status !== undefined && !link.memory.has(MEMORY)) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    });
  }

  /// The programs granted the station's data (GET /outflow/grants, the `outflowGrants` topic, docs/data-outflow.md),
  /// read each time a page shows them; then as the station tells (`outflow-grants`). A station from before: none.
  outflowShown(address: string): void {
    this.#enqueue(address, "outflowGrants", Priority.shown, this.#outflow(address));
  }

  #outflow(address: string): Effect.Effect<void, CoreError> {
    const key = topicKey({ topic: "outflowGrants", station: address });
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/outflow/grants", null, { quiet: true }));
      if (answer._tag === "Success") {
        link.errors.delete(key);
        link.memory.set(OUTFLOW, answer.success);
        this.onChange(address, "log", key);
      } else if (answer.failure.status === 404) {
        link.errors.delete(key);
        link.memory.set(OUTFLOW, { unsupported: true });
        this.onChange(address, "log", key);
      } else if (answer.failure.status !== undefined && !link.memory.has(OUTFLOW)) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    });
  }

  /// What a web link in a message is (GET /link-preview, the `linkPreview` topic), read as its card shows it (cardShown).
  linkPreviewShown(address: string, url: string): void {
    this.#cardShown(address, { topic: "linkPreview", station: address, url }, `/link-preview?url=${encode(url)}`, linkPreviewKey(url));
  }

  /// What a file a message names by its path is (GET /sessions/:key/peek, the `filePeek` topic: a few of its lines, a
  /// thumbnail, a directory's entries), read under the session `key`'s working directory as its card shows it (cardShown).
  filePeekShown(address: string, key: string, path: string, line: number | null): void {
    const topic: Topic = { topic: "filePeek", station: address, key, path, ...(line !== null ? { line } : {}) };
    const at = `/sessions/${encode(key)}/peek?path=${encode(path)}${line !== null ? `&line=${line}` : ""}`;
    this.#cardShown(address, topic, at, filePeekKey(key, path, line));
  }

  /// What a link in a message is, for its card (`topic`, the station's `path`), read each time the card shows it (a pull
  /// request's state moves, a file is written; the station keeps what it found a while, so it answers at once), what was
  /// read last kept in the link's memory (`kept`, the latest few of its kind) and shown meanwhile.
  #cardShown(address: string, topic: Topic, path: string, kept: string): void {
    const key = topicKey(topic);
    this.#enqueue(address, key, Priority.shown, Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", path, null, { quiet: true }));
      if (answer._tag === "Success") {
        link.errors.delete(key);
        link.memory.set(kept, answer.success);
        this.onChange(address, "log", key);
      } else if (answer.failure.status !== undefined && !link.memory.has(kept)) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    }));
  }

  /// A job's log as it is now (its `lines` last lines), once a run: its topic opened (what was kept of it shows
  /// meanwhile). The station's stream says how it grows from then on (an older station's does not: its log is as it was
  /// when opened, docs/core-ts.md).
  readLog(address: string, job: string, lines: number): void {
    const key = logKey(job, lines);
    if (this.#links.get(address)?.memory.fresh(key)) return;
    this.#enqueue(
      address,
      `log/${job}/${lines}`,
      Priority.shown,
      Effect.gen({ self: this }, function* () {
        const link = this.#links.get(address);
        if (!link || !this.reachable(address)) return;
        const answer = yield* this.requests.call(link.addr, "GET", `/jobs/${encode(job)}/log?lines=${lines}`, null, { quiet: true });
        link.followsLogs = get(answer, "follows") === true;
        // What the stream said meanwhile is newer.
        if (!link.memory.fresh(key)) {
          link.memory.set(key, { text: get(answer, "text") ?? "", outputAt: get(answer, "outputAt") ?? null });
          this.onChange(address, "log", topicKey({ topic: "jobLog", station: address, job, lines }));
        }
      }),
    );
  }

  /// What a search finds on the station (`stationSearch`, docs/search.md): asked a moment after the words stop changing
  /// (one shown that long), at the urgency of what is shown, and again as it is shown again; held in memory while
  /// shown, the station's answer as it came. A station from before search answers 404: said so (its `err`), and it is not asked again while shown.
  /// `again`: asked again as the station's chats changed (said to it: `again=1`, answered as found lately).
  searchShown(topic: Topic, again = false): void {
    const address = topic.station as string;
    const key = topicKey(topic);
    const link = this.#links.get(address);
    // Asked again each time it is shown (what was found before shown meanwhile): what a station holds changes.
    const refused = link?.errors.get(key);
    if (!link || (refused && (refused.status ?? 500) < 500)) return;
    this.#core.runner.fork(
      Effect.sleep(SEARCH_SETTLE_MS).pipe(
        Effect.andThen(
          Effect.sync(() => {
            if (this.#core.views.searchShownNow(topic)) this.#enqueue(address, `search/${key}`, Priority.shown, this.#search(topic, again));
          }),
        ),
      ),
    );
  }

  #search(topic: Topic, again: boolean): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const address = topic.station as string;
      const key = topicKey(topic);
      const link = this.#links.get(address);
      if (!link || !this.reachable(address) || !this.#core.views.searchShownNow(topic)) return;
      const params = [`q=${encode(topic.q as string)}`];
      if (typeof topic.kind === "string") params.push(`kinds=${encode(topic.kind)}`);
      if (typeof topic.limit === "number") params.push(`limit=${topic.limit}`);
      if (again) params.push("again=1");
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", `/search?${params.join("&")}`, null, { quiet: true }));
      if (answer._tag === "Success") {
        // (what a search found: asked again each time it is shown, not kept)
        link.memory.hold(key, answer.success);
        this.onChange(address, "log", key);
      } else if (answer.failure.status !== undefined) {
        // Refused (a station from before search), or busy (its index starting: asked again as it is shown again).
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    });
  }

  /// What the station holds changed (a chat said in, archived, removed; a job): the searches of it shown are asked
  /// again (what was found shown meanwhile), the rest let go.
  #searchStale(address: string): void {
    if (this.#staleSearches.has(address)) return;
    this.#staleSearches.add(address);
    this.#core.runner.fork(
      Effect.sleep(SEARCH_STALE_MS).pipe(
        Effect.andThen(
          Effect.sync(() => {
            this.#staleSearches.delete(address);
            this.#askSearchesAgain(address);
          }),
        ),
      ),
    );
  }

  #askSearchesAgain(address: string): void {
    const link = this.#links.get(address);
    if (!link) return;
    for (const key of [...link.memory.keys()]) {
      if (!key.includes('"stationSearch"')) continue;
      const topic = JSON.parse(key) as Topic;
      if (topic.topic !== "stationSearch") continue;
      if (this.#core.views.searchShownNow(topic)) this.searchShown(topic, true);
      else if (!this.#core.store.inUse(topic)) link.memory.delete(key);
    }
  }

  /// A search no longer shown: let go.
  searchHidden(topic: Topic): void {
    const link = this.#links.get(topic.station as string);
    if (!link) return;
    const key = topicKey(topic);
    link.memory.delete(key);
    link.errors.delete(key);
  }

  /// A task of the station's lane; its key is `<address> <what>` (what `prioritize` matches).
  #enqueue(address: string, what: string, priority: number, work: Effect.Effect<void, CoreError>) {
    return this.#core.scheduler.enqueue(address, `${address} ${what}`, priority, work);
  }

  /// Asks for a task and waits on it (a write's after-effects, a call a person waits on).
  ask(address: string, what: string, work: Effect.Effect<void, CoreError>): Effect.Effect<void, CoreError> {
    return this.#core.scheduler.ask(address, `${address} ${what}`, Priority.asked, work);
  }

  #slackConnects(address: string): string[] {
    const overview = this.#core.data.shared({ topic: "overview", station: address });
    return ((get(overview, "connects") as unknown[] | undefined) ?? []).flatMap((c) => {
      const id = str(get(c, "id"));
      return id && (get(c, "kind") === "slack" || get(c, "slack") !== undefined || get(c, "surface") === "slack") ? [id] : [];
    });
  }

  /// Reads one held topic: a 4xx while nothing is held is its error (the topic says so); anything else passes, and
  /// is read again a little later (less and less often, a few times) while the station stays reached.
  /// `unread`: told where it is not read (the station read afresh: cursor.ts).
  #read(address: string, topic: Topic, path: string, shape?: (answer: unknown) => unknown, ctx: SpanContext | null = null, attempt = 0, unread?: () => void): Effect.Effect<void, CoreError> {
    return this.#asked((read) => Effect.gen({ self: this }, function* () {
      if (!this.reachable(address) || !this.#links.has(address)) return unread?.();
      const link = this.#links.get(address)!;
      const answer = yield* Effect.result(shape ? this.requests.call(link.addr, "GET", path, null, { quiet: true, ctx }) : this.#whole(link, topic, path, ctx));
      const key = topicKey(topic);
      if (answer._tag === "Success") {
        link.errors.delete(key);
        this.#core.data.set(topic, shape ? shape(answer.success) : answer.success);
        this.#retell(address, read);
        return;
      }
      // Not answered (a station's no is how it stands, read again or not).
      if (answer.failure.status === undefined || answer.failure.status >= 500) unread?.();
      if (this.#core.data.shared(topic) === undefined && answer.failure.status !== undefined && answer.failure.status >= 400 && answer.failure.status < 500) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      } else if ((answer.failure.status === undefined || answer.failure.status >= 500) && attempt < READ_RETRIES) {
        const again = Effect.sleep(READ_RETRY_MS * 2 ** attempt).pipe(
          Effect.andThen(Effect.sync(() => void this.#enqueue(address, `again/${key}`, Priority.background, this.#read(address, topic, path, shape, null, attempt + 1)))),
        );
        this.#core.runner.fork(again, link.scoped);
      }
    }));
  }

  /// A read of a station's, asked as `work` starts: what it is known by while it is out (retold.ts), for what it brings to
  /// be told again on top of (`#retell`).
  #asked<A, E>(work: (read: number) => Effect.Effect<A, E>): Effect.Effect<A, E> {
    return Effect.suspend(() => {
      const read = this.#retold.asked();
      return work(read).pipe(Effect.ensuring(Effect.sync(() => this.#retold.over(read))));
    });
  }

  /// What `GET path` answers. A list some of which is held is asked as what changed of it (POST /changed/<list>, each
  /// held row's digest sent), and put together from what came and what is held, in the station's order: read again
  /// after a stream that could not be resumed, most of a list is as it is held, and on a slow link it was most of the
  /// wait. A station from before is asked the list whole (and tried again after CHANGES_RETRY_MS).
  #whole(link: Link, topic: Topic, path: string, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
    const whole = this.requests.call(link.addr, "GET", path, null, { quiet: true, ctx });
    const id = LIST_ID[topic.topic];
    const refused = link.changesRefused !== null && this.#core.host.nowMs() - link.changesRefused < CHANGES_RETRY_MS;
    const held = id === undefined || refused ? undefined : this.#core.data.shared(topic);
    if (id === undefined || !Array.isArray(held) || held.length === 0) return whole;
    const rows = new Map<string, unknown>();
    const digests: Record<string, string> = {};
    for (const row of held) {
      const key = idText(get(row, id));
      if (key === null) continue;
      rows.set(key, row);
      digests[key] = digest(row);
    }
    return Effect.gen({ self: this }, function* () {
      const asked = yield* Effect.result(this.requests.call(link.addr, "POST", `/changed${path}`, { held: digests }, { quiet: true, ctx, headers: [[READS, "1"]] }));
      if (asked._tag === "Failure") {
        // Not answered: failed as a read is. Answered no (a station from before has no such route): read whole.
        if (asked.failure.status === undefined) return yield* Effect.fail(asked.failure);
        if (asked.failure.status === 404 && asked.failure.message.startsWith("no route ")) link.changesRefused = this.#core.host.nowMs();
        return yield* whole;
      }
      const order = get(asked.success, "order");
      const changed = get(asked.success, "rows");
      if (!Array.isArray(order) || !Array.isArray(changed)) return yield* whole;
      for (const row of changed) {
        const key = idText(get(row, id));
        if (key !== null) rows.set(key, row);
      }
      const list: unknown[] = [];
      for (const key of order) {
        const row = rows.get(idText(key) ?? "");
        // Neither held nor sent: read whole.
        if (row === undefined) return yield* whole;
        list.push(row);
      }
      return list;
    });
  }

  /// The station's logins (docs/remote-login.md), read whole: in its link's memory, as its stream then tells them. A
  /// station from before them answers 404: it has none (the page offers none).
  #machineLogins(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/machine-logins", null, { quiet: true, ctx }));
      if (answer._tag === "Success") logins.putList(link, answer.success);
      else if (answer.failure.status === 404) logins.unsupported(link);
      else return;
      this.onChange(address, "logins");
    });
  }

  /// A login as its station says it now (an event, or a write's answer): in place; ended, its relay stops.
  putMachineLogin(address: string, login: unknown): void {
    const link = this.#links.get(address);
    if (!link || !logins.putLogin(link, login)) return;
    const id = str(get(login, "id"));
    if (id !== null && typeof get(login, "endedAt") === "number") this.relays.ended(address, id);
    this.onChange(address, "logins");
  }

  /// The station's usage changed (or may have: read again): read while a page shows it, else only marked to be read once
  /// one does. It is some 200 KB and changes with every model call an agent makes: read on each whatever was shown, it
  /// was most of what a slow link carried. The read asked for, if any.
  #usageChanged(address: string, ctx: SpanContext | null = null): Deferred.Deferred<void, CoreError>[] {
    const link = this.#links.get(address);
    if (link) link.usageCurrent = false;
    if (!this.#core.store.inUse({ topic: "stationUsage", station: address })) return [];
    return [this.#enqueue(address, "usage", Priority.background, this.#usage(address, ctx))];
  }

  /// The station's archived chats may have changed: read while a page shows them (the archive), else only marked to be
  /// read once one does. Every chat ever archived: read with each snapshot and archiving, it was a large part of what a
  /// slow link carried for a page seldom opened.
  #archivedChanged(address: string, ctx: SpanContext | null = null): Deferred.Deferred<void, CoreError>[] {
    const link = this.#links.get(address);
    if (link) link.archivedCurrent = false;
    if (!this.#core.store.inUse({ topic: "archivedRows", station: address })) return [];
    return [this.#enqueue(address, "archived", Priority.background, this.#archived(address, ctx))];
  }

  /// A page shows the station's archived chats: read, unless what is held is as the station has it.
  archivedShown(address: string): void {
    const link = this.#links.get(address);
    if (link && !link.archivedCurrent) this.#enqueue(address, "archived", Priority.shown, this.#archived(address));
  }

  #archived(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const link = this.#links.get(address);
      if (link) link.archivedCurrent = true;
      return this.#read(address, { topic: "archivedRows", station: address }, "/chats?archived=1", undefined, ctx);
    });
  }

  /// A page shows the station's usage: read, unless what is held is as the station has it.
  /// A folder of the station's drive shown: read again, ahead of what is kept current around it.
  driveShown(address: string, root: string, path: string): void {
    if (this.#links.has(address)) this.#enqueue(address, `drive/${root}/${path}`, Priority.shown, this.#drive(address, root, path));
  }

  /// A folder of the drive read: held as the station has it now. Refused (gone, out of its root, not a root any more):
  /// said so even where it was held before, which stays to be seen meanwhile. Not answered (no answer in time, the
  /// station failing, the link dropping): what is held stays; where nothing is, why is said rather than a wait that never
  /// ends (it is read again as it is shown again, and as the station's stream comes back).
  #drive(address: string, root: string, path: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const topic: Topic = { topic: "drive", station: address, root, path };
      const key = topicKey(topic);
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", `/drive/list?root=${encode(root)}&path=${encode(path)}`, null, { quiet: true, ctx }));
      if (answer._tag === "Success") {
        const had = link.errors.delete(key);
        this.#core.data.set(topic, answer.success);
        if (had) this.onChange(address, "errors", key);
      } else if (answer.failure.status !== undefined && answer.failure.status >= 400 && answer.failure.status < 500) {
        // Not there now: what was held of it is let go, for the refusal to be what is shown.
        link.errors.set(key, answer.failure);
        this.#core.data.forgetTopic(topic);
        this.onChange(address, "errors", key);
      } else if (this.#core.data.shared(topic) === undefined) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    });
  }

  /// A folder of the drive shown, kept as it is on the station's disk (an agent writing there, a file renamed on the
  /// machine): the station answers GET /drive/watch once something in it changes (else after a while), and it is read
  /// again. A station from before watching, or a folder gone, answers 4xx: then it is read only as it is shown.
  /// What still.fail uses of the station's machine now (GET /resources), while shown (a fiber of the topic's,
  /// topics.ts) and a page of the app is in view: the station tells it as it looks, on a stream of its own (asked as
  /// events). A station from before answers it once instead: asked again every RESOURCES_EVERY_MS. One that has none
  /// says so (its refusal), asked again as often.
  resourcesWatch(address: string): Effect.Effect<void, never> {
    const key = topicKey({ topic: "stationResources", station: address });
    const attend = this.#core.attention?.attend;
    const told = (link: Link, value: unknown) => {
      link.errors.delete(key);
      link.memory.set(key, value);
      this.onChange(address, "log", key);
    };
    const follow = Effect.scoped(
      Effect.gen({ self: this }, function* () {
        const link = this.#links.get(address);
        if (!link || !this.reachable(address)) return;
        const opened = yield* Effect.result(this.requests.stream(link.addr, "/resources", null));
        if (opened._tag === "Failure") {
          const status = opened.failure.status;
          if (status !== undefined && status < 500) {
            link.errors.set(key, opened.failure);
            this.onChange(address, "errors", key);
          }
          return;
        }
        const reply = opened.success;
        // From before: what it is now, once.
        if (!(replyHeader(reply, "content-type") ?? "").startsWith("text/event-stream")) {
          const bytes = yield* Effect.result(readAll(reply.body));
          const value = bytes._tag === "Success" ? parseJson(bytes.success) : undefined;
          if (value !== undefined) told(link, value);
          return;
        }
        const parser = new SseParser();
        const silent = Effect.sleep(RESOURCES_SILENT_MS).pipe(Effect.as(null));
        for (;;) {
          const next = yield* Effect.raceFirst(Effect.result(reply.body.take), silent);
          if (next === null || next._tag === "Failure" || next.success === null) return;
          for (const [name, data] of parser.feed(next.success)) {
            const value = name === "resources" ? parseJson(data) : undefined;
            if (value !== undefined) told(link, value);
          }
        }
      }),
    );
    // (not while no page of the app is in view: a phone in a pocket asks nothing)
    const whileShown = attend ? Effect.andThen(Effect.suspend(() => attend.untilShown()), Effect.raceFirst(follow, Effect.suspend(() => attend.untilHidden()))) : follow;
    return Effect.forever(Effect.andThen(whileShown, Effect.sleep(RESOURCES_EVERY_MS)));
  }

  driveWatch(address: string, root: string, path: string): Effect.Effect<void, never> {
    const id = Array.from(crypto.getRandomValues(new Uint8Array(9)), (b) => b.toString(16).padStart(2, "0")).join("");
    const asked = `/drive/watch?root=${encode(root)}&path=${encode(path)}&id=${id}`;
    return Effect.gen({ self: this }, function* () {
      for (;;) {
        const link = this.#links.get(address);
        if (!link || !this.reachable(address)) {
          yield* Effect.sleep(WATCH_AGAIN_MS);
          continue;
        }
        const answer = yield* Effect.result(this.requests.call(link.addr, "GET", asked, null, { quiet: true }));
        if (answer._tag === "Failure") {
          const status = answer.failure.status;
          if (status !== undefined && status >= 400 && status < 500) return;
          yield* Effect.sleep(WATCH_AGAIN_MS);
          continue;
        }
        if (get(answer.success, "changed") === true) yield* Effect.ignore(this.ask(address, `drive/${root}/${path}`, this.#drive(address, root, path)), { log: "Unhandled", message: "drive read" });
      }
    });
  }

  /// A folder read again for a person who asked (`drive.refresh`), answering once it is.
  driveRefresh(address: string, root: string, path: string): Effect.Effect<void, CoreError> {
    return this.ask(address, `drive/${root}/${path}`, this.#drive(address, root, path));
  }

  usageShown(address: string): void {
    const link = this.#links.get(address);
    if (link && !link.usageCurrent) this.#enqueue(address, "usage", Priority.shown, this.#usage(address));
  }

  /// What the station's agents spent over the last 30 days, days as this device's clock has them. Current from when it is
  /// asked: a change said meanwhile has it read again.
  #usage(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const link = this.#links.get(address);
      if (link) link.usageCurrent = true;
      const now = this.#core.host.nowMs();
      const offset = this.#core.host.utcOffsetMin(now);
      const day = 86_400_000;
      const local = Math.trunc(now) + offset * 60_000;
      const from = local - (((local % day) + day) % day) - 29 * day - offset * 60_000;
      return this.#read(address, { topic: "stationUsage", station: address }, `/usage?from=${from}&tz=${offset}`, undefined, ctx);
    });
  }

  /// A station's history onto the device, in the background: each listed session's detail (turns, threads, jobs) where
  /// it is not held or its turns changed, every thread's entries (the latest threads first, a page each in turn), and
  /// the latest page of each listed session's transcript. A batch a run (POST /batch: some 40 reads in one request,
  /// compressed as one), the task asking itself again while there is more, so what is more urgent goes between: a read
  /// a request, a new device made some 500 of them of one station, each compressed on its own. Each read is asked once
  /// a sweep: one that brought nothing new waits for the next. A station from before batches is read a request a read.
  #historyStart(address: string): void {
    const link = this.#links.get(address);
    if (!link) return;
    link.historyAsked.clear();
    link.history = this.#historyReads(address);
    this.#enqueue(address, "history", Priority.background, this.#history(address, 0));
  }

  #history(address: string, attempt: number): Effect.Effect<void, CoreError> {
    return this.#asked((asked) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      if (link.batchRefused !== null && this.#core.host.nowMs() - link.batchRefused < CHANGES_RETRY_MS) return this.#historyEach(address);
      const batch: HistoryRead[] = [];
      let cost = 0;
      while (link.history.length > 0 && (batch.length === 0 || cost + link.history[0]!.cost <= HISTORY_BATCH)) {
        const read = link.history.shift()!;
        if (link.historyAsked.has(read.path)) continue;
        link.historyAsked.add(read.path);
        batch.push(read);
        cost += read.cost;
      }
      if (batch.length === 0) return;
      const answered = yield* Effect.result(this.requests.batch(link.addr, batch.map((r) => r.path), null));
      if (answered._tag === "Failure") {
        const e = answered.failure;
        for (const r of batch) link.historyAsked.delete(r.path);
        link.history.unshift(...batch);
        if (e.status === 404 && e.message.startsWith("no route ")) {
          link.batchRefused = this.#core.host.nowMs();
          return this.#historyEach(address);
        }
        // Not answered (its link went, say): asked again a little later, a few times.
        if ((e.status === undefined || e.status >= 500) && attempt < READ_RETRIES) {
          const again = Effect.sleep(READ_RETRY_MS * 2 ** attempt).pipe(Effect.andThen(Effect.sync(() => void this.#enqueue(address, "history", Priority.background, this.#history(address, attempt + 1)))));
          this.#core.runner.fork(again, link.scoped);
        }
        return;
      }
      batch.forEach((read, i) => {
        const after = read.apply(answered.success[i]!);
        if (after !== null && !link.historyAsked.has(after.path)) link.history.push(after);
      });
      this.#retell(address, asked);
      // More to bring: asked again, behind what is more urgent.
      if (link.history.length > 0) this.#enqueue(address, "history", Priority.background, this.#history(address, 0));
    }));
  }

  /// What a station's history has yet to bring onto the device, in the order it is brought: each listed session's
  /// detail where its turns changed, each thread's next page of entries (the latest threads first), each listed
  /// session's latest page of its transcript where none is held.
  #historyReads(address: string): HistoryRead[] {
    const data = this.#core.data;
    const sessions = data.sessionsToRead(address);
    const reads: HistoryRead[] = [];
    for (const [key, again] of sessions) {
      if (!again) continue;
      const topic = { topic: "session", station: address, key };
      reads.push({ path: `/sessions/${encode(key)}`, cost: 1, apply: (a) => (this.#took(address, topic, a), null) });
    }
    for (const channel of [...data.threadIds(address).map((id) => entriesOf(address, id)), ...sessions.map(([key]) => transcriptOf(address, key))]) {
      const read = this.#channelRead(channel);
      if (read !== null) reads.push(read);
    }
    return reads;
  }

  /// A channel's next read (channels/channels.ts `next`) as a read of its station's history, the read after it while
  /// items come.
  #channelRead(channel: Channel): HistoryRead | null {
    const read = this.channels.batched(channel);
    if (read === null) return null;
    const apply = (a: { status: number; body: unknown }) => {
      const came = read.took(a.status >= 200 && a.status < 300 ? { _tag: "Success", success: a.body } : { _tag: "Failure", failure: httpError(a.status, a.body) });
      return came > 0 ? this.#channelRead(channel) : null;
    };
    return { path: read.path, cost: channel.kind.cost, apply };
  }

  /// A read of a channel made in the background answered. A thread's: one that is gone goes with what is held of it; one
  /// not to be read (no longer this viewer's) says so while nothing of it is held.
  #channelAnswered(channel: Channel, error: CoreError | null, nothing: boolean): void {
    const link = this.#links.get(channel.station);
    if (!link) return;
    // A transcript read: what the station has of it is known (a history with nothing in it is not still loading).
    if (channel.kind === TRANSCRIPT) {
      if (error === null) this.#transcriptKnown(link, channel.id);
      return;
    }
    if (channel.kind !== ENTRIES) return;
    const id = Number(channel.id);
    const topic = topicKey({ topic: "thread", station: channel.station, thread: id });
    // Not brought now (it is read again later, as the sync goes): not waited on while catching up.
    if (error !== null) this.#caughtUp(channel.station, id, true);
    if (error === null) {
      if (link.errors.delete(topic)) this.onChange(channel.station, "errors", topic);
    } else if (error.status === 404) this.#threadGone(channel.station, id);
    else if (error.status !== undefined && error.status >= 400 && error.status < 500 && nothing) {
      link.errors.set(topic, error);
      this.onChange(channel.station, "errors", topic);
    }
  }

  /// A read of a held topic answered in a batch, as #read takes its answer (a 4xx while nothing is held is its error).
  #took(address: string, topic: Topic, a: { status: number; body: unknown }): void {
    const link = this.#links.get(address);
    if (!link) return;
    const key = topicKey(topic);
    if (a.status >= 200 && a.status < 300) {
      link.errors.delete(key);
      this.#core.data.set(topic, a.body);
    } else if (a.status >= 400 && a.status < 500 && this.#core.data.shared(topic) === undefined) {
      link.errors.set(key, httpError(a.status, a.body));
      this.onChange(address, "errors", key);
    }
  }

  /// A station from before batches: its history a read a task, each its own request.
  #historyEach(address: string): void {
    const link = this.#links.get(address);
    if (link) link.history = [];
    for (const [key, again] of this.#core.data.sessionsToRead(address)) {
      if (again) this.#enqueue(address, `session/${key}`, Priority.background, this.#session(address, key));
      this.channels.bring(transcriptOf(address, key), Priority.background - 1);
    }
    for (const id of this.#core.data.threadIds(address)) this.channels.bring(entriesOf(address, id), Priority.background);
  }

  #session(address: string, key: string): Effect.Effect<void, CoreError> {
    return this.#read(address, { topic: "session", station: address, key }, `/sessions/${encode(key)}`);
  }

  /// A session's transcript entries `from` to `to` whole, in place of what is held of them in brief (`history.detail`):
  /// never pushed, read when a history's step is opened, behind what is shown in brief (Priority.detail). Asked for by
  /// someone waiting on it, it is tried while the station seems away too: what went wrong is theirs to see.
  detail(address: string, key: string, from: number, to: number): Effect.Effect<void, CoreError> {
    const work = Effect.suspend(() => (this.#links.has(address) ? Effect.asVoid(this.channels.read(transcriptOf(address, key), { from, to, whole: true }, { quiet: true })) : Effect.void));
    return Deferred.await(this.#enqueue(address, `detail/${key}/${from}-${to}`, Priority.detail, work));
  }

  /// A thread gone from its station: its row and its entries go, and its topic says so.
  #threadGone(address: string, id: number): void {
    this.#core.data.dropThread(address, id);
    const link = this.#links.get(address);
    if (link) {
      const key = topicKey({ topic: "thread", station: address, thread: id });
      link.errors.set(key, new CoreError("http_404", t("station.core.noChat"), 404));
      this.onChange(address, "errors", key);
    }
  }

  // ── events ──

  onEvent(address: string, name: string, raw: string): void {
    const data = parseJson(raw);
    if (data === undefined) return;
    const core = this.#core;
    if (SEARCHED.has(name)) this.#searchStale(address);
    if (RETOLD.has(name)) {
      this.#retold.told(address, name, data);
      this.#held(address, name, data);
      // A sidebar row: an agent starting or ending its turn, which a stream to a station from before follows by name.
      if (name === "chat") this.openEvents(address, false);
      return;
    }
    switch (name) {
      case "thread": {
        const id = u64(get(data, "id"));
        if (id === null) return;
        const entries = (get(data, "entries") as unknown[] | undefined) ?? [];
        const items = ENTRIES.items(data, { latest: true });
        const newest = Math.max(-1, ...items.map(([n]) => n));
        this.onTold(address, id, entries);
        // Into its channel: the thread goes that far at once (the rest of its summary is read below), and a gap what
        // was told left is read. A chat let go for room (and not opened since) is not kept current: what it said is
        // read when it is opened. History older than what is held comes with the station's (#history).
        this.channels.told(entriesOf(address, id), items);
        // Its summary for the viewer: told by the station (`thread-view`) when it tells it, else read.
        const viewed = this.#links.get(address)?.viewed.get(id);
        if (viewed === undefined || viewed < newest) this.#markDirty(address, id);
        return;
      }
      case "live": {
        const key = str(get(data, "key"));
        if (key) this.#onLive(address, key, data);
        return;
      }
      case "job-log": {
        const id = str(get(data, "id"));
        const lines = u64(get(data, "lines"));
        const link = this.#links.get(address);
        if (id && lines !== null && link) {
          link.memory.set(logKey(id, lines), { text: get(data, "text") ?? "", outputAt: get(data, "outputAt") ?? null });
          this.onChange(address, "log", topicKey({ topic: "jobLog", station: address, job: id, lines }));
        }
        return;
      }
      // The stream that took over could not be told all that came since the last its predecessor gave: read again.
      case "missed":
        return this.snapshot(address);
      case "host": {
        const link = this.#links.get(address);
        if (link) {
          link.memory.set("host", data);
          this.onChange(address, "host");
        }
        return;
      }
      case "usage":
        this.#usageChanged(address);
        return;
      // Its screens came or went, or who is on them changed (docs/remote-screens.md).
      case "screens":
        this.#heldScreens(address, { screens: Array.isArray(get(data, "screens")) ? (get(data, "screens") as unknown[]) : [], outdated: false });
        return;
      // A login of the station's (docs/remote-login.md).
      case "machine-logins": {
        const link = this.#links.get(address);
        if (!link) return;
        if (isObject(get(data, "login"))) this.putMachineLogin(address, get(data, "login"));
        return;
      }
      // The programs granted the station's data changed, or read it (docs/data-outflow.md).
      case "outflow-grants": {
        const link = this.#links.get(address);
        if (!link || !Array.isArray(get(data, "grants"))) return;
        link.memory.set(OUTFLOW, data);
        this.onChange(address, "log", topicKey({ topic: "outflowGrants", station: address }));
        return;
      }
      // A login's terminal as it changes (while one is shown).
      case "login-screen": {
        const link = this.#links.get(address);
        const id = link ? logins.putScreen(link, data) : null;
        if (id !== null) this.onChange(address, "loginScreen", id);
        return;
      }
      default:
        for (const part of this.also) part.event(address, name, data);
    }
  }

  /// What a stream told of what reads bring too (RETOLD) into what is held: as it is told, and again on top of what a
  /// read asked before it brought (`#retell`).
  #held(address: string, name: string, data: unknown): void {
    const core = this.#core;
    switch (name) {
      case "session":
        return this.#onSession(address, data);
      case "session-removed": {
        const key = str(get(data, "key"));
        if (key) this.#onSessionRemoved(address, key);
        return;
      }
      case "thread-view": {
        // A thread as GET /threads/:id has it for this viewer, told after something was said in it: in place, and not
        // read again.
        const id = u64(get(data, "id"));
        const link = this.#links.get(address);
        if (id === null || !link) return;
        link.viewed.set(id, u64(get(data, "last")) ?? 0);
        link.dirty.delete(id);
        this.putThread(address, data);
        return;
      }
      case "thread-removed": {
        const id = u64(get(data, "id"));
        if (id !== null) this.#threadGone(address, id);
        return;
      }
      case "read": {
        const thread = u64(get(data, "thread"));
        const n = u64(get(data, "n"));
        if (thread !== null && n !== null) this.putRead(address, thread, n);
        return;
      }
      case "chat":
        return core.data.putChat(address, data);
      case "chat-removed": {
        const id = str(get(data, "id"));
        if (id) core.data.dropChat(address, id);
        return;
      }
      case "job":
        return this.onJob(address, data);
      case "job-removed": {
        const id = str(get(data, "id"));
        const key = str(get(data, "session"));
        if (id && key) {
          core.data.patchDetail(address, key, (detail) => {
            if (isObject(detail) && Array.isArray(detail.jobs)) detail.jobs = detail.jobs.filter((j) => get(j, "id") !== id);
          });
        }
        return;
      }
      case "overview":
      case "footprint":
        return core.data.set({ topic: name, station: address }, data);
    }
  }

  /// What `address`'s stream told since `read` was asked, on top of what it brought (retold.ts).
  #retell(address: string, read: number): void {
    for (const { name, data } of this.#retold.since(read, address)) this.#held(address, name, data);
  }

  /// A session's summary changed: in place among the listed (and in its detail); its detail is read again when its
  /// turns changed.
  #onSession(address: string, summary: unknown): void {
    const key = str(get(summary, "key"));
    if (!key) return;
    if (this.#core.data.putSummary(address, summary)) this.#enqueue(address, `session/${key}`, Priority.shown, this.#session(address, key));
    // How far its transcript goes: what the device lacks of it after what it holds is read (channels.ts `settle`).
    const length = u64(get(summary, "transcriptLength"));
    if (length !== null && length > 0) this.channels.goesTo(transcriptOf(address, key), length - 1);
  }

  #onSessionRemoved(address: string, key: string): void {
    const core = this.#core;
    core.data.dropSession(address, key);
    const link = this.#links.get(address);
    if (link) {
      const topic = topicKey({ topic: "session", station: address, key });
      link.errors.set(topic, new CoreError("http_404", t("station.core.sessionDeleted"), 404));
      this.onChange(address, "errors", topic);
    }
  }

  /// A job as it is now: in place in its session's jobs, and among the station's open ones while it is open.
  onJob(address: string, job: unknown): void {
    const id = str(get(job, "id"));
    const key = str(get(job, "session"));
    if (!id || !key) return;
    const core = this.#core;
    core.data.patchDetail(address, key, (detail) => {
      if (!isObject(detail) || !Array.isArray(detail.jobs)) return;
      const i = detail.jobs.findIndex((j) => get(j, "id") === id);
      if (i >= 0) detail.jobs[i] = job as never;
      else detail.jobs.unshift(job as never);
    });
    const state = get(job, "state");
    const open = state === "running" || (state === "exited" && (get(job, "port") ?? null) !== null);
    // A new one: which chat it is in is the station's to say.
    if (core.data.putJob(address, job, open)) this.#enqueue(address, "jobs", Priority.shown, this.#read(address, { topic: "jobs", station: address }, "/jobs"));
  }

  /// A thread's summary into the station's threads, and the details of the sessions taking part. It says how far the
  /// thread goes: its channel is read if the device is behind on it.
  putThread(address: string, view: unknown): void {
    this.#core.data.putThread(address, view);
    const id = u64(get(view, "id"));
    const last = u64(get(view, "last"));
    if (id !== null && last !== null) this.channels.goesTo(entriesOf(address, id), last);
    // Found further while catching up (its summary read again after what was missed): one more to catch up on.
    const catching = this.#links.get(address)?.catching;
    if (id !== null && catching?.tallied && !catching.behind.has(id) && this.#behind(address, id)) {
      catching.behind.add(id);
      this.onChange(address, "link");
    }
  }

  /// The viewer read a thread up to entry `n`: its read position moves there, nothing unread once it covers the last
  /// entry (otherwise the count is read again).
  putRead(address: string, thread: number, n: number): void {
    if (this.#core.data.setRead(address, thread, n)) this.#markDirty(address, thread);
  }

  /// A thread's summary read again once the burst of events is over.
  #markDirty(address: string, thread: number): void {
    const link = this.#links.get(address);
    if (!link) return;
    link.dirty.add(thread);
    if (link.flushing) return;
    link.flushing = true;
    this.#core.runner.fork(
      Effect.sleep(EVENTS_COALESCE_MS).pipe(
        Effect.andThen(
          Effect.sync(() => {
            link.flushing = false;
            const dirty = [...link.dirty];
            link.dirty.clear();
            for (const id of dirty) this.#enqueue(address, `thread/${id}`, Priority.shown, this.#threadSummary(address, id));
          }),
        ),
      ),
      link.scoped,
    );
  }

  #threadSummary(address: string, id: number): Effect.Effect<void, CoreError> {
    return this.#asked((read) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link) return;
      const view = yield* Effect.result(this.requests.call(link.addr, "GET", `/threads/${id}`, null, { quiet: true }));
      if (view._tag === "Success") this.putThread(address, view.success);
      else if (view.failure.status === 404) this.#core.data.unlistThread(address, id);
      this.#retell(address, read);
    }));
  }

  /// One message of the live stream: transcript items into the records, steps and phase into the live view.
  #onLive(address: string, key: string, message: unknown): void {
    {
      const core = this.#core;
      const link = this.#links.get(address);
      if (!link) return;
      let view = link.lives.get(key);
      if (!view) {
        view = { steps: [], phase: null, rate: null, usage: null, loaded: false };
        link.lives.set(key, view);
      }
      const now = core.host.nowMs();
      const kind = str(get(message, "type")) ?? "";
      if (kind === "timeline" && core.data.evicted("transcript", address, key)) {
        // Let go for room and not opened since: its items are read when it is opened.
      } else if (kind === "timeline") {
        const start = u64(get(message, "start")) ?? 0;
        const entries = (get(message, "entries") as unknown[] | undefined) ?? [];
        // Written anew from before what is held ends: what came after it goes. Past what is held (the latest page
        // only): it is put as it is, and the topic shows the run that ends the transcript.
        const held = core.data.logSpan("transcript", address, key);
        const top = held ? held.max + 1 : 0;
        this.channels.told(transcriptOf(address, key), entries.map((e, i) => [start + i, e] as [number, unknown]), start < top ? start + entries.length - 1 : null);
        // Where it stands, told as a stream opens or as its usage changes (nothing of it): the device reads what it
        // lacks before there.
        if (entries.length === 0 && start > 0) this.channels.goesTo(transcriptOf(address, key), start - 1);
        view.usage = get(message, "usage") ?? null;
        // Ended steps stay until the entries that record them arrive.
        if (entries.length > 0) view.steps = view.steps.filter((s) => get(s, "ended") !== true);
      } else if (kind === "steps") {
        view.steps = ((get(message, "steps") as unknown[] | undefined) ?? []).slice();
        const phase = get(message, "phase");
        view.phase = phase === null || phase === undefined ? null : { phase: get(phase, "phase") ?? null, since: Math.round(now - (typeof get(phase, "elapsedMs") === "number" ? (get(phase, "elapsedMs") as number) : 0)) };
        view.loaded = true;
      } else if (kind === "clear") {
        Object.assign(view, { steps: [], phase: null, rate: 0 });
      } else if (kind === "rate") {
        view.rate = u64(get(message, "tokensPerSecond")) ?? 0;
      } else if (kind === "work") {
        // Whole each time: how long each task has run, as since when on this device's clock.
        view.tasks = ((get(message, "tasks") as unknown[] | undefined) ?? []).map((task) => ({ ...(task as object), since: Math.round(now - (typeof get(task, "elapsedMs") === "number" ? (get(task, "elapsedMs") as number) : 0)) }));
        view.plan = ((get(message, "plan") as unknown[] | undefined) ?? []).slice();
      } else if (kind === "step") {
        const event = get(message, "event");
        if (event !== undefined) applyStep(view, event, now);
      } else return;
      this.onChange(address, "live", key);
    }
  }

  /// A session's transcript was read, or told as it stands: its history is loaded (`loaded`), what it holds what there is.
  #transcriptKnown(link: Link, key: string): void {
    let view = link.lives.get(key);
    if (!view) link.lives.set(key, (view = { steps: [], phase: null, rate: null, usage: null, loaded: false }));
    if (view.loaded) return;
    view.loaded = true;
    this.onChange(link.address, "live", key);
  }

  /// What the chat shows of a session at work (activity.ts), from its live view.
  activity(view: Record<string, unknown>, stations?: ReadonlyMap<string, string>): unknown {
    return historyActivity(view, stations);
  }

  // ── writes ──

  /// An operation on a station: its request (its fallback where the station is from before it), and once it
  /// succeeded what it changed brought up to date — from its answer where it says, else read again — before it answers.
  perform(op: Request, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const address = "station" in op.target ? op.target.station : "";
      const addr = StationAddr.parse(address);
      if (op.method === "POST" && op.path === "/updates/all") return yield* this.#updateAll(addr, ctx);
      let current: Request = op;
      for (;;) {
        const result = yield* Effect.result(this.requests.call(addr, current.method, current.path, current.body, { ctx }));
        if (result._tag === "Failure") {
          if (result.failure.status === 404 && current.fallback) {
            current = current.fallback;
            continue;
          }
          return yield* Effect.fail(result.failure);
        }
        yield* this.afterWrite(address, current.effect, result.success);
        return result.success;
      }
    });
  }

  /// Brings what a successful write changed up to date before it answers.
  afterWrite(address: string, effect: OpEffect, answer: unknown): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const reads: [string, Effect.Effect<void, CoreError>][] = [];
      const read = (what: string, topic: Topic, path: string) => reads.push([what, this.#read(address, topic, path)]);
      const rows = () => read("chats", { topic: "chatRows", station: address }, "/chats");
      // The archive: read again before the call answers only while a page shows it, else marked to be (#archivedChanged).
      const archived = () => {
        const link = this.#links.get(address);
        if (link) link.archivedCurrent = false;
        if (this.#core.store.inUse({ topic: "archivedRows", station: address })) reads.push(["archived", this.#archived(address)]);
      };
      switch (effect.kind) {
        case "none":
          return;
        case "session": {
          if (effect.key !== null) reads.push([`session/${effect.key}`, this.#session(address, effect.key)]);
          read("sessions", { topic: "sessions", station: address }, "/sessions");
          rows();
          archived();
          read("footprint", { topic: "footprint", station: address }, "/footprint");
          const thread = get(answer, "thread");
          if (isObject(thread)) this.putThread(address, thread);
          break;
        }
        // Its process warmed, stopped or let go: its own detail before the call answers; the lists that show it (its
        // summary, its chat's row, the overview's counts) its station tells as they change. Read whole again, they were
        // most of what warming a chat as it opened cost on a slow link.
        case "process":
          if (effect.key !== "") reads.push([`session/${effect.key}`, this.#session(address, effect.key)]);
          break;
        case "thread": {
          let rowsRead = false;
          if (get(answer, "surface") !== undefined) {
            this.putThread(address, answer);
            rowsRead = true;
          } else {
            const thread = u64(get(answer, "thread"));
            const n = u64(get(answer, "n"));
            if (thread !== null && n !== null) this.putRead(address, thread, n);
          }
          if (get(answer, "dismissed") !== undefined) rowsRead = true;
          if (rowsRead || effect.archived) rows();
          if (effect.archived) archived();
          break;
        }
        case "connect":
          read("overview", { topic: "overview", station: address }, "/overview");
          read("sessions", { topic: "sessions", station: address }, "/sessions");
          if (effect.id !== null) read(`slackApp/${effect.id}`, { topic: "slackApp", station: address, connect: effect.id }, `/connects/${encode(effect.id)}/slack-app`);
          break;
        case "overview":
          read("overview", { topic: "overview", station: address }, "/overview");
          break;
        case "footprint":
          read("footprint", { topic: "footprint", station: address }, "/footprint");
          read("overview", { topic: "overview", station: address }, "/overview");
          break;
        case "slack":
          read("overview", { topic: "overview", station: address }, "/overview");
          for (const id of this.#slackConnects(address)) read(`slackApp/${id}`, { topic: "slackApp", station: address, connect: id }, `/connects/${encode(id)}/slack-app`);
          break;
        case "job":
          if (get(answer, "id") !== undefined && get(answer, "state") !== undefined) this.onJob(address, answer);
          break;
        // What the agents' memory says of it changed (a skill shared or no longer): read again where it is shown or held.
        case "memory":
          if (this.#core.store.inUse({ topic: "memory", station: address }) || this.#links.get(address)?.memory.has(MEMORY)) reads.push(["memory", this.#memory(address)]);
          break;
        case "outflowGrants":
          reads.push(["outflowGrants", this.#outflow(address)]);
          break;
        case "identity":
          read("overview", { topic: "overview", station: address }, "/overview");
          rows();
          break;
        // A login started, cancelled or given its callback: as it is now, at once (its station tells the rest).
        case "machineLogins":
          this.putMachineLogin(address, isObject(get(answer, "login")) ? get(answer, "login") : answer);
          break;
        // A sign-in for a new profile started, given its code or dropped: as the station answered, at once, until its
        // overview says as much (a dropped one's answer has no job: let go).
        case "login": {
          const id = effect.id ?? str(get(answer, "id"));
          if (id !== null) this.#core.data.stepLogin(address, id, get(answer, "job"), effect.from);
          break;
        }
        // The folders a change of the drive was in: read again where they are held or shown.
        case "drive":
          for (const path of new Set(effect.paths)) {
            const topic = { topic: "drive", station: address, root: effect.root, path };
            if (this.#core.store.inUse(topic) || this.#core.data.shared(topic) !== undefined) reads.push([`drive/${effect.root}/${path}`, this.#drive(address, effect.root, path)]);
          }
          break;
      }
      // Profile and connect edits answer the overview as it is now (the Feishu routes beside what they made, as
      // `overview`).
      const told = get(answer, "connects") !== undefined && get(answer, "profiles") !== undefined ? answer : get(get(answer, "overview"), "connects") !== undefined && get(get(answer, "overview"), "profiles") !== undefined ? get(answer, "overview") : undefined;
      if (told !== undefined) {
        this.#core.data.set({ topic: "overview", station: address }, told);
        reads.splice(0, reads.length, ...reads.filter(([what]) => what !== "overview"));
      }
      yield* Effect.all(
        reads.map(([what, work]) => Effect.ignore(this.ask(address, what, work), { log: "Unhandled", message: "station read" })),
        { concurrency: "unbounded", discard: true },
      );
    });
  }

  /// Runtimes first, the station last: one at a time, each awaited to its end: the overview as the station's events
  /// tell it (its updates' progress is pushed as it goes, as the pages see it), never asked again on a timer.
  #updateAll(addr: StationAddr, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
    const topic: Topic = { topic: "overview", station: addr.toString() };
    // (each change of the overview counted, and whoever waits for the next woken: held from the first update to the end)
    let changes = 0;
    let next: Deferred.Deferred<void> | null = null;
    let watch: { drop(): void } | null = null;
    const changed = () => {
      changes++;
      if (next) Deferred.doneUnsafe(next, Exit.void);
    };
    return Effect.gen({ self: this }, function* () {
      const address = addr.toString();
      watch = this.#core.store.watch(topic, changed);
      const overview = yield* this.requests.call(addr, "GET", "/overview", null, { ctx });
      const updates = get(overview, "updates");
      if (!Array.isArray(updates)) return yield* Effect.fail(CoreError.invalid(t("station.core.updatesUnsupported")));
      if (updates.some((v) => get(v, "state") === "updating")) return yield* Effect.fail(CoreError.invalid(t("station.core.updateBusy")));
      const selected = updates.filter((v) => get(v, "installed") === true && get(v, "updatable") === true && (get(v, "newer") === true || get(v, "downgrade") === true || get(v, "state") === "failed"));
      // A stable sort: the station last.
      selected.sort((a, b) => Number(get(a, "id") === "station") - Number(get(b, "id") === "station"));
      let answer: unknown = updates;
      for (const item of selected) {
        const id = str(get(item, "id"));
        if (id === null) return yield* Effect.fail(CoreError.invalid(t("station.core.noSoftwareId")));
        answer = yield* this.requests.call(addr, "POST", "/updates", { id }, { ctx });
        yield* this.afterWrite(address, { kind: "overview" }, answer);
        if (id === "station") break;
        const deadline = this.#core.host.nowMs() + 15 * 60_000;
        let seen = changes;
        for (;;) {
          const status = Array.isArray(answer) ? answer.find((v) => get(v, "id") === id) : undefined;
          if (status === undefined) return yield* Effect.fail(CoreError.invalid(t("station.core.progressUnreadable")));
          if (get(status, "state") === "failed") {
            const name = str(get(item, "name")) ?? id;
            const message = str(get(status, "message")) ?? t("station.core.retryInDetails");
            return yield* Effect.fail(CoreError.invalid(t("station.core.updateFailed", { name, error: message })));
          }
          if (get(status, "state") !== "updating") break;
          const left = deadline - this.#core.host.nowMs();
          if (left <= 0) return yield* Effect.fail(CoreError.invalid(t("station.core.updateUnfinished")));
          // (the next change the station tells, unless one came since this one was looked at)
          if (changes === seen) {
            next = Deferred.makeUnsafe<void>();
            yield* Effect.raceFirst(Deferred.await(next), Effect.sleep(left));
            next = null;
          }
          seen = changes;
          answer = get(this.#core.data.get(topic), "updates") ?? answer;
        }
      }
      return answer;
    }).pipe(Effect.ensuring(Effect.sync(() => watch?.drop())));
  }

  /// A person's message into a thread; answers its entry number as the station takes it.
  post(address: string, thread: number, message: unknown, ctx: SpanContext | null, idempotency?: string): Effect.Effect<number, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const addr = StationAddr.parse(address);
      const headers: [string, string][] = idempotency ? [[IDEMPOTENCY_KEY, idempotency]] : [];
      const answer = yield* this.requests.call(addr, "POST", `/threads/${thread}/messages`, message, { ctx, headers });
      const n = u64(get(answer, "n"));
      if (n === null) return yield* Effect.fail(new CoreError("bad_response", t("station.core.noMessageNumber")));
      // Sent: the station has it. The thread goes that far now, and its entry comes as anything said in it does (its
      // stream tells it; else it is read once the burst is over), not waited on here.
      this.channels.goesTo(entriesOf(address, thread), n);
      return n;
    });
  }

  /// Records how far the viewer has read a thread; nothing is sent when it is read that far already.
  read(address: string, thread: number, n: number, ctx: SpanContext | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const position = this.readPosition(address, thread);
      if (position !== null && position >= n) return;
      const answer = yield* this.requests.call(StationAddr.parse(address), "PUT", `/threads/${thread}/read`, { n }, { ctx });
      this.putRead(address, thread, u64(get(answer, "n")) ?? n);
    });
  }

  /// How far the viewer has read a thread, as its summary says.
  readPosition(address: string, thread: number): number | null {
    return this.#core.data.readPosition(address, thread);
  }

  /// Uploads, files, previews (station/transport.rs), by address.
  upload(address: string, name: string, bytes: Uint8Array, ctx: SpanContext | null) {
    return Effect.flatMap(Effect.try({ try: () => StationAddr.parse(address), catch: asCoreError }), (addr) => this.requests.upload(addr, name, bytes, ctx));
  }

  /// A station's error as this module says one.
  static error(status: number, data: unknown): CoreError {
    return httpError(status, data);
  }

  /// The body of a reply, whole (for those who hold a reply).
  static body = readAll;

  /// Lets go of every link (the core closes).
  close(): void {
    this.relays.close();
    this.#links.close();
  }

  /// A link scope's fibers are interrupted with it.
  static scope = Scope;
  static exit = Exit;
  static join = join;
}
