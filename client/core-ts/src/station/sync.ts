// What the core keeps in sync with the stations, by itself, whatever the UI shows (rule 6; station.rs
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
import { Deferred, Effect, Exit, Scope, type Fiber } from "effect";
import type { Inner } from "../core.ts";
import { join } from "../data.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { encode, type Effect as OpEffect, type Request } from "../ops.ts";
import { topicKey, type Topic } from "../protocol.ts";
import { Kind, type SpanContext } from "../trace.ts";
import { equal, get, isObject, parseJson } from "../util.ts";
import { Priority } from "../sync/scheduler.ts";
import * as present from "../present.ts";
import { activity as historyActivity } from "../history.ts";
import { StationAddr } from "./addr.ts";
import { IDEMPOTENCY_KEY, JSON_IDLE_MS, READS, Requests, httpError } from "./requests.ts";
import { digest } from "../digest.ts";
import { logged } from "../log-lines.ts";
import { type Channel, Channels } from "../channels/channels.ts";
import { ENTRIES, LETTERS, PAGE, TRANSCRIPT, TRANSCRIPT_PAGE, entriesOf, heldIn, lettersOf, transcriptOf } from "./channel-kinds.ts";
import { type HistoryRead, type Link, Links, type LiveView, MEMORY, RECONNECT_MAX_MS, PRESETS, filePeekKey, linkPreviewKey, logKey, messagePeekKey } from "./link.ts";
import { concat, readAll, replyHeader, type StationWire } from "./wire.ts";
import { SseParser } from "../sse.ts";
import * as logins from "./machine-logins.ts";
import { Relays } from "./machine-logins.ts";
import { Retold } from "./retold.ts";
import { Seen } from "./seen.ts";
import { dayOf, holdsWhole, sameDetailCoverage, usageHistoryRange, withPart } from "./usage-part.ts";
import { threadAfter, threadAfterLetters } from "./thread-after.ts";
import { type Marks, OwnHeld, markDismissed, markPin, markRead, markThread, marksOf, marksPut, rowShared, rowWords, rowsMade, rowsShared, sharedPlace, sharedWhole } from "./rows-made.ts";
import { timed } from "../spent.ts";
import { glanced } from "../work.ts";
import { isOwnSurface } from "../titles.ts";

export { HOST_KEY, LINK_KEY, LONG_MISSES, MISSES, OFFLINE_RETRY_MS, RECONNECT_MAX_MS, RECONNECT_MS, STREAM_IDLE_MS, STREAM_QUIET_MS, Link } from "./link.ts";
export type { EventsFor, LiveView } from "./link.ts";

/// A burst of `thread` events becomes one read of each thread's summary.
export const EVENTS_COALESCE_MS = 400;
export { PAGE, TRANSCRIPT_PAGE };
export const RECHECK_MS = 5 * 60 * 1000;
/// A read that failed in passing (a 5xx, the link dropping) is tried again after this, doubling, this many times.
export const READ_RETRY_MS = 2_000;
export const READ_RETRIES = 5;
/// How long a read that failed `n` times in a row before waits to be asked again: twice as long each time, at most
/// RECONNECT_MAX_MS.
export const retryAfter = (n: number): number => Math.min(READ_RETRY_MS * 2 ** Math.min(n, 10), RECONNECT_MAX_MS);
/// The field naming a row of each list read whole that may be asked as what changed of it (POST /changed/<list>).
const LIST_ID: Record<string, string> = { chatRows: "id", archivedRows: "id", threads: "id", sessions: "key" };
/// A station from before POST /changed/<list> reads its lists whole, and is tried again after this.
export const CHANGES_RETRY_MS = 3_600_000;
/// How much of a station's history one batch asks (POST /batch, #history): a page of entries or a session's detail is
/// one, a page of a transcript (200 steps in brief) five (each channel's kind says, channel-kinds.ts).
export const HISTORY_BATCH = 40;
/// Background history work shares the engine with page input. Give other work a turn after a small slice, and sooner
/// when a few large answers already took time. The count also bounds work when a test's clock is stopped. A slice's
/// turn is the store's (`turn`): while a page waits for its first value, the next slice waits till it has gone out.
const HISTORY_SLICE_ITEMS = 64;
const HISTORY_SLICE_MS = 8;
const HISTORY_SESSION_GROUP = 32;
/// A session's detail as the device reads it: without its turns. Its summary says how many it had, how long they ran and
/// its latest (db/account.ts `counted`), what its every turn was read for; a station from before lists them all.
/// And its jobs that may matter now (`jobs=now`: those up, and its latest), what its list shows (jobs.ts `isCurrent`).
const sessionPath = (key: string) => `/sessions/${encode(key)}?turns=0&jobs=now`;

export const RECHECKING = "等它回来确认";
/// The station's events that change what a search of it finds.
/// The station's open jobs, without the chat each is in: named here from the sidebar held (views.ts `longJobs`); a
/// station from before names them all the same.
const JOBS = "/jobs?chats=0";
const SEARCHED = new Set(["session", "session-removed", "thread", "thread-removed", "job", "job-removed"]);
/// The station's events that say what its reads bring too: told again on top of what a read asked before them brought
/// (retold.ts).
const RETOLD = new Set(["session", "session-pending", "session-removed", "thread-removed", "read", "chat-shared", "chat-shared-removed", "job", "job-removed", "overview", "pin", "dismiss", "kept", "hidden", "muted"]);
const SHARED_RETOLD = new Set(["chat-shared", "chat-shared-removed"]);

/// Which rows of a list its station makes for everyone a change makes again (#remake): those of their ids (a row's id
/// is its agent's session key), of their threads, or all of them.
type Rows = { ids?: readonly string[]; threads?: readonly number[]; whole?: boolean };

/// How long the words of a search stay as they are before the stations are asked what they find.
export const SEARCH_SETTLE_MS = 150;
/// A station's changes ask the searches of it shown again at most this often: a busy station tells of its chats many
/// times a second, each search asked again a search of the machine's files there.
export const SEARCH_STALE_MS = 2_000;
/// How long after a station's resources stream ended it is opened again; and how long one that tells them is waited on
/// after its last before the stream is taken for gone.
export const RESOURCES_EVERY_MS = 5_000;
const RESOURCES_SILENT_MS = 4 * RESOURCES_EVERY_MS;

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
/// A row's id as text (sessions' and chats' are strings, threads' numbers).
const idText = (v: unknown): string | null => (typeof v === "string" ? v : typeof v === "number" ? String(v) : null);

/// One `step` event, as useLiveSession applies it. `held`: how far the transcript held here goes (its last item's number
/// and one), kept with a step as it ends.
export function applyStep(view: LiveView, event: unknown, now: number, held = 0): void {
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
    // On new steps: the ones there are in the live topic's value as it was made (shared).
    view.steps = view.steps.map((s) => (equal(get(s, "id"), id) && isObject(s) ? { ...s, ended: true, held } : s));
  }
}

/// Whether a step is still to be shown, the transcript held here going as far as `held`: one in flight is; one that
/// ended, until what is held goes past where it went as the step ended (the entry that records it is in by then, however
/// it came: told on the stream or read).
export function stepShown(step: unknown, held: number): boolean {
  if (get(step, "ended") !== true) return true;
  const at = get(step, "held");
  return typeof at === "number" && held <= at;
}

/// How long a folder's watch waits before opening its stream again after it failed: doubling, up to WATCH_AGAIN_MAX_MS.
const WATCH_AGAIN_MS = 1_000;
const WATCH_AGAIN_MAX_MS = 30_000;

export class StationsSync {
  /// Reads held on the device that their station has not taken yet (`read`), by `<address>\u0001<thread>`.
  readonly #heldReads = new Map<string, number>();
  readonly #core: Inner;
  readonly requests: Requests;
  /// What its stations hold that is only added to (threads' entries, sessions' transcripts), kept in sync by number.
  readonly channels: Channels;
  /// Its stations' links: their streams, opened and tried again (link.ts).
  readonly #links: Links;
  /// What their streams told while a read was out, to tell again on top of what it brings.
  readonly #retold = new Retold();
  /// Tells of a row while its post-restore read is out invalidate that answer.
  readonly #restoreVersions = new Map<string, number>();
  /// The transcripts of the histories shown whose reads failed, how many times in a row.
  readonly #transcriptMisses = new Map<string, number>();
  readonly #transcriptAgain = new Set<string>();
  /// The stations whose searches shown are to be asked again once SEARCH_STALE_MS is up.
  readonly #staleSearches = new Set<string>();
  /// A usage preparation can take many bounded batches; it has its own cancellable stream, outside the sync lane.
  readonly #usageReading = new Map<string, { link: Link; fiber: Fiber.Fiber<void, never> | null }>();
  /// What the station topics want of a stream beyond what the sync wants (host samples, logs, sessions shown).
  wanted: (address: string) => { host: boolean; logs: [string, number][]; logins?: string[] } = () => ({ host: false, logs: [] });
  /// What a station holds beyond the records (link, live views, host, logs), as its readers see it change.
  readonly seen = new Seen();
  /// Told when what a station holds beyond the records changed, after its readers (`seen`).
  onTouched: (address: string, what: "link" | "live" | "host" | "log" | "errors" | "screens" | "logins" | "loginScreen", key?: string) => void = () => {};

  onChange(address: string, what: "link" | "live" | "host" | "log" | "errors" | "screens" | "logins" | "loginScreen", key?: string): void {
    this.seen.touch(address, what === "errors" ? "log" : what, key);
    this.onTouched(address, what, key);
    if (what === "link") {
      const waiting = this.#linkWaits.get(address);
      this.#linkWaits.delete(address);
      if (waiting) Deferred.doneUnsafe(waiting, Effect.void);
    }
  }

  /// Those waiting for a station's link to change (`#linkChange`).
  readonly #linkWaits = new Map<string, Deferred.Deferred<void>>();

  /// Until the station's link changes (it came up, say).
  #linkChange(address: string): Effect.Effect<void> {
    let waiting = this.#linkWaits.get(address);
    if (!waiting) {
      waiting = Deferred.makeUnsafe<void>();
      this.#linkWaits.set(address, waiting);
    }
    return Deferred.await(waiting);
  }
  /// The loopback relays of logins this device takes the callback of.
  readonly relays: Relays;
  /// Told of entries that came as they were said (an event): they come in with a motion.
  onTold: (address: string, id: number, entries: unknown[]) => void = () => {};
  /// What other parts read of a station whenever it is read again (its stream opened afresh), each a task of its own
  /// (the vault's: views/vault.ts); and hear of its events they know.
  readonly also: { read(address: string): Effect.Effect<void, CoreError>; event(address: string, name: string, data: unknown): void; resume?: boolean }[] = [];

  constructor(core: Inner, wire: StationWire) {
    this.#core = core;
    this.requests = new Requests(core, wire);
    this.#links = new Links(core, this.requests, {
      wanted: (address) => this.wanted(address),
      afresh: (address, ctx) => this.snapshot(address, ctx),
      goesOn: (address, how) => this.#goesOn(address, how),
      event: (address, name, raw, again) => this.onEvent(address, name, raw, again),
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
    this.channels = new Channels(heldIn(core.data), {
      read: (station, path, options) => Effect.suspend(() => this.requests.call(this.#links.get(station)?.addr ?? StationAddr.parse(station), "GET", path, null, options)),
      reached: (station) => this.#links.has(station) && this.reachable(station),
      enqueue: (station, task, priority, work) => this.#enqueue(station, task, priority, work),
      later: (station, work) => {
        const link = this.#links.get(station);
        if (link) core.runner.fork(Effect.sleep(EVENTS_COALESCE_MS).pipe(Effect.andThen(work)), link.scoped);
        else core.runner.fork(work);
      },
      now: () => core.host.monotonicMs(),
      firstWaiting: () => core.store.firstValuesPending(),
      turn: () => core.store.turn(),
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
    if (how.away || how.restored) this.checkRestores(address);
    if (how.away || how.restored) this.#catchingFrom(address);
    if (how.away) this.#catchUpShown(address);
    // Its screens and its logins are held in its link's memory, not its log of events (what was kept of them shows
    // meanwhile): its screens read again whenever the stream was not there to hear them change, both once a run.
    const memory = this.#links.get(address)?.memory;
    if (how.away || how.restored || memory?.fresh("screens") !== true) this.#enqueue(address, "screens", Priority.background, this.#screens(address));
    if (memory?.fresh(logins.HELD) !== true) this.#enqueue(address, "machineLogins", Priority.background, this.#machineLogins(address));
    // A part's kept data may have been written by an older core or station. A resumed stream only tells what changed
    // since its cursor; parts that need a fresh whole read ask for one after an absence.
    if (how.away || how.restored) for (const [i, part] of this.also.entries()) if (part.resume) this.#enqueue(address, `also/${i}`, Priority.background, part.read(address));
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
    this.checkRestores(address);
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
      this.#enqueue(address, "chats", p, Effect.andThen(this.#chats(address, ctx, unread), Effect.sync(() => this.openEvents(address, false)))),
      ...(link?.shared ? [this.#enqueue(address, "shared", p, this.#sharedWhole(address, ctx, unread))] : []),
      ...this.#archivedChanged(address, ctx),
      this.#enqueue(address, "jobs", p, read({ topic: "jobs", station: address }, JOBS)),
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
  /// not hold yet is found in its session's detail (its threads); of a station not linked, nothing is read. Done once
  /// it is held, or could not be read.
  bringPushed(address: string, session: string, seq: number | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const bound = () => {
        const thread = get(this.#core.data.chatOfSession(address, session), "thread");
        return typeof thread === "number" ? thread : this.#core.data.threadOf(address, session);
      };
      let thread = bound();
      if (thread === null) {
        yield* this.ask(address, `session/${session}`, this.#session(address, session));
        const threads = get(this.#core.data.get({ topic: "session", station: address, key: session }), "threads");
        thread = bound() ?? (Array.isArray(threads) ? threads.map((t) => u64(get(t, "id"))).find((id) => id !== null) ?? null : null);
      }
      if (thread !== null) yield* this.channels.pushed(entriesOf(address, thread), seq, Priority.focused);
    });
  }

  /// The station's stream was away: the threads a UI shows are asked what was said in them after what is held, and the
  /// drive's folders shown are read again (one never read while the station was down is read now).
  #catchUpShown(address: string): void {
    for (const topic of this.#core.store.liveTopics()) {
      if (topic.station !== address) continue;
      if (topic.topic === "thread" && typeof topic.thread === "number") {
        this.channels.catchUp(entriesOf(address, topic.thread), Priority.shown);
        // An opening around an unread or saved position may still be missing even if a later page is held. Recompute it
        // so its failed range read is asked again, independently of whether the catch-up read brings anything new.
        this.#core.store.invalidate(topic);
      }
      // A history shown: its first read may have failed while the stream was away, and the station tells nothing of one
      // at rest, so it would wait for ever.
      else if (topic.topic === "live") this.channels.bring(transcriptOf(address, String(topic.key)), Priority.shown, "latest");
      else if (topic.topic === "drive" && this.#core.store.inUse(topic)) this.driveShown(address, String(topic.root), String(topic.path));
    }
  }

  /// The station's screens as it has them now, in its link's memory (kept: what was said last
  /// shows as the app opens again, until they are read). A station from before screens has none (404): it is held so,
  /// and said (`outdated`).
  #screens(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/screens", null, { quiet: true, ctx }));
      if (answer._tag === "Success") this.#heldScreens(address, { screens: Array.isArray(get(answer.success, "screens")) ? (get(answer.success, "screens") as unknown[]) : [], outdated: false, ...(get(answer.success, "browser") === true ? { browser: true } : {}) });
      else if (answer.failure.status === 404) this.#heldScreens(address, { screens: [], outdated: true });
      else return yield* Effect.fail(answer.failure);
    });
  }

  #heldScreens(address: string, held: { screens: unknown[]; outdated: boolean; browser?: boolean }): void {
    const link = this.#links.get(address);
    if (!link) return;
    link.memory.set("screens", held);
    this.onChange(address, "screens");
  }

  /// What is held of the station's screens; undefined while it has not said. A tab this device is opening
  /// (`#openingTabs`) is among them until the station lists it, said `opening`.
  screens(address: string): { screens: unknown[]; outdated: boolean; browser?: boolean } | undefined {
    const held = this.#links.get(address)?.memory.get("screens") as { screens: unknown[]; outdated: boolean; browser?: boolean } | undefined;
    const opening = this.#openingTabs.get(address);
    if (held === undefined || opening === undefined || opening.size === 0) return held;
    // (the same object while neither changed: the views compare what they read by reference first)
    const kept = this.#screensWithOpening.get(address);
    if (kept !== undefined && kept.held === held && kept.opening === opening) return kept.value;
    const listed = new Set(held.screens.map((s) => get(s, "id")));
    const more = [...opening.values()].filter((s) => !listed.has(s.id));
    const value = more.length === 0 ? held : { ...held, screens: [...held.screens, ...more] };
    this.#screensWithOpening.set(address, { held, opening, value });
    return value;
  }

  /// The tabs of each station's browser this device is opening (`screen.openBrowser` with an id), by their screen id.
  /// Replaced whole as one comes or goes (so the merged list above is made again).
  readonly #openingTabs = new Map<string, Map<string, { id: string; kind: "browser"; title: string; width: 0; height: 0; viewers: []; controlledBy: []; userTab: true; opening: true; closable: true; openUrl: true }>>();
  readonly #screensWithOpening = new Map<string, { held: unknown; opening: unknown; value: { screens: unknown[]; outdated: boolean; browser?: boolean } }>();

  #tabOpening(address: string, screen: string, on: boolean): void {
    const next = new Map(this.#openingTabs.get(address) ?? []);
    if (on) next.set(screen, { id: screen, kind: "browser", title: "", width: 0, height: 0, viewers: [], controlledBy: [], userTab: true, opening: true, closable: true, openUrl: true });
    else next.delete(screen);
    if (next.size === 0) this.#openingTabs.delete(address);
    else this.#openingTabs.set(address, next);
    this.onChange(address, "screens");
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

  /// The workspace's presets on the station (GET /presets, the `presets` topic), read as a page shows them (with the
  /// directories offered for a new one, which change as its chats work), and as one is made, changed or removed; what
  /// was read last shows meanwhile.
  presetsShown(address: string): void {
    this.#enqueue(address, "presets", Priority.shown, this.#presets(address));
  }

  #presets(address: string): Effect.Effect<void, CoreError> {
    const key = topicKey({ topic: "presets", station: address });
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/presets", null, { quiet: true }));
      if (answer._tag === "Success") {
        link.errors.delete(key);
        link.memory.set(PRESETS, answer.success);
        this.onChange(address, "log", key);
      } else if (answer.failure.status !== undefined && !link.memory.has(PRESETS)) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    });
  }

  /// The presets as the station said them last; undefined while it has not.
  presets(address: string): unknown {
    return this.#links.get(address)?.memory.get(PRESETS);
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

  /// One message of a chat a link names (GET /threads/:id/entries of that entry alone, the `messagePeek` topic), read as
  /// its card shows it (cardShown).
  messagePeekShown(address: string, thread: number, seq: number): void {
    this.#cardShown(address, { topic: "messagePeek", station: address, thread, seq }, `/threads/${thread}/entries?from=${seq}&to=${seq}`, messagePeekKey(thread, seq));
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
      } else if (answer.failure.status !== undefined && (topic.topic === "filePeek" || !link.memory.has(kept))) {
        // A path may no longer exist (or be readable). Its previous preview must not conceal the station's answer.
        if (topic.topic === "filePeek") link.memory.delete(kept);
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    }));
  }

  /// A job's log as it is now (its `lines` last lines), once a run: its topic opened (what was kept of it shows
  /// meanwhile). The station's stream says how it grows from then on (an older station's does not: its log is as it was
  /// when opened).
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
          link.memory.set(key, logged(link.memory.get(key), str(get(answer, "text")) ?? "", get(answer, "outputAt") ?? null));
          this.onChange(address, "log", topicKey({ topic: "jobLog", station: address, job, lines }));
        }
      }),
    );
  }

  /// What a search finds on the station (`stationSearch`): asked a moment after the words stop changing
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
      if (topic.archived === true) params.push("archived=1");
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
      const answer = yield* Effect.result(shape ? Effect.map(this.requests.call(link.addr, "GET", path, null, { quiet: true, ctx }), (value) => ({ value: shape(value), changed: undefined })) : this.#whole(link, topic, path, ctx));
      const key = topicKey(topic);
      if (answer._tag === "Success") {
        link.errors.delete(key);
        this.#core.data.set(topic, answer.success.value, true, answer.success.changed);
        if (topic.topic === "jobs" && !link.jobsRead) {
          link.jobsRead = true;
          this.onChange(address, "link");
        }
        this.#retell(address, read);
        // (a list its station makes reads neither)
        if (topic.topic === "sessions" || topic.topic === "threads") this.#remake(address, {});
        if (topic.topic === "sessions") this.unlisted(address);
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
  /// wait. A station from before is asked the list whole (and tried again after CHANGES_RETRY_MS). `changed`: the keys of
  /// the rows it sent, the rest being as held (none where it was read whole), so that only those are compared with what
  /// is written (account.ts setSessions, setThreads).
  #whole(link: Link, topic: Topic, path: string, ctx: SpanContext | null): Effect.Effect<{ value: unknown; changed: ReadonlySet<string> | undefined }, CoreError> {
    const whole = Effect.map(this.requests.call(link.addr, "GET", path, null, { quiet: true, ctx }), (value) => ({ value, changed: undefined }));
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
      const sent = new Set<string>();
      for (const row of changed) {
        const key = idText(get(row, id));
        if (key === null) continue;
        rows.set(key, row);
        sent.add(key);
      }
      const list: unknown[] = [];
      for (const key of order) {
        const row = rows.get(idText(key) ?? "");
        // Neither held nor sent: read whole.
        if (row === undefined) return yield* whole;
        list.push(row);
      }
      return { value: list, changed: sent };
    });
  }

  /// The station's logins, read whole: in its link's memory, as its stream then tells them. A
  /// station from before them answers 404: it has none (the page offers none).
  #machineLogins(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/machine-logins", null, { quiet: true, ctx }));
      if (answer._tag === "Success") logins.putList(link, answer.success);
      else if (answer.failure.status === 404) logins.unsupported(link);
      // (the station's no: what its logins' topics answer while none is kept, till a read is answered)
      else if (answer.failure.status !== undefined) link.errors.set(logins.LIST_KEY, answer.failure);
      else return;
      if (answer._tag === "Success" || answer.failure.status === 404) link.errors.delete(logins.LIST_KEY);
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
  /// was most of what a slow link carried. `from`: when the earliest call recorded since was made, as the station said
  /// (only the days from then on are read again); null: all of it. The read asked for, if any.
  #usageChanged(address: string, ctx: SpanContext | null = null, from: number | null = null): Deferred.Deferred<void, CoreError>[] {
    const link = this.#links.get(address);
    if (link) {
      link.usageCurrent = false;
      link.usageFrom = from === null || link.usageFrom === null ? null : Math.min(link.usageFrom ?? Infinity, from);
    }
    if (!this.#core.store.inUse({ topic: "stationUsage", station: address })) return [];
    if (this.#usageReading.get(address)?.link === link) return [];
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

  /// The station's archive, read a page at a time from its latest (`?page=`, its next where the one before ended): each
  /// page put in with what is held of those older than it, until its end, then what was read alone. Read whole at once,
  /// the archive of many chats took 60 s on a station, every other read of devices waiting (2026-11-03). A station from
  /// before pages none: its answer, the whole list, is put in as it was. A page not answered is asked again a little later
  /// (as `#read`); given up on, what was read stays, said to fall short (`archiveFailed`), and it is read again as it is shown again.
  #archived(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const link = this.#links.get(address);
      if (link) {
        link.archivedCurrent = true;
        link.archiveReading = true;
        link.archiveFailed = null;
        this.onChange(address, "link");
      }
      const topic = { topic: "archivedRows", station: address };
      return this.#archivedFrom(address, topic, "", [], ctx);
    });
  }

  #archivedFrom(address: string, topic: Topic, page: string, read: unknown[], ctx: SpanContext | null, attempt = 0): Effect.Effect<void, CoreError> {
    return this.#asked((asked) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link) return;
      const stopped = (why: string | null) => {
        link.archivedCurrent = false;
        link.archiveReading = false;
        link.archiveFailed = why;
        this.onChange(address, "link");
      };
      if (!this.reachable(address)) return stopped(null);
      const said = yield* Effect.result(this.requests.call(link.addr, "GET", `/chats?archived=1&page=${encode(page)}`, null, { quiet: true, ctx }));
      if (said._tag === "Failure") {
        const { status, message } = said.failure;
        if ((status !== undefined && status < 500) || attempt >= READ_RETRIES) return stopped(message);
        const again = Effect.sleep(READ_RETRY_MS * 2 ** attempt).pipe(
          Effect.andThen(Effect.sync(() => void this.#enqueue(address, `archived/${page}`, Priority.background, this.#archivedFrom(address, topic, page, read, null, attempt + 1)))),
        );
        this.#core.runner.fork(again, link.scoped);
        return;
      }
      const answer = said.success;
      const key = topicKey(topic);
      link.errors.delete(key);
      if (Array.isArray(answer)) {
        link.archiveReading = false;
        this.#core.data.set(topic, answer);
        this.#retell(address, asked);
        this.onChange(address, "link");
        return;
      }
      // A page's rows are all that its items touch, so a chat of several agents can be in more than one page: once.
      const seen = new Set(read.map((r) => str(get(r, "id"))));
      const rows = [...read];
      for (const r of arr(get(answer, "rows"))) {
        if (seen.has(str(get(r, "id")))) continue;
        seen.add(str(get(r, "id")));
        rows.push(r);
      }
      const next = str(get(answer, "next"));
      const end = next === null ? null : Number(next.slice(0, next.indexOf(":")));
      const held = end === null ? [] : arr(this.#core.data.shared(topic)).filter((r) => !seen.has(str(get(r, "id"))) && (u64(get(get(r, "archived"), "at")) ?? 0) < end);
      if (next === null) link.archiveReading = false;
      this.#core.data.set(topic, [...rows, ...held]);
      this.#retell(address, asked);
      if (next === null) this.onChange(address, "link");
      else this.#enqueue(address, `archived/${next}`, Priority.background, this.#archivedFrom(address, topic, next, rows, null));
    }));
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
  /// machine): the station tells of each change on a stream (GET /drive/watch as events), and the folder is read again.
  /// The stream is opened as the station is reached; one that ended is opened again, the folder read then for what
  /// changed meanwhile. A station from before streaming it, or a folder gone, refuses it: then it is read only as shown.
  /// What still.fail uses of the station's machine now (GET /resources), while shown (a fiber of the topic's,
  /// topics.ts) and a page of the app is in view: the station tells it as it looks, on a stream of its own (asked as
  /// events), opened again RESOURCES_EVERY_MS after it ends. A station from before answers it once instead, and one
  /// that has none says so (its refusal): either is what is shown, not asked again on a timer.
  resourcesWatch(address: string): Effect.Effect<void, never> {
    const key = topicKey({ topic: "stationResources", station: address });
    const attend = this.#core.attention?.attend;
    const told = (link: Link, value: unknown) => {
      link.errors.delete(key);
      link.memory.set(key, value);
      this.onChange(address, "log", key);
    };
    /// Follows the station's stream; false once there is nothing to follow (a refusal, a station from before streams).
    const follow = Effect.scoped(
      Effect.gen({ self: this }, function* () {
        const link = this.#links.get(address);
        if (!link || !this.reachable(address)) return true;
        const opened = yield* Effect.result(this.requests.stream(link.addr, "/resources", null));
        if (opened._tag === "Failure") {
          const status = opened.failure.status;
          if (status !== undefined && status < 500) {
            link.errors.set(key, opened.failure);
            this.onChange(address, "errors", key);
            return false;
          }
          return true;
        }
        const reply = opened.success;
        // From before: what it is now, once.
        if (!(replyHeader(reply, "content-type") ?? "").startsWith("text/event-stream")) {
          const bytes = yield* Effect.result(readAll(reply.body));
          const value = bytes._tag === "Success" ? parseJson(bytes.success) : undefined;
          if (value !== undefined) told(link, value);
          return false;
        }
        const parser = new SseParser();
        const silent = Effect.sleep(RESOURCES_SILENT_MS).pipe(Effect.as(null));
        for (;;) {
          const next = yield* Effect.raceFirst(Effect.result(reply.body.take), silent);
          if (next === null || next._tag === "Failure" || next.success === null) return true;
          for (const [name, data] of parser.feed(next.success)) {
            const value = name === "resources" ? parseJson(data) : undefined;
            if (value !== undefined) told(link, value);
          }
        }
      }),
    );
    // (not while no page of the app is in view: a phone in a pocket asks nothing)
    const whileShown = attend
      ? Effect.andThen(Effect.suspend(() => attend.untilShown()), Effect.raceFirst(follow, Effect.as(Effect.suspend(() => attend.untilHidden()), true)))
      : follow;
    return Effect.gen(function* () {
      while (yield* whileShown) yield* Effect.sleep(RESOURCES_EVERY_MS);
    });
  }

  driveWatch(address: string, root: string, path: string): Effect.Effect<void, never> {
    const asked = `/drive/watch?root=${encode(root)}&path=${encode(path)}`;
    // (asked when it runs: `ask` asks as it is called)
    const read = Effect.suspend(() => Effect.ignore(this.ask(address, `drive/${root}/${path}`, this.#drive(address, root, path)), { log: "Unhandled", message: "drive read" }));
    return Effect.gen({ self: this }, function* () {
      let wait = WATCH_AGAIN_MS;
      let opened = 0;
      for (;;) {
        const link = this.#links.get(address);
        if (!link || !this.reachable(address)) {
          yield* this.#linkChange(address);
          continue;
        }
        const ended = yield* Effect.scoped(
          Effect.gen({ self: this }, function* () {
            const reply = yield* Effect.result(this.requests.stream(link.addr, asked, null));
            if (reply._tag === "Failure") {
              const status = reply.failure.status;
              return status !== undefined && status >= 400 && status < 500 ? ("refused" as const) : ("failed" as const);
            }
            if (!(replyHeader(reply.success, "content-type") ?? "").startsWith("text/event-stream")) return "refused" as const;
            wait = WATCH_AGAIN_MS;
            // Opened again: what changed while none was open is read now.
            if (opened++ > 0) yield* read;
            const parser = new SseParser();
            for (;;) {
              const next = yield* Effect.result(reply.success.body.take);
              if (next._tag === "Failure" || next.success === null) return "ended" as const;
              if (parser.feed(next.success).some(([name]) => name === "changed")) yield* read;
            }
          }),
        );
        if (ended === "refused") return;
        yield* Effect.raceFirst(Effect.sleep(wait), this.#linkChange(address));
        wait = Math.min(wait * 2, WATCH_AGAIN_MAX_MS);
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

  /// A topic kept after its last viewer is eventually stopped. A preparation which is still open goes with it.
  usageHidden(address: string): void {
    const active = this.#usageReading.get(address);
    if (!active) return;
    this.#usageReading.delete(address);
    active.link.usageCurrent = false;
    active.link.usageFrom = null;
    if (active.fiber) this.#core.runner.interrupt(active.fiber);
  }

  /// A stream tells the independent history while preparing recent details, then the complete read. Events received
  /// in between only mark the earliest changed day; after the complete answer that part is read once more. The wait
  /// does not hold a sync lane or retain unrelated station events, and leaving it closes its request scope.
  #usageRead(address: string, topic: Topic, path: string, shape?: (answer: unknown) => unknown,
    ctx: SpanContext | null = null, attempt = 0): Effect.Effect<void, CoreError> {
    return Effect.sync(() => {
      const link = this.#links.get(address);
      if (!link) return;
      if (!this.reachable(address) || !this.#core.store.inUse(topic)) {
        link.usageCurrent = false;
        link.usageFrom = null;
        return;
      }
      const previous = this.#usageReading.get(address);
      if (previous?.link === link) return;
      if (previous?.fiber) this.#core.runner.interrupt(previous.fiber);
      const active: { link: Link; fiber: Fiber.Fiber<void, never> | null } = { link, fiber: null };
      this.#usageReading.set(address, active);
      const stillHere = () => this.#links.get(address) === link && this.#usageReading.get(address) === active;
      const timeout = () => new CoreError("timeout", t("core-logic.mesh.timed_out"));
      const read = Effect.scoped(Effect.gen({ self: this }, function* () {
        const reply = yield* Effect.timeoutOrElse(this.requests.stream(link.addr, path, ctx), {
          duration: JSON_IDLE_MS, orElse: () => Effect.fail(timeout()),
        });
        const take = () => Effect.timeoutOrElse(Effect.mapError(reply.body.take, asCoreError), {
          duration: JSON_IDLE_MS, orElse: () => Effect.fail(timeout()),
        });
        const told = (value: unknown) => {
          if (!stillHere() || !this.#core.store.inUse(topic)) return false;
          link.errors.delete(topicKey(topic));
          this.#core.data.set(topic, shape ? shape(value) : value);
          return true;
        };
        if (!(replyHeader(reply, "content-type") ?? "").startsWith("text/event-stream")) {
          // A station from before streams answers with its ordinary complete JSON.
          const chunks: Uint8Array[] = [];
          for (;;) {
            const chunk = yield* take();
            if (chunk === null) break;
            chunks.push(chunk);
          }
          const value = parseJson(concat(chunks));
          if (value === undefined) return yield* Effect.fail(new CoreError("bad_response", t("station.core.invalidReply")));
          return told(value);
        }
        const parser = new SseParser();
        for (;;) {
          const chunk = yield* take();
          if (!stillHere() || !this.#core.store.inUse(topic)) return false;
          if (chunk === null) return yield* Effect.fail(new CoreError("bad_response", t("station.core.invalidReply")));
          for (const [name, data] of parser.feed(chunk)) {
            if (name === "error") {
              const failure = parseJson(data);
              const status = get(failure, "status");
              return yield* Effect.fail(httpError(typeof status === "number" ? status : 500, get(failure, "body")));
            }
            if (name !== "usage") continue;
            const value = parseJson(data);
            if (value === undefined) return yield* Effect.fail(new CoreError("bad_response", t("station.core.invalidReply")));
            if (!told(value)) return false;
            if (get(value, "detailsPreparing") !== true) return true;
          }
        }
      }));
      const work = Effect.gen({ self: this }, function* () {
        const answer = yield* Effect.result(read);
        if (!stillHere()) return;
        if (answer._tag === "Success" && answer.success) {
          this.#usageReading.delete(address);
          if (!link.usageCurrent && this.#core.store.inUse(topic)) this.#enqueue(address, "usage", Priority.background, this.#usage(address));
          return;
        }
        link.usageCurrent = false;
        link.usageFrom = null;
        if (answer._tag === "Success") { this.#usageReading.delete(address); return; }
        const key = topicKey(topic), status = answer.failure.status;
        if (status !== undefined && status >= 400 && status < 500) {
          this.#usageReading.delete(address);
          this.#core.data.forgetTopic(topic);
          link.errors.set(key, answer.failure);
          this.onChange(address, "errors", key);
        } else if (this.#core.store.inUse(topic)) {
          const delay = Math.min(READ_RETRY_MS * 2 ** Math.min(attempt, 4), 30_000);
          // Remain the one active read during the delay: usage events are coalesced instead of bypassing backoff.
          yield* Effect.sleep(delay);
          if (stillHere()) {
            this.#usageReading.delete(address);
            if (this.#core.store.inUse(topic)) this.#enqueue(address, "usage", Priority.background, this.#usage(address, null, attempt + 1));
          }
        }
      }).pipe(Effect.ensuring(Effect.sync(() => {
        if (this.#usageReading.get(address) === active) this.#usageReading.delete(address);
      })));
      active.fiber = this.#core.runner.fork(work, link.scoped);
    });
  }

  /// What the station's agents spent over the last 60 days, days as this device's clock has them: the usage page's 30 at
  /// most and as many before, to say its totals against (views/usage.ts); and everything since it began counting by
  /// day (`history`: the page's summary, views/usage-summary.ts). Current from when it is asked: a change said
  /// meanwhile has it read again. Held whole for these same days, only the days a change since touched are read again
  /// (usage-part.ts), from the earliest call the station said it recorded.
  #usage(address: string, ctx: SpanContext | null = null, attempt = 0): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const link = this.#links.get(address);
      if (link && this.#usageReading.get(address)?.link === link) return Effect.void;
      const changed = link?.usageFrom;
      if (link) {
        link.usageCurrent = true;
        link.usageFrom = undefined;
      }
      const now = this.#core.host.nowMs();
      const offset = this.#core.host.utcOffsetMin(now);
      const from = dayOf(now, offset).from - 59 * 86_400_000;
      const topic: Topic = { topic: "stationUsage", station: address };
      if (typeof changed === "number" && changed >= from && holdsWhole(this.#core.data.shared(topic), from)) {
        const part = dayOf(changed, offset);
        const put = (answer: unknown) => {
          const held = this.#core.data.shared(topic);
          if (holdsWhole(held, from) && sameDetailCoverage(held, answer)) return withPart(held, answer, part.day, part.from);
          // What is held was let go meanwhile: read whole as it is shown next.
          if (link) {
            link.usageCurrent = false;
            link.usageFrom = null;
            this.#enqueue(address, "usage/coverage", Priority.shown, this.#usage(address));
          }
          return held;
        };
        return this.#usageRead(address, topic, `/usage?from=${part.from}&tz=${offset}`, put, ctx, attempt);
      }
      const range = usageHistoryRange(now, offset);
      const path = `/usage?from=${from}&tz=${offset}&history=1&historyFrom=${range.from}&historyTo=${range.to}`;
      return this.#usageRead(address, topic, `${path}&allowPartial=1`, undefined, ctx, attempt);
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
    const sweep = ++link.historySweep;
    this.#enqueue(address, `history/prepare/${sweep}`, Priority.background, Effect.gen({ self: this }, function* () {
      const reads = yield* this.#historyReads(address, link, sweep);
      if (reads === null || this.#links.get(address) !== link || link.historySweep !== sweep) return;
      link.historyAsked.clear();
      link.history = reads;
      this.#enqueue(address, "history", Priority.background, this.#history(address, 0));
    }));
  }

  #history(address: string, attempt: number): Effect.Effect<void, CoreError> {
    return this.#asked((asked) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      if (link.batchRefused !== null && this.#core.host.nowMs() - link.batchRefused < CHANGES_RETRY_MS) return yield* this.#historyEach(address);
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
          return yield* this.#historyEach(address);
        }
        // Not answered (its link went, say): asked again a little later, a few times.
        if ((e.status === undefined || e.status >= 500) && attempt < READ_RETRIES) {
          const again = Effect.sleep(READ_RETRY_MS * 2 ** attempt).pipe(Effect.andThen(Effect.sync(() => void this.#enqueue(address, "history", Priority.background, this.#history(address, attempt + 1)))));
          this.#core.runner.fork(again, link.scoped);
        }
        return;
      }
      let sliceAt = this.#core.host.monotonicMs();
      let sliced = 0;
      for (let i = 0; i < batch.length; i++) {
        // A link may have been let go while another task ran between answers.
        if (this.#links.get(address) !== link) return;
        const read = batch[i]!;
        const after = read.apply(answered.success[i]!);
        if (after !== null && !link.historyAsked.has(after.path)) link.history.push(after);
        sliced++;
        if (i + 1 < batch.length && (i === 1 || this.#core.store.firstValuesPending() || sliced >= HISTORY_SLICE_ITEMS || this.#core.host.monotonicMs() - sliceAt >= HISTORY_SLICE_MS)) {
          // A stream may have said something newer while the batch was away or between slices. Put it back before a
          // view can see this slice; later answers may overlap it too. A slice runs without anything else seeing it.
          this.#retell(address, asked);
          yield* this.#core.store.turn();
          sliceAt = this.#core.host.monotonicMs();
          sliced = 0;
        }
      }
      this.#retell(address, asked);
      // More to bring: asked again, behind what is more urgent.
      if (link.history.length > 0) this.#enqueue(address, "history", Priority.background, this.#history(address, 0));
    }));
  }

  /// What a station's history has yet to bring onto the device, in the order it is brought: each listed session's
  /// detail where its turns changed, each thread's next page of entries (the latest threads first), each listed
  /// session's latest page of its transcript where none is held.
  #historyReads(address: string, link: Link, sweep: number): Effect.Effect<HistoryRead[] | null> {
    return Effect.gen({ self: this }, function* () {
      if (this.#links.get(address) !== link || link.historySweep !== sweep) return null;
      const data = this.#core.data;
      const keys = data.sessionKeys(address);
      const sessions: [string, boolean][] = [];
      let sliceAt = this.#core.host.monotonicMs();
      let sliced = 0;
      for (let at = 0; at < keys.length; at += HISTORY_SESSION_GROUP) {
        if (this.#links.get(address) !== link || link.historySweep !== sweep) return null;
        const group = keys.slice(at, at + HISTORY_SESSION_GROUP);
        sessions.push(...data.sessionsToRead(address, group));
        sliced += group.length;
        if (at === 0 || this.#core.store.firstValuesPending() || sliced >= HISTORY_SLICE_ITEMS || this.#core.host.monotonicMs() - sliceAt >= HISTORY_SLICE_MS) {
          yield* this.#core.store.turn();
          sliceAt = this.#core.host.monotonicMs();
          sliced = 0;
        }
      }
      const reads: HistoryRead[] = [];
      for (const [key, again] of sessions) {
        if (this.#links.get(address) !== link || link.historySweep !== sweep) return null;
        if (again) {
          const topic = { topic: "session", station: address, key };
          reads.push({ path: sessionPath(key), cost: 1, apply: (a) => (this.#took(address, topic, a), null) });
        }
        if (this.#core.store.firstValuesPending() || ++sliced >= HISTORY_SLICE_ITEMS || this.#core.host.monotonicMs() - sliceAt >= HISTORY_SLICE_MS) {
          yield* this.#core.store.turn();
          sliceAt = this.#core.host.monotonicMs();
          sliced = 0;
        }
      }
      const channels = [...data.threadIds(address).map((id) => entriesOf(address, id)), ...sessions.map(([key]) => transcriptOf(address, key))];
      let visited = 0;
      for (const channel of channels) {
        if (this.#links.get(address) !== link || link.historySweep !== sweep) return null;
        const read = this.#channelRead(channel);
        if (read !== null) reads.push(read);
        // Finding the next page can read a chat's index from the database. Do not make a page being opened wait for
        // every other chat's index to be read first.
        if (visited++ === 0 || this.#core.store.firstValuesPending() || ++sliced >= HISTORY_SLICE_ITEMS || this.#core.host.monotonicMs() - sliceAt >= HISTORY_SLICE_MS) {
          yield* this.#core.store.turn();
          sliceAt = this.#core.host.monotonicMs();
          sliced = 0;
        }
      }
      return reads;
    });
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
    // A transcript read: what the station has of it is known (a history with nothing in it is not still loading). One
    // that failed is said, and asked again while it is shown: nothing else would ask (a stream that follows the sessions
    // at work tells nothing of one at rest, and it stays open).
    if (channel.kind === TRANSCRIPT) {
      if (error === null) this.#transcriptKnown(link, channel.id);
      else this.#transcriptFailed(link, channel.id, error);
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
  #historyEach(address: string): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link) return;
      const sweep = link.historySweep;
      link.history = [];
      const data = this.#core.data;
      const keys = data.sessionKeys(address);
      let at = this.#core.host.monotonicMs();
      let sliced = 0;
      for (let start = 0; start < keys.length; start += HISTORY_SESSION_GROUP) {
        if (this.#links.get(address) !== link || link.historySweep !== sweep) return;
        for (const [key, again] of data.sessionsToRead(address, keys.slice(start, start + HISTORY_SESSION_GROUP))) {
          if (again) this.#enqueue(address, `session/${key}`, Priority.background, this.#session(address, key));
          this.channels.bring(transcriptOf(address, key), Priority.background - 1);
          sliced++;
        }
        if (start === 0 || this.#core.store.firstValuesPending() || sliced >= HISTORY_SLICE_ITEMS || this.#core.host.monotonicMs() - at >= HISTORY_SLICE_MS) {
          yield* this.#core.store.turn();
          at = this.#core.host.monotonicMs();
          sliced = 0;
        }
      }
      let visited = 0;
      for (const id of data.threadIds(address)) {
        if (this.#links.get(address) !== link || link.historySweep !== sweep) return;
        this.channels.bring(entriesOf(address, id), Priority.background);
        sliced++;
        if (visited++ === 0 || this.#core.store.firstValuesPending() || sliced >= HISTORY_SLICE_ITEMS || this.#core.host.monotonicMs() - at >= HISTORY_SLICE_MS) {
          yield* this.#core.store.turn();
          at = this.#core.host.monotonicMs();
          sliced = 0;
        }
      }
    });
  }

  #session(address: string, key: string): Effect.Effect<void, CoreError> {
    return this.#read(address, { topic: "session", station: address, key }, sessionPath(key));
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
    this.#remake(address, { threads: [id] });
    const link = this.#links.get(address);
    if (link) {
      const key = topicKey({ topic: "thread", station: address, thread: id });
      link.errors.set(key, new CoreError("http_404", t("station.core.noChat"), 404));
      this.onChange(address, "errors", key);
    }
  }

  // ── events ──

  /// `again`: told again as its stream resumed (link.ts), not as it happened.
  onEvent(address: string, name: string, raw: string, again = false): void {
    timed(`event.${name}`, () => this.#onEvent(address, name, raw, again));
  }

  #onEvent(address: string, name: string, raw: string, again: boolean): void {
    const data = parseJson(raw);
    if (data === undefined) return;
    const core = this.#core;
    if (SEARCHED.has(name)) this.#searchStale(address);
    // An archive and restore can be coalesced: there may be no second removal in the shared-row stream.
    if (name === "session" || name === "session-removed") {
      const session = str(get(data, "key"));
      if (session !== null) {
        const couldRemove = name === "session-removed" || get(data, "archivedAt") != null;
        if (couldRemove) core.views.local.activateRestoreGuards(address, { session });
        this.checkRestores(address, { session, waitingOnly: !couldRemove });
      }
    } else if (name === "chat-changed" || name === "thread-removed") {
      const thread = u64(get(data, name === "chat-changed" ? "thread" : "id"));
      if (thread !== null) {
        core.views.local.activateRestoreGuards(address, { thread });
        this.checkRestores(address, { thread });
      }
    } else if (name === "chat-shared" || name === "chat-shared-removed") {
      const row = str(get(data, "id"));
      if (row !== null) {
        if (name === "chat-shared-removed") core.views.local.activateRestoreGuards(address, { row });
        this.checkRestores(address, { row, waitingOnly: name === "chat-shared" });
      }
    }
    if (RETOLD.has(name)) {
      this.#retold.told(address, name, data);
      this.#held(address, name, data);
      return;
    }
    switch (name) {
      case "thread": {
        const id = u64(get(data, "id"));
        if (id === null) return;
        const entries = (get(data, "entries") as unknown[] | undefined) ?? [];
        const items = ENTRIES.items(data, { latest: true });
        const newest = Math.max(-1, ...items.map(([n]) => n));
        // Its summary as held before what was said goes into its channel (which takes its `last` on to it).
        const was = this.#core.data.of(address)?.thread(address, id);
        const before = isObject(was) ? { ...was } : undefined;
        // As it happened: it comes in with a motion; told again on resuming, it was said before and is caught up on.
        if (!again) this.onTold(address, id, entries);
        // Its rows, as what was said makes them (told again on top of a read asked before it, as the station's own were).
        this.#retold.told(address, "said", data);
        this.#held(address, "said", data);
        // Into its channel: the thread goes that far at once (the rest of its summary is read below), and a gap what
        // was told left is read. A chat let go for room (and not opened since) is not kept current: what it said is
        // read when it is opened. History older than what is held comes with the station's (#history).
        this.channels.told(entriesOf(address, id), items);
        // Its summary for the viewer, brought on by what was said (thread-after.ts): the station leaves it to the device.
        // Where it cannot be made here, read.
        const link = this.#links.get(address);
        const me = this.#me(address);
        const next = me === null ? null : threadAfter(before, entries, me);
        if (next !== null && link) {
          this.putThread(address, next);
          link.viewed.set(id, Math.max(link.viewed.get(id) ?? 0, u64(get(next, "last")) ?? 0));
          link.dirty.delete(id);
          return;
        }
        const viewed = link?.viewed.get(id);
        if (viewed === undefined || viewed < newest) this.#markDirty(address, id);
        return;
      }
      case "letters": {
        // A thread's letters kept in their own log (channel-kinds.ts LETTERS): into it, as entries into theirs; how many
        // it has, its summary.
        const id = u64(get(data, "id"));
        if (id === null) return;
        this.channels.told(lettersOf(address, id), LETTERS.items(data, { latest: true }));
        // How many it has and how far its log goes, in its summary (thread-after.ts); read where that cannot be said.
        const held = this.#core.data.of(address)?.thread(address, id);
        if (held === undefined) return;
        const next = threadAfterLetters(held, (get(data, "letters") as unknown[] | undefined) ?? []);
        if (next === null) this.#markDirty(address, id);
        else if (next !== held) this.putThread(address, next);
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
          // (its lines numbered on from what it said before: log-lines.ts)
          const key = logKey(id, lines);
          link.memory.set(key, logged(link.memory.get(key), str(get(data, "text")) ?? "", get(data, "outputAt") ?? null));
          this.onChange(address, "log", topicKey({ topic: "jobLog", station: address, job: id, lines }));
        }
        return;
      }
      case "made":
      case "chat-mark":
      case "chat-changed":
        return this.#held(address, name, data);
      // The stream that took over could not be told all that came since the last its predecessor gave: read again.
      case "missed":
        return this.snapshot(address);
      case "host": {
        const link = this.#links.get(address);
        if (link) {
          link.memory.set("host", data);
          this.onChange(address, "host");
          const unreadable = !present.hostFits(data);
          if (unreadable !== link.hostUnreadable) {
            link.hostUnreadable = unreadable;
            this.onChange(address, "link");
          }
        }
        return;
      }
      case "usage": {
        const from = get(data, "from");
        this.#usageChanged(address, null, typeof from === "number" && Number.isFinite(from) ? from : null);
        return;
      }
      // Its screens came or went, or who is on them changed.
      case "screens":
        this.#heldScreens(address, { screens: Array.isArray(get(data, "screens")) ? (get(data, "screens") as unknown[]) : [], outdated: false, ...(get(data, "browser") === true ? { browser: true } : {}) });
        return;
      // A login of the station's.
      case "machine-logins": {
        const link = this.#links.get(address);
        if (!link) return;
        if (isObject(get(data, "login"))) this.putMachineLogin(address, get(data, "login"));
        return;
      }
      // The presets, or the folders offered for one, changed (one made on another device, the machine's repositories
      // found after they were asked for): read again where shown or held.
      case "presets":
        if (this.#core.store.inUse({ topic: "presets", station: address }) || this.#links.get(address)?.memory.has(PRESETS)) this.presetsShown(address);
        return;
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
  #held(address: string, name: string, data: unknown, details = true): void {
    const core = this.#core;
    switch (name) {
      case "session":
        return this.#onSession(address, data, details);
      case "session-pending": {
        // Its messages taken (how many it has yet to take): in its summary at once, its summary told after.
        const key = str(get(data, "key"));
        const pending = u64(get(data, "pending"));
        const held = key === null ? undefined : this.#core.data.of(address)?.summary(address, key);
        if (key === null || pending === null || !isObject(held) || get(held, "pending") === pending) return;
        // Fewer: taken by its agent, into the turn it runs (begun, or steered), which the summary told after says. Its
        // last turn held may be one that ended asking a person: not standing asking again until then.
        const taken = pending < (u64(get(held, "pending")) ?? 0);
        const now = taken ? { ...held, pending, process: "running" } : { ...held, pending };
        this.#core.data.putSummary(address, now);
        this.#rowsAfterSession(address, key, held, now);
        return;
      }
      case "session-removed": {
        const key = str(get(data, "key"));
        if (key) this.#onSessionRemoved(address, key);
        return;
      }
      case "thread-removed": {
        const id = u64(get(data, "id"));
        if (id === null) return;
        this.#threadGone(address, id);
        // Its rows go with it.
        for (const row of core.data.chatsOf(address, { thread: id })) this.#dropRow(address, row);
        return;
      }
      case "read": {
        const thread = u64(get(data, "thread"));
        const n = u64(get(data, "n"));
        if (thread !== null && n !== null) this.putRead(address, thread, n);
        return;
      }
      case "hidden": {
        const thread = u64(get(data, "thread"));
        const hidden = get(data, "hidden");
        if (thread === null || typeof hidden !== "boolean") return;
        const link = this.#links.get(address);
        if (link?.marks) {
          markThread(link.marks, link.own, "hidden", thread, hidden);
          return this.#remake(address, { threads: [thread] });
        }
        for (const row of core.data.chatsOf(address, { thread })) if (isObject(row)) core.data.putChat(address, { ...row, hidden });
        return;
      }
      case "muted": {
        const thread = u64(get(data, "thread"));
        const muted = get(data, "muted");
        if (thread === null || typeof muted !== "boolean") return;
        const link = this.#links.get(address);
        if (link?.marks) {
          markThread(link.marks, link.own, "muted", thread, muted);
          return this.#remake(address, { threads: [thread] });
        }
        for (const row of core.data.chatsOf(address, { thread })) if (isObject(row)) core.data.putChat(address, { ...row, muted });
        return;
      }
      case "pin": {
        // What the viewer pinned (or let go), into the marks the sidebar is made of.
        const session = str(get(data, "session"));
        const at = u64(get(data, "at"));
        const link = this.#links.get(address);
        if (link?.marks && session !== null) {
          markPin(link.marks, link.own, session, at);
          // (a row of the list its station makes is its agent's, by its key)
          return this.#remake(address, { ids: [session] });
        }
        return;
      }
      case "dismiss": {
        // What waits in a chat the viewer will not take up (its card, its agent's need), in its rows.
        const thread = u64(get(data, "thread"));
        const n = u64(get(data, "n"));
        if (thread === null || n === null) return;
        const link = this.#links.get(address);
        if (link?.marks) {
          markDismissed(link.marks, link.own, thread, n);
          return this.#remake(address, { threads: [thread] });
        }
        return;
      }
      case "kept": {
        // A chat the viewer kept from being offered for archiving, or let be again.
        const thread = u64(get(data, "thread"));
        if (thread === null || typeof get(data, "kept") !== "boolean") return;
        const link = this.#links.get(address);
        if (link?.marks) {
          markThread(link.marks, link.own, "kept", thread, get(data, "kept") === true);
          return this.#remake(address, { threads: [thread] });
        }
        return;
      }
      case "said": {
        // What was said in a chat: the marks it changes, and the sidebar made again (rows-made.ts).
        const link = this.#links.get(address);
        const id = u64(get(data, "id"));
        if (link?.marks && id !== null) {
          const entries = ((get(data, "entries") as unknown[] | undefined) ?? []).filter(isObject);
          // The review's marks hold while the chat stands as it looked at it; a card posted, or a person writing (what
          // waits answered), is the station's to say.
          // (the older path's list, walked: rows-made.ts marksPut)
          glanced.marksWalked += link.marks.suggested.length;
          link.marks.suggested = link.marks.suggested.filter((t) => t !== id);
          delete link.marks.verdicts[String(id)];
          if (entries.some((e) => get(e, "card") !== undefined || get(e, "authorKind") === "person" || get(e, "kind") === "edit")) this.#marksRead(address, { threads: [id] });
          this.#remake(address, { threads: [id] });
        }
        return;
      }
      case "made": {
        // The station keeps the marks beside the summaries (`marks`): the whole sidebar made here (rows-made.ts).
        const link = this.#links.get(address);
        if (!link) return;
        if (link.marks === null) this.#enqueue(address, "chats", Priority.shown, this.#marksWhole(address));
        // The chat list the station makes once for everyone: the sidebar made of it and what is the viewer's own.
        link.shared = get(data, "shared") === true;
        if (link.shared && link.sharedRows === null) this.#enqueue(address, "shared", Priority.shown, this.#sharedWhole(address));
        return;
      }
      case "chat-shared": {
        // A row of the chat list as it is now, as the station made it for everyone who sees it.
        const id = str(get(data, "id"));
        const link = this.#links.get(address);
        if (id === null || !link?.sharedRows) return;
        this.#sharedPut(link, id, data as Record<string, any>);
        return this.#remake(address, { ids: [id] });
      }
      case "chat-shared-removed": {
        const id = str(get(data, "id"));
        const link = this.#links.get(address);
        if (id === null || !link?.sharedRows) return;
        this.#sharedPut(link, id, undefined);
        return this.#remake(address, { ids: [id] });
      }
      case "chat-changed": {
        // What changes which rows there are and what they say, and only the station can say (a chat's sessions, its
        // settings, who the viewer is on Slack): those of a chat read again, or all of them.
        const thread = u64(get(data, "thread"));
        if (this.#links.get(address)?.marks) {
          // Its sessions or shares changed: its summary and marks read again; or anything (settings): all the marks.
          if (thread === null) return this.#marksRead(address, { whole: true });
          this.#markDirty(address, thread);
          return this.#marksRead(address, { threads: [thread] });
        }
        // Its marks not read yet: all of it read as they are.
        this.#enqueue(address, "chats", Priority.shown, this.#chats(address));
        return;
      }
      case "chat-mark": {
        // What was written of a chat beside what is said in it (the review's marks, who it is shared with, a chat opened
        // from it): its rows as the station has them now, where it leaves them to the device.
        const session = str(get(data, "session"));
        const thread = u64(get(data, "thread"));
        if (this.#links.get(address)?.marks && session !== null) this.#marksRead(address, { sessions: [session], threads: thread === null ? [] : [thread] });
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
        return core.data.set({ topic: name, station: address }, data);
    }
  }

  /// What `address`'s stream told since `read` was asked, on top of what it brought (retold.ts).
  /// `details`: whether a summary told again may ask its session's detail read again. Not after a read of the marks,
  /// which brings no detail: the summary asked its detail as it was first told (a session new to the device was read
  /// twice so, the second while the first was on its way).
  #retell(address: string, read: number, shared = false, details = true): void {
    // Only a shared-list read replaces sharedRows. Replaying its events after an unrelated, slower read could put an
    // older row back over a newer shared-list answer.
    for (const { name, data } of this.#retold.since(read, address)) if (SHARED_RETOLD.has(name) === shared) this.#held(address, name, data, details);
  }

  /// A session's summary changed: in place among the listed (and in its detail); its detail is read again when its
  /// turns changed.
  #onSession(address: string, summary: unknown, details = true): void {
    const key = str(get(summary, "key"));
    if (!key) return;
    const before = this.#core.data.of(address)?.summary(address, key);
    // (written before the sidebar is made again of it: a task enqueued may run at once)
    const again = this.#core.data.putSummary(address, summary);
    this.#rowsAfterSession(address, key, before, summary);
    if (again && details) this.#enqueue(address, `session/${key}`, Priority.shown, this.#session(address, key));
    // How far its transcript goes: what the device lacks of it after what it holds is read (channels.ts `settle`).
    const length = u64(get(summary, "transcriptLength"));
    if (length !== null && length > 0) this.channels.goesTo(transcriptOf(address, key), length - 1);
  }

  /// A session's summary into the sidebar made here (rows-made.ts): the station's marks of it read where they may
  /// have changed.
  #rowsAfterSession(address: string, key: string, before: unknown, summary: unknown): void {
    const link = this.#links.get(address);
    if (link?.marks) {
      // New to the device, or its last turn now asks something of a person or no longer does: the station's marks of it.
      // Not of a list its station makes: what its rows read of the marks (where the viewer read to, what they let go,
      // kept, hid, muted, pinned, who they are) is the viewer's doing, not a turn's; what a turn asks is in the row it
      // tells (`chat-shared`).
      const ask = (s: unknown) => JSON.stringify(get(s, "lastTurn") ?? null);
      if (!link.shared && (!isObject(before) || ask(before) !== ask(summary))) {
        const threads = (this.#core.data.shared({ topic: "threads", station: address }) as unknown[] | undefined ?? [])
          .filter((t) => Array.isArray(get(t, "sessions")) && (get(t, "sessions") as unknown[]).some((m) => get(m, "session") === key))
          .flatMap((t) => u64(get(t, "id")) ?? []);
        this.#marksRead(address, { sessions: [key], threads });
      }
      // (a list its station makes reads no summary)
      this.#remake(address, {});
    }
  }

  /// The station's sidebar: made here (rows-made.ts) from the summaries held and what the station keeps beside them
  /// (GET /chats?marks=1).
  #chats(address: string, ctx: SpanContext | null = null, unread?: () => void): Effect.Effect<void, CoreError> {
    return this.#marksWhole(address, ctx, unread);
  }

  /// Reconcile a completed optimistic restore when it answers, its own chat changes, or the stream reconnects. The
  /// station's scoped read is bounded to that chat. A tell during the read queues a new one and invalidates its answer.
  checkRestores(address: string, match: { change?: number; session?: string; thread?: number; row?: string; waitingOnly?: boolean } = {}, attempt = 0): void {
    const link = this.#links.get(address);
    if (!link || !this.reachable(address)) return;
    for (const c of this.#core.views.local.restores(address)) {
      if (match.change !== undefined && c.id !== match.change) continue;
      if (match.session !== undefined && c.session !== match.session) continue;
      if (match.thread !== undefined && c.thread !== match.thread) continue;
      if (match.row !== undefined && get(c.restore, "id") !== match.row) continue;
      const key = join([address, String(c.id)]);
      if (match.waitingOnly && c.restoreGuard && !this.#restoreVersions.has(key)) continue;
      this.#restoreVersions.set(key, (this.#restoreVersions.get(key) ?? 0) + 1);
      this.#enqueue(address, `restore/${c.id}`, Priority.shown, Effect.gen({ self: this }, function* () {
        const current = this.#core.views.local.restores(address).find((r) => r.id === c.id);
        const l = this.#links.get(address);
        if (!current || !l || !this.reachable(address)) { this.#restoreVersions.delete(key); return; }
        const version = this.#restoreVersions.get(key);
        const query = `session=${encode(current.session)}${current.thread === null ? "" : `&thread=${current.thread}`}`;
        const answer = yield* Effect.result(this.requests.call(l.addr, "GET", `/chats?${l.shared ? "shared=1&" : ""}${query}`, null, { quiet: true }));
        if (this.#restoreVersions.get(key) !== version) return;
        if (this.#links.get(address) !== l) { this.#restoreVersions.delete(key); return; }
        this.#restoreVersions.delete(key);
        if (answer._tag === "Failure") {
          if ((answer.failure.status === undefined || answer.failure.status >= 500) && attempt < READ_RETRIES) {
            // timer: retry after a failed read, bounded and cancelled with the link.
            const again = Effect.sleep(READ_RETRY_MS * 2 ** attempt).pipe(
              Effect.andThen(Effect.sync(() => this.checkRestores(address, { change: c.id }, attempt + 1))),
            );
            this.#core.runner.fork(again, l.scoped);
          }
          return;
        }
        if (!Array.isArray(get(answer.success, "rows"))) return;
        const rowId = str(get(current.restore, "id"));
        if (rowId === null) return;
        if (!this.#core.views.local.restores(address).some((r) => r.id === current.id)) return;
        const present = arr(get(answer.success, "rows")).some((row) => str(get(row, "id")) === rowId);
        if (present) {
          // If the row is not held yet, keep the optimistic copy until its shared-row tell arrives. If it is held,
          // the station has confirmed it: leave a quiet guard for an older removal still on its way.
          if (l.shared && !l.sharedRows?.has(rowId)) return;
          if (l.shared) this.#made(address, { ids: [rowId] });
          const listed = current.thread === null ? this.#core.data.chatOfSession(address, current.session) : this.#core.data.chatOfThread(address, current.thread);
          if (listed !== undefined) this.#core.views.local.guardRestore(address, current.id);
          return;
        }
        // A full shared-list read may have started before this scoped answer: replay this removal over its result.
        if (l.shared) this.#retold.told(address, "chat-shared-removed", { id: rowId });
        if (l.sharedRows?.has(rowId)) this.#sharedPut(l, rowId, undefined);
        l.rows.rows.delete(rowId);
        this.#core.data.dropChat(address, rowId);
        this.#core.views.local.restoreSettled(address, current.id);
      }));
    }
  }

  /// The chat list as the station makes it for everyone (GET /chats?shared=1), what the viewer sees of it; the sidebar
  /// made of it.
  #sharedWhole(address: string, ctx: SpanContext | null = null, unread?: () => void, attempt = 0): Effect.Effect<void, CoreError> {
    return this.#asked((asked) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return unread?.();
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/chats?shared=1", null, { quiet: true, ctx }));
      if (answer._tag === "Failure") {
        unread?.();
        if ((answer.failure.status === undefined || answer.failure.status >= 500) && attempt < READ_RETRIES) {
          const again = Effect.sleep(READ_RETRY_MS * 2 ** attempt).pipe(
            Effect.andThen(Effect.sync(() => void this.#enqueue(address, "shared", Priority.background, this.#sharedWhole(address, null, undefined, attempt + 1)))),
          );
          this.#core.runner.fork(again, link.scoped);
        }
        return;
      }
      if (!Array.isArray(answer.success)) return unread?.();
      link.sharedRows = new Map();
      link.sharedThreads.clear();
      for (const r of answer.success) if (isObject(r) && typeof get(r, "id") === "string") this.#sharedPut(link, get(r, "id") as string, r as Record<string, any>);
      this.#retell(address, asked, true);
      this.#made(address, { whole: true });
    }));
  }

  #marksWhole(address: string, ctx: SpanContext | null = null, unread?: () => void): Effect.Effect<void, CoreError> {
    return this.#asked((asked) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return unread?.();
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", "/chats?marks=1", null, { quiet: true, ctx }));
      if (answer._tag === "Failure") {
        if (answer.failure.status === undefined || answer.failure.status >= 500) unread?.();
        return yield* Effect.fail(answer.failure);
      }
      const marks = marksOf(answer.success);
      if (marks === null) return yield* Effect.fail(new CoreError("bad_response", t("station.core.invalidReply")));
      link.marks = marks;
      this.#made(address, { whole: true });
      this.#retell(address, asked, false, false);
    }));
  }

  /// What the station keeps beside the summaries of some chats (or all: `whole`), read again: what it asks is gathered
  /// while the read waits, one read for all of it. Then the sidebar made again.
  #marksRead(address: string, of: { sessions?: string[]; threads?: number[]; whole?: boolean }): void {
    const link = this.#links.get(address);
    if (!link?.marks) return;
    for (const key of of.sessions ?? []) link.marksWanted.sessions.add(key);
    for (const id of of.threads ?? []) link.marksWanted.threads.add(id);
    if (of.whole) link.marksWanted.whole = true;
    this.#enqueue(address, "marks", Priority.shown, this.#asked((asked) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link?.marks || !this.reachable(address)) return;
      const whole = link.marksWanted.whole;
      const scope = { sessions: [...link.marksWanted.sessions], threads: [...link.marksWanted.threads] };
      link.marksWanted.sessions.clear();
      link.marksWanted.threads.clear();
      link.marksWanted.whole = false;
      if (!whole && scope.sessions.length === 0 && scope.threads.length === 0) return;
      const query = whole ? "" : [...scope.sessions.map((k) => `&session=${encode(k)}`), ...scope.threads.map((id) => `&thread=${id}`)].join("");
      const read = marksOf(yield* this.requests.call(link.addr, "GET", `/chats?marks=1${query}`, null, { quiet: true }));
      if (read === null || !link.marks) return;
      if (whole) link.marks = read;
      else {
        // (what is kept of them for a list its station makes, by their keys too, before whose rows they are is put:
        // where that changed, all made again of them)
        if (link.own !== null && link.own.marks === link.marks) link.own.scoped(read, scope);
        marksPut(link.marks, read, scope);
      }
      this.#made(address, whole ? { whole: true } : { ids: scope.sessions, threads: scope.threads });
      this.#retell(address, asked, false, false);
    })));
  }

  /// The sidebar made again from what is held, once what is being told now is in (rows-made.ts). Of a list its station
  /// makes, only `rows` (none where it names none: what changed is nothing such a list's rows read); else all of it, as
  /// rowsMade makes it.
  #remake(address: string, rows: Rows): void {
    const link = this.#links.get(address);
    if (!link?.marks) return;
    if (link.shared && !this.#wanted(link, rows)) return;
    this.#enqueue(address, "remake", Priority.shown, Effect.sync(() => this.#made(address, {})));
  }

  /// `rows` gathered with those wanted already of a list its station makes: whether any is.
  #wanted(link: Link, rows: Rows): boolean {
    const w = link.rowsWanted;
    if (rows.whole) w.whole = true;
    for (const id of rows.ids ?? []) w.ids.add(id);
    for (const thread of rows.threads ?? []) w.threads.add(thread);
    return w.whole || w.ids.size > 0 || w.threads.size > 0;
  }

  /// A row of the list its station makes, as read or told (undefined: gone), and which row its thread's.
  #sharedPut(link: Link, id: string, row: Record<string, any> | undefined): void {
    const was = u64(link.sharedRows!.get(id)?.thread);
    if (was !== null && link.sharedThreads.get(was) === id) link.sharedThreads.delete(was);
    if (row === undefined) link.sharedRows!.delete(id);
    else link.sharedRows!.set(id, row);
    const thread = u64(row?.thread);
    if (thread !== null) link.sharedThreads.set(thread, id);
  }

  #made(address: string, rows: Rows): void {
    const link = this.#links.get(address);
    const me = this.#me(address);
    if (!link?.marks || me === null) return;
    const data = this.#core.data;
    if (link.shared) {
      // Of the chat list the station makes for everyone, once it is read: till then the rows held stand.
      this.#wanted(link, rows);
      if (link.sharedRows === null) return;
      const w = link.rowsWanted;
      const ids = new Set(w.ids);
      for (const thread of w.threads) {
        const id = link.sharedThreads.get(thread);
        if (id !== undefined) ids.add(id);
      }
      const whole = w.whole;
      w.ids.clear();
      w.threads.clear();
      w.whole = false;
      const words = rowWords();
      // Whole where what every row reads changed (the marks read whole, whose rows they are, the words) or the list was
      // read; else each row by its key, at its place (sharedPlace), nothing else looked at.
      const own = link.own?.of(link.marks, me) ? link.own : null;
      if (whole || own === null || link.rows.whole !== sharedWhole(me, link.marks.selves, words)) {
        if (own === null) link.own = new OwnHeld(link.marks, me);
        const list = rowsShared(link.sharedRows.values(), link.marks, me, words, link.rows, link.own!);
        return data.setChatsAt(address, list, list.map(sharedPlace));
      }
      for (const id of ids) {
        const shared = link.sharedRows.get(id);
        if (shared === undefined) {
          link.rows.rows.delete(id);
          data.dropChat(address, id);
          continue;
        }
        const row = rowShared(shared, own, words, link.rows);
        data.putChat(address, row, sharedPlace(row));
      }
      return;
    }
    const sessions = data.shared({ topic: "sessions", station: address });
    const threads = data.shared({ topic: "threads", station: address });
    if (!Array.isArray(sessions) || !Array.isArray(threads)) return;
    data.set({ topic: "chatRows", station: address }, rowsMade(sessions, threads, link.marks, me, rowWords(), link.rows));
  }

  /// A row gone from the list, by its id.
  #dropRow(address: string, row: unknown): void {
    const id = str(get(row, "id"));
    if (id !== null) this.#core.data.dropChat(address, id);
  }

  #onSessionRemoved(address: string, key: string): void {
    const core = this.#core;
    core.data.dropSession(address, key);
    this.#remake(address, { ids: [key] });
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
    if (core.data.putJob(address, job, open)) this.#enqueue(address, "jobs", Priority.shown, this.#read(address, { topic: "jobs", station: address }, JOBS));
  }

  /// A thread's summary into the station's threads, and the details of the sessions taking part. It says how far the
  /// thread goes: its channel is read if the device is behind on it.
  putThread(address: string, view: unknown): void {
    this.#core.data.putThread(address, view);
    // (a list its station makes reads no thread's summary)
    this.#remake(address, {});
    const id = u64(get(view, "id"));
    const last = u64(get(view, "last"));
    if (id !== null && last !== null) this.channels.goesTo(entriesOf(address, id), last);
    // (its letters' own log, as far as it goes: read if the device holds some of it and is behind)
    const letters = u64(get(view, "lettersLast"));
    if (id !== null && letters !== null) this.channels.goesTo(lettersOf(address, id), letters);
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
    // Where the viewer read to, theirs on the chat list's rows: as it is read here, not only once the station's stream
    // says it again (a read whose event never came left its row unread, 2026-11-10).
    const link = this.#links.get(address);
    if (link?.shared && link.marks) markRead(link.marks, link.own, thread, n);
    this.#remake(address, { threads: [thread] });
  }

  /// The email the viewer reaches `address`'s workspace with: whose messages there are their own.
  #me(address: string): string | null {
    let workspace: string;
    try {
      workspace = StationAddr.parse(address).workspace;
    } catch {
      return null;
    }
    const sub = this.#core.workspaces.of(workspace).owner;
    return sub === null ? null : (this.#core.accounts.list().find((a) => a.sub === sub)?.email ?? null);
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

  /// A chat opened with no summary held (made since the threads were read, elsewhere or while away; opened from a
  /// link): its summary read at once, as its entries are (topics.ts `start`).
  summaryOf(address: string, id: number): void {
    if (this.#links.has(address)) this.#enqueue(address, `thread/${id}`, Priority.shown, this.#threadSummary(address, id));
  }

  /// An agent's session asked for (a chat opened by it) that the station's list read has not, with nothing held of it:
  /// made since, or a reference the station has no chat for. Read at once, so the page has it or the station's no as
  /// its error: the sweep reads only what the list has, so the page would wait for good (2026-11-12). Asked as the
  /// topic starts (topics.ts `start`) and as the list comes, of those shown then.
  unlisted(address: string, key: string | null = null): void {
    const data = this.#core.data;
    if (!this.#links.has(address) || !data.listed(address, "sessions")) return;
    const keys = key !== null ? [key] : this.#core.store.liveTopics().filter((t) => t.topic === "session" && t.station === address).map((t) => t.key as string);
    for (const k of keys) {
      if (data.listedSummary(address, k) !== undefined || data.shared({ topic: "session", station: address, key: k }) !== undefined) continue;
      this.#enqueue(address, `session/${k}`, Priority.shown, this.#session(address, k));
    }
  }

  #threadSummary(address: string, id: number): Effect.Effect<void, CoreError> {
    return this.#asked((read) => Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link) return;
      const view = yield* Effect.result(this.requests.call(link.addr, "GET", `/threads/${id}`, null, { quiet: true }));
      if (view._tag === "Success") this.putThread(address, view.success);
      else if (view.failure.status === 404) this.#threadGone(address, id);
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
        if (event !== undefined) {
          const span = core.data.logSpan("transcript", address, key);
          const held = span ? span.max + 1 : 0;
          applyStep(view, event, now, held);
          // Those the transcript recorded since are let go.
          view.steps = view.steps.filter((s) => stepShown(s, held));
        }
      } else return;
      this.onChange(address, "live", key);
    }
  }

  /// A session's transcript was read, or told as it stands: its history is loaded (`loaded`), what it holds what there is.
  #transcriptKnown(link: Link, key: string): void {
    let view = link.lives.get(key);
    if (!view) link.lives.set(key, (view = { steps: [], phase: null, rate: null, usage: null, loaded: false }));
    this.#transcriptMisses.delete(`${link.address}\u0001${key}`);
    if (view.loaded && view.failed === undefined) return;
    view.loaded = true;
    delete view.failed;
    this.onChange(link.address, "live", key);
  }

  /// A read of a session's transcript failed: why, for its history to say, and read again after a while, less often each
  /// time it fails in a row, while its history is shown.
  #transcriptFailed(link: Link, key: string, error: CoreError): void {
    let view = link.lives.get(key);
    if (!view) link.lives.set(key, (view = { steps: [], phase: null, rate: null, usage: null, loaded: false }));
    if (view.failed !== error.message) {
      view.failed = error.message;
      this.onChange(link.address, "live", key);
    }
    const topic: Topic = { topic: "live", station: link.address, key };
    if (!this.#core.store.inUse(topic)) return;
    const miss = `${link.address}\u0001${key}`;
    // (one read again at a time: two that failed together wait as one)
    if (this.#transcriptAgain.has(miss)) return;
    this.#transcriptAgain.add(miss);
    const n = this.#transcriptMisses.get(miss) ?? 0;
    this.#transcriptMisses.set(miss, n + 1);
    // timer: retry after a failure, with a backoff
    const again = Effect.sleep(retryAfter(n)).pipe(
      Effect.andThen(Effect.sync(() => {
        this.#transcriptAgain.delete(miss);
        if (this.#core.store.inUse(topic)) this.channels.bring(transcriptOf(link.address, key), Priority.shown, "latest");
      })),
      Effect.onInterrupt(() => Effect.sync(() => this.#transcriptAgain.delete(miss))),
    );
    this.#core.runner.fork(again, link.scoped);
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
      // A tab opened by the id made here: listed at once (a view of it waits for the station), until the station lists
      // it as it makes it, or refuses it.
      const tab = op.effect.kind === "tab" ? op.effect.screen : null;
      if (tab !== null) this.#tabOpening(address, tab, true);
      for (;;) {
        const result = yield* Effect.result(this.requests.call(addr, current.method, current.path, current.body, { ctx }));
        if (tab !== null) {
          if (result._tag === "Success") yield* Effect.ignore(this.readScreens(address));
          this.#tabOpening(address, tab, false);
        }
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
      const rows = () => reads.push(["chats", this.#chats(address)]);
      // The archive: read again before the call answers only while a page shows it, else marked to be (#archivedChanged).
      const archived = () => {
        const link = this.#links.get(address);
        if (link) link.archivedCurrent = false;
        if (this.#core.store.inUse({ topic: "archivedRows", station: address })) reads.push(["archived", this.#archived(address)]);
      };
      switch (effect.kind) {
        case "none":
        // (its list read before it answered: perform's)
        case "tab":
          return;
        case "session": {
          if (effect.key !== null) reads.push([`session/${effect.key}`, this.#session(address, effect.key)]);
          read("sessions", { topic: "sessions", station: address }, "/sessions");
          rows();
          archived();
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
        case "presets":
          reads.push(["presets", this.#presets(address)]);
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
      const key = `${address}\u0001${thread}`;
      const position = this.readPosition(address, thread);
      // (read so far as the station has it: not as far as a read held here that it has not taken yet)
      const held = this.#heldReads.get(key);
      if (position !== null && position >= n && !(held !== undefined && held >= n)) return;
      // Held read here as it is asked, not once the station answers: the list's row and its workspace's mark were
      // unread for that round trip, and read again after it (2026-11-08). The station's next summary says otherwise
      // if it does not take it, and the read is asked again (attend.ts `failed`).
      this.#heldReads.set(key, Math.max(held ?? 0, n));
      this.putRead(address, thread, n);
      const answer = yield* this.requests.call(StationAddr.parse(address), "PUT", `/threads/${thread}/read`, { n }, { ctx });
      if ((this.#heldReads.get(key) ?? 0) <= n) this.#heldReads.delete(key);
      this.putRead(address, thread, u64(get(answer, "n")) ?? n);
    });
  }

  /// How far the viewer has read a thread. A shared sidebar uses the viewer's marks, which may be behind an optimistic
  /// thread summary after an interrupted write and a restart: a read is not confirmed past either of them.
  readPosition(address: string, thread: number): number | null {
    const position = this.#core.data.readPosition(address, thread);
    const link = this.#links.get(address);
    if (position === null || !link?.shared || !link.sharedThreads.has(thread) || link.marks === null) return position;
    return Math.min(position, u64(link.marks.reads[String(thread)]) ?? 0);
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
