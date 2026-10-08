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
import { IDEMPOTENCY_KEY, Requests, httpError } from "./requests.ts";
import { SseParser } from "./sse.ts";
import { readAll, type StationWire } from "./wire.ts";

/// How long a failed or ended stream waits before it is opened again; a station not reached is tried again at
/// RECONNECT_MS, doubling up to RECONNECT_MAX_MS.
export const RECONNECT_MS = 2_000;
export const RECONNECT_MAX_MS = 60_000;
/// How many tries in a row a station that was up may miss before it is taken for down.
export const MISSES = 3;
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
export const RECHECKING = "等它回来确认";

/// The steps in flight and the phase of a session at work, as its stream says them.
export type LiveView = { steps: unknown[]; phase: unknown | null; rate: number | null; usage: unknown; loaded: boolean };

/// What a station's `/events` stream is opened for: host samples, the sessions followed as they run, the jobs' logs.
export type EventsFor = { host: boolean; live: string[]; logs: [string, number][] };

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

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
  /// Sessions at work as their stream says (steps, phase, rate, usage).
  readonly lives = new Map<string, LiveView>();
  /// Threads whose summaries are read again once a burst of events is over.
  readonly dirty = new Set<number>();
  flushing = false;
  /// Whether it follows jobs' logs on its stream (as it said); null until one is read.
  followsLogs: boolean | null = null;
  /// What a read of a topic failed with while nothing is held of it.
  readonly errors = new Map<string, CoreError>();
  /// Host samples and jobs' logs as they come (measurements and output shown while watched).
  readonly memory = new Map<string, unknown>();
  /// When the host sample was last written down (HOST_KEY).
  hostSaved = 0;

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

  /// Opens the station's stream for what it is wanted for now, unless it is already open for that (or `anew`): the
  /// new one opens first, and the old one goes once it has.
  openEvents(address: string, anew: boolean): void {
    const link = this.#links.get(address);
    if (!link || !this.reachable(address)) return;
    const wants = this.#wants(address);
    if (!anew && link.events && equal(link.events.wants, wants)) return;
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
      let previous: [string, number] | null = null;
      let misses = 0;
      let reached = false;
      for (;;) {
        // Replaced before it opened: its successor asks instead.
        if (link.generation !== generation) return;
        const span = core.tracer.root(first ? "station.connect" : "station.reconnect", Kind.Internal);
        first = false;
        span.set("stillfail.station", address);
        if (previous) {
          span.set("stillfail.previous.end", previous[0]);
          span.set("stillfail.previous.lasted_ms", Math.round(previous[1]));
        }
        // Each try in a scope of its own: the stream closes with it.
        const ended = yield* Effect.scoped(
          Effect.gen(function* () {
            // Asked anew each time: a session is followed from what is held of it by then. Taking over from a stream
            // still open: what that one is yet to give (said before this one is the station's) comes on this one.
            const path = self.#path(address, wants, handing ? link.lastEvent : null);
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
            span.end();
            // Nothing is replayed: what the station holds is read now, in the trace of its connecting (unless this
            // stream took over from one still open).
            if (!handing) self.snapshot(address, span.context);
            handing = false;
            const parser = new SseParser();
            const openedAt = core.host.nowMs();
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
              for (const [name, data, id] of parser.feed(chunk)) {
                self.onEvent(address, name, data);
                if (id !== undefined) heardEvent(link, id);
              }
            }
            if (link.generation !== generation) return { done: true } as const;
            link.heard = null;
            const woke = why === GONE || why === NETWORK || why === t("station.core.replaced");
            self.setLink(address, { state: "reconnecting", message: why === "ended" ? t("station.core.disconnected") : why });
            return { again: woke, why, lasted: core.host.nowMs() - openedAt } as const;
          }),
        );
        if ("done" in ended) return;
        if ("again" in ended) {
          previous = [ended.why ?? "", "lasted" in ended ? (ended.lasted ?? 0) : 0];
          if (ended.again) continue;
        } else previous = [ended.failed, 0];
        // Not reached: less and less often. A UI back after being away wants it now.
        const wait = Math.min(RECONNECT_MS * 2 ** Math.min(Math.max(misses - 1, 0), 8), RECONNECT_MAX_MS);
        const woken = yield* Effect.raceFirst(Effect.sleep(wait).pipe(Effect.as(false)), core.wakes.next.pipe(Effect.as(true)));
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
      this.#enqueue(address, "sessions", p, Effect.andThen(read({ topic: "sessions", station: address }, "/sessions"), Effect.sync(() => this.#details(address)))),
      this.#enqueue(address, "threads", p, Effect.andThen(read({ topic: "threads", station: address }, "/threads"), Effect.sync(() => this.#entries(address)))),
      this.#enqueue(address, "chats", p, Effect.andThen(read({ topic: "chatRows", station: address }, "/chats"), Effect.sync(() => this.openEvents(address, false)))),
      this.#enqueue(address, "archived", Priority.background, read({ topic: "archivedRows", station: address }, "/chats?archived=1")),
      this.#enqueue(address, "jobs", p, read({ topic: "jobs", station: address }, "/jobs")),
      this.#enqueue(address, "footprint", Priority.background, read({ topic: "footprint", station: address }, "/footprint")),
      this.#enqueue(address, "usage", Priority.background, this.#usage(address, ctx)),
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
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", path, null, { quiet: true, ctx }));
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

  /// What the station's agents spent over the last 30 days, days as this device's clock has them.
  #usage(address: string, ctx: SpanContext | null = null): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const now = this.#core.host.nowMs();
      const offset = this.#core.host.utcOffsetMin(now);
      const day = 86_400_000;
      const local = Math.trunc(now) + offset * 60_000;
      const from = local - (((local % day) + day) % day) - 29 * day - offset * 60_000;
      return this.#read(address, { topic: "stationUsage", station: address }, `/usage?from=${from}&tz=${offset}`, undefined, ctx);
    });
  }

  /// Each listed session's detail (turns, threads, jobs) where it is not held or its turns changed, and the latest page
  /// of its transcript.
  #details(address: string): void {
    for (const [key, again] of this.#core.data.sessionsToRead(address)) {
      if (again) this.#enqueue(address, `session/${key}`, Priority.background, this.#session(address, key));
      this.syncTranscript(address, key, Priority.background - 1);
    }
  }

  #session(address: string, key: string): Effect.Effect<void, CoreError> {
    return this.#read(address, { topic: "session", station: address, key }, `/sessions/${encode(key)}`);
  }

  /// Every thread's entries, the latest first.
  #entries(address: string): void {
    for (const id of this.#core.data.threadIds(address)) this.syncEntries(address, id, Priority.background);
  }

  /// Brings a thread's entries onto the device: what came after what is held, then any gap, then the pages before,
  /// one page a run (the task asks itself again while there is more, so what is more urgent goes between).
  syncEntries(address: string, id: number, priority: number): void {
    // Let go for room and not opened since: left as it is (data.ts KEPT).
    if (this.#core.data.evicted("entry", address, String(id))) return;
    this.#enqueue(address, `entries/${id}`, priority, this.#entriesPage(address, id, priority));
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

  #entriesPage(address: string, id: number, priority: number): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address) || this.#core.data.evicted("entry", address, String(id))) return;
      const data = this.#core.data;
      const held = data.logNumbers("entry", address, String(id));
      let path: string;
      if (held.length === 0) path = `/threads/${id}/entries?limit=${PAGE}`;
      else {
        const top = held[held.length - 1];
        const listed = data.threadLast(address, id);
        if (listed > top) path = `/threads/${id}/entries?after=${top}`;
        else {
          const missing = this.#missing(address, id, held);
          if (missing === null) return;
          // The gap only: from just past the held entry below it, a page at most.
          let below = 0;
          for (const n of held) if (n < missing && n > below) below = n;
          path = `/threads/${id}/entries?from=${Math.max(below + 1, missing - PAGE + 1)}&to=${missing}`;
        }
      }
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", path, null, { quiet: true }));
      const topic = topicKey({ topic: "thread", station: address, thread: id });
      if (answer._tag === "Failure") {
        // A thread that is gone: what is held of it goes. One not to be read (no longer this viewer's): said so.
        const status = answer.failure.status;
        if (status === 404) this.#threadGone(address, id);
        else if (status !== undefined && status >= 400 && status < 500 && held.length === 0) {
          link.errors.set(topic, answer.failure);
          this.onChange(address, "errors", topic);
        }
        return;
      }
      if (link.errors.delete(topic)) this.onChange(address, "errors", topic);
      const entries = (get(answer.success, "entries") as unknown[] | undefined) ?? [];
      this.putEntries(address, id, entries);
      // More to bring: asked again, behind what is more urgent.
      if (entries.length > 0 && this.#missing(address, id, data.logNumbers("entry", address, String(id))) !== null) this.syncEntries(address, id, priority);
    });
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
      const at = before ?? 1e15;
      const page = yield* this.requests.call(link.addr, "GET", `/sessions/${encode(key)}/timeline?before=${at}&limit=${TRANSCRIPT_PAGE}&brief=1`, null, { quiet: before === null });
      const start = u64(get(page, "start")) ?? 0;
      const items = (get(page, "entries") as unknown[] | undefined) ?? [];
      if (items.length === 0) return;
      this.#core.data.putItems(
        "transcript",
        address,
        key,
        items.map((item, i) => [start + i, item] as [number, unknown]),
      );
    });
  }

  /// A session's transcript entries `from` to `to` whole, in place of what is held of them in brief (`history.detail`):
  /// never pushed, read when a history's step is opened, behind what is shown in brief (Priority.detail). Asked for by
  /// someone waiting on it, it is tried while the station seems away too: what went wrong is theirs to see.
  detail(address: string, key: string, from: number, to: number): Effect.Effect<void, CoreError> {
    const work = Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link) return;
      const page = yield* this.requests.call(link.addr, "GET", `/sessions/${encode(key)}/timeline?from=${from}&to=${to}`, null, { quiet: true });
      const start = u64(get(page, "start")) ?? from;
      const items = (get(page, "entries") as unknown[] | undefined) ?? [];
      if (items.length > 0) this.#core.data.putItems("transcript", address, key, items.map((item, i) => [start + i, item] as [number, unknown]));
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
        if (!core.data.evicted("entry", address, String(id))) {
          this.putEntries(address, id, entries);
          this.syncEntries(address, id, Priority.shown);
        }
        this.#markDirty(address, id);
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
        this.#enqueue(address, "usage", Priority.background, this.#usage(address));
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
      switch (effect.kind) {
        case "none":
          return;
        case "session": {
          if (effect.key !== null) reads.push([`session/${effect.key}`, this.#session(address, effect.key)]);
          read("sessions", { topic: "sessions", station: address }, "/sessions");
          rows();
          read("archived", { topic: "archivedRows", station: address }, "/chats?archived=1");
          read("footprint", { topic: "footprint", station: address }, "/footprint");
          const thread = get(answer, "thread");
          if (isObject(thread)) this.putThread(address, thread);
          break;
        }
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
          if (effect.archived) read("archived", { topic: "archivedRows", station: address }, "/chats?archived=1");
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
      if (this.#core.data.logCount("entry", address, String(thread), n, n) === 0) yield* Effect.ignore(this.ask(address, `entries/${thread}`, this.#entriesPage(address, thread, Priority.asked)));
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
