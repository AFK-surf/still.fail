// `Core`: takes messages from connected UIs, answers calls, keeps subscriptions (core.rs for the
// protocol). Construction opens the signed-in accounts' databases (data.ts), wires the modules together and starts the
// sync (sync/), which keeps everything the core holds current by itself; subscriptions only read what is held.
import { Cause, Effect, type Clock, type Fiber } from "effect";
import type { AccountView } from "./accounts.ts";
import { type AccountProvider, type AccountProviderFactory, type AccountSessions, stillfailAccountProvider } from "./account-provider.ts";
import * as brand from "./brand.ts";
import * as commands from "./commands.ts";
import { findGo } from "./chat-find.ts";
import { mentionView, relayView } from "./relay-pick.ts";
import { wordsAnswer } from "./words.ts";
import { toolCall, toolResult, type ToolPart } from "./tool-step.ts";
import * as fonts from "./fonts.ts";
import { MermaidAbsent, mermaidChart, provideMermaid } from "./mermaid.ts";
import { parseCall, cancellable, callStation, counts, type Call } from "./core/calls.ts";
import { execute, handlers, hooks } from "./core/execute.ts";
import { Router } from "./core/routing.ts";
import { importFormer } from "./db/import.ts";
import { Data, holds } from "./data.ts";
import { chatDerive } from "./views/views.ts";
import { Doing, FAILED_SHOWN_MS, heavy } from "./doing.ts";
import { DriveKept } from "./drive-kept.ts";
import { CoreError, asCoreError, failedIn } from "./error.ts";
import { HEDGE, type Host } from "./host.ts";
import { t } from "./i18n.ts";
import { markdown } from "./markdown.ts";
import { AHEAD_AFTER_MS, MdAhead } from "./md-ahead.ts";
import * as prefs from "./prefs.ts";
import { Beside, parseClientMessage, type ClientId, type ClientMessage, type CoreMessage, type RequestId } from "./protocol.ts";
import { TRACES } from "./route.ts";
import { laterSleep, Runner } from "./runtime.ts";
import { stationId } from "./station/addr.ts";
import { Status, Waited } from "./status.ts";
import { Store } from "./store.ts";
import { CloudSync } from "./sync/cloud.ts";
import { Priority, Scheduler } from "./sync/scheduler.ts";
import { Kind, SAMPLE, Tracer } from "./trace.ts";
import { spentClock } from "./spent.ts";
import { checkWith, keepVerified } from "./vault/verified.ts";
import { Wakes, WakingHost } from "./wake.ts";
import { Workspaces } from "./workspace.ts";
import { install as installStationCalls } from "./station/calls.ts";
import { install as installScreens } from "./screens.ts";
import { Composers, install as installComposer } from "./composer.ts";
import { StationsSync } from "./station/sync.ts";
import { StationTopics } from "./station/topics.ts";
import type { StationWire } from "./station/wire.ts";
import type { Mesh } from "./mesh.ts";
import { credentialsFor, meshWire } from "./station/mesh-wire.ts";
import type { Iroh } from "./iroh.ts";
import { ViewCalls } from "./views/calls.ts";
import { Attend } from "./attend.ts";
import { Attention } from "./attention.ts";
import { Pills } from "./pill.ts";
import { AdminRelays } from "./sync/admin-relays.ts";
import type { Choose } from "./choose.ts";
import { installChoose } from "./choose-calls.ts";
import { install as installShareIn } from "./share-in.ts";
import { Changelog } from "./changelog.ts";
import { FeedbackReplies } from "./feedback-replies.ts";
import { FontFiles } from "./font-files.ts";
import { installForms, type Forms } from "./forms-calls.ts";
import { Loads } from "./preview-load.ts";
import { Asks } from "./asks.ts";
import { Adb } from "./adb.ts";
import { Rigs } from "./rigs.ts";
import { Devices } from "./devices.ts";
import { Signer } from "./lock.ts";
import { PersonalLock } from "./personal-lock.ts";
import { answersOf, asked, bindPerson, enrolled, inForceOf, keepToPerson, lockSeen, movedBySelf, movedHere, ownLockEnv, ownLockFor, personalStations, refusedAgain, signerOf, signsAs, takeOffBound, tellStations, tookOrRefused, withBound } from "./views/lock.ts";
import { personalBegin, personalCancel, personalPairState, personalProve } from "./views/pair.ts";
import { envOf, Views } from "./views/views.ts";
import * as xshare from "./views/xshare.ts";
import * as memberships from "./views/memberships.ts";
import * as publish from "./views/publish.ts";
import * as lockCalls from "./views/lock.ts";
import * as pairing from "./views/pair.ts";
import * as vaultCalls from "./views/vault.ts";
import * as waysCalls from "./views/ways-stations.ts";
import * as stationMarkCalls from "./views/station-marks.ts";
import * as transferCalls from "./views/transfers.ts";
import * as browseCalls from "./views/browse.ts";
import * as downloads from "./views/downloads.ts";
import * as fill from "./fill.ts";
import { get, isObject, sha256 } from "./util.ts";

/// Where a device's member credentials are kept (`credential/<account>/<workspace>`), and how long one serves.
export const CREDENTIAL_KEY = "credential";
export const CREDENTIAL_FOR_S = 24 * 60 * 60;
export const CREDENTIAL_OTHERS = "others";
export const CREDENTIAL_OTHERS_KEPT = 8;
/// Where this device's push registration is kept.
export const PUSH_KEY = "push";

/// How far a call has got, for a UI that asked to hear it; `bytes` go beside the value, not in it (protocol.ts).
export type Progress = (value: unknown, bytes?: Uint8Array) => void;

export type Options = {
  /// How the core reaches stations: the mesh by default; tests' stations answer over the host's fetch.
  wire?: (inner: Inner) => StationWire;
  /// The share of traces recorded (0: none).
  sample?: number;
  /// The clock the core's timers run on (a TestClock in tests).
  clock?: Clock.Clock;
  /// The iroh this host has (iroh.ts); none: stations are not reached over the mesh.
  iroh?: Iroh | null;
  /// Who the accounts are with (account-provider.ts): still.fail cloud unless the embedding app gives another
  /// (`commaAccountProvider`, comma.ts).
  account?: AccountProviderFactory;
};

/// What the core holds: every module.
export class Inner {
  host!: Host;
  runner!: Runner;
  tracer!: Tracer;
  /// Client errors recorded lately, by source and message, and when.
  reported = new Map<string, number>();
  /// The control plane the accounts are with, and the accounts.
  provider!: AccountProvider;
  accounts!: AccountSessions;
  store!: Store;
  data!: Data;
  workspaces!: Workspaces;
  /// What the device waits on: still.fail cloud, its sockets, the relay for no station.
  status!: Status;
  /// The requests waited on now, every workspace's and the device's (status.ts).
  waited!: Waited;
  /// Files of the stations' drives kept on this device once read, for an app that asks (drive-kept.ts).
  driveKept!: DriveKept;
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
  /// The workspaces' rigs (rigs.ts).
  rigs!: Rigs;
  /// The workspaces' devices (devices.ts).
  devices!: Devices;
  viewCalls!: ViewCalls;
  /// This device's downloads of chats' files (views/downloads.ts).
  downloads!: downloads.Downloads;
  /// What was opened and let go, brought whole after everything else (fill.ts).
  fill!: fill.Fill;
  router!: Router;
  /// The calls under way that a UI can stop, by `client/id`.
  calls = new Map<string, Fiber.Fiber<unknown, unknown>>();
  doing = new Doing();
  /// What is being written in each chat (composer.ts).
  composers!: Composers;
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
      inner.host = new WakingHost(host, inner.wakes, HEDGE);
      inner.driveKept = new DriveKept(inner.host);
      // (the files kept for messages left behind a week)
      inner.runner.fork(inner.driveKept.dropOldUploads());
      brand.setTestChannel(inner.host.testChannel());
      brand.setCloud(inner.host.cloudOrigin());
      fonts.setOrigin(inner.host.cloudOrigin(), inner.host.testChannel());
      inner.tracer = new Tracer(inner.host, inner.runner, options.sample ?? SAMPLE, TRACES);
      spentClock(() => inner.host.monotonicMs());
      // A failure let go of is a span of its own: Cloud Trace has it though nothing waited on it.
      inner.runner.onIgnored = (what, error) => {
        const span = inner.tracer.root("ignored", Kind.Internal);
        span.set("stillfail.ignored", what);
        failedIn(span, asCoreError(error));
        span.end();
      };
      inner.waited = new Waited(() => inner.host.nowMs());
      inner.status = new Status(inner.host, inner.runner, inner.waited);
      inner.provider = yield* (options.account ?? stillfailAccountProvider)({ host: inner.host, tracer: inner.tracer, status: inner.status });
      inner.accounts = inner.provider.accounts;
      inner.workspaces = new Workspaces(inner.host, inner.runner, inner.waited);
      inner.store = new Store(inner.host, inner.runner, inner.tracer);
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
      // (signatures checked once on this device, kept with its own values: vault/verified.ts)
      keepVerified({ get: (k) => inner.data.device.get("verified", k), put: (k, ok) => void inner.data.device.put("verified", k, ok) });
      // (checked by the host's own, where it has one: a native app's shell, libcrux)
      checkWith(inner.host.verify ? (alg, key, signature, message) => inner.host.verify!(alg, key, signature, message) : null);
      prefs.followLang(inner.data);
      prefs.followApp(inner.data);
      // What goes out is what the clients' types say (client/core-ts/src/shapes/schema.ts).
      store.setShaped();
      store.setHeld((topic) => topic.topic === "draft"
        ? inner.composers.readDraft(String(topic.station), String(topic.chat))
        : inner.data.shared(topic), (topic) => inner.data.release(topic));
      inner.data.onChange((topic) => {
        if (topic.topic === "*") {
          for (const t of store.liveTopics()) if (holds(t)) store.changed(t);
        } else store.changed(topic);
      });
      // Why a station down is not reached is said again as still.fail cloud is reached, or no longer is.
      inner.status.onCloud = () => inner.stations?.recause();
      inner.scheduler = new Scheduler(inner.runner, inner.runner.root);
      inner.cloudSync = new CloudSync(inner);
      inner.status.setNames((address) => inner.cloudSync.nameOf(address));
      inner.workspaces.wireStatus((address) => inner.cloudSync.nameOf(address));
      inner.router = new Router(inner);
      store.setSource(inner.router);
      inner.iroh = options.iroh ?? null;
      inner.stations = new StationsSync(inner, options.wire ? options.wire(inner) : meshWire(inner));
      inner.stationTopics = new StationTopics(inner, inner.stations);
      inner.router.owners.push(inner.stationTopics);
      installStationCalls();
      installScreens();
      inner.composers = new Composers(inner);
      installComposer();
      inner.views = new Views(envOf(inner));
      inner.views.local.onMade = (station, key) => inner.composers.made(station, key);
      inner.router.owners.push(inner.views);
      inner.viewCalls = new ViewCalls(inner, inner.views);
      inner.viewCalls.install();
      // What agents said lately read ahead, kept on the device: a chat opens with its Markdown read (md-ahead.ts).
      const ahead = new MdAhead(inner.data, inner.runner, () => inner.host.nowMs(), (station, of) => inner.data.mdChanged(station, of));
      inner.data.onOldMd = (station, of, text) => ahead.refresh(station, of, text);
      inner.data.onLogChange((table, station, id) => {
        if (table === "entry") ahead.thread(station, Number(id));
      });
      xshare.install(inner);
      memberships.install(inner);
      publish.install(inner);
      lockCalls.install(inner);
      pairing.install(inner);
      vaultCalls.install(inner);
      waysCalls.install(inner);
      stationMarkCalls.install(inner);
      transferCalls.install(inner);
      browseCalls.install(inner);
      downloads.install(inner);
      fill.install(inner);
      inner.attention = new Attention(inner, yield* Attend.load(inner.host));
      inner.router.owners.push(inner.attention);
      inner.router.after = (topic, value) => inner.attention.attended(topic, value);
      inner.router.attends = (topic) => topic.topic === "chat";
      inner.attention.install();
      inner.choose = installChoose(inner);
      installShareIn(inner);
      inner.forms = installForms(inner);
      const asks = new Asks(inner.host, (from, to) => inner.changelog.brings(from, to), (address) => inner.views?.stationNow(address) ?? address);
      asks.follow(inner.accounts);
      // A release may be out (still.fail cloud said one is, or its events socket opened again: what it said while closed
      // is not said again): the newest of each feed read again when next asked, and the app told (the `releases`
      // topic's `told`) so the build it gets ready is the newest, not one read before.
      let told = 0;
      const releaseOut = () => {
        asks.released();
        told += 1;
        inner.store.invalidate({ topic: "releases" });
      };
      inner.router.owners.push({ owns: (topic) => topic.topic === "releases", compute: () => ({ ok: { told } }) });
      inner.cloudSync.onRelease = releaseOut;
      inner.adb = new Adb({
        host: inner.host,
        runner: inner.runner,
        store: inner.store,
        mesh: () => inner.mesh(),
        credentials: credentialsFor(inner, () => inner.meshNow()),
        relays: (workspace) => inner.cloudSync.workspaceRelays(workspace),
        off: (workspace) => inner.cloudSync.workspaceOff(workspace),
        part: (station, key, name, offset, length) => inner.stations.requests.filePart(station, key, name, offset, length, null, undefined, undefined, undefined, true),
        lends: () => inner.host.tcp !== undefined && (inner.data.shared({ topic: "prefs" }) as { device?: { app?: unknown } } | undefined)?.device?.app === "android",
        personal: new PersonalLock({
          host: inner.host,
          runner: inner.runner,
          cloud: (sub, method, path, body) => inner.provider.request(sub, method, path, body),
          device: () => Effect.map(inner.mesh(), (m) => m.deviceId()),
          label: () => prefs.deviceName(inner.data) ?? "",
          signKey: () => signerOf(inner),
          ...ownLockEnv(inner),
          changed: () => {
            inner.adb.touched();
            inner.rigs?.touched();
            for (const [ws] of inner.workspaces.owned()) {
              lockSeen(inner).touch(`lock ${ws}`);
              inner.runner.fork(bindPerson(inner, ws));
              inner.runner.fork(keepToPerson(inner, ws));
              inner.runner.fork(ownLockFor(inner, ws));
              refusedAgain(inner, ws);
              // (handed over by itself once a station took all it said: views/lock.ts `movedBySelf`)
              inner.runner.fork(movedBySelf(inner, ws));
              // (where its chain moved, the state in force made anew of the person's log now, the vaults following it:
              // views/lock.ts `inForceOf`, whether or not anything shown reads it)
              if (movedHere(inner, ws)) inner.runner.fork(laterSleep(0).pipe(Effect.andThen(Effect.sync(() => void inForceOf(inner, ws)))));
            }
          },
          told: (sub, chain) => tellStations(inner, sub, chain),
          stations: personalStations(inner),
          asked: () => asked(inner),
        }),
        tookOff: (sub, id, removal) => withBound(inner, sub, Effect.tap(removal, () => takeOffBound(inner, sub, id))),
        subOf: (workspace) => inner.workspaces.owner(workspace),
        subs: () => inner.accounts.list().map((a) => ({ sub: a.sub, email: a.email })),
        pair: {
          begin: (subs) => personalBegin(inner, subs),
          code: (typed) => personalProve(inner, typed),
          cancel: () => personalCancel(inner),
          state: (sub) => personalPairState(inner, sub),
        },
      });
      handlers.adb = (_i, call) => inner.adb.run((call as Extract<Call, { kind: "adb" }>).call);
      // The workspaces' rigs (a station that only runs tasks), as their stations say them; what their person signs for them.
      inner.rigs = new Rigs({
        host: inner.host,
        store: inner.store,
        personal: () => inner.adb.personal(),
        subOf: (workspace) => inner.workspaces.owner(workspace),
        view: (workspace) => inner.data.shared({ topic: "workspace", workspace }),
        call: (station, method, path, body) => inner.stations.requests.call(station, method, path, body, { quiet: true }),
        cloud: (sub, method, path, body) => inner.provider.request(sub, method, path, body),
        first: (asks, at) => answersOf(inner, asks, tookOrRefused, at),
        lock: {
          locked: (workspace) => signsAs(inner, workspace).locked,
          enrolled: (sub, workspace, made) => enrolled(inner, sub, workspace, made),
          signsAs: (workspace) => signsAs(inner, workspace).as,
          signAdd: (_workspace, bytes) =>
            Effect.flatMap(Signer.load(inner.host), (signer) =>
              signer === null ? Effect.fail(new CoreError("lock_no_signer", t("core-misc.rig.notSigner"))) : Effect.succeed({ key: signer.id, sig: signer.signBytes(bytes) })),
        },
        sha256,
      });
      handlers.rig = (_i, call) => inner.rigs.run((call as Extract<Call, { kind: "rig" }>).call);
      // (read whole as a station is first read; after that its `rigs` event says each change, a stream that was away
      // told the last of them as it goes on)
      inner.stations.also.push({ read: (address) => inner.rigs.read(address), event: (address, name, data) => inner.rigs.heard(address, name, data) });
      // The workspaces' devices: the whole stations' own, the rigs' (as the rigs say them), the phones lent to stations.
      inner.devices = new Devices({
        host: inner.host,
        store: inner.store,
        rigs: () => inner.rigs,
        personal: () => inner.adb.personal(),
        subOf: (workspace) => inner.workspaces.owner(workspace),
        emailOf: (workspace) => {
          const sub = inner.workspaces.owner(workspace);
          return sub === null ? null : (inner.accounts.list().find((a) => a.sub === sub)?.email ?? null);
        },
        view: (workspace) => inner.data.shared({ topic: "workspace", workspace }),
        call: (station, method, path, body) => inner.stations.requests.call(station, method, path, body, { quiet: true }),
      });
      handlers.device = (_i, call) => inner.devices.run((call as Extract<Call, { kind: "device" }>).call);
      inner.stations.also.push({ read: (address) => inner.devices.read(address), event: (address, name, data) => inner.devices.heard(address, name, data) });
      // This person's chats' grants of their phone, as each station says them.
      inner.stations.also.push({ read: (address) => inner.adb.readGrants(address), event: (address, name, data) => (name === "adb-grant" ? inner.adb.heard(address, data) : undefined), resume: true });
      handlers.ask = (_i, call) => asks.run((call as Extract<Call, { kind: "ask" }>).ask, inner.accounts);
      inner.changelog = new Changelog(inner.host, inner.store, inner.data);
      inner.router.owners.push(inner.changelog);
      const feedbackReplies = new FeedbackReplies(inner.host, inner.data, (workspace) => inner.workspaces.owner(workspace));
      inner.router.owners.push(feedbackReplies);
      handlers.changelogSeen = () => Effect.sync(() => (inner.changelog.seen(), null));
      handlers.feedbackDismiss = (_i, call) => {
        const c = call as Extract<Call, { kind: "feedbackDismiss" }>;
        return Effect.sync(() => (feedbackReplies.dismiss(c.workspace, c.id, c.reply), null));
      };
      handlers.historyTool = (_i, call) => {
        const c = call as Extract<Call, { kind: "historyTool" }>;
        // Markdown read here for the clients that draw its tree (markdown.ts), as everywhere else.
        const withMd = (parts: ToolPart[]) =>
          parts.map((part) => {
            if (part.kind === "markdown") return { ...part, md: markdown(part.text) };
            if (part.kind === "fields") {
              return {
                ...part,
                rows: part.rows.map((r) => (r.form === "long" ? { ...r, md: markdown(r.value) } : r)),
              };
            }
            return part;
          });
        return Effect.sync(() => ({
          call: withMd(toolCall(c.name, c.call, c.said, t)),
          result: c.result === null ? null : withMd(toolResult(c.name, c.call, c.result, c.failed, t)),
        }));
      };
      handlers.words = (_i, call) => {
        const c = call as Extract<Call, { kind: "words" }>;
        return Effect.sync(() => wordsAnswer(c.what, c.text, c.caret, c.here));
      };
      handlers.chatFindGo = (_i, call) => {
        const c = call as Extract<Call, { kind: "chatFindGo" }>;
        return Effect.sync(() => findGo(c.hits, c.at, c.by, c.from, c.to, c.drawn));
      };
      handlers.relayView = (_i, call) => {
        const c = call as Extract<Call, { kind: "relayView" }>;
        return Effect.sync(() => relayView(c.connects, c.query, c.all, c.bot, t));
      };
      handlers.relayMentions = (_i, call) => {
        const c = call as Extract<Call, { kind: "relayMentions" }>;
        return Effect.sync(() => mentionView(c.people, c.note));
      };
      handlers.commandsFind = (_i, call) => {
        const c = call as Extract<Call, { kind: "commandsFind" }>;
        return Effect.sync(() => commands.find(c.query, c.offered, t));
      };
      handlers.mermaidChart = (_i, call) => {
        const c = call as Extract<Call, { kind: "mermaidChart" }>;
        // refused: the chart's code as mermaid read it is no chart this draws (the app shows it another way)
        return Effect.tryPromise({
          try: () => mermaidChart(c.code, c.look, c.width),
          catch: (e) => new CoreError(e instanceof MermaidAbsent ? "mermaid_absent" : "unsupported", e instanceof Error ? e.message : String(e)),
        });
      };
      handlers.mermaidLoad = (_i, call) => {
        const c = call as Extract<Call, { kind: "mermaidLoad" }>;
        return Effect.tryPromise({
          try: () => provideMermaid(c.bytes).then(() => null),
          catch: (e) => new CoreError("unsupported", e instanceof Error ? e.message : String(e)),
        });
      };
      const fontFiles = new FontFiles(inner.host, inner.store);
      fonts.setKeptAt((sha256) => fontFiles.at(sha256));
      inner.router.owners.push(fontFiles);
      handlers.fonts = (_i, call) => fontFiles.run((call as Extract<Call, { kind: "fonts" }>).call);
      hooks.device = (_inner, facts) => inner.changelog.device(facts);
      const adminRelays = new AdminRelays(inner);
      inner.router.owners.push(adminRelays);
      inner.cloudSync.onRelayLoad = (sub) => adminRelays.told(sub);
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
      inner.adb.accountsKnown();
      inner.tracer.setExport((body) => {
        const account = inner.accounts.list()[0];
        // Sent again when the network or the cloud was down; not one the cloud refused (it would be refused again).
        const refused = (e: CoreError) => e.status !== undefined && e.status >= 400 && e.status < 500 && e.status !== 408 && e.status !== 429;
        return account ? Effect.catch(inner.provider.traces(account.sub, body), (e) => (refused(e) ? Effect.void : Effect.fail(e))) : Effect.void;
      });
      // An account signed in has its database opened; one signed out, removed (before what it reached is let go).
      inner.accounts.onChange(() => {
        inner.adb.accountsKnown();
        inner.runner.fork(Effect.andThen(inner.data.accounts(inner.accounts.list().map((a) => a.sub)), Effect.sync(() => inner.cloudSync.accountsChanged())));
      });
      // From now on the core keeps what it holds current, whatever the UI shows.
      inner.provider.start();
      inner.cloudSync.start();
      inner.stations.reconcile();
      // The chats spoken in latest, read ahead once what the first views ask has gone.
      inner.runner.fork(Effect.andThen(laterSleep(AHEAD_AFTER_MS), Effect.sync(() => ahead.seed())));
      // What was on its way when the core last stopped goes on.
      inner.viewCalls.resume();
      inner.downloads.resume();
      inner.fill.start();
      // What changed in still.fail: read now, and again each time an account's events socket opens (a release missed
      // while it was closed too).
      inner.scheduler.enqueue("cloud", "changelog", Priority.background, inner.changelog.read());
      inner.cloudSync.onOpen = () => {
        inner.scheduler.enqueue("cloud", "changelog", Priority.background, inner.changelog.read());
        inner.cloudSync.onRelease();
      };
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
  receiveJson(client: ClientId, json: string, bytes?: Uint8Array): void {
    let raw: unknown;
    try {
      raw = JSON.parse(json);
    } catch {
      return;
    }
    this.receiveRaw(client, raw, bytes);
  }

  /// A message from a UI as an object; `bytes`, those a native host handed over beside it.
  receiveRaw(client: ClientId, raw: unknown, bytes?: Uint8Array): void {
    const message = parseClientMessage(raw, bytes);
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
        return inner.store.subscribe(client, message.id, message.subscribe, message.keyed === true, message.from, message.have);
      case "unsubscribe":
        return inner.store.unsubscribe(client, message.id, message.keep === true);
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
        return this.#call(client, message.id, message.call, message.params, message.bytes);
    }
  }

  #call(client: ClientId, id: RequestId, name: string, params: unknown, bytes: Uint8Array | undefined): void {
    const inner = this.inner;
    const asked = heavy(name) ? null : params;
    let call: Call;
    try {
      call = parseCall(name, params, bytes);
    } catch (e) {
      inner.host.emit(client, answer(id, { err: asCoreError(e) }));
      return;
    }
    // Under way from now until it answers, for every page to show where it is (doing.ts).
    let doing: number | null = null;
    if (asked !== null && counts(call, name)) {
      doing = inner.doing.start(name, asked, inner.host.nowMs());
    }
    // Each call is a trace: what it asks of stations and still.fail cloud are its spans. One that asks nothing and
    // answers at once is not sent (trace.ts QUIET_MS).
    const span = inner.tracer.root(name, Kind.Internal);
    span.quiet();
    const station = callStation(call);
    if (station !== null) span.set("stillfail.station", stationId(station));
    // A preview's resource: its page's progress counts it (preview-load.ts).
    const loads = call.kind === "stationPreview" ? inner.workspaces.ofStation(call.station).part("previewLoad", () => new Loads()) : null;
    const resource = loads !== null && call.kind === "stationPreview" ? loads.start(call.station, call.port, call.method, call.path, call.headers, inner.host.nowMs()) : null;
    const progress: Progress = (value, bytes) => {
      const head = isObject(value) && isObject(value.head) ? value.head : null;
      if (loads && resource && head && typeof head.status === "number") {
        loads.head(resource, head.status);
        // Event streams stay open after they have connected.
        const stream = Array.isArray(head.headers) && head.headers.some((h) => Array.isArray(h) && typeof h[0] === "string" && h[0].toLowerCase() === "content-type" && typeof h[1] === "string" && h[1].startsWith("text/event-stream"));
        if (stream) loads.end(resource, inner.host.nowMs(), null);
      }
      inner.host.emit(client, bytes === undefined ? { id, value } : { id, value, bytes });
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
          }
          if (doing !== null) {
            inner.doing.end(doing);
          }
          inner.host.emit(client, answer(id, { err: cancelled }));
        }),
      ),
      Effect.exit,
      Effect.flatMap((exit) =>
        Effect.gen(function* () {
          if (stoppable) inner.calls.delete(key);
          const result: { ok: unknown } | { err: CoreError } = exit._tag === "Success" ? { ok: exit.value } : { err: failureOf(exit.cause) };
          if ("err" in result) failedIn(span, result.err);
          if (loads && resource) {
            const said = "ok" in result ? (result.ok instanceof Beside ? result.ok.value : result.ok) : undefined;
            const status = isObject(said) ? said.status : undefined;
            if (typeof status === "number") loads.head(resource, status);
            loads.end(resource, inner.host.nowMs(), "err" in result ? result.err.message : null);
          }
          span.end();
          let failed: number | null = null;
          if (doing !== null) {
            if ("err" in result) {
              inner.doing.fail(doing, result.err.message);
              failed = doing;
            } else inner.doing.end(doing);
          }
          inner.host.emit(client, answer(id, result));
          if (failed !== null) {
            yield* Effect.sleep(FAILED_SHOWN_MS);
            inner.doing.end(failed);
          }
        }),
      ),
    );
    // Only a call that holds something open for its page, or streams to it what it reads, can be stopped (cancellable);
    // any other runs to its end whoever waits.
    const fiber = inner.runner.fork(run);
    if (stoppable) inner.calls.set(key, fiber as Fiber.Fiber<unknown, unknown>);
  }

  #closing: Promise<void> | null = null;

  /// Lets the core go: its fibers stop, then what the device's tables changed and were yet to write is written (a core
  /// that follows on the same storage reads it). Fails with what could not be written; the core is gone all the same.
  close(): Promise<void> {
    if (this.#closing) return this.#closing;
    const { runner, data } = this.inner;
    runner.shutdown();
    this.#closing = runner.run(data.device.close());
    return this.#closing;
  }
}

function failureOf(cause: Cause.Cause<unknown>): CoreError {
  // The cause's failure: a CoreError (a defect said as one).
  return asCoreError(Cause.squash(cause));
}

export function answer(id: RequestId, result: { ok: unknown } | { err: CoreError }): CoreMessage {
  if (!("ok" in result)) return { id, error: result.err };
  return result.ok instanceof Beside ? { id, ok: result.ok.value, bytes: result.ok.bytes } : { id, ok: result.ok };
}

/// The relays a `/v1/me` names: `relay_urls`, still.fail's own first, or `relay_url` alone from a cloud from before.
export function relaysOf(me: unknown): string[] | null {
  if (!isObject(me)) return null;
  const all = Array.isArray(me.relay_urls) ? me.relay_urls.filter((v): v is string => typeof v === "string") : [];
  if (all.length > 0) return all;
  return typeof me.relay_url === "string" ? [me.relay_url] : null;
}

/// The forwarding entries a `/v1/me` names (`relay_entries`, cloud relays.ts), separate from the relays themselves.
export function entriesOf(me: unknown): string[] {
  if (!isObject(me) || !Array.isArray(me.relay_entries)) return [];
  return me.relay_entries.filter((v): v is string => typeof v === "string");
}

/// The relay on the other side of each entry, when the cloud knows it.
export function entryTargetsOf(me: unknown): Record<string, string> {
  if (!isObject(me) || !isObject(me.relay_entry_targets)) return {};
  return Object.fromEntries(Object.entries(me.relay_entry_targets).filter((entry): entry is [string, string] => typeof entry[1] === "string"));
}

export function gone(): CoreError {
  return new CoreError("closed", t("core-misc.core.closed"));
}
