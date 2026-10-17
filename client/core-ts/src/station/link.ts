// A station's link: its `/admin/api/events` stream, held open for as long as the station is reached, and opened again
// with backoff when it drops (docs/core-ts.md, rule 6). Every station of every workspace an account reaches has one.
//
// This is the way to a station only: when its stream is opened, tried again, or taken over by another that follows
// something else. What comes on it and what is read as it opens is the sync's (sync.ts), told here as `Told`: a stream
// opens either afresh (nothing says what the device missed: the station is read again) or going on from where the
// device was in the station's log of events (cursor.ts: what changed meanwhile is told first).
import { Deferred, Effect, type Fiber } from "effect";
import type { Inner } from "../core.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { encode } from "../ops.ts";
import type { Scoped } from "../runtime.ts";
import { Kind, type SpanContext } from "../trace.ts";
import { equal, get, isObject } from "../util.ts";
import { GONE, NETWORK } from "../wake.ts";
import { StationAddr } from "./addr.ts";
import { TRANSCRIPT_PAGE } from "./channel-kinds.ts";
import { Cursor } from "./cursor.ts";
import { RESUMED, type Requests } from "./requests.ts";
import { SseParser } from "./sse.ts";
import { replyHeader } from "./wire.ts";

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

/// The steps in flight and the phase of a session at work, as its stream says them.
export type LiveView = { steps: unknown[]; phase: unknown | null; rate: number | null; usage: unknown; loaded: boolean };

/// What a station's `/events` stream is opened for: host samples, the sessions followed as they run, the jobs' logs.
export type EventsFor = { host: boolean; live: string[]; logs: [string, number][]; logins?: string[] };

/// Whether a stream opened for `open` gives what `wants` asks: the same host samples and logs, and every session it
/// asks among those it follows. One that follows more is kept: a session no longer at work or shown says little more.
function covers(open: EventsFor, wants: EventsFor): boolean {
  return open.host === wants.host && equal(open.logs, wants.logs) && equal(open.logins ?? [], wants.logins ?? []) && wants.live.every((key) => open.live.includes(key));
}

/// A read of a station's history (sync.ts `#history`): its path, how much of a batch it takes, and what its answer
/// does (and the read after it, as a channel has more to bring).
export type HistoryRead = { path: string; cost: number; apply: (answer: { status: number; body: unknown }) => HistoryRead | null };

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
  /// When the station last answered a request (2xx); null until one is.
  answered: number | null = null;
  /// Where it is in the station's log of events: what its next stream goes on from (cursor.ts).
  cursor = new Cursor();
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

/// What the links tell the sync, and ask it.
export type Told = {
  /// What a station's stream is wanted for beyond the sessions at work: what a UI shows of it.
  wanted(address: string): EventsFor;
  /// A stream opened with nothing saying what the device missed (the first, one that could not go on from where the
  /// device was, or one that said so after it opened: `missed`): what the station holds is read again.
  afresh(address: string, ctx: SpanContext | null): void;
  /// A stream opened going on from where the device was. `away`: it came back after the one before it went, as against
  /// taking over from one still heard; `restored`: where the device was is as a core before this one wrote it down.
  goesOn(address: string, how: { away: boolean; restored: boolean }): void;
  /// An event of a stream.
  event(address: string, name: string, raw: string): void;
  /// How a station's link is, or its host figures as last kept, changed.
  changed(address: string, what: "link" | "host"): void;
  /// A station is no longer linked.
  gone(address: string): void;
};

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

export class Links {
  readonly #core: Inner;
  readonly #requests: Requests;
  readonly #told: Told;
  readonly #links = new Map<string, Link>();

  constructor(core: Inner, requests: Requests, told: Told) {
    this.#core = core;
    this.#requests = requests;
    this.#told = told;
  }

  get(address: string): Link | undefined {
    return this.#links.get(address);
  }

  has(address: string): boolean {
    return this.#links.has(address);
  }

  values(): Link[] {
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

  /// The station answered a request: it is reached, and its stream waiting to be tried again (for as long as
  /// OFFLINE_RETRY_MS) is tried now. A person's message went through and what it brought was read, while what the
  /// agent said after it stayed unsaid until the wait was over.
  answered(address: string): void {
    const link = this.#links.get(address);
    if (!link) return;
    link.answered = this.#core.host.nowMs();
    if (link.heard === null) this.cameOnline(address);
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
      this.#told.gone(address);
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
    // after it, and nothing is read again when the station still has that (the app started again within the hour). Not
    // when its lists are not held (a database begun anew): they are read.
    const heard = core.data.record("heard", address);
    const held = (["chats", "sessions", "threads"] as const).every((list) => core.data.listed(address, list));
    link.cursor = new Cursor(typeof heard === "string" && held ? heard : null);
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
                this.#told.changed(address, "link");
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
        this.#told.changed(address, "host");
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
    this.#told.changed(address, "link");
  }

  /// Down, and tried again now, until the try ends: one found offline is still taken for down (views.ts `down`), what
  /// shows of it unchanged but its 重试 turning (`retrying`), so a try that fails moves nothing; one that answered with
  /// an error is coming back.
  #retrying(address: string): void {
    const link = this.#links.get(address);
    const state = link?.state.state;
    if (state === "offline") this.setLink(address, { state: "connecting", last: "offline", retrying: true, message: link?.state.message ?? null });
    else if (state === "error") this.setLink(address, { state: "reconnecting", message: link?.state.message ?? null });
  }

  // ── the events stream ──

  /// What the stream is to be opened for now: host samples while shown; the sessions at work (as the rows say) and
  /// those shown; the logs shown.
  #wants(address: string): EventsFor {
    const shown = this.#told.wanted(address);
    const live = new Set(shown.live);
    for (const row of this.#core.data.running(address)) {
      for (const agent of (get(row, "agents") as unknown[] | undefined) ?? []) {
        const key = str(get(agent, "key"));
        if (key && get(agent, "process") === "running") live.add(key);
      }
    }
    return { host: shown.host, live: [...live].sort(), logs: [...shown.logs].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] - b[1])), logins: [...(shown.logins ?? [])].sort() };
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
  #path(address: string, wants: EventsFor, since: string | null = null): string {
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
    // The logins' terminals shown (docs/remote-login.md).
    for (const id of wants.logins ?? []) query.push(`login=${encode(id)}`);
    if (since !== null) query.push(`since=${encode(since)}`);
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
        const tried = core.host.nowMs();
        // Each try in a scope of its own: the stream closes with it.
        const ended = yield* Effect.scoped(
          Effect.gen(function* () {
            // Asked anew each time: a session is followed from what is held of it by then. From the last event heard
            // (taking over from a stream still open, or coming back after one went): what came after it comes first.
            const since = link.cursor.since;
            const path = self.#path(address, wants, since);
            const sent = core.host.nowMs();
            const races = self.#requests.wire.races?.() ?? false;
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
            const opened = yield* Effect.raceFirst(Effect.result(self.#requests.stream(link.addr, path, span.context)), dropped);
            if ("dropped" in opened) {
              self.#requests.wire.reset?.(link.addr);
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
            if (link.cursor.restored) span.set("stillfail.restored", true);
            span.end();
            let snapshotted = !handing && !resumed;
            if (snapshotted) self.#told.afresh(address, span.context);
            // Told what changed while it was away, or handed over from a stream still heard (nothing was away).
            else self.#told.goesOn(address, { away: !handing, restored: link.cursor.restored });
            link.cursor.restored = false;
            handing = false;
            const parser = new SseParser();
            const openedAt = core.host.nowMs();
            // What came on it, for the span of the stream after it.
            let read = 0;
            let events = 0;
            let why = "ended";
            let heard = openedAt;
            const replaced = self.#requests.wire.replaced ? self.#requests.wire.replaced(link.addr).pipe(Effect.as({ replaced: true } as const)) : Effect.never;
            const gone = Effect.suspend(() => core.wakes.until((w) => !races && w.dropsStream(heard))).pipe(Effect.as({ gone: true } as const));
            const idle = Effect.sleep(STREAM_IDLE_MS).pipe(Effect.as({ idle: true } as const));
            for (;;) {
              const next = yield* Effect.raceAllFirst([Effect.result(Effect.mapError(body.take, asCoreError)).pipe(Effect.map((r) => ({ chunk: r }) as const)), gone, replaced, idle]);
              if ("gone" in next) {
                self.#requests.wire.reset?.(link.addr);
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
                  if (!snapshotted) self.#told.afresh(address, null);
                  snapshotted = true;
                } else self.#told.event(address, name, data);
                if (id !== undefined) link.cursor.heard(id);
              }
              // Written down in the same write as what the events changed: a core after this one takes up from it.
              const keep = link.cursor.toKeep();
              if (keep !== null) core.data.put("heard", address, keep);
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
        // reached for long. A UI back after being away wants it now, and so does the cloud saying it is back, or the
        // station answering a request. One that was up is coming back for MISSES tries whatever the cloud says (the
        // cloud hears of a station on another way than this one: a station whose stream had just ended was left
        // OFFLINE_RETRY_MS untried); one that answered a request since this try began is tried again as one that is up.
        const answered = link.answered !== null && link.answered >= tried;
        const comingBack = reached && misses < MISSES;
        const offline = !answered && (misses >= LONG_MISSES || (!comingBack && self.#cloudSaysOffline(address)));
        const wait = offline ? OFFLINE_RETRY_MS : answered ? RECONNECT_MS : Math.min(RECONNECT_MS * 2 ** Math.min(Math.max(misses - 1, 0), 8), RECONNECT_MAX_MS);
        const back = self.#backOf(address);
        const woken = yield* Effect.raceFirst(Effect.sleep(wait).pipe(Effect.as(false)), Effect.raceFirst(core.wakes.next.pipe(Effect.as(true)), Deferred.await(back).pipe(Effect.as(true))));
        if (woken) self.#retrying(address);
      }
    });
  }

  /// Lets go of every link (the core closes).
  close(): void {
    for (const link of this.#links.values()) {
      this.#core.runner.close(link.scoped);
      this.#told.gone(link.address);
    }
    this.#links.clear();
  }
}
