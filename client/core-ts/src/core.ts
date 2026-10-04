// `Core`: takes messages from connected UIs, answers calls, keeps subscriptions (docs/client-core.md; core.rs for the
// protocol). Construction opens the signed-in accounts' databases (data.ts), wires the modules together and starts the
// sync (sync/), which keeps everything the core holds current by itself; subscriptions only read what is held.
import { Cause, Effect, type Clock, type Fiber } from "effect";
import { Accounts, type AccountView } from "./accounts.ts";
import * as brand from "./brand.ts";
import { Cloud } from "./cloud.ts";
import { parseCall, cancellable, callStation, counts, type Call } from "./core/calls.ts";
import { execute, handlers, hooks } from "./core/execute.ts";
import { Router } from "./core/routing.ts";
import { importFormer } from "./db/import.ts";
import { Data, holds } from "./data.ts";
import { chatDerive } from "./views/views.ts";
import { Doing, FAILED_SHOWN_MS, heavy } from "./doing.ts";
import { CoreError, asCoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import * as prefs from "./prefs.ts";
import { parseClientMessage, type ClientId, type ClientMessage, type CoreMessage, type RequestId } from "./protocol.ts";
import { Runner } from "./runtime.ts";
import { stationId } from "./station/addr.ts";
import { Status } from "./status.ts";
import { Store } from "./store.ts";
import { CloudSync } from "./sync/cloud.ts";
import { Priority, Scheduler } from "./sync/scheduler.ts";
import { Kind, SAMPLE, Tracer } from "./trace.ts";
import { Wakes, WakingHost } from "./wake.ts";
import { Workspaces } from "./workspace.ts";
import { install as installStationCalls } from "./station/calls.ts";
import { StationsSync } from "./station/sync.ts";
import { StationTopics } from "./station/topics.ts";
import type { StationWire } from "./station/wire.ts";
import { meshWire, type Mesh } from "./mesh.ts";
import type { Iroh } from "./iroh.ts";
import { ViewCalls } from "./views/calls.ts";
import { Attend } from "./attend.ts";
import { Attention } from "./attention.ts";
import { Pills } from "./pill.ts";
import type { Choose } from "./choose.ts";
import { installChoose } from "./choose-calls.ts";
import { Changelog } from "./changelog.ts";
import { installForms, type Forms } from "./forms-calls.ts";
import { Loads } from "./preview-load.ts";
import { Asks } from "./asks.ts";
import { Adb } from "./adb.ts";
import { envOf, Views } from "./views/views.ts";
import { isObject } from "./util.ts";

/// Where a device's member credentials are kept (`credential/<account>/<workspace>`), and how long one serves.
export const CREDENTIAL_KEY = "credential";
export const CREDENTIAL_FOR_S = 24 * 60 * 60;
export const CREDENTIAL_OTHERS = "others";
export const CREDENTIAL_OTHERS_KEPT = 8;
/// Where this device's push registration is kept.
export const PUSH_KEY = "push";

/// How far a call has got, for a UI that asked to hear it.
export type Progress = (value: unknown) => void;

export type Options = {
  /// How the core reaches stations: the mesh by default; tests' stations answer over the host's fetch.
  wire?: (inner: Inner) => StationWire;
  /// The share of traces recorded (0: none).
  sample?: number;
  /// The clock the core's timers run on (a TestClock in tests).
  clock?: Clock.Clock;
  /// The iroh this host has (iroh.ts); none: stations are not reached over the mesh.
  iroh?: Iroh | null;
};

/// What the core holds: every module.
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
  workspaces!: Workspaces;
  /// What the device waits on: still.fail cloud, its sockets, the relay for no station.
  status!: Status;
  wakes!: Wakes;
  scheduler!: Scheduler;
  cloudSync!: CloudSync;
  stations!: StationsSync;
  stationTopics!: StationTopics;
  views!: Views;
  /// The iroh this host has, and the mesh over it once up (mesh.ts).
  iroh: Iroh | null = null;
  /// None until a wire over the mesh is made (a core whose stations answer otherwise has none).
  mesh: () => Effect.Effect<Mesh, CoreError> = () => Effect.fail(new CoreError("unsupported", t("station.core.oneWay")));
  meshNow: () => Mesh | null = () => null;
  attention!: Attention;
  choose!: Choose;
  changelog!: Changelog;
  forms!: Forms;
  adb!: Adb;
  viewCalls!: ViewCalls;
  router!: Router;
  /// The calls under way that a UI can stop, by `client/id`.
  calls = new Map<string, Fiber.Fiber<unknown, unknown>>();
  doing = new Doing();
  /// The accounts as last shown, so a change UIs cannot see (a refreshed token) is not one.
  shownAccounts: AccountView[] = [];
}

export class Core {
  readonly inner: Inner;
  #nextClient = 1;

  private constructor(inner: Inner) {
    this.inner = inner;
  }

  /// A core on `host`, its timers on `options.clock`; it starts syncing at once, from what the database holds.
  static create(host: Host, options: Options = {}): Promise<Core> {
    const inner = new Inner();
    inner.runner = new Runner(options.clock);
    return inner.runner.run(Core.make(inner, host, options));
  }

  static make(inner: Inner, host: Host, options: Options): Effect.Effect<Core> {
    return Effect.gen(function* () {
      inner.wakes = new Wakes();
      // Everything the core asks of the host is given up or opened again when a UI comes back (wake.ts).
      inner.host = new WakingHost(host, inner.wakes);
      brand.setTestChannel(inner.host.testChannel());
      inner.tracer = new Tracer(inner.host, inner.runner, options.sample ?? SAMPLE);
      inner.accounts = yield* Accounts.load(inner.host);
      inner.accounts.setTracer(inner.tracer);
      inner.status = new Status(inner.host, inner.runner);
      inner.cloud = new Cloud(inner.host, inner.accounts, inner.tracer, inner.status);
      inner.workspaces = new Workspaces(inner.host, inner.runner);
      inner.store = new Store(inner.host, inner.runner);
      const store = inner.store;
      // Each signed-in account's database, opened before any network: the first view is answered from it.
      inner.data = new Data(inner.host, inner.runner, {
        owner: (workspace) => inner.workspaces.owner(workspace),
        derive: chatDerive,
      });
      // What the former records store and the Rust core's kept chunks held, brought into an account's new database once.
      inner.data.onOpened = (db) =>
        Effect.andThen(
          importFormer(inner.host, inner.runner, inner.data, inner.accounts.list().map((a) => a.sub), db),
          // What was done here and kept in it goes on (a database opened after the start: signed in).
          Effect.sync(() => inner.views?.local.opened(db)),
        );
      inner.data.onSignedOut = (sub, me) => inner.cloudSync?.signedOut(sub, me);
      inner.data.onNote = () => inner.status.setDb(inner.data.notes);
      yield* inner.data.open(inner.accounts.list().map((a) => a.sub));
      prefs.followLang(inner.data);
      // What goes out is what the clients' types say (client/core-ts/src/shapes/schema.ts).
      store.setShaped();
      store.setHeld((topic) => inner.data.shared(topic), (topic) => inner.data.release(topic));
      inner.data.onChange((topic) => {
        if (topic.topic === "*") {
          for (const t of store.liveTopics()) if (holds(t)) store.changed(t);
        } else store.changed(topic);
      });
      inner.status.onChange(() => store.invalidateAll((t) => t.topic === "status"));
      inner.scheduler = new Scheduler(inner.runner, inner.runner.root);
      inner.cloudSync = new CloudSync(inner);
      inner.status.setNames((address) => inner.cloudSync.nameOf(address));
      inner.workspaces.wireStatus(
        (id) => {
          store.invalidateAll((t) => t.topic === "status" && (t.workspace === undefined || t.workspace === id));
          store.invalidate({ topic: "doing" });
        },
        (address) => inner.cloudSync.nameOf(address),
      );
      inner.router = new Router(inner);
      store.setSource(inner.router);
      inner.iroh = options.iroh ?? null;
      inner.stations = new StationsSync(inner, options.wire ? options.wire(inner) : meshWire(inner));
      inner.stationTopics = new StationTopics(inner, inner.stations);
      inner.router.owners.push(inner.stationTopics);
      installStationCalls();
      inner.views = new Views(envOf(inner));
      inner.router.owners.push(inner.views);
      inner.viewCalls = new ViewCalls(inner, inner.views);
      inner.viewCalls.install();
      inner.attention = new Attention(inner, yield* Attend.load(inner.host));
      inner.router.owners.push(inner.attention);
      inner.router.after = (topic, value) => inner.attention.attended(topic, value);
      inner.attention.install();
      inner.choose = installChoose(inner);
      inner.forms = installForms(inner);
      const asks = new Asks(inner.host);
      inner.adb = new Adb({
        host: inner.host,
        runner: inner.runner,
        store: inner.store,
        mesh: () => inner.mesh(),
        credentials: (workspace) => (device, fresh) => inner.cloudSync.credential(workspace, device, fresh, inner.meshNow()?.deviceId() ?? null),
        relays: (workspace) => inner.cloudSync.workspaceRelays(workspace),
      });
      handlers.adb = (_i, call) => inner.adb.run((call as Extract<Call, { kind: "adb" }>).call);
      handlers.ask = (_i, call) => asks.run((call as Extract<Call, { kind: "ask" }>).ask, inner.accounts);
      inner.changelog = new Changelog(inner.host, inner.store, inner.data);
      inner.router.owners.push(inner.changelog);
      handlers.changelogSeen = () => Effect.sync(() => (inner.changelog.seen(), null));
      hooks.device = (_inner, facts) => inner.changelog.device(facts);
      inner.router.owners.push(new Pills(inner.store, inner.runner, () => inner.host.nowMs(), (station) => inner.views.stationName(station)));
      // The stations every account reaches are linked, as the workspaces say (once a burst of changes settles).
      let reconciling = false;
      inner.cloudSync.onReach = () => {
        if (reconciling) return;
        reconciling = true;
        inner.runner.fork(
          Effect.sync(() => {
            reconciling = false;
            inner.stations.reconcile();
          }),
        );
      };
      inner.shownAccounts = inner.accounts.list();
      inner.tracer.setExport((body) => {
        const account = inner.accounts.list()[0];
        return account ? Effect.ignore(inner.cloud.traces(account.sub, body)) : Effect.void;
      });
      // An account signed in has its database opened; one signed out, removed (before what it reached is let go).
      inner.accounts.onChange(() => {
        inner.runner.fork(Effect.andThen(inner.data.accounts(inner.accounts.list().map((a) => a.sub)), Effect.sync(() => inner.cloudSync.accountsChanged())));
      });
      // From now on the core keeps what it holds current, whatever the UI shows.
      inner.cloudSync.start();
      inner.stations.reconcile();
      // What was on its way when the core last stopped goes on.
      inner.viewCalls.resume();
      // What changed in still.fail: read now, and again each time an account's events socket opens.
      inner.scheduler.enqueue("cloud", "changelog", Priority.background, inner.changelog.read());
      inner.cloudSync.onOpen = () => inner.scheduler.enqueue("cloud", "changelog", Priority.background, inner.changelog.read());
      return new Core(inner);
    });
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
    this.inner.attention.attend.gone(client);
    this.inner.forms.disconnect(this.inner, client);
    for (const [key, fiber] of [...this.inner.calls]) {
      if (key.startsWith(`${client}/`)) {
        this.inner.calls.delete(key);
        this.inner.runner.interrupt(fiber);
      }
    }
  }

  /// A message from a UI as JSON (what the native hosts are given): one that is none answers `bad_message`.
  receiveJson(client: ClientId, json: string): void {
    let raw: unknown;
    try {
      raw = JSON.parse(json);
    } catch {
      return;
    }
    this.receiveRaw(client, raw);
  }

  /// A message from a UI as an object.
  receiveRaw(client: ClientId, raw: unknown): void {
    const message = parseClientMessage(raw);
    if ("invalid" in message) {
      const id = isObject(raw) && typeof raw.id === "number" && Number.isInteger(raw.id) && raw.id >= 0 ? raw.id : null;
      if (id !== null) this.inner.host.emit(client, { id, error: new CoreError("bad_message", t("core-misc.host.bad_message", { error: message.invalid })) });
      return;
    }
    this.receive(client, message);
  }

  /// A message from a UI. Answers and values go out through `Host.emit`.
  receive(client: ClientId, message: ClientMessage): void {
    const inner = this.inner;
    switch (message.kind) {
      case "subscribe":
        return inner.store.subscribe(client, message.id, message.subscribe, message.keyed === true);
      case "unsubscribe":
        return inner.store.unsubscribe(client, message.id);
      case "cancel": {
        const key = `${client}/${message.id}`;
        const fiber = inner.calls.get(key);
        if (fiber) {
          inner.calls.delete(key);
          inner.runner.interrupt(fiber);
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
    const span = inner.tracer.root(name, Kind.Internal);
    const station = callStation(call);
    if (station !== null) span.set("stillfail.station", stationId(station));
    // A preview's resource: its page's progress counts it (preview-load.ts).
    const loads = call.kind === "stationPreview" ? inner.workspaces.ofStation(call.station).part("previewLoad", () => new Loads()) : null;
    const resource = loads !== null && call.kind === "stationPreview" ? loads.start(call.station, call.port, call.method, call.path, call.headers, inner.host.nowMs()) : null;
    if (resource) inner.store.invalidate(resource[0]);
    const progress: Progress = (value) => {
      const head = isObject(value) && isObject(value.head) ? value.head : null;
      if (loads && resource && head && typeof head.status === "number") {
        loads.head(resource, head.status);
        // Event streams stay open after they have connected.
        const stream = Array.isArray(head.headers) && head.headers.some((h) => Array.isArray(h) && typeof h[0] === "string" && h[0].toLowerCase() === "content-type" && typeof h[1] === "string" && h[1].startsWith("text/event-stream"));
        if (stream) loads.end(resource, inner.host.nowMs(), null);
        inner.store.invalidate(resource[0]);
      }
      inner.host.emit(client, { id, value });
    };
    const key = `${client}/${id}`;
    const stoppable = cancellable(call);
    const run = execute(inner, call, progress, [client, id], span.context).pipe(
      Effect.mapError(asCoreError),
      // Stopped (a UI cancelled it, or went): it says so.
      Effect.onInterrupt(() =>
        Effect.sync(() => {
          inner.calls.delete(key);
          span.cancel();
          const cancelled = new CoreError("cancelled", t("core-misc.call.cancelled"));
          // Its resource ends with it: the page's progress counts it as failed.
          if (loads && resource) {
            loads.end(resource, inner.host.nowMs(), cancelled.message);
            inner.store.invalidate(resource[0]);
          }
          if (doing !== null) {
            inner.doing.end(doing);
            inner.store.invalidate({ topic: "doing" });
          }
          inner.host.emit(client, answer(id, { err: cancelled }));
        }),
      ),
      Effect.exit,
      Effect.flatMap((exit) =>
        Effect.gen(function* () {
          if (stoppable) inner.calls.delete(key);
          const result: { ok: unknown } | { err: CoreError } = exit._tag === "Success" ? { ok: exit.value } : { err: failureOf(exit.cause) };
          if (loads && resource) {
            const status = "ok" in result && isObject(result.ok) ? result.ok.status : undefined;
            if (typeof status === "number") loads.head(resource, status);
            loads.end(resource, inner.host.nowMs(), "err" in result ? result.err.message : null);
            inner.store.invalidate(resource[0]);
          }
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
            yield* Effect.sleep(FAILED_SHOWN_MS);
            inner.doing.end(failed);
            inner.store.invalidate({ topic: "doing" });
          }
        }),
      ),
    );
    // Only a call that holds something open for its page can be stopped; any other runs to its end whoever waits.
    const fiber = inner.runner.fork(run);
    if (stoppable) inner.calls.set(key, fiber as Fiber.Fiber<unknown, unknown>);
  }

  /// Lets the core go: its fibers stop.
  close(): void {
    this.inner.runner.shutdown();
  }
}

function failureOf(cause: Cause.Cause<unknown>): CoreError {
  // The cause's failure: a CoreError (a defect said as one).
  return asCoreError(Cause.squash(cause));
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
