// The station's services: what its parts are given, each a Context key with the layer that makes it. Async and
// long-lived work is Effect (fibers in scopes: a part stopped stops all it started); computing what to answer is plain
// functions (src/read). docs/station-ts.md, 「模块划分」.
import { Context, Effect, Layer, Queue, Stream, SubscriptionRef } from "effect";
import { join } from "node:path";
import { Admin } from "./api/admin.ts";
import { Events as EventStreams } from "./api/events.ts";
import { Host } from "./api/host.ts";
import { outputAt, tail } from "./read/jobs.ts";
import { Store as StationStore } from "./store/store.ts";
import { type StationKey, loadKey } from "./cloud/key.ts";
import { Cloud as CloudState } from "./cloud/state.ts";
import { type Mesh, loadMesh } from "./mesh/native.ts";
import { Readers as ReaderPool } from "./read/pool.ts";

/// Where the station keeps its data, and the release it runs from.
export class Paths extends Context.Service<Paths, { readonly data: string; readonly app: string }>()("stillfail/Paths") {}

/// still.fail cloud's state for this station (cloud.json), and its changes as they happen.
export class Cloud extends Context.Service<Cloud, { readonly state: CloudState; readonly changes: Stream.Stream<void> }>()("stillfail/Cloud") {
  static readonly layer = Layer.effect(
    Cloud,
    Effect.gen(function* () {
      const { data } = yield* Paths;
      const state = yield* Effect.acquireRelease(Effect.sync(() => new CloudState(data)), (s) => Effect.sync(() => s.close()));
      const changes = Stream.callback<void>((queue) =>
        Effect.acquireRelease(
          Effect.sync(() => state.listen(() => void Queue.offerUnsafe(queue, undefined))),
          (unlisten) => Effect.sync(unlisten),
        ),
      );
      return Cloud.of({ state, changes });
    }),
  );
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

/// The station's store (stillfail.db, archive/): what is written, on this thread; the readers read the same file.
export class Store extends Context.Service<Store, StationStore>()("stillfail/Store") {
  static readonly layer = Layer.effect(
    Store,
    Effect.gen(function* () {
      const { data } = yield* Paths;
      return yield* Effect.acquireRelease(
        Effect.sync(() => StationStore.open(join(data, "stillfail.db"), join(data, "archive"))),
        (store) => Effect.sync(() => store.close()),
      );
    }),
  );
}

/// The event streams (GET /events): the store's changes, pushed.
export class Events extends Context.Service<Events, EventStreams>()("stillfail/Events") {
  static readonly layer = Layer.effect(
    Events,
    Effect.gen(function* () {
      const store = yield* Store;
      const readers = yield* Readers;
      const admin = yield* AdminHost;
      return new EventStreams({
        readers,
        subscribe: (listener) => store.subscribe(listener),
        host: () => admin.sample(),
        jobLog: (id) => store.getJob(id)?.log ?? null,
        tail,
        outputAt,
        sessionExists: (key) => store.getSession(key) !== null,
      });
    }),
  );
}

/// The machine's state, shared by GET /host and the events.
export class AdminHost extends Context.Service<AdminHost, Host>()("stillfail/AdminHost") {
  static readonly layer = Layer.effect(
    AdminHost,
    Effect.gen(function* () {
      return new Host(yield* Readers);
    }),
  );
}

/// The admin API.
export class AdminApi extends Context.Service<AdminApi, Admin>()("stillfail/AdminApi") {
  static readonly layer = Layer.effect(
    AdminApi,
    Effect.gen(function* () {
      return new Admin(yield* Readers, { store: yield* Store, events: yield* Events, host: yield* AdminHost });
    }),
  );
}

/// The native mesh addon.
export class MeshNative extends Context.Service<MeshNative, Mesh>()("stillfail/MeshNative") {
  static readonly layer = Layer.effect(MeshNative, Effect.sync(loadMesh));
}
