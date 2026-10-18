// Modules: what an app adds to the core besides what every app has (docs/core-modules.md). The core is the platform:
// accounts, still.fail cloud, the links to stations, the device's databases, calls and topics. An app gives its
// modules to `Core.create(host, { modules })`; each is installed once the platform is up and owns the calls and topics
// named `<module>.…`, and reaches its own part on a station (`/admin/api/m/<module>/…`, docs/station-modules.md).
import { Effect, type Scope } from "effect";
import { type Spec, addSpec } from "./collections.ts";
import type { Inner, Progress } from "./core.ts";
import type { Owner } from "./core/routing.ts";
import { CoreError, asCoreError } from "./error.ts";
import type { ClientId, RequestId, Topic } from "./protocol.ts";
import { StationAddr } from "./station/addr.ts";
import type { WireReply } from "./station/wire.ts";
import type { SpanContext } from "./trace.ts";

/// A call a module answers: `<module>.<name>` with its params.
export type ModuleCall<P = unknown> = {
  /// The params checked and made what `run` takes; a wrong one throws (`CoreError.invalid`).
  parse(params: unknown, bytes: Uint8Array | undefined): P;
  run(p: P, at: CallAt): Effect.Effect<unknown, CoreError>;
  /// The station it is about (its trace says it).
  station?(p: P): string | null;
  /// One a person does and waits on: every page shows it under way (doing.ts).
  counts?: boolean;
  /// One that holds something open for its page: the UI stops it (`{id, cancel}`), and it stops as the UI goes.
  cancellable?: boolean;
};

/// Where a call came from, and how it says how far it has got.
export type CallAt = { progress: Progress; client: ClientId; id: RequestId; trace: SpanContext };

/// What a module is given of the core.
export type ModuleEnv = {
  /// Its own name (its calls, topics and station part are under it).
  readonly name: string;
  nowMs(): number;
  /// Work that goes on by itself (a topic's sync), ended as the core closes.
  fork(effect: Effect.Effect<unknown, never>): void;
  /// A JSON request to the module's part on a station (`path` under `/admin/api/m/<module>`); a non-2xx answer is an
  /// error. `quiet`: in the background, not said to be waited on.
  request(station: string, method: string, path: string, body: unknown, options?: { quiet?: boolean; trace?: SpanContext | null }): Effect.Effect<unknown, CoreError>;
  /// The same, its answer as it is (bytes: a picture); any status.
  exchange(station: string, method: string, path: string, headers: [string, string][], body: Uint8Array, options?: { quiet?: boolean; trace?: SpanContext | null }): Effect.Effect<{ status: number; headers: [string, string][]; body: Uint8Array }, CoreError>;
  /// An event stream of the module's part, open while the scope is.
  stream(station: string, path: string): Effect.Effect<WireReply, CoreError, Scope.Scope>;
  /// What the module keeps of a station on the device (in the account's database that reaches it), by name; undefined
  /// while nothing is.
  kept(station: string, name: string): unknown;
  /// Keeps it; `topic`'s value is computed again.
  keep(station: string, name: string, value: unknown, topic: Topic): void;
  /// A topic's value is to be computed again (what it reads changed).
  changed(topic: Topic): void;
};

/// What a module adds.
export type ModuleParts = {
  /// Its calls, by name (`<module>.` before it is what the UIs call).
  calls?: Record<string, ModuleCall<any>>;
  /// What computes its topics (each named `<module>.…`).
  topics?: Owner;
  /// Its topics' keyed lists (collections.ts), by topic name.
  keyed?: Record<string, Spec>;
};

export interface CoreModule {
  readonly name: string;
  install(env: ModuleEnv): ModuleParts;
}

/// A module's call as the core holds it: what was asked, checked.
export type HeldCall = { def: ModuleCall<any>; params: unknown };

/// Installs `modules` into the core: their calls by full name, their topics' owners in the router. The platform's own
/// calls come first (calls.ts): a module's call of the same name is never reached.
export function installModules(inner: Inner, modules: readonly CoreModule[]): Map<string, ModuleCall<any>> {
  const calls = new Map<string, ModuleCall<any>>();
  const names = new Set<string>();
  for (const module of modules) {
    if (!/^[a-z][a-z0-9]{0,31}$/.test(module.name) || names.has(module.name)) throw new Error(`a module's name is its own: ${module.name}`);
    names.add(module.name);
    const parts = module.install(envOf(inner, module.name));
    for (const [name, def] of Object.entries(parts.calls ?? {})) calls.set(`${module.name}.${name}`, def);
    const owner = parts.topics;
    if (owner) {
      const owns = owner.owns.bind(owner);
      // Only its own topics, whatever it says.
      owner.owns = (topic) => topic.topic.startsWith(`${module.name}.`) && owns(topic);
      inner.router.owners.push(owner);
    }
    for (const [topic, spec] of Object.entries(parts.keyed ?? {})) {
      if (!topic.startsWith(`${module.name}.`)) throw new Error(`a module's topic is under its name: ${topic}`);
      addSpec(topic, spec);
    }
  }
  return calls;
}

/// A module's call parsed, if `name` is one.
export function parseModuleCall(calls: Map<string, ModuleCall<any>>, name: string, params: unknown, bytes: Uint8Array | undefined): HeldCall | null {
  const def = calls.get(name);
  return def ? { def, params: def.parse(params, bytes) } : null;
}

function envOf(inner: Inner, name: string): ModuleEnv {
  const base = `/m/${name}`;
  const addr = (station: string) => Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError });
  const under = (path: string) => {
    if (!path.startsWith("/")) throw CoreError.invalid(`a module's path starts with /: ${path}`);
    return base + path;
  };
  const kind = (key: string) => `${base}/${key}`;
  return {
    name,
    nowMs: () => inner.host.nowMs(),
    fork: (effect) => void inner.runner.fork(effect),
    request: (station, method, path, body, options = {}) =>
      Effect.flatMap(addr(station), (a) => inner.stations.requests.call(a, method, under(path), body, { quiet: options.quiet, ctx: options.trace ?? null })),
    exchange: (station, method, path, headers, body, options = {}) =>
      Effect.flatMap(addr(station), (a) => inner.stations.requests.exchange(a, method, under(path), headers, body, options.quiet ?? false, options.trace ?? null)),
    stream: (station, path) => Effect.flatMap(addr(station), (a) => inner.stations.requests.stream(a, under(path), null)),
    kept: (station, key) => inner.data.of(station)?.stationDoc(station, kind(key)) as unknown,
    keep: (station, key, value, topic) => {
      const db = inner.data.of(station);
      if (db) db.putStationDoc(station, kind(key), value, inner.host.nowMs(), topic);
      inner.store.invalidate(topic);
    },
    changed: (topic) => inner.store.invalidate(topic),
  };
}
