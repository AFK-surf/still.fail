// `Core`: takes messages from connected UIs, answers calls, keeps subscriptions (core.rs). Construction wires the
// modules together: accounts → cloud → mesh links → stations; the store routes topics to accounts (accounts,
// workspaces, workspace), stations (everything with a station) or the views. What the core has of each workspace is
// that workspace's (workspace.ts).
//
// The account topics live here: `accounts` is the list itself, `workspaces` every account's `/v1/me`, `workspace` one
// `GET /v1/workspaces/:id`. While `workspaces` or a `workspace` is live, each signed-in account holds still.fail cloud's
// `/v1/events` socket, and the topics change when it says so. Every time a socket opens, the live account topics are
// read once (nothing is replayed). They are also read when the accounts change and after a write to still.fail cloud;
// never on a timer.
import type { Clock } from "effect";
import type { Fiber } from "effect";
import { Accounts, type AccountView } from "./accounts.ts";
import * as brand from "./brand.ts";
import { Cloud } from "./cloud.ts";
import * as accountState from "./core/account_state.ts";
import { parseCall, type Call } from "./core/calls.ts";
import { execute } from "./core/execute.ts";
import { Router } from "./core/routing.ts";
import { Data } from "./data.ts";
import { Doing, FAILED_SHOWN_MS, heavy } from "./doing.ts";
import { CoreError, asCoreError } from "./error.ts";
import type { Host } from "./host.ts";
import * as prefs from "./prefs.ts";
import { parseClientMessage, type ClientId, type ClientMessage, type CoreMessage, type RequestId, type Topic } from "./protocol.ts";
import { Runner } from "./runtime.ts";
import { stationId } from "./station/addr.ts";
import { Status } from "./status.ts";
import { Store } from "./store.ts";
import { Kind, SAMPLE, Tracer, type Span } from "./trace.ts";
import { Wakes, WakingHost } from "./wake.ts";
import { Workspaces } from "./workspace.ts";
import { cancellable, callStation, counts } from "./core/calls.ts";
import { isObject, parseJson } from "./util.ts";
import { t } from "./i18n.ts";

/// The first wait before an events socket is opened again; it doubles up to SOCKET_RETRY_MAX_MS.
export const SOCKET_RETRY_MS = 1_000;
export const SOCKET_RETRY_MAX_MS = 60_000;
/// An events socket that answered a ping before and then heard nothing this long is opened again.
export const SOCKET_IDLE_MS = 2 * 25_000 + 10_000;
/// The subprotocol still.fail cloud's `/v1/events` answers with; the token travels as a second one.
export const EVENTS_PROTOCOL = "stillfail-events";

/// Where a device's member credentials are kept (`credential/<account>/<workspace>`), and how long one serves.
export const CREDENTIAL_KEY = "credential";
export const CREDENTIAL_FOR_S = 24 * 60 * 60;
export const CREDENTIAL_OTHERS = "others";
export const CREDENTIAL_OTHERS_KEPT = 8;
/// Where this device's push registration is kept, and the accounts that have it.
export const PUSH_KEY = "push";

export type SocketState = "connecting" | "open" | "retrying";

/// How far a call has got, for a UI that asked to hear it.
export type Progress = (value: unknown) => void;

/// What later parts of the core plug in (the station links, the views…): each a module of its own, wired here.
export interface Parts {
  /// The topics of stations: started, stopped, computed (station.ts).
  stations?: {
    start(topic: Topic): void;
    stop(topic: Topic): void;
  };
}

export type Options = {
  /// The share of traces recorded (0: none).
  sample?: number;
  /// The clock the core's timers run on (a TestClock in tests).
  clock?: Clock.Clock;
};

/// What the core holds: every module, and the account topics' state.
export class Inner {
  host!: Host;
  runner!: Runner;
  tracer!: Tracer;
  /// Client errors recorded lately, by source and message, and when.
  reported = new Map<string, number>();
  accounts!: Accounts;
  cloud!: Cloud;
  store!: Store;
  data!: Data;
  /// still.fail's relays, its own first, as the first `/v1/me` of this run or the kept one said.
  relays: string[] | null = null;
  workspaces!: Workspaces;
  /// Whether each account's latest `/v1/me` answered this run (null), or why it failed.
  mes = new Map<string, CoreError | null>();
  /// The accounts as last shown, so a change that UIs cannot see (a refreshed token) is not one.
  shownAccounts: AccountView[] = [];
  /// Every account's `/v1/me` under way.
  meLoading: Promise<void> | null = null;
  /// Numbers the `/v1/me` requests per account, so only the newest answer is kept.
  meFetches = new Map<string, number>();
  /// The live `workspaces` / `workspace` / `loginSessions` / `admin` topics, each with the number of its newest fetch.
  live = new Map<string, { topic: Topic; fetch: number }>();
  /// Per account, its still.fail cloud events socket while an account topic is live.
  sockets = new Map<string, { fiber: Fiber.Fiber<unknown, unknown>; state: SocketState }>();
  /// What the device waits on: still.fail cloud, its sockets, the relay for no station.
  status!: Status;
  wakes!: Wakes;
  /// The calls under way that a UI can stop, by client and id.
  calls = new Map<string, () => void>();
  doing = new Doing();
  parts: Parts = {};
  /// The mesh endpoint, brought up once (phase 2: station links).
  meshWarm: (() => void) | null = null;
  closed = false;

  /// The data center's topics go to the data center, the rest to the store (data.rs `Center::set`).
  centerSet(topic: Topic, value: { ok: unknown } | { err: CoreError }): void {
    accountState.centerSet(this, topic, value);
  }
}

export class Core {
  readonly inner: Inner;
  #nextClient = 1;

  private constructor(inner: Inner) {
    this.inner = inner;
  }

  /// A core on `host`; its timers on `options.clock` (the live clock by default).
  static async create(host: Host, options: Options = {}): Promise<Core> {
    const inner = new Inner();
    inner.wakes = new Wakes();
    // Everything the core asks of the host is given up or opened again when a UI comes back (wake.ts).
    inner.host = new WakingHost(host, inner.wakes);
    inner.runner = new Runner(options.clock);
    brand.setTestChannel(inner.host.testChannel());
    inner.tracer = new Tracer(inner.host, inner.runner, options.sample ?? SAMPLE);
    inner.accounts = await Accounts.load(inner.host);
    inner.accounts.setTracer(inner.tracer);
    inner.status = new Status(inner.host, inner.runner);
    inner.cloud = new Cloud(inner.host, inner.accounts, inner.tracer, inner.status);
    // What was last known is there before any UI asks.
    inner.data = new Data(inner.host, inner.runner);
    await inner.data.load();
    prefs.followLang(inner.data);
    inner.workspaces = new Workspaces(inner.host, inner.runner);
    inner.store = new Store(inner.host, inner.runner);
    const store = inner.store;
    // What goes out is what the clients' types say (client/shapes).
    store.setShaped();
    store.setHeld((topic) => inner.data.shown(topic));
    inner.data.onChange((topic) => store.changed(topic));
    inner.status.onChange(() => store.invalidateAll((t) => t.topic === "status"));
    inner.status.setNames((address) => accountState.nameOf(inner, address));
    inner.workspaces.wireStatus(
      (id) => {
        store.invalidateAll((t) => t.topic === "status" && (t.workspace === undefined || t.workspace === id));
        store.invalidate({ topic: "doing" });
      },
      (address) => accountState.nameOf(inner, address),
    );
    store.setSource(new Router(inner));
    inner.shownAccounts = inner.accounts.list();
    // Whom each account reaches, as the data center has it from the last run.
    accountState.recomputeOwners(inner);
    const kept = parseJson(await inner.host.storageGet(PUSH_KEY).catch(() => null));
    void kept;
    inner.tracer.setExport(async (body) => {
      const account = inner.accounts.list()[0];
      if (!account) return;
      await inner.cloud.traces(account.sub, body).catch(() => undefined);
    });
    inner.accounts.onChange(() => accountState.accountsChanged(inner));
    return new Core(inner);
  }

  /// Keeps times in words fresh while anything is shown (a UI's core).
  keepTime(): void {
    this.inner.store.setClock();
  }

  /// A UI connected; its messages and emissions use this id.
  connect(): ClientId {
    return this.#nextClient++;
  }

  /// A UI went away: its subscriptions end, its calls that hold something open for it stop.
  disconnect(client: ClientId): void {
    this.inner.store.dropClient(client);
    for (const [key, stop] of [...this.inner.calls]) {
      if (key.startsWith(`${client}/`)) {
        this.inner.calls.delete(key);
        stop();
      }
    }
  }

  /// A message from a UI as JSON (what the native hosts are given): one that is none answers `bad_message`.
  receiveJson(client: ClientId, json: string): void {
    let raw: unknown;
    try {
      raw = JSON.parse(json);
    } catch (e) {
      return;
    }
    this.receiveRaw(client, raw);
  }

  /// A message from a UI as an object.
  receiveRaw(client: ClientId, raw: unknown): void {
    const message = parseClientMessage(raw);
    if ("invalid" in message) {
      const id = isObject(raw) && typeof raw.id === "number" && Number.isInteger(raw.id) && raw.id >= 0 ? raw.id : null;
      if (id === null) return;
      this.inner.host.emit(client, { id, error: new CoreError("bad_message", t("core-misc.host.bad_message", { error: message.invalid })) });
      return;
    }
    this.receive(client, message);
  }

  /// A message from a UI. Answers and values go out through `Host.emit`.
  receive(client: ClientId, message: ClientMessage): void {
    const inner = this.inner;
    switch (message.kind) {
      case "subscribe":
        return inner.store.subscribe(client, message.id, message.subscribe);
      case "unsubscribe":
        return inner.store.unsubscribe(client, message.id);
      case "cancel": {
        const key = `${client}/${message.id}`;
        const stop = inner.calls.get(key);
        if (stop) {
          inner.calls.delete(key);
          stop();
        }
        return;
      }
      case "call":
        return this.#call(client, message.id, message.call, message.params);
    }
  }

  #call(client: ClientId, id: RequestId, name: string, params: unknown): void {
    const inner = this.inner;
    const asked = heavy(name) ? null : params;
    let call: Call;
    try {
      call = parseCall(name, params);
    } catch (e) {
      inner.host.emit(client, answer(id, { err: asCoreError(e) }));
      return;
    }
    // Under way from now until it answers, for every page to show where it is (doing.ts).
    let doing: number | null = null;
    if (asked !== null && counts(call, name)) {
      doing = inner.doing.start(name, asked, inner.host.nowMs());
      inner.store.invalidate({ topic: "doing" });
    }
    // Each call is a trace: what it asks of stations and still.fail cloud are its spans.
    const span: Span = inner.tracer.root(name, Kind.Internal);
    const station = callStation(call);
    if (station !== null) span.set("stillfail.station", stationId(station));
    const progress: Progress = (value) => inner.host.emit(client, { id, value });
    // Only a call that holds something open for its page can be stopped (and is, with the page).
    let cancelled: (() => void) | null = null;
    const stopped = new Promise<never>((_, reject) => {
      cancelled = () => reject(new CoreError("cancelled", t("core-misc.call.cancelled")));
    });
    const abort = new AbortController();
    if (cancellable(call)) {
      inner.calls.set(`${client}/${id}`, () => {
        abort.abort();
        cancelled!();
      });
    }
    inner.runner.spawn(async () => {
      let result: { ok: unknown } | { err: CoreError };
      try {
        const run = execute(inner, call, progress, [client, id], span.context, abort.signal);
        result = { ok: await (cancellable(call) ? Promise.race([run, stopped]) : run) };
      } catch (e) {
        result = { err: asCoreError(e) };
      }
      inner.calls.delete(`${client}/${id}`);
      if ("err" in result) {
        span.fail();
        span.set("error.type", result.err.code);
      }
      span.end();
      let failed: number | null = null;
      if (doing !== null) {
        if ("err" in result) {
          inner.doing.fail(doing, result.err.message);
          failed = doing;
        } else inner.doing.end(doing);
        inner.store.invalidate({ topic: "doing" });
      }
      inner.host.emit(client, answer(id, result));
      if (failed !== null) {
        await inner.runner.sleep(FAILED_SHOWN_MS);
        inner.doing.end(failed);
        inner.store.invalidate({ topic: "doing" });
      }
    });
  }

  /// Lets the core go: its timers and sockets stop.
  close(): void {
    this.inner.closed = true;
    for (const socket of this.inner.sockets.values()) this.inner.runner.interrupt(socket.fiber);
    this.inner.sockets.clear();
    this.inner.runner.close();
  }
}

export function answer(id: RequestId, result: { ok: unknown } | { err: CoreError }): CoreMessage {
  return "ok" in result ? { id, ok: result.ok } : { id, error: result.err };
}

/// The relays a `/v1/me` names: `relay_urls`, still.fail's own first, or `relay_url` alone from a cloud from before.
export function relaysOf(me: unknown): string[] | null {
  if (!isObject(me)) return null;
  const all = Array.isArray(me.relay_urls) ? me.relay_urls.filter((v): v is string => typeof v === "string") : [];
  if (all.length > 0) return all;
  return typeof me.relay_url === "string" ? [me.relay_url] : null;
}

export function gone(): CoreError {
  return new CoreError("closed", t("core-misc.core.closed"));
}
