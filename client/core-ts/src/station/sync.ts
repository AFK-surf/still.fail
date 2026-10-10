// What the core keeps in sync with the stations, by itself, whatever the UI shows (docs/core-ts.md, rule 6; station.rs
// and sync.rs for what a station says and how). Every station of every workspace an account reaches has a link: its
// `/admin/api/events` stream, held open for as long as the station is reached, opened again with backoff when it drops.
// Each time it opens, what the station holds is read again (as tasks of the station's lane in the sync scheduler); its
// events bring what changes as it changes, into the records. Then the rest is brought onto the device in the
// background, the most urgent first: every chat's entries (from its latest page back to its first), every session's
// detail and the latest page of its transcript. The UI makes some of it more urgent (`prioritize`), never more or less.
import { Deferred, Effect, Exit, Fiber, Scope } from "effect";
import type { Inner } from "../core.ts";
import { join } from "../data.ts";
import { CoreError, asCoreError } from "../error.ts";
import { nOf } from "../entries.ts";
import { t } from "../i18n.ts";
import { encode, type Effect as OpEffect, type Request } from "../ops.ts";
import { topicKey, type Topic } from "../protocol.ts";
import type { Scoped } from "../runtime.ts";
import { Kind, type SpanContext } from "../trace.ts";
import { equal, get, isObject, parseJson } from "../util.ts";
import { GONE, NETWORK } from "../wake.ts";
import { Priority } from "../sync/scheduler.ts";
import { activity as historyActivity } from "../history.ts";
import { StationAddr } from "./addr.ts";
import { IDEMPOTENCY_KEY, READS, RESUMED, Requests, httpError } from "./requests.ts";
import { digest } from "../digest.ts";
import { SseParser } from "./sse.ts";
import { readAll, replyHeader, type StationWire } from "./wire.ts";

/// How long a failed or ended stream waits before it is opened again; a station not reached is tried again at
/// RECONNECT_MS, doubling up to RECONNECT_MAX_MS.
export const RECONNECT_MS = 2_000;
export const RECONNECT_MAX_MS = 60_000;
/// A station not reached that still.fail cloud says is not online is tried again this seldom, and at once when it says it
/// is back (or the UI comes back): tried every minute, an unreachable station took a phone some 50 dials an hour, each
/// waiting 10 s for nothing.
export const OFFLINE_RETRY_MS = 10 * 60_000;
/// How many tries in a row a station that was up may miss before it is taken for down.
export const MISSES = 3;
/// A station not reached this many tries in a row (some ten minutes of trying) is tried as seldom as one the cloud says
/// is not online, though it says it is: one too old to take this client's access, or one that lost its relay, was
/// dialled by every client about once a minute, some 1,600 dials a day for one such station.
export const LONG_MISSES = 12;
export const LINK_KEY = "link";
/// Where a station's last host sample is kept (`host/<address>`), so its figures show from before it is reached again;
/// written at most every HOST_SAVE_MS.
export const HOST_KEY = "host";
export const HOST_SAVE_MS = 60_000;
/// A station's streams carry a keepalive every 25 s; one silent this long is on a link that is gone.
export const STREAM_IDLE_MS = 40_000;
/// A stream silent past one keepalive (and a little) may be on a link that is gone.
export const STREAM_QUIET_MS = 30_000;
/// A burst of `thread` events becomes one read of each thread's summary.
export const EVENTS_COALESCE_MS = 400;
/// Entries per page of a thread, and items per page of a transcript.
export const PAGE = 50;
export const TRANSCRIPT_PAGE = 200;
export const RECHECK_MS = 5 * 60 * 1000;
/// A read that failed in passing (a 5xx, the link dropping) is tried again after this, doubling, this many times.
export const READ_RETRY_MS = 2_000;
export const READ_RETRIES = 5;
/// The field naming a row of each list read whole that may be asked as what changed of it (POST /changed/<list>).
const LIST_ID: Record<string, string> = { chatRows: "id", archivedRows: "id", threads: "id", sessions: "key" };
/// A station from before POST /changed/<list> reads its lists whole, and is tried again after this.
export const CHANGES_RETRY_MS = 3_600_000;
/// How much of a station's history one batch asks (POST /batch, #history): a page of entries or a session's detail is
/// one, a page of a transcript (200 steps in brief) TRANSCRIPT_COST.
export const HISTORY_BATCH = 40;
const TRANSCRIPT_COST = 5;

/// A read of a station's history (#history): its path, how much of a batch it takes, and what its answer does (and
/// the read after it, as a thread has more pages to bring).
type HistoryRead = { path: string; cost: number; apply: (answer: { status: number; body: unknown }) => HistoryRead | null };
export const RECHECKING = "等它回来确认";

/// The steps in flight and the phase of a session at work, as its stream says them.
export type LiveView = { steps: unknown[]; phase: unknown | null; rate: number | null; usage: unknown; loaded: boolean };

/// What a station's `/events` stream is opened for: host samples, the sessions followed as they run, the jobs' logs.
export type EventsFor = { host: boolean; live: string[]; logs: [string, number][] };

/// Whether a stream opened for `open` gives what `wants` asks: the same host samples and logs, and every session it
/// asks among those it follows. One that follows more is kept: a session no longer at work or shown says little more.
function covers(open: EventsFor, wants: EventsFor): boolean {
  return open.host === wants.host && equal(open.logs, wants.logs) && wants.live.every((key) => open.live.includes(key));
}

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
/// A row's id as text (sessions' and chats' are strings, threads' numbers).
const idText = (v: unknown): string | null => (typeof v === "string" ? v : typeof v === "number" ? String(v) : null);
/// The latest page of a session's transcript, in brief (what a history shows unopened).
const latestPage = (key: string) => `/sessions/${encode(key)}/timeline?before=1000000000000000&limit=${TRANSCRIPT_PAGE}&brief=1`;

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
    for (const s of view.steps) if (equal(get(s, "id"), id) && isObject(s)) s.ended = true;
  }
}

/// An event's id heard on a link's stream: the station's run and its number in it (`<run>.<n>`), kept the latest of.
function heardEvent(link: Link, id: string): void {
  const m = /^([0-9a-f]+)\.(\d+)$/.exec(id);
  if (!m) return;
  const n = Number(m[2]);
  if (link.lastEvent === null || link.lastEvent.run !== m[1] || n > link.lastEvent.n) link.lastEvent = { run: m[1]!, n };
}

/// One station's link and what is held of it beyond the records.
export class Link {
  readonly address: string;
  readonly addr: StationAddr;
  readonly scoped: Scoped;
  /// How the link is: connecting (with `last`, as it was last time), online, reconnecting, offline, error.
  state: Record<string, unknown> = { state: "connecting" };
  /// Numbers the streams opened; only the newest reports.
  generation = 0;
  /// The stream open now (or opening), and what it was opened for; the one it replaces, until it is open.
  events: { fiber: Fiber.Fiber<void, never>; wants: EventsFor } | null = null;
  replaced: Fiber.Fiber<void, never> | null = null;
  /// When the open stream last gave anything; null while none is open.
  heard: number | null = null;
  /// The last event its streams gave, by its id: the station's run and its number in it (a station from before has
  /// none). A stream taking over from another asks for what came after it (`since`).
  lastEvent: { run: string; n: number } | null = null;
  /// The last event as written down with what it told (`heard`); `restored`: it was, by a core before this one, and no
  /// stream has opened since.
  keptEvent: { run: string; n: number } | null = null;
  restored = false;
  /// Sessions at work as their stream says (steps, phase, rate, usage).
  readonly lives = new Map<string, LiveView>();
  /// Threads whose summaries are read again once a burst of events is over.
  readonly dirty = new Set<number>();
  flushing = false;
  /// How far each thread went as its station last told its summary (a `thread-view`): told so, it is not read again.
  readonly viewed = new Map<number, number>();
  /// Whether it follows jobs' logs on its stream (as it said); null until one is read.
  followsLogs: boolean | null = null;
  /// What a read of a topic failed with while nothing is held of it.
  readonly errors = new Map<string, CoreError>();
  /// Host samples and jobs' logs as they come (measurements and output shown while watched).
  readonly memory = new Map<string, unknown>();
  /// When the host sample was last written down (HOST_KEY).
  hostSaved = 0;
  /// Whether the usage held is as the station has it: read since it last said its usage changed.
  usageCurrent = false;
  /// Whether the archived chats held are as the station has them: read since anything could have changed them.
  archivedCurrent = false;
  /// When the station said it has no POST /changed/<list> (one from before): its lists are read whole a while.
  changesRefused: number | null = null;
  /// When the station said it has no POST /batch (one from before): its history is read a request a read a while.
  batchRefused: number | null = null;
  /// What is left of the sweep of its history under way (#history), and what the sweep asked (each read once).
  history: HistoryRead[] = [];
  readonly historyAsked = new Set<string>();

  constructor(address: string, addr: StationAddr, scoped: Scoped) {
    this.address = address;
    this.addr = addr;
    this.scoped = scoped;
  }
}

export class StationsSync {
  readonly #core: Inner;
  readonly requests: Requests;
  readonly #links = new Map<string, Link>();
  /// What the station topics want of a stream beyond what the sync wants (host samples, logs, sessions shown).
  wanted: (address: string) => { host: boolean; live: string[]; logs: [string, number][] } = () => ({ host: false, live: [], logs: [] });
  /// Told when what a station holds beyond the records changed (link, live views, host, logs).
  onChange: (address: string, what: "link" | "live" | "host" | "log" | "errors", key?: string) => void = () => {};
  /// Told of entries that came as they were said (an event): they come in with a motion.
  onTold: (address: string, id: number, entries: unknown[]) => void = () => {};

  constructor(core: Inner, wire: StationWire) {
    this.#core = core;
    this.requests = new Requests(core, wire);
  }

  get wire(): StationWire {
    return this.requests.wire;
  }

  link(address: string): Link | undefined {
    return this.#links.get(address);
  }

  links(): Link[] {
    return [...this.#links.values()];
  }

  /// What a station's reconnecting waits on besides its time: still.fail cloud saying it is online (`cameOnline`).
  readonly #backs = new Map<string, Deferred.Deferred<void>>();

  #backOf(address: string): Deferred.Deferred<void> {
    let back = this.#backs.get(address);
    if (!back) {
      back = Deferred.makeUnsafe<void>();
      this.#backs.set(address, back);
    }
    return back;
  }

  /// still.fail cloud says the station came online: one waiting to reconnect tries now.
  cameOnline(address: string): void {
    const back = this.#backs.get(address);
    if (!back) return;
    this.#backs.delete(address);
    Deferred.doneUnsafe(back, Effect.void);
  }

  /// Whether still.fail cloud says the station is not online (its workspace as held lists it so).
  #cloudSaysOffline(address: string): boolean {
    let addr: StationAddr;
    try {
      addr = StationAddr.parse(address);
    } catch {
      return false;
    }
    const workspace = this.#core.data.shared({ topic: "workspace", workspace: addr.workspace });
    const station = isObject(workspace) && Array.isArray(workspace.stations) ? workspace.stations.find((s) => get(s, "id") === addr.station) : undefined;
    return get(station, "online") === false;
  }

  /// Whether the station is worth asking now: not while its link has found it down.
  reachable(address: string): boolean {
    return this.#links.get(address)?.state.state !== "offline";
  }

  /// Every station of every workspace an account reaches, as the workspaces are held: those not linked yet are
  /// linked, those no longer listed let go.
  reconcile(): void {
    const core = this.#core;
    const wanted = new Set<string>();
    for (const [id] of core.workspaces.owned()) {
      const workspace = core.data.shared({ topic: "workspace", workspace: id });
      for (const s of isObject(workspace) && Array.isArray(workspace.stations) ? workspace.stations : []) {
        if (isObject(s) && typeof s.id === "string") wanted.add(`${id}/${s.id}`);
      }
    }
    for (const [address, link] of [...this.#links]) {
      if (wanted.has(address)) continue;
      this.#links.delete(address);
      core.runner.close(link.scoped);
      core.scheduler.drop(address, new CoreError("gone", t("station.core.localGone")));
    }
    for (const address of wanted) if (!this.#links.has(address)) this.#start(address);
  }

  #start(address: string): void {
    const core = this.#core;
    let addr: StationAddr;
    try {
      addr = StationAddr.parse(address);
    } catch {
      return;
    }
    const link = new Link(address, addr, core.runner.child());
    this.#links.set(address, link);
    // The last event it told a core before this one, written down with what it told: the first stream asks what came
    // after it, and nothing is read again when the station still has that (the app started again within the hour).
    const heard = core.data.record("heard", address);
    if (typeof heard === "string") heardEvent(link, heard);
    link.keptEvent = link.lastEvent;
    link.restored = link.lastEvent !== null;
    // How it was last time, until the link finds out anew: kept in its workspace's database, there as the link is.
    const last = core.data.record("link", address);
    if (last === "online" || last === "offline") link.state = { state: "connecting", last };
    else
      // As cores before kept it, in the host's storage (a file of its own): moved into the database once.
      core.runner.fork(
        Effect.ignore(
          Effect.gen({ self: this }, function* () {
            const bytes = yield* core.host.storageGet(`${LINK_KEY}/${address}`);
            if (!bytes) return;
            const was = new TextDecoder().decode(bytes);
            if ((was === "online" || was === "offline") && core.data.record("link", address) === undefined) {
              core.data.put("link", address, was);
              if (link.state.state === "connecting" && link.state.last === undefined) {
                link.state = { state: "connecting", last: was };
                this.onChange(address, "link");
              }
            }
            yield* core.host.storageDelete(`${LINK_KEY}/${address}`);
          }),
        ),
        link.scoped,
      );
    // Its figures as last heard, until it says them anew.
    core.runner.fork(
      Effect.map(Effect.orElseSucceed(core.host.storageGet(`${HOST_KEY}/${address}`), () => null), (bytes) => {
        if (!bytes || link.memory.has("host")) return;
        try {
          link.memory.set("host", JSON.parse(new TextDecoder().decode(bytes)));
        } catch {
          return;
        }
        this.onChange(address, "host");
      }),
      link.scoped,
    );
    this.openEvents(address, false);
  }

  setLink(address: string, value: Record<string, unknown>): void {
    const link = this.#links.get(address);
    if (!link) return;
    const state = value.state;
    if ((state === "online" || state === "offline") && this.#core.data.record("link", address) !== state) this.#core.data.put("link", address, state);
    link.state = value;
    this.onChange(address, "link");
  }

  /// Down, and tried again now: `reconnecting` until the try ends.
  #retrying(address: string): void {
    const link = this.#links.get(address);
    if (link && (link.state.state === "offline" || link.state.state === "error")) this.setLink(address, { state: "reconnecting", message: link.state.message ?? null });
  }

  // ── the events stream ──

  /// What the stream is to be opened for now: host samples while shown; the sessions at work (as the rows say) and
  /// those shown; the logs shown.
  #wants(address: string): EventsFor {
    const shown = this.wanted(address);
    const live = new Set(shown.live);
    for (const row of this.#core.data.running(address)) {
      for (const agent of (get(row, "agents") as unknown[] | undefined) ?? []) {
        const key = str(get(agent, "key"));
        if (key && get(agent, "process") === "running") live.add(key);
      }
    }
    return { host: shown.host, live: [...live].sort(), logs: [...shown.logs].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] - b[1])) };
  }

  /// Opens the station's stream for what it is wanted for now, unless the one open gives that (or `anew`): the new one
  /// opens first, and the old one goes once it has. An agent ending its turn opens none: as agents started and ended
  /// turns, a client's stream to a busy station was opened anew some 90 times an hour.
  openEvents(address: string, anew: boolean): void {
    const link = this.#links.get(address);
    if (!link || !this.reachable(address)) return;
    const wants = this.#wants(address);
    if (!anew && link.events && covers(link.events.wants, wants)) return;
    // Handed over from a stream that is open and heard lately (wanted for more or less now): it kept the records
    // current until the new one opens, so the new one reads nothing again. One quiet past a keepalive may have died
    // unnoticed (the device asleep): what it may have missed is read.
    const handover = !anew && link.events !== null && link.heard !== null && this.#core.host.nowMs() - link.heard < STREAM_QUIET_MS;
    if (link.events) {
      link.replaced?.pipe((f) => this.#core.runner.interrupt(f as Fiber.Fiber<unknown, unknown>));
      link.replaced = link.events.fiber;
    }
    const generation = ++link.generation;
    const fiber = this.#core.runner.fork(this.#follow(link, wants, generation, handover), link.scoped);
    link.events = { fiber, wants };
  }

  /// The stream's path for `wants`, each session asked for from the transcript items held; `since`: the last event the
  /// stream it takes over from gave (what was told after it comes first, else `missed`).
  #path(address: string, wants: EventsFor, since: Link["lastEvent"] = null): string {
    const query: string[] = [];
    if (wants.host) query.push("host=1");
    for (const key of wants.live) {
      const held = this.#core.data.logSpan("transcript", address, key);
      const from = held ? held.max + 1 : 0;
      query.push(`live=${encode(key)}&from=${from}&last=${TRANSCRIPT_PAGE}`);
    }
    // Their transcript entries in brief: what a history shows before a step is opened (`detail` reads it whole then).
    if (wants.live.length > 0) query.push("brief=1");
    for (const [job, lines] of wants.logs) query.push(`job=${encode(job)}&lines=${lines}`);
    if (since !== null) query.push(`since=${encode(`${since.run}.${since.n}`)}`);
    return query.length === 0 ? "/events" : `/events?${query.join("&")}`;
  }

  /// Holds the station's stream open; its events keep the records current. Each open reads the station again.
  #follow(link: Link, wants: EventsFor, generation: number, handover = false): Effect.Effect<void, never> {
    const core = this.#core;
    const self = this;
    const address = link.address;
    return Effect.gen(function* () {
      let first = true;
      let handing = handover;
      /// How the stream before this one ended: why, how long it lasted, what came on it (over the link, and as read).
      let previous: { why: string; lasted: number; bytes: number; read: number; events: number } | null = null;
      let misses = 0;
      let reached = false;
      for (;;) {
        // Replaced before it opened: its successor asks instead.
        if (link.generation !== generation) return;
        const span = core.tracer.root(first ? "station.connect" : "station.reconnect", Kind.Internal);
        first = false;
        span.set("stillfail.station", address);
        if (previous) {
          span.set("stillfail.previous.end", previous.why);
          span.set("stillfail.previous.lasted_ms", Math.round(previous.lasted));
          if (previous.events > 0 || previous.bytes > 0) {
            span.set("stillfail.previous.bytes", previous.bytes);
            span.set("stillfail.previous.read_bytes", previous.read);
            span.set("stillfail.previous.events", previous.events);
          }
        }
        // Each try in a scope of its own: the stream closes with it.
        const ended = yield* Effect.scoped(
          Effect.gen(function* () {
            // Asked anew each time: a session is followed from what is held of it by then. From the last event heard
            // (taking over from a stream still open, or coming back after one went): what came after it comes first.
            const since = link.lastEvent;
            const path = self.#path(address, wants, since);
            const sent = core.host.nowMs();
            const races = self.wire.races?.() ?? false;
            // Still opening as the UI comes back from being away since before: tried anew.
            const dropped = Effect.flatMap(
              core.wakes.until((w) => {
                if (w.suspectsConnections() || w.dropsRequest(sent)) {
                  if (!(!races && w.dropsRequest(sent))) self.#retrying(address);
                  return !races && w.dropsRequest(sent);
                }
                return false;
              }),
              () => Effect.succeed({ dropped: true } as const),
            );
            const opened = yield* Effect.raceFirst(Effect.result(self.requests.stream(link.addr, path, span.context)), dropped);
            if ("dropped" in opened) {
              self.wire.reset?.(link.addr);
              span.fail();
              span.end();
              return { again: true, why: GONE } as const;
            }
            // Its successor took over meanwhile.
            if (link.generation !== generation) return { done: true } as const;
            if (link.replaced) {
              core.runner.interrupt(link.replaced as Fiber.Fiber<unknown, unknown>);
              link.replaced = null;
            }
            if (opened._tag === "Failure") {
              const error = opened.failure;
              span.fail();
              span.set("error.type", error.code);
              span.end();
              misses++;
              // It answered, but no: it is there. Not reached at all: coming back, or down.
              const state = error.status !== undefined ? "error" : reached && misses < MISSES ? "reconnecting" : "offline";
              self.setLink(address, { state, message: error.message });
              return { failed: `open failed: ${error.message}` } as const;
            }
            const body = opened.success.body;
            misses = 0;
            reached = true;
            link.heard = core.host.nowMs();
            self.setLink(address, { state: "online" });
            // Told what came after the last event heard (RESUMED): nothing is read again. Otherwise (the first stream,
            // one that could not be resumed, a station from before) what the station holds is read now, in the trace of
            // its connecting; unless this stream took over from one still open (a station from before resuming says
            // `missed` when it cannot tell all it missed).
            const resumed = since !== null && replyHeader(opened.success, RESUMED) === "1";
            span.set("stillfail.resumed", resumed);
            if (link.restored) span.set("stillfail.restored", true);
            span.end();
            let snapshotted = !handing && !resumed;
            if (snapshotted) self.snapshot(address, span.context);
            // Taken up from where a core before this one was: its history is swept as a reading of everything would.
            else if (link.restored) self.#historyStart(address);
            link.restored = false;
            handing = false;
            const parser = new SseParser();
            const openedAt = core.host.nowMs();
            // What came on it, for the span of the stream after it.
            let read = 0;
            let events = 0;
            let why = "ended";
            let heard = openedAt;
            const replaced = self.wire.replaced ? self.wire.replaced(link.addr).pipe(Effect.as({ replaced: true } as const)) : Effect.never;
            const gone = Effect.suspend(() => core.wakes.until((w) => !races && w.dropsStream(heard))).pipe(Effect.as({ gone: true } as const));
            const idle = Effect.sleep(STREAM_IDLE_MS).pipe(Effect.as({ idle: true } as const));
            for (;;) {
              const next = yield* Effect.raceAllFirst([Effect.result(Effect.mapError(body.take, asCoreError)).pipe(Effect.map((r) => ({ chunk: r }) as const)), gone, replaced, idle]);
              if ("gone" in next) {
                self.wire.reset?.(link.addr);
                why = GONE;
                break;
              }
              if ("replaced" in next) {
                why = t("station.core.replaced");
                break;
              }
              if ("idle" in next) {
                why = t("station.core.streamIdle");
                break;
              }
              if (next.chunk._tag === "Failure") {
                why = next.chunk.failure.message;
                break;
              }
              const chunk = next.chunk.success;
              if (chunk === null) break;
              heard = core.host.nowMs();
              link.heard = heard;
              read += chunk.length;
              for (const [name, data, id] of parser.feed(chunk)) {
                events++;
                // Not all that was missed could be told: read again (once for this stream).
                if (name === "missed") {
                  if (!snapshotted) self.snapshot(address);
                  snapshotted = true;
                } else self.onEvent(address, name, data);
                if (id !== undefined) heardEvent(link, id);
              }
              // Written down in the same write as what the events changed: a core after this one takes up from it.
              if (link.lastEvent !== link.keptEvent && link.lastEvent !== null) {
                core.data.put("heard", address, `${link.lastEvent.run}.${link.lastEvent.n}`);
                link.keptEvent = link.lastEvent;
              }
            }
            if (link.generation !== generation) return { done: true } as const;
            link.heard = null;
            const woke = why === GONE || why === NETWORK || why === t("station.core.replaced");
            self.setLink(address, { state: "reconnecting", message: why === "ended" ? t("station.core.disconnected") : why });
            return { again: woke, why, lasted: core.host.nowMs() - openedAt, bytes: opened.success.came?.bytes ?? read, read, events } as const;
          }),
        );
        if ("done" in ended) return;
        if ("again" in ended) {
          previous = "lasted" in ended
            ? { why: ended.why ?? "", lasted: ended.lasted ?? 0, bytes: ended.bytes ?? 0, read: ended.read ?? 0, events: ended.events ?? 0 }
            : { why: ended.why ?? "", lasted: 0, bytes: 0, read: 0, events: 0 };
          if (ended.again) continue;
        } else previous = { why: ended.failed, lasted: 0, bytes: 0, read: 0, events: 0 };
        // Not reached: less and less often, and seldom while still.fail cloud says it is not online or it has not been
        // reached for long. A UI back after being away wants it now, and so does the cloud saying it is back.
        const offline = self.#cloudSaysOffline(address) || misses >= LONG_MISSES;
        const wait = offline ? OFFLINE_RETRY_MS : Math.min(RECONNECT_MS * 2 ** Math.min(Math.max(misses - 1, 0), 8), RECONNECT_MAX_MS);
        const back = self.#backOf(address);
        const woken = yield* Effect.raceFirst(Effect.sleep(wait).pipe(Effect.as(false)), Effect.raceFirst(core.wakes.next.pipe(Effect.as(true)), Deferred.await(back).pipe(Effect.as(true))));
        if (woken) self.#retrying(address);
      }
    });
  }

  // ── reading what a station holds ──

  /// Everything the station holds, read again (its stream opened): the lists, then what they name. One span
  /// (`station.read`, under `parent` where given) has each read under it, and ends once they all have.
  snapshot(address: string, parent: SpanContext | null = null): void {
    const p = Priority.shown;
    const span = this.#core.tracer.span("station.read", Kind.Internal, parent);
    span.set("stillfail.station", address);
    const ctx = span.context;
    const read = (topic: Topic, path: string) => this.#read(address, topic, path, undefined, ctx);
    const done = [
      this.#enqueue(address, "overview", p, read({ topic: "overview", station: address }, "/overview")),
      this.#enqueue(address, "sessions", p, Effect.andThen(read({ topic: "sessions", station: address }, "/sessions"), Effect.sync(() => this.#historyStart(address)))),
      this.#enqueue(address, "threads", p, Effect.andThen(read({ topic: "threads", station: address }, "/threads"), Effect.sync(() => this.#historyStart(address)))),
      this.#enqueue(address, "chats", p, Effect.andThen(read({ topic: "chatRows", station: address }, "/chats"), Effect.sync(() => this.openEvents(address, false)))),
      ...this.#archivedChanged(address, ctx),
      this.#enqueue(address, "jobs", p, read({ topic: "jobs", station: address }, "/jobs")),
      this.#enqueue(address, "footprint", Priority.background, read({ topic: "footprint", station: address }, "/footprint")),
      ...this.#usageChanged(address, ctx),
      ...this.#slackConnects(address).map((id) => this.#enqueue(address, `slackApp/${id}`, Priority.background, read({ topic: "slackApp", station: address, connect: id }, `/connects/${encode(id)}/slack-app`))),
    ];
    this.#core.runner.fork(Effect.ensuring(Effect.ignore(Effect.all(done.map((d) => Deferred.await(d)), { mode: "result" })), Effect.sync(() => span.end())));
  }

  /// A job's log as it is now (its `lines` last lines), once: its topic opened. The station's stream says how it grows
  /// from then on (an older station's does not: its log is as it was when opened, docs/core-ts.md).
  readLog(address: string, job: string, lines: number): void {
    const key = topicKey({ topic: "jobLog", station: address, job, lines });
    if (this.#links.get(address)?.memory.has(key)) return;
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
        if (!link.memory.has(key)) {
          link.memory.set(key, { text: get(answer, "text") ?? "", outputAt: get(answer, "outputAt") ?? null });
          this.onChange(address, "log", key);
        }
      }),
    );
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
  #read(address: string, topic: Topic, path: string, shape?: (answer: unknown) => unknown, ctx: SpanContext | null = null, attempt = 0): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.reachable(address) || !this.#links.has(address)) return;
      const link = this.#links.get(address)!;
      const answer = yield* Effect.result(shape ? this.requests.call(link.addr, "GET", path, null, { quiet: true, ctx }) : this.#whole(link, topic, path, ctx));
      const key = topicKey(topic);
      if (answer._tag === "Success") {
        link.errors.delete(key);
        this.#core.data.set(topic, shape ? shape(answer.success) : answer.success);
      } else if (this.#core.data.shared(topic) === undefined && answer.failure.status !== undefined && answer.failure.status >= 400 && answer.failure.status < 500) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      } else if ((answer.failure.status === undefined || answer.failure.status >= 500) && attempt < READ_RETRIES) {
        const again = Effect.sleep(READ_RETRY_MS * 2 ** attempt).pipe(
          Effect.andThen(Effect.sync(() => void this.#enqueue(address, `again/${key}`, Priority.background, this.#read(address, topic, path, shape, null, attempt + 1)))),
        );
        this.#core.runner.fork(again, link.scoped);
      }
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
    return Effect.gen({ self: this }, function* () {
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
      // More to bring: asked again, behind what is more urgent.
      if (link.history.length > 0) this.#enqueue(address, "history", Priority.background, this.#history(address, 0));
    });
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
    for (const id of data.threadIds(address)) {
      const read = this.#entriesRead(address, id);
      if (read !== null) reads.push(read);
    }
    for (const [key] of sessions) {
      if (data.evicted("transcript", address, key) || data.logSpan("transcript", address, key) !== null) continue;
      reads.push({ path: latestPage(key), cost: TRANSCRIPT_COST, apply: (a) => (this.#tookTranscript(address, key, a), null) });
    }
    return reads;
  }

  /// A thread's next page of entries as a read of its history, the read after it while pages come.
  #entriesRead(address: string, id: number): HistoryRead | null {
    const path = this.#entriesPath(address, id);
    if (path === null) return null;
    const apply = (a: { status: number; body: unknown }) => {
      const came = this.#tookEntries(address, id, a.status >= 200 && a.status < 300 ? { ok: a.body } : { error: httpError(a.status, a.body) });
      return came > 0 ? this.#entriesRead(address, id) : null;
    };
    return { path, cost: 1, apply };
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

  /// The latest page of a session's transcript answered in a batch, as `transcript` takes it.
  #tookTranscript(address: string, key: string, a: { status: number; body: unknown }): void {
    if (a.status < 200 || a.status >= 300) return;
    this.#putTranscript(address, key, a.body, 0);
  }

  /// A station from before batches: its history a read a task, each its own request.
  #historyEach(address: string): void {
    const link = this.#links.get(address);
    if (link) link.history = [];
    for (const [key, again] of this.#core.data.sessionsToRead(address)) {
      if (again) this.#enqueue(address, `session/${key}`, Priority.background, this.#session(address, key));
      this.syncTranscript(address, key, Priority.background - 1);
    }
    for (const id of this.#core.data.threadIds(address)) this.syncEntries(address, id, Priority.background);
  }

  #session(address: string, key: string): Effect.Effect<void, CoreError> {
    return this.#read(address, { topic: "session", station: address, key }, `/sessions/${encode(key)}`);
  }

  /// Brings a thread's entries onto the device: what came after what is held, then any gap, then the pages before,
  /// one page a run (the task asks itself again while there is more, so what is more urgent goes between); `once`: the
  /// next page only (a chat opened, the rest of its history coming with the station's, #history).
  syncEntries(address: string, id: number, priority: number, once = false): void {
    // Let go for room and not opened since: left as it is (data.ts KEPT).
    if (this.#core.data.evicted("entry", address, String(id))) return;
    this.#enqueue(address, `entries/${id}`, priority, this.#entriesPage(address, id, priority, once));
  }

  /// The highest entry a thread is missing on the device, as far as it is known to go (`held`: the numbers held, in
  /// order).
  #missing(address: string, id: number, held: number[]): number | null {
    let n = Math.max(this.#core.data.threadLast(address, id), held.length > 0 ? held[held.length - 1] : 0);
    for (let i = held.length - 1; n >= 1; n--) {
      while (i >= 0 && held[i] > n) i--;
      if (i < 0 || held[i] !== n) return n;
    }
    return null;
  }

  /// The read that brings a thread's next page of entries onto the device: what came after what is held, then any gap
  /// (from just past the held entry below it, a page at most), the latest page when none is held; null when it has
  /// them all, or they were let go for room and it was not opened since.
  #entriesPath(address: string, id: number): string | null {
    const data = this.#core.data;
    if (data.evicted("entry", address, String(id))) return null;
    const held = data.logNumbers("entry", address, String(id));
    if (held.length === 0) return `/threads/${id}/entries?limit=${PAGE}`;
    const top = held[held.length - 1];
    if (data.threadLast(address, id) > top) return `/threads/${id}/entries?after=${top}`;
    const missing = this.#missing(address, id, held);
    if (missing === null) return null;
    let below = 0;
    for (const n of held) if (n < missing && n > below) below = n;
    return `/threads/${id}/entries?from=${Math.max(below + 1, missing - PAGE + 1)}&to=${missing}`;
  }

  /// Whether a thread misses entries between the lowest it holds and its latest (a gap what was told left), as against
  /// history older than what is held (brought with the station's, #history).
  #gapAbove(address: string, id: number): boolean {
    const held = this.#core.data.logNumbers("entry", address, String(id));
    if (held.length === 0) return false;
    const missing = this.#missing(address, id, held);
    return missing !== null && missing > held[0]!;
  }

  /// Whether a thread's latest entries are not on the device: none held, or its summary goes further.
  latestMissing(address: string, id: number): boolean {
    const held = this.#core.data.logSpan("entry", address, String(id));
    return held === null || this.#core.data.threadLast(address, id) > held.max;
  }

  #entriesPage(address: string, id: number, priority: number, once: boolean): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const path = this.#entriesPath(address, id);
      if (path === null) return;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", path, null, { quiet: true }));
      const entries = this.#tookEntries(address, id, answer._tag === "Success" ? { ok: answer.success } : { error: answer.failure });
      // More to bring: asked again, behind what is more urgent.
      if (!once && entries > 0 && this.#entriesPath(address, id) !== null) this.syncEntries(address, id, priority);
    });
  }

  /// A page of a thread's entries as the station answered it: into its log; a thread that is gone goes with what is held
  /// of it; one not to be read (no longer this viewer's) says so while nothing of it is held. How many came.
  #tookEntries(address: string, id: number, answer: { ok: unknown } | { error: CoreError }): number {
    const link = this.#links.get(address);
    if (!link) return 0;
    const topic = topicKey({ topic: "thread", station: address, thread: id });
    if ("error" in answer) {
      const status = answer.error.status;
      if (status === 404) this.#threadGone(address, id);
      else if (status !== undefined && status >= 400 && status < 500 && this.#core.data.logSpan("entry", address, String(id)) === null) {
        link.errors.set(topic, answer.error);
        this.onChange(address, "errors", topic);
      }
      return 0;
    }
    if (link.errors.delete(topic)) this.onChange(address, "errors", topic);
    const entries = (get(answer.ok, "entries") as unknown[] | undefined) ?? [];
    this.putEntries(address, id, entries);
    return entries.length;
  }

  /// Entries into a thread's log.
  putEntries(address: string, id: number, entries: unknown[]): void {
    const items: [number, unknown][] = entries.flatMap((e) => {
      const n = nOf(e);
      return n === null ? [] : [[n, e] as [number, unknown]];
    });
    if (items.length > 0) this.#core.data.putItems("entry", address, String(id), items);
  }

  /// Brings a session's transcript onto the device (its latest page), unless it was let go for room and not opened since.
  syncTranscript(address: string, key: string, priority: number): void {
    if (this.#core.data.evicted("transcript", address, key)) return;
    this.#enqueue(address, `transcript/${key}`, priority, this.transcript(address, key, null));
  }

  /// A session's transcript: its latest page when none is held, or the page before `before` (history.older).
  transcript(address: string, key: string, before: number | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      if (before === null && this.#core.data.logSpan("transcript", address, key) !== null) return;
      const page = yield* this.requests.call(link.addr, "GET", before === null ? latestPage(key) : `/sessions/${encode(key)}/timeline?before=${before}&limit=${TRANSCRIPT_PAGE}&brief=1`, null, { quiet: before === null });
      this.#putTranscript(address, key, page, 0);
    });
  }

  /// A page of a session's transcript into its log, from its `start` (else `from`).
  #putTranscript(address: string, key: string, page: unknown, from: number): void {
    const start = u64(get(page, "start")) ?? from;
    const items = (get(page, "entries") as unknown[] | undefined) ?? [];
    if (items.length > 0) this.#core.data.putItems("transcript", address, key, items.map((item, i) => [start + i, item] as [number, unknown]));
  }

  /// A session's transcript entries `from` to `to` whole, in place of what is held of them in brief (`history.detail`):
  /// never pushed, read when a history's step is opened, behind what is shown in brief (Priority.detail). Asked for by
  /// someone waiting on it, it is tried while the station seems away too: what went wrong is theirs to see.
  detail(address: string, key: string, from: number, to: number): Effect.Effect<void, CoreError> {
    const work = Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link) return;
      const page = yield* this.requests.call(link.addr, "GET", `/sessions/${encode(key)}/timeline?from=${from}&to=${to}`, null, { quiet: true });
      this.#putTranscript(address, key, page, from);
    });
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
    switch (name) {
      case "session":
        return this.#onSession(address, data);
      case "session-removed": {
        const key = str(get(data, "key"));
        if (key) this.#onSessionRemoved(address, key);
        return;
      }
      case "thread": {
        const id = u64(get(data, "id"));
        if (id === null) return;
        const entries = (get(data, "entries") as unknown[] | undefined) ?? [];
        const newest = Math.max(-1, ...entries.map((e) => nOf(e) ?? -1));
        // How far the thread goes, at once; the rest of its summary is read below.
        if (newest >= 0) core.data.raiseLast(address, id, newest);
        this.onTold(address, id, entries);
        // A chat let go for room (and not opened since) is not kept current: what it said is read when it is opened.
        // A gap what was told left is read at once; history older than what is held comes with the station's (#history).
        if (!core.data.evicted("entry", address, String(id))) {
          this.putEntries(address, id, entries);
          if (this.#gapAbove(address, id)) this.syncEntries(address, id, Priority.shown, true);
        }
        // Its summary for the viewer: told by the station (`thread-view`) when it tells it, else read.
        const viewed = this.#links.get(address)?.viewed.get(id);
        if (viewed === undefined || viewed < newest) this.#markDirty(address, id);
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
        return this.putRow(address, data);
      case "chat-removed": {
        const id = str(get(data, "id"));
        if (id) core.data.dropChat(address, id);
        return;
      }
      case "live": {
        const key = str(get(data, "key"));
        if (key) this.#onLive(address, key, data);
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
      case "job-log": {
        const id = str(get(data, "id"));
        const lines = u64(get(data, "lines"));
        const link = this.#links.get(address);
        if (id && lines !== null && link) {
          const key = topicKey({ topic: "jobLog", station: address, job: id, lines });
          link.memory.set(key, { text: get(data, "text") ?? "", outputAt: get(data, "outputAt") ?? null });
          this.onChange(address, "log", key);
        }
        return;
      }
      case "overview":
        core.data.set({ topic: "overview", station: address }, data);
        return;
      // The stream that took over could not be told all that came since the last its predecessor gave: read again.
      case "missed":
        return this.snapshot(address);
      case "host": {
        const link = this.#links.get(address);
        if (link) {
          link.memory.set("host", data);
          this.onChange(address, "host");
          const now = core.host.nowMs();
          if (now - link.hostSaved >= HOST_SAVE_MS) {
            link.hostSaved = now;
            core.runner.fork(Effect.ignore(core.host.storageSet(`${HOST_KEY}/${address}`, new TextEncoder().encode(JSON.stringify(data)))));
          }
        }
        return;
      }
      case "usage":
        this.#usageChanged(address);
        return;
      case "footprint":
        core.data.set({ topic: "footprint", station: address }, data);
        return;
    }
  }

  /// A session's summary changed: in place among the listed (and in its detail); its detail is read again when its
  /// turns changed.
  #onSession(address: string, summary: unknown): void {
    const key = str(get(summary, "key"));
    if (!key) return;
    if (this.#core.data.putSummary(address, summary)) this.#enqueue(address, `session/${key}`, Priority.shown, this.#session(address, key));
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

  /// A row of the viewer's sidebar, new or changed.
  putRow(address: string, row: unknown): void {
    this.#core.data.putChat(address, row);
    // An agent starting or ending its turn: the stream follows what is at work.
    this.openEvents(address, false);
  }

  /// A thread's summary into the station's threads, and the details of the sessions taking part.
  putThread(address: string, view: unknown): void {
    this.#core.data.putThread(address, view);
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
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link) return;
      const view = yield* Effect.result(this.requests.call(link.addr, "GET", `/threads/${id}`, null, { quiet: true }));
      if (view._tag === "Success") this.putThread(address, view.success);
      else if (view.failure.status === 404) this.#core.data.unlistThread(address, id);
    });
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
        core.data.putItems("transcript", address, key, entries.map((e, i) => [start + i, e] as [number, unknown]), start < top ? start + entries.length - 1 : null);
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
      } else if (kind === "step") {
        const event = get(message, "event");
        if (event !== undefined) applyStep(view, event, now);
      } else return;
      this.onChange(address, "live", key);
    }
  }

  /// What the chat shows of a session at work (activity.ts), from its live view.
  activity(view: Record<string, unknown>): unknown {
    return historyActivity(view);
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
        case "identity":
          read("overview", { topic: "overview", station: address }, "/overview");
          rows();
          break;
      }
      // Profile and connect edits answer the overview as it is now.
      if (get(answer, "connects") !== undefined && get(answer, "profiles") !== undefined) {
        this.#core.data.set({ topic: "overview", station: address }, answer);
        reads.splice(0, reads.length, ...reads.filter(([what]) => what !== "overview"));
      }
      yield* Effect.all(
        reads.map(([what, work]) => Effect.ignore(this.ask(address, what, work))),
        { concurrency: "unbounded", discard: true },
      );
    });
  }

  /// Runtimes first, the station last: one at a time, each awaited to its end (the overview as it goes).
  #updateAll(addr: StationAddr, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const address = addr.toString();
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
        for (;;) {
          const status = Array.isArray(answer) ? answer.find((v) => get(v, "id") === id) : undefined;
          if (status === undefined) return yield* Effect.fail(CoreError.invalid(t("station.core.progressUnreadable")));
          if (get(status, "state") === "failed") {
            const name = str(get(item, "name")) ?? id;
            const message = str(get(status, "message")) ?? t("station.core.retryInDetails");
            return yield* Effect.fail(CoreError.invalid(t("station.core.updateFailed", { name, error: message })));
          }
          if (get(status, "state") !== "updating") break;
          if (this.#core.host.nowMs() >= deadline) return yield* Effect.fail(CoreError.invalid(t("station.core.updateUnfinished")));
          yield* Effect.sleep(1000);
          const now = yield* this.requests.call(addr, "GET", "/overview", null, { ctx });
          this.#core.data.set({ topic: "overview", station: address }, now);
          answer = get(now, "updates");
        }
      }
      return answer;
    });
  }

  /// A person's message into a thread; answers its entry number once the thread's entries hold it.
  post(address: string, thread: number, message: unknown, ctx: SpanContext | null, idempotency?: string): Effect.Effect<number, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const addr = StationAddr.parse(address);
      const headers: [string, string][] = idempotency ? [[IDEMPOTENCY_KEY, idempotency]] : [];
      const answer = yield* this.requests.call(addr, "POST", `/threads/${thread}/messages`, message, { ctx, headers });
      const n = u64(get(answer, "n"));
      if (n === null) return yield* Effect.fail(new CoreError("bad_response", t("station.core.noMessageNumber")));
      // The thread goes that far now: what came after what is held is read.
      this.#core.data.raiseLast(address, thread, n);
      if (this.#core.data.logCount("entry", address, String(thread), n, n) === 0) yield* Effect.ignore(this.ask(address, `entries/${thread}`, this.#entriesPage(address, thread, Priority.asked, true)));
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

  /// The page of a thread's entries before `before`, onto the device (a person scrolled up): from what is held, else
  /// read now. Answers whether older ones exist.
  older(address: string, thread: number, before: number, ctx: SpanContext | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const from = Math.max(1, before - PAGE);
      const all = this.#core.data.logCount("entry", address, String(thread), from, before - 1) === before - from;
      if (all || before <= 1) return;
      const page = yield* this.requests.call(StationAddr.parse(address), "GET", `/threads/${thread}/entries?before=${before}&limit=${PAGE}`, null, { ctx });
      this.putEntries(address, thread, ((get(page, "entries") as unknown[] | undefined) ?? []).filter((e) => (nOf(e) ?? Infinity) < before));
    });
  }

  /// Entries `from ..= to` onto the device (a window moved there): read now if not all held.
  range(address: string, thread: number, from: number, to: number, ctx: SpanContext | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (to < from) return;
      if (this.#core.data.logCount("entry", address, String(thread), from, to) === to - from + 1) return;
      const page = yield* this.requests.call(StationAddr.parse(address), "GET", `/threads/${thread}/entries?from=${from}&to=${to}`, null, { ctx });
      this.putEntries(address, thread, ((get(page, "entries") as unknown[] | undefined) ?? []).filter((e) => {
        const n = nOf(e);
        return n !== null && n >= from && n <= to;
      }));
    });
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
    for (const link of this.#links.values()) this.#core.runner.close(link.scoped);
    this.#links.clear();
  }

  /// A link scope's fibers are interrupted with it.
  static scope = Scope;
  static exit = Exit;
  static join = join;
}
