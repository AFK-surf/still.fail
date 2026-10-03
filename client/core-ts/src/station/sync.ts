// What the core keeps in sync with the stations, by itself, whatever the UI shows (docs/core-ts.md, rule 6; station.rs
// and sync.rs for what a station says and how). Every station of every workspace an account reaches has a link: its
// `/admin/api/events` stream, held open for as long as the station is reached, opened again with backoff when it drops.
// Each time it opens, what the station holds is read again (as tasks of the station's lane in the sync scheduler); its
// events bring what changes as it changes, into the records. Then the rest is brought onto the device in the
// background, the most urgent first: every chat's entries (from its latest page back to its first), every session's
// detail and the latest page of its transcript. The UI makes some of it more urgent (`prioritize`), never more or less.
import { Effect, Exit, Fiber, Scope } from "effect";
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
import * as activity from "../activity.ts";
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
export const RECHECKING = "等它回来确认";

/// The steps in flight and the phase of a session at work, as its stream says them.
export type LiveView = { steps: unknown[]; phase: unknown | null; rate: number | null; usage: unknown; loaded: boolean };

/// What a station's `/events` stream is opened for: host samples, the sessions followed as they run, the jobs' logs.
export type EventsFor = { host: boolean; live: string[]; logs: [string, number][] };

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

/// Threads as the station lists them: the latest message first, then the newest thread.
export function sortThreads(threads: unknown[]): void {
  const f = (v: unknown) => (typeof v === "number" ? v : 0);
  threads.sort((a, b) => f(get(get(b, "lastMessage"), "createdAt")) - f(get(get(a, "lastMessage"), "createdAt")) || f(get(b, "createdAt")) - f(get(a, "createdAt")) || f(get(b, "id")) - f(get(a, "id")));
}

/// Puts a thread's summary into a list, replacing the one with its id.
export function upsertThread(list: unknown[], view: unknown): void {
  const id = get(view, "id");
  const i = list.findIndex((t) => equal(get(t, "id"), id));
  if (i >= 0) list[i] = structuredClone(view);
  else list.push(structuredClone(view));
  sortThreads(list);
}

/// Whether the turns a session detail lists still end as its summary says.
export function sameTurns(turns: unknown, summary: unknown): boolean {
  const list = Array.isArray(turns) ? turns : [];
  if (get(summary, "turns") !== list.length) return false;
  const lastTurn = get(summary, "lastTurn") ?? null;
  const record = list.length > 0 ? list[list.length - 1] : null;
  if (record === null && lastTurn === null) return true;
  if (record === null || lastTurn === null) return false;
  return ["kind", "outcome", "declared", "detail", "startedAt", "endedAt"].every((k) => equal(get(record, k), get(lastTurn, k)));
}

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
      const workspace = core.data.get({ topic: "workspace", workspace: id });
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
    // How it was last time, until the link finds out anew.
    core.runner.fork(
      Effect.map(Effect.orElseSucceed(core.host.storageGet(`${LINK_KEY}/${address}`), () => null), (bytes) => {
        if (bytes && link.state.state === "connecting") {
          link.state = { state: "connecting", last: new TextDecoder().decode(bytes) };
          this.onChange(address, "link");
        }
      }),
      link.scoped,
    );
    this.openEvents(address, false);
  }

  setLink(address: string, value: Record<string, unknown>): void {
    const link = this.#links.get(address);
    if (!link) return;
    const state = value.state;
    if ((state === "online" || state === "offline") && link.state.state !== state) {
      this.#core.runner.fork(Effect.ignore(this.#core.host.storageSet(`${LINK_KEY}/${address}`, new TextEncoder().encode(state))));
    }
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
    for (const row of (this.#core.data.get({ topic: "chatRows", station: address }) as unknown[] | undefined) ?? []) {
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
    if (link.events) {
      link.replaced?.pipe((f) => this.#core.runner.interrupt(f as Fiber.Fiber<unknown, unknown>));
      link.replaced = link.events.fiber;
    }
    const generation = ++link.generation;
    const fiber = this.#core.runner.fork(this.#follow(link, wants, generation), link.scoped);
    link.events = { fiber, wants };
  }

  /// The stream's path for `wants`, each session asked for from the transcript items held.
  #path(address: string, wants: EventsFor): string {
    const query: string[] = [];
    if (wants.host) query.push("host=1");
    for (const key of wants.live) {
      const held = this.#core.data.loaded("transcript", address, key);
      const from = held && held.size > 0 ? Math.max(...held.keys()) + 1 : 0;
      query.push(`live=${encode(key)}&from=${from}&last=${TRANSCRIPT_PAGE}`);
    }
    for (const [job, lines] of wants.logs) query.push(`job=${encode(job)}&lines=${lines}`);
    return query.length === 0 ? "/events" : `/events?${query.join("&")}`;
  }

  /// Holds the station's stream open; its events keep the records current. Each open reads the station again.
  #follow(link: Link, wants: EventsFor, generation: number): Effect.Effect<void, never> {
    const core = this.#core;
    const self = this;
    const address = link.address;
    return Effect.gen(function* () {
      let first = true;
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
            // Asked anew each time: a session is followed from what is held of it by then.
            for (const key of wants.live) yield* core.data.log("transcript", address, key);
            const path = self.#path(address, wants);
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
            // Nothing is replayed: what the station holds is read now.
            self.snapshot(address);
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
              for (const [name, data] of parser.feed(chunk)) self.onEvent(address, name, data);
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

  /// Everything the station holds, read again (its stream opened): the lists, then what they name.
  snapshot(address: string): void {
    const p = Priority.shown;
    this.#enqueue(address, "overview", p, this.#read(address, { topic: "overview", station: address }, "/overview"));
    this.#enqueue(address, "sessions", p, Effect.andThen(this.#read(address, { topic: "sessions", station: address }, "/sessions"), Effect.sync(() => this.#details(address))));
    this.#enqueue(address, "threads", p, Effect.andThen(this.#read(address, { topic: "threads", station: address }, "/threads"), Effect.sync(() => this.#entries(address))));
    this.#enqueue(address, "chats", p, Effect.andThen(this.#read(address, { topic: "chatRows", station: address }, "/chats"), Effect.sync(() => this.openEvents(address, false))));
    this.#enqueue(address, "archived", Priority.background, this.#read(address, { topic: "archivedRows", station: address }, "/chats?archived=1"));
    this.#enqueue(address, "jobs", p, this.#read(address, { topic: "jobs", station: address }, "/jobs"));
    this.#enqueue(address, "footprint", Priority.background, this.#read(address, { topic: "footprint", station: address }, "/footprint"));
    this.#enqueue(address, "usage", Priority.background, this.#usage(address));
    for (const id of this.#slackConnects(address)) this.#enqueue(address, `slackApp/${id}`, Priority.background, this.#read(address, { topic: "slackApp", station: address, connect: id }, `/connects/${encode(id)}/slack-app`));
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
    const overview = this.#core.data.get({ topic: "overview", station: address });
    return ((get(overview, "connects") as unknown[] | undefined) ?? []).flatMap((c) => {
      const id = str(get(c, "id"));
      return id && (get(c, "kind") === "slack" || get(c, "slack") !== undefined || get(c, "surface") === "slack") ? [id] : [];
    });
  }

  /// Reads one held topic: a 4xx while nothing is held is its error (the topic says so); anything else passes.
  #read(address: string, topic: Topic, path: string, shape?: (answer: unknown) => unknown): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.reachable(address) || !this.#links.has(address)) return;
      const link = this.#links.get(address)!;
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", path, null, { quiet: true }));
      const key = topicKey(topic);
      if (answer._tag === "Success") {
        link.errors.delete(key);
        this.#core.data.set(topic, shape ? shape(answer.success) : answer.success);
      } else if (this.#core.data.get(topic) === undefined && answer.failure.status !== undefined && answer.failure.status >= 400 && answer.failure.status < 500) {
        link.errors.set(key, answer.failure);
        this.onChange(address, "errors", key);
      }
    });
  }

  /// What the station's agents spent over the last 30 days, days as this device's clock has them.
  #usage(address: string): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const now = this.#core.host.nowMs();
      const offset = this.#core.host.utcOffsetMin(now);
      const day = 86_400_000;
      const local = Math.trunc(now) + offset * 60_000;
      const from = local - (((local % day) + day) % day) - 29 * day - offset * 60_000;
      return this.#read(address, { topic: "stationUsage", station: address }, `/usage?from=${from}&tz=${offset}`);
    });
  }

  /// Each shown session's detail (turns, threads, jobs), and the latest page of its transcript.
  #details(address: string): void {
    for (const s of (this.#core.data.get({ topic: "sessions", station: address }) as unknown[] | undefined) ?? []) {
      const key = str(get(s, "key"));
      if (!key) continue;
      const detail = this.#core.data.get({ topic: "session", station: address, key });
      if (detail === undefined || !sameTurns(get(detail, "turns"), s)) this.#enqueue(address, `session/${key}`, Priority.background, this.#session(address, key));
      this.#enqueue(address, `transcript/${key}`, Priority.background - 1, this.transcript(address, key, null));
    }
  }

  #session(address: string, key: string): Effect.Effect<void, CoreError> {
    return this.#read(address, { topic: "session", station: address, key }, `/sessions/${encode(key)}`);
  }

  /// Every thread's entries, the latest first.
  #entries(address: string): void {
    for (const thread of (this.#core.data.get({ topic: "threads", station: address }) as unknown[] | undefined) ?? []) {
      const id = u64(get(thread, "id"));
      if (id !== null) this.syncEntries(address, id, Priority.background);
    }
  }

  /// Brings a thread's entries onto the device: what came after what is held, then any gap, then the pages before,
  /// one page a run (the task asks itself again while there is more, so what is more urgent goes between).
  syncEntries(address: string, id: number, priority: number): void {
    this.#enqueue(address, `entries/${id}`, priority, this.#entriesPage(address, id, priority));
  }

  /// The highest entry a thread is missing on the device, as far as it is known to go.
  #missing(address: string, id: number, held: Map<number, unknown>): number | null {
    const summary = ((this.#core.data.get({ topic: "threads", station: address }) as unknown[] | undefined) ?? []).find((t) => u64(get(t, "id")) === id);
    let latest = u64(get(summary, "last")) ?? 0;
    for (const n of held.keys()) latest = Math.max(latest, n);
    for (let n = latest; n >= 1; n--) if (!held.has(n)) return n;
    return null;
  }

  #entriesPage(address: string, id: number, priority: number): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const held = yield* this.#core.data.log("entry", address, String(id));
      let path: string;
      if (held.size === 0) path = `/threads/${id}/entries?limit=${PAGE}`;
      else {
        const top = Math.max(...held.keys());
        const summary = ((this.#core.data.get({ topic: "threads", station: address }) as unknown[] | undefined) ?? []).find((t) => u64(get(t, "id")) === id);
        const listed = u64(get(summary, "last")) ?? 0;
        if (listed > top) path = `/threads/${id}/entries?after=${top}`;
        else {
          const missing = this.#missing(address, id, held);
          if (missing === null) return;
          path = `/threads/${id}/entries?from=${Math.max(1, missing - PAGE + 1)}&to=${missing}`;
        }
      }
      const answer = yield* Effect.result(this.requests.call(link.addr, "GET", path, null, { quiet: true }));
      if (answer._tag === "Failure") {
        // A thread that is gone: what is held of it goes.
        if (answer.failure.status === 404) yield* this.#threadGone(address, id);
        return;
      }
      const entries = (get(answer.success, "entries") as unknown[] | undefined) ?? [];
      yield* this.putEntries(address, id, entries);
      // More to bring: asked again, behind what is more urgent.
      if (entries.length > 0 && this.#missing(address, id, held) !== null) this.syncEntries(address, id, priority);
    });
  }

  /// Entries into a thread's log.
  putEntries(address: string, id: number, entries: unknown[]): Effect.Effect<void> {
    const items: [number, unknown][] = entries.flatMap((e) => {
      const n = nOf(e);
      return n === null ? [] : [[n, e] as [number, unknown]];
    });
    return items.length === 0 ? Effect.void : this.#core.data.putItems("entry", address, String(id), items);
  }

  /// A session's transcript: its latest page when none is held, or the page before `before` (history.older).
  transcript(address: string, key: string, before: number | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.#links.get(address);
      if (!link || !this.reachable(address)) return;
      const held = yield* this.#core.data.log("transcript", address, key);
      if (before === null && held.size > 0) return;
      const at = before ?? 1e15;
      const page = yield* this.requests.call(link.addr, "GET", `/sessions/${encode(key)}/timeline?before=${at}&limit=${TRANSCRIPT_PAGE}`, null, { quiet: before === null });
      const start = u64(get(page, "start")) ?? 0;
      const items = (get(page, "entries") as unknown[] | undefined) ?? [];
      if (items.length === 0) return;
      yield* this.#core.data.putItems(
        "transcript",
        address,
        key,
        items.map((item, i) => [start + i, item] as [number, unknown]),
      );
    });
  }

  #threadGone(address: string, id: number): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      this.#removeThread(address, id);
      yield* this.#core.data.forgetLog("entry", address, String(id));
      const link = this.#links.get(address);
      if (link) {
        const key = topicKey({ topic: "thread", station: address, thread: id });
        link.errors.set(key, new CoreError("http_404", t("station.core.noChat"), 404));
        this.onChange(address, "errors", key);
      }
    });
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
        if (newest >= 0) {
          core.data.update({ topic: "threads", station: address }, (list) => {
            for (const t of Array.isArray(list) ? list : []) if (isObject(t) && u64(t.id) === id && (u64(t.last) ?? 0) < newest) t.last = newest;
            return list;
          });
        }
        this.onTold(address, id, entries);
        core.runner.fork(Effect.andThen(this.putEntries(address, id, entries), Effect.sync(() => this.syncEntries(address, id, Priority.shown))));
        this.#markDirty(address, id);
        return;
      }
      case "thread-removed": {
        const id = u64(get(data, "id"));
        if (id !== null) core.runner.fork(this.#threadGone(address, id));
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
        if (id) core.data.update({ topic: "chatRows", station: address }, (rows) => (Array.isArray(rows) ? rows.filter((r) => get(r, "id") !== id) : rows));
        return;
      }
      case "live": {
        const key = str(get(data, "key"));
        if (key) core.runner.fork(this.#onLive(address, key, data));
        return;
      }
      case "job":
        return this.onJob(address, data);
      case "job-removed": {
        const id = str(get(data, "id"));
        const key = str(get(data, "session"));
        if (id && key) {
          core.data.update({ topic: "session", station: address, key }, (detail) => {
            if (isObject(detail) && Array.isArray(detail.jobs)) detail.jobs = detail.jobs.filter((j) => get(j, "id") !== id);
            return detail;
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
      case "host": {
        const link = this.#links.get(address);
        if (link) {
          link.memory.set("host", data);
          this.onChange(address, "host");
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

  /// A session's summary changed: it replaces the one in `sessions` and in its detail; the detail's turns are read
  /// again when the summary says they changed.
  #onSession(address: string, summary: unknown): void {
    const key = str(get(summary, "key"));
    if (!key) return;
    const core = this.#core;
    const shown = (get(summary, "archivedAt") ?? null) === null;
    core.data.update({ topic: "sessions", station: address }, (list) => {
      if (!Array.isArray(list)) return list;
      const i = list.findIndex((s) => get(s, "key") === key);
      if (i >= 0 && shown) list[i] = summary;
      else if (i >= 0) list.splice(i, 1);
      else if (shown) list.unshift(summary);
      return list;
    });
    let changed = false;
    core.data.update({ topic: "session", station: address, key }, (detail) => {
      changed = !sameTurns(get(detail, "turns"), summary);
      if (isObject(detail)) detail.session = summary as never;
      return detail;
    });
    if (changed || core.data.get({ topic: "session", station: address, key }) === undefined) this.#enqueue(address, `session/${key}`, Priority.shown, this.#session(address, key));
  }

  #onSessionRemoved(address: string, key: string): void {
    const core = this.#core;
    core.data.update({ topic: "sessions", station: address }, (list) => (Array.isArray(list) ? list.filter((s) => get(s, "key") !== key) : list));
    core.data.forgetTopic({ topic: "session", station: address, key });
    const link = this.#links.get(address);
    if (link) {
      const topic = topicKey({ topic: "session", station: address, key });
      link.errors.set(topic, new CoreError("http_404", t("station.core.sessionDeleted"), 404));
      this.onChange(address, "errors", topic);
    }
    core.runner.fork(core.data.forgetLog("transcript", address, key));
    core.data.update({ topic: "threads", station: address }, (list) => {
      if (!Array.isArray(list)) return list;
      for (const thread of list) if (isObject(thread) && Array.isArray(thread.sessions)) thread.sessions = thread.sessions.filter((m) => get(m, "session") !== key);
      return list.filter((t) => Array.isArray(get(t, "sessions")) && (get(t, "sessions") as unknown[]).length > 0);
    });
  }

  /// A job as it is now: in place in its session's jobs, and among the station's open ones while it is open.
  onJob(address: string, job: unknown): void {
    const id = str(get(job, "id"));
    const key = str(get(job, "session"));
    if (!id || !key) return;
    const core = this.#core;
    core.data.set({ topic: "job", station: address, id }, job);
    core.data.update({ topic: "session", station: address, key }, (detail) => {
      if (!isObject(detail) || !Array.isArray(detail.jobs)) return detail;
      const i = detail.jobs.findIndex((j) => get(j, "id") === id);
      if (i >= 0) detail.jobs[i] = job as never;
      else detail.jobs.unshift(job as never);
      return detail;
    });
    const state = get(job, "state");
    const open = state === "running" || (state === "exited" && (get(job, "port") ?? null) !== null);
    let unknown = false;
    core.data.update({ topic: "jobs", station: address }, (list) => {
      if (!Array.isArray(list)) return list;
      const i = list.findIndex((j) => get(j, "id") === id);
      if (i >= 0 && open) {
        const chat = get(list[i], "chat");
        list[i] = structuredClone(job);
        if (chat !== undefined && isObject(list[i])) (list[i] as Record<string, unknown>).chat = chat;
      } else if (i >= 0) list.splice(i, 1);
      else if (open) unknown = true;
      return list;
    });
    // A new one: which chat it is in is the station's to say.
    if (unknown) this.#enqueue(address, "jobs", Priority.shown, this.#read(address, { topic: "jobs", station: address }, "/jobs"));
  }

  /// A row of the viewer's sidebar, new or changed.
  putRow(address: string, row: unknown): void {
    const id = str(get(row, "id"));
    if (!id) return;
    this.#core.data.update({ topic: "chatRows", station: address }, (rows) => {
      if (!Array.isArray(rows)) return rows;
      const i = rows.findIndex((r) => get(r, "id") === id);
      if (i >= 0) rows[i] = row;
      else rows.push(row);
      return rows;
    });
    // An agent starting or ending its turn: the stream follows what is at work.
    this.openEvents(address, false);
  }

  /// A thread's summary into every list that has it: `threads`, and the details of the sessions taking part.
  putThread(address: string, view: unknown): void {
    const id = u64(get(view, "id"));
    if (id === null) return;
    const core = this.#core;
    const members = ((get(view, "sessions") as unknown[] | undefined) ?? []).flatMap((m) => (typeof get(m, "session") === "string" ? [get(m, "session") as string] : []));
    core.data.update({ topic: "threads", station: address }, (list) => {
      if (Array.isArray(list)) upsertThread(list, view);
      return list;
    });
    for (const [key] of core.data.records("session")) {
      const [station, session] = key.split("\u0001");
      if (station !== address) continue;
      core.data.update({ topic: "session", station: address, key: session }, (detail) => {
        if (!isObject(detail) || !Array.isArray(detail.threads)) return detail;
        if (members.includes(session)) upsertThread(detail.threads, view);
        else detail.threads = detail.threads.filter((t) => u64(get(t, "id")) !== id);
        return detail;
      });
    }
  }

  #removeThread(address: string, id: number): void {
    const core = this.#core;
    const drop = (list: unknown) => (Array.isArray(list) ? list.filter((t) => u64(get(t, "id")) !== id) : list);
    core.data.update({ topic: "threads", station: address }, drop);
    for (const [key] of core.data.records("session")) {
      const [station, session] = key.split("\u0001");
      if (station === address)
        core.data.update({ topic: "session", station: address, key: session }, (detail) => {
          if (isObject(detail) && Array.isArray(detail.threads)) detail.threads = drop(detail.threads) as never;
          return detail;
        });
    }
  }

  /// The viewer read a thread up to entry `n`: its read position moves there, nothing unread once it covers the last
  /// entry (otherwise the count is read again).
  putRead(address: string, thread: number, n: number): void {
    const core = this.#core;
    let stale = false;
    const apply = (list: unknown) => {
      for (const t of Array.isArray(list) ? list : []) {
        if (!isObject(t) || u64(t.id) !== thread || (u64(t.read) ?? -1) >= n) continue;
        t.read = n;
        const last = u64(t.last);
        if (last === null || n >= last) t.unread = 0;
        else stale = true;
      }
      return list;
    };
    core.data.update({ topic: "threads", station: address }, apply);
    core.data.update({ topic: "chatRows", station: address }, (rows) => {
      for (const row of Array.isArray(rows) ? rows : []) {
        if (!isObject(row) || u64(row.thread) !== thread) continue;
        const last = u64(get(row.last, "seq"));
        if (last === null || n >= last) row.unread = false;
      }
      return rows;
    });
    for (const [key] of core.data.records("session")) {
      const [station, session] = key.split("\u0001");
      if (station === address)
        core.data.update({ topic: "session", station: address, key: session }, (detail) => {
          if (isObject(detail)) apply(detail.threads);
          return detail;
        });
    }
    if (stale) this.#markDirty(address, thread);
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
      else if (view.failure.status === 404) this.#removeThread(address, id);
    });
  }

  /// One message of the live stream: transcript items into the records, steps and phase into the live view.
  #onLive(address: string, key: string, message: unknown): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
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
      if (kind === "timeline") {
        const start = u64(get(message, "start")) ?? 0;
        const entries = (get(message, "entries") as unknown[] | undefined) ?? [];
        // The transcript written anew (or past what is held: the latest page only): it starts there.
        const held = yield* core.data.log("transcript", address, key);
        const top = held.size > 0 ? Math.max(...held.keys()) + 1 : 0;
        if (start > top || start < top) {
          if (start < top) {
            // Written anew from `start`: what came after goes.
            yield* core.data.putItems("transcript", address, key, entries.map((e, i) => [start + i, e] as [number, unknown]), true);
          } else yield* core.data.putItems("transcript", address, key, entries.map((e, i) => [start + i, e] as [number, unknown]));
        } else yield* core.data.putItems("transcript", address, key, entries.map((e, i) => [start + i, e] as [number, unknown]));
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
    });
  }

  /// What the chat shows of a session at work (activity.ts), from its live view.
  activity(view: Record<string, unknown>): unknown {
    return activity.present(view);
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
      const held = yield* this.#core.data.log("entry", address, String(thread));
      if (!held.has(n)) yield* Effect.ignore(this.ask(address, `entries/${thread}`, this.#entriesPage(address, thread, Priority.asked)));
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

  /// How far the viewer has read a thread, as the lists that have it say.
  readPosition(address: string, thread: number): number | null {
    let best: number | null = null;
    const look = (list: unknown) => {
      for (const t of Array.isArray(list) ? list : []) if (u64(get(t, "id")) === thread) {
        const r = u64(get(t, "read"));
        if (r !== null) best = best === null ? r : Math.max(best, r);
      }
    };
    look(this.#core.data.get({ topic: "threads", station: address }));
    for (const [key, detail] of this.#core.data.records("session")) if (key.startsWith(`${address}\u0001`)) look(get(detail, "threads"));
    return best;
  }

  /// The page of a thread's entries before `before`, onto the device (a person scrolled up): from what is held, else
  /// read now. Answers whether older ones exist.
  older(address: string, thread: number, before: number, ctx: SpanContext | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const held = yield* this.#core.data.log("entry", address, String(thread));
      const from = Math.max(1, before - PAGE);
      let all = true;
      for (let n = from; n < before; n++) if (!held.has(n)) all = false;
      if (all || before <= 1) return;
      const page = yield* this.requests.call(StationAddr.parse(address), "GET", `/threads/${thread}/entries?before=${before}&limit=${PAGE}`, null, { ctx });
      yield* this.putEntries(address, thread, ((get(page, "entries") as unknown[] | undefined) ?? []).filter((e) => (nOf(e) ?? Infinity) < before));
    });
  }

  /// Entries `from ..= to` onto the device (a window moved there): read now if not all held.
  range(address: string, thread: number, from: number, to: number, ctx: SpanContext | null): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (to < from) return;
      const held = yield* this.#core.data.log("entry", address, String(thread));
      let all = true;
      for (let n = from; n <= to; n++) if (!held.has(n)) all = false;
      if (all) return;
      const page = yield* this.requests.call(StationAddr.parse(address), "GET", `/threads/${thread}/entries?from=${from}&to=${to}`, null, { ctx });
      yield* this.putEntries(address, thread, ((get(page, "entries") as unknown[] | undefined) ?? []).filter((e) => {
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
