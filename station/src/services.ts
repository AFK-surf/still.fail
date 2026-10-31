// The station's services: what its parts are given, each a Context key with the layer that makes it. Async and
// long-lived work is Effect (fibers in scopes: a part stopped stops all it started); computing what to answer is plain
// functions (src/read). docs/station-ts.md, 「模块划分」.
import { Context, Effect, Layer, Queue, Stream, SubscriptionRef } from "effect";
import { homedir } from "node:os";
import { join } from "node:path";
import { Admin } from "./api/admin.ts";
import { Events as EventStreams, eventsHandoverFile } from "./api/events.ts";
import { Host } from "./api/host.ts";
import { jobSeen, sessionSeen, threadSeen } from "./api/seen.ts";
import { outputAt, tail } from "./read/jobs.ts";
import { Store as StationStore } from "./store/store.ts";
import { type StationKey, loadKey } from "./cloud/key.ts";
import { Cloud as CloudState } from "./cloud/state.ts";
import { type ControlPlaneShape, makeControlPlane } from "./cloud/plane.ts";
import type { Provider } from "./cloud/provider.ts";
import { type Mesh, loadMesh } from "./mesh/native.ts";
import { Readers as ReaderPool } from "./read/pool.ts";
import type { AgentsParts } from "./sessions/agents.ts";
import { log } from "./ops/log.ts";
import { platform } from "./platform/index.ts";
import { ScreenHub } from "./screens/hub.ts";
import { Desktop } from "./screens/desktop.ts";
import { Simulators } from "./screens/simulator.ts";
import { WindowsDesktop, screenBinary } from "./screens/win-desktop.ts";
import { uiBinary } from "./screens/ui.ts";
import { type Drive, dropFolder, stationDrive } from "./drive/drive.ts";
import { ModuleSet } from "./modules/modules.ts";
import { Packages } from "./modules/packages.ts";
import { stationVersion } from "./ops/version.ts";
import { channelOf } from "./updates/versions.ts";
import { HelperApp, helperApp } from "./helper/app.ts";
import { HelperGrants } from "./helper/grants.ts";
import { HelperFiles } from "./helper/files.ts";
import { ConfigFile } from "./ops/config.ts";
import { Own as OwnPaths } from "./ops/own.ts";
import { previousProcess } from "./ops/previous.ts";
import { PeerBus } from "./mesh/bus.ts";
import type { Outside } from "./mesh/peer.ts";
import { Net } from "./jobs/load.ts";
import type { PeerRoute } from "./tools/http.ts";
import { StationParts } from "./parts.ts";
import { wall } from "./ops/fibers.ts";

/// Where the station keeps its data, and the release it runs from.
export class Paths extends Context.Service<Paths, { readonly data: string; readonly app: string }>()("stillfail/Paths") {}

/// The control plane this station is enrolled in (cloud/plane.ts): cloud.json and its changes, the presence socket,
/// notices, traces, releases and which credentials it takes. `layer` follows cloud.json's provider (still.fail cloud
/// when it names none); `layerFor` keeps to one (tests).
export class ControlPlane extends Context.Service<ControlPlane, ControlPlaneShape>()("stillfail/ControlPlane") {
  static readonly layer = ControlPlane.make();
  static layerFor(provider: Provider) {
    return ControlPlane.make(provider);
  }

  private static make(provider?: Provider) {
    return Layer.effect(
      ControlPlane,
      Effect.gen(function* () {
        const { data } = yield* Paths;
        const key = yield* Key;
        const up = yield* Up;
        const state = yield* Effect.acquireRelease(Effect.sync(() => new CloudState(data)), (s) => Effect.sync(() => s.close()));
        const changes = Stream.callback<void>((queue) =>
          Effect.acquireRelease(
            Effect.sync(() => state.listen(() => void Queue.offerUnsafe(queue, undefined))),
            (unlisten) => Effect.sync(unlisten),
          ),
        );
        return ControlPlane.of(makeControlPlane({ state, changes, key, up, provider }));
      }),
    );
  }
}

/// The station's key.
export class Key extends Context.Service<Key, StationKey>()("stillfail/Key") {
  static readonly layer = Layer.effect(
    Key,
    Effect.gen(function* () {
      return loadKey((yield* Paths).data);
    }),
  );
}

/// Whether the station answers now: its parts started, not stopping or handing over.
export class Up extends Context.Service<Up, SubscriptionRef.SubscriptionRef<boolean>>()("stillfail/Up") {
  static readonly layer = Layer.effect(Up, SubscriptionRef.make(false));
}

/// The readers (worker threads) answering the admin API's reads.
export class Readers extends Context.Service<Readers, ReaderPool>()("stillfail/Readers") {
  static readonly layer = Layer.effect(
    Readers,
    Effect.gen(function* () {
      const { data } = yield* Paths;
      return yield* Effect.acquireRelease(Effect.sync(() => new ReaderPool(data)), (pool) => Effect.sync(() => pool.close()));
    }),
  );
}

/// The store's log written into the database by the readers as the store changes (read/pool.ts `checkpointSoon`), not
/// by the main thread (store.ts).
export const CheckpointsLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const store = yield* Store;
    const readers = yield* Readers;
    yield* Effect.acquireRelease(
      Effect.sync(() => store.subscribe(() => readers.checkpointSoon())),
      (off) => Effect.sync(off),
    );
  }),
);

/// The station's store (stillfail.db, archive/): what is written, on this thread; the readers read the same file.
export class Store extends Context.Service<Store, StationStore>()("stillfail/Store") {
  static readonly layer = Layer.effect(
    Store,
    Effect.gen(function* () {
      const { data } = yield* Paths;
      return yield* Effect.acquireRelease(
        Effect.sync(() => {
          const store = StationStore.open(join(data, "stillfail.db"), join(data, "archive"));
          const lost = store.lostArchives();
          if (lost.length > 0) log.warn("store", "archived threads whose file is not there read as empty", { n: lost.length, threads: lost.join(" ") });
          return store;
        }),
        (store) => Effect.sync(() => store.close()),
      );
    }),
  );
}

/// still.fail Helper (macOS; docs/station-ts-native.md §4), installed and talked to under <data>/helper: this Mac's
/// screen (the desktop's) and the drive's protected folders (helper/files.ts); null where there is none.
export class Helper extends Context.Service<Helper, HelperApp | null>()("stillfail/Helper") {
  static readonly layer = Layer.effect(
    Helper,
    Effect.gen(function* () {
      const { data } = yield* Paths;
      const app = platform.desktopScreen === "helper" ? helperApp() : null;
      return app === null ? null : new HelperApp({ app, dir: join(data, "helper") });
    }),
  );
}

/// What macOS lets still.fail Helper do here (helper/grants.ts): one look at its grants and one window asking for them,
/// for the desktop's screen, the drive, the station's page and the agents; null where there is no helper.
export class Grants extends Context.Service<Grants, HelperGrants | null>()("stillfail/Grants") {
  static readonly layer = Layer.effect(
    Grants,
    Effect.gen(function* () {
      const helper = yield* Helper;
      return helper === null ? null : new HelperGrants({ helper, folders: platform.hasFolderPermissions });
    }),
  );
}

/// The screens members see and drive (docs/remote-screens.md): the registry the station's parts add their sources to
/// (`add`), with this machine's display among them from the start; views of them end as the station stops.
export class ScreenRegistry extends Context.Service<ScreenRegistry, ScreenHub>()("stillfail/Screens") {
  static readonly layer = Layer.effect(
    ScreenRegistry,
    Effect.gen(function* () {
      const hub = yield* Effect.acquireRelease(Effect.sync(() => new ScreenHub({ drop: () => dropFolder(homedir()) })), (hub) => Effect.sync(() => hub.close()));
      const helper = yield* Helper;
      // Windows': stillfail-screen, a process a view; macOS's: still.fail Helper, with its grants.
      const desktop: Desktop | WindowsDesktop =
        platform.desktopScreen === "screen"
          ? new WindowsDesktop({ binary: screenBinary(), ui: uiBinary(), changed: () => hub.changed() })
          : new Desktop({ supported: platform.desktopScreen === "helper", helper, grants: yield* Grants, changed: () => hub.changed() });
      // Back after it ended by itself: the desktop asks again for a grant still missing.
      if (desktop instanceof Desktop) helper?.onBack(() => void desktop.helperBack());
      yield* Effect.acquireRelease(
        Effect.sync(() => {
          const remove = hub.add(desktop);
          // Its size and grants are looked at as the screens are asked for (the helper started then, not before).
          const unrefresh = hub.refresher(() => desktop.refresh());
          return () => (unrefresh(), remove(), void desktop.close());
        }),
        (stop) => Effect.sync(stop),
      );
      // The iOS Simulators booted on this Mac, each a screen while it is (still.fail Helper's, as the desktop is).
      yield* Effect.acquireRelease(
        Effect.sync(() => {
          const simulators = new Simulators({ screens: hub, helper });
          void simulators.start();
          const unrefresh = hub.refresher(() => simulators.refresh());
          return () => (unrefresh(), simulators.close());
        }),
        (stop) => Effect.sync(stop),
      );
      return hub;
    }),
  );
}

/// The event streams (GET /events): the store's changes, pushed. What they told goes on in the next process (a
/// handover, or the next start), taken up once this one is gone.
export class Events extends Context.Service<Events, EventStreams>()("stillfail/Events") {
  static readonly layer = Layer.effect(
    Events,
    Effect.gen(function* () {
      const store = yield* Store;
      const readers = yield* Readers;
      const admin = yield* AdminHost;
      const screens = yield* ScreenRegistry;
      const { data } = yield* Paths;
      const previous = yield* Previous;
      const events = new EventStreams({
        readers,
        subscribe: (listener) => store.subscribe(listener),
        host: () => admin.sample(),
        jobLog: (id) => store.getJob(id)?.log ?? null,
        tail,
        outputAt,
        sessionExists: (key) => store.getSession(key) !== null,
        seen: (viewer, of) => ("session" in of ? sessionSeen(store, viewer, of.session) : "thread" in of ? threadSeen(store, viewer, of.thread) : jobSeen(store, viewer, of.job)),
        handover: { file: eventsHandoverFile(data), previous },
      });
      // Handed over as the station stops, after the parts made on it (the agents' side has handed over its sessions,
      // the mesh let go of every stream): the last it tells is told by then.
      yield* Effect.addFinalizer(() => Effect.promise(() => events.handOver()));
      // The screens as they change, and who is on them (`screens`).
      yield* Effect.acquireRelease(
        Effect.sync(() => screens.onChange(() => events.screens((lang) => screens.listed(lang)))),
        (off) => Effect.sync(off),
      );
      return events;
    }),
  );
}

/// The machine's state, shared by GET /host, the events and what other stations are told of this one's load; its
/// CPUs noted every few seconds for their recent average (Host.follow) while the station runs.
export class AdminHost extends Context.Service<AdminHost, Host>()("stillfail/AdminHost") {
  static readonly layer = Layer.effect(
    AdminHost,
    Effect.gen(function* () {
      const host = new Host(yield* Readers);
      yield* Effect.acquireRelease(Effect.sync(() => host.follow()), (stop) => Effect.sync(stop));
      return host;
    }),
  );
}

/// The modules beside the station (docs/station-modules.md): which there are and how each is now, for the admin API
/// (passed on to them), the overview and modules/live.ts (which starts them). Their changes told as the overview's.
export class Modules extends Context.Service<Modules, ModuleSet>()("stillfail/Modules") {
  static readonly layer = Layer.effect(
    Modules,
    Effect.gen(function* () {
      const events = yield* Events;
      return new ModuleSet((yield* Paths).data, () => events.overviewChanged());
    }),
  );
}

/// The packages of the modules the station installs itself (modules/packages.ts): from where its own releases are, on
/// its channel, once the process before it is gone; started by ModulesLive, read and updated with the station's own
/// updates (the agents' side adds them to its updates: a line each).
export class ModulePackages extends Context.Service<ModulePackages, Packages>()("stillfail/ModulePackages") {
  static readonly layer = Layer.effect(
    ModulePackages,
    Effect.gen(function* () {
      const { data, app } = yield* Paths;
      const plane = yield* ControlPlane;
      const config = yield* StationConfig;
      const previous = yield* Previous;
      const version = stationVersion(app);
      return yield* Effect.acquireRelease(
        Effect.sync(() =>
          new Packages({
            data,
            station: version === undefined ? null : Number(version.slice("0.1.".length)),
            base: () => plane.releaseBase(),
            channel: () => channelOf(config.raw(), app),
            previousGone: previous.gone,
          }),
        ),
        (packages) => Effect.promise(() => packages.close()),
      );
    }),
  );
}

/// config.json (ops/config.ts): one for the whole station. What an edit must pass is said by the parts that read it
/// (the agents' side: accounts/check.ts).
export class StationConfig extends Context.Service<StationConfig, ConfigFile>()("stillfail/Config") {
  static readonly layer = Layer.effect(
    StationConfig,
    Effect.gen(function* () {
      return new ConfigFile((yield* Paths).data);
    }),
  );
}

/// What is the station's own on this machine (ops/own.ts): its data and config, and what its parts add as they are made.
export class Own extends Context.Service<Own, OwnPaths>()("stillfail/Own") {
  static readonly layer = Layer.effect(
    Own,
    Effect.gen(function* () {
      return new OwnPaths((yield* Paths).data, (yield* StationConfig).path);
    }),
  );
}

/// The station process before this one (ops/previous.ts), and its end: what only one process may have waits on it, and
/// what its event streams told is taken up from it alone (api/events.ts). Looked for as this process starts, before it
/// writes its own run/hub.json.
export class Previous extends Context.Service<Previous, { readonly pid: number | null; readonly gone: Promise<void> }>()("stillfail/Previous") {
  static readonly layer = Layer.effect(
    Previous,
    Effect.gen(function* () {
      return previousProcess(join((yield* Paths).data, "run"));
    }),
  );
}

/// The station's requests to and from the other stations of its workspace (mesh/bus.ts): the mesh attaches the
/// transport, the parts say what they answer.
export class Peers extends Context.Service<Peers, PeerBus>()("stillfail/Peers") {
  static readonly layer = Layer.sync(Peers, () => new PeerBus({ sleep: (ms) => wall.sleep(ms) }));
}

/// What the mesh (mesh/mesh.ts) shares with the agents' side, each filled by the one that has it: the relay link as the
/// mesh sees it (`net`, told to other stations with this one's load), the mesh's way to other stations' web services
/// (`peers`, the agents' door's /peer requests), and what the agents say: the stations of other workspaces this one
/// shares chats with (`outside`), a port of another station forwarded here (`forwarded`), the runtimes its device tools
/// see (`runtimes`). The mesh no longer reaches into the agents' side.
export type MeshSideShape = {
  readonly net: Net;
  readonly peers: { route: PeerRoute | null };
  outside: Outside | null;
  forwarded: (port: number) => boolean;
  runtimes: () => string[];
};
export class MeshSide extends Context.Service<MeshSide, MeshSideShape>()("stillfail/MeshSide") {
  static readonly layer = Layer.sync(MeshSide, (): MeshSideShape => ({ net: new Net(), peers: { route: null }, outside: null, forwarded: () => false, runtimes: () => [] }));
}

/// The station's parts in its own process (parts.ts): what each adds to the admin API, the overview and the agents'
/// tools, said as it is made.
export class Parts extends Context.Service<Parts, StationParts>()("stillfail/Parts") {
  static readonly layer = Layer.sync(Parts, () => new StationParts());
}

/// The folders macOS protects (Documents, Desktop, Downloads, disks) through still.fail Helper (helper/files.ts): the
/// drive's, a search's and the directories people and agents name; none where there is no helper for them. Their
/// grants' changes are the overview's.
export class HelperFolders extends Context.Service<HelperFolders, HelperFiles | null>()("stillfail/HelperFolders") {
  static readonly layer = Layer.effect(
    HelperFolders,
    Effect.gen(function* () {
      const grants = yield* Grants;
      const events = yield* Events;
      return grants && platform.hasFolderPermissions ? new HelperFiles({ helper: grants.helper, grants, changed: () => events.overviewChanged() }) : null;
    }),
  );
}

/// The station's drive (drive/drive.ts, docs/drive.md): one, for the admin API's routes and the modules' local API.
/// config.json's roots; what is the station's own never reached; the folders macOS protects through still.fail Helper.
export class StationDrive extends Context.Service<StationDrive, Drive>()("stillfail/Drive") {
  static readonly layer = Layer.effect(
    StationDrive,
    Effect.gen(function* () {
      const own = yield* Own;
      return stationDrive(yield* StationConfig, () => own.more(), yield* HelperFolders);
    }),
  );
}

/// The agents' side once it is made (sessions/agents.ts sets it): the admin API is made before it and asks for it as a
/// request comes; nothing of the platform waits on it.
export class AgentsSide extends Context.Service<AgentsSide, { current: AgentsParts | null }>()("stillfail/AgentsSide") {
  static readonly layer = Layer.sync(AgentsSide, () => ({ current: null }));
}

/// The admin API: the platform's routes, the agents' side's as a request comes (AgentsSide), the parts' (parts.ts).
export class AdminApi extends Context.Service<AdminApi, Admin>()("stillfail/AdminApi") {
  static readonly layer = Layer.effect(
    AdminApi,
    Effect.gen(function* () {
      const side = yield* AgentsSide;
      const config = yield* StationConfig;
      return new Admin(yield* Readers, {
        store: yield* Store, events: yield* Events, host: yield* AdminHost, agents: () => side.current ?? undefined, screens: yield* ScreenRegistry, helper: yield* Helper, grants: yield* Grants,
        drive: yield* StationDrive, modules: yield* Modules, parts: yield* Parts, config, data: (yield* Paths).data, cloud: (yield* ControlPlane).state,
      });
    }),
  );
}

/// The native mesh addon.
export class MeshNative extends Context.Service<MeshNative, Mesh>()("stillfail/MeshNative") {
  static readonly layer = Layer.effect(MeshNative, Effect.sync(loadMesh));
}
