// A chat's files downloaded to this device (docs/client-core.md, Downloads): asked of the core from whatever page, and
// fetched by it whatever becomes of that page (a preview closed, another opened), a part at a time, each part kept with
// its chat as it comes (drive-kept.ts `chat`): one stopped, or asked again after the app was closed, goes on from what
// was kept. Every page shows how far each has come (a message's file, its preview); once all of it is here the page
// that asked takes it (`download.take`, once) and saves it, reading it as kept (`station.file`, `station.file.part`
// with `keep` and its size: from the device, not the station). Held in memory: the list is this run's.
//
// Topic:
//   downloads {}                  this device's downloads under way, ready to be saved or failed, newest first
// Calls:
//   download.start {station, key, name, size}
//                                 the file a message names fetched to be saved: one of it under way or ready is that one
//                                 (a failed one starts again); answers {download}
//   download.take {id}            a ready one out of the list, for the page to save: {taken} true for the first to take it
//   download.cancel {id}          stopped and out of the list, what was kept of it let go
import { Effect, type Fiber } from "effect";
import type { Inner } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { chatKeptId } from "../drive-kept.ts";
import { CoreError, asCoreError } from "../error.ts";
import { bytes } from "../format.ts";
import { t } from "../i18n.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";

type Of = Extract<Call, { kind: "download" }>;

/// A part fetched at a time (as the pages read a big file).
export const DOWNLOAD_PART = 4 * 1024 * 1024;
/// The most a station from before parts sends whole.
const WHOLE_MAX = 50 * 1024 * 1024;

type State = "going" | "ready" | "failed";

type Download = {
  id: string;
  station: string;
  key: string;
  name: string;
  size: number;
  loaded: number;
  state: State;
  error: string | null;
  startedAt: number;
  /// The percent last told (the list is told again as it moves on a whole percent, not at every piece).
  told: number;
  fiber: Fiber.Fiber<void, never> | null;
};

const mem = new WeakMap<Inner, Map<string, Download>>();
const heldOf = (inner: Inner) => {
  let m = mem.get(inner);
  if (!m) mem.set(inner, (m = new Map()));
  return m;
};

function invalidate(inner: Inner): void {
  inner.store.invalidateAll((topic) => topic.topic === "downloads");
}

const percent = (d: Download) => (d.size > 0 ? Math.floor((d.loaded / d.size) * 100) : 100);

/// How far it has come: told again as it moves on a whole percent.
function moved(inner: Inner, d: Download, loaded: number): void {
  d.loaded = Math.min(loaded, d.size);
  if (percent(d) === d.told) return;
  d.told = percent(d);
  invalidate(inner);
}

/// A download as the list shows it.
export function shown(d: Download): Record<string, unknown> {
  const statusText =
    d.state === "going" ? t("core-logic.download.going", { percent: percent(d), total: bytes(d.size) })
    : d.state === "ready" ? t("core-logic.download.ready", { total: bytes(d.size) })
    : t("core-logic.download.failed", { error: d.error ?? "" });
  return {
    id: d.id,
    station: d.station,
    key: d.key,
    name: d.name,
    size: d.size,
    loaded: d.loaded,
    progress: d.size > 0 ? d.loaded / d.size : d.state === "going" ? 0 : 1,
    state: d.state,
    statusText,
    ...(d.error !== null ? { error: d.error } : {}),
    startedAt: d.startedAt,
  };
}

/// The `downloads` topic: newest first.
export function downloadsView(inner: Inner): { downloads: Record<string, unknown>[] } {
  return { downloads: [...heldOf(inner).values()].sort((a, b) => b.startedAt - a.startedAt).map(shown) };
}

/// The whole of it here, a part at a time: each part read as kept, or fetched and kept. A station from before parts
/// sends it whole (as long as it is not too big for that).
function fetchAll(inner: Inner, d: Download): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const addr = StationAddr.parse(d.station);
    for (let at = 0; at < d.size;) {
      const length = Math.min(DOWNLOAD_PART, d.size - at);
      const held = yield* inner.driveKept.read(d.id, 0, d.size, at, length);
      if (held !== null && held.bytes.length > 0) {
        at += held.bytes.length;
        moved(inner, d, at);
        continue;
      }
      const from = at;
      const got = yield* Effect.result(inner.stations.requests.filePart(addr, d.key, d.name, at, length, null, (n) => moved(inner, d, from + n)));
      if (got._tag === "Failure") {
        if (at === 0 && got.failure.code === "unsupported" && d.size <= WHOLE_MAX) {
          const [type, whole] = yield* inner.stations.requests.file(addr, d.key, d.name, false, (loaded) => moved(inner, d, loaded), null);
          d.size = whole.length;
          yield* inner.driveKept.keep(d.id, "chat", 0, d.size, type, 0, whole);
          moved(inner, d, d.size);
          return;
        }
        return yield* Effect.fail(got.failure);
      }
      const part = got.success;
      // (the station says how big it is: what the message said may be short of it)
      if (part.total !== d.size) d.size = part.total;
      if (part.bytes.length === 0) {
        if (at < d.size) return yield* Effect.fail(new CoreError("io", t("station.core.fileUnreadable")));
        break;
      }
      yield* inner.driveKept.keep(d.id, "chat", 0, d.size, part.type, at, part.bytes);
      at += part.bytes.length;
      moved(inner, d, at);
    }
  });
}

/// Fetching it, in the core's own scope: on by itself until it is all here, has failed, or is called off.
function go(inner: Inner, d: Download): void {
  d.state = "going";
  d.error = null;
  d.told = -1;
  moved(inner, d, 0);
  d.fiber = inner.runner.fork(
    Effect.map(Effect.result(fetchAll(inner, d)), (r) => {
      d.fiber = null;
      if (heldOf(inner).get(d.id) !== d) return;
      if (r._tag === "Success") {
        d.state = "ready";
        d.loaded = d.size;
      } else {
        d.state = "failed";
        d.error = r.failure.message;
      }
      invalidate(inner);
    }),
  );
}

const need = (v: unknown, field: string): string => {
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
  return v;
};

function run(inner: Inner, c: Of): Effect.Effect<unknown, CoreError> {
  // (what is wrong with its params said as its failure)
  return Effect.flatten(Effect.try({ try: () => asked(inner, c), catch: asCoreError }));
}

function asked(inner: Inner, c: Of): Effect.Effect<unknown, CoreError> {
  const p = c.params;
  const held = heldOf(inner);
  if (c.action === "start") {
    const station = need(p.station, "station");
    const key = need(p.key, "key");
    const name = need(p.name, "name");
    const size = typeof p.size === "number" && Number.isSafeInteger(p.size) && p.size >= 0 ? p.size : null;
    if (size === null) throw CoreError.invalid(t("core-misc.params.missing", { field: "size" }));
    StationAddr.parse(station);
    const id = chatKeptId(station, key, name);
    let d = held.get(id);
    if (d === undefined) {
      d = { id, station, key, name, size, loaded: 0, state: "going", error: null, startedAt: inner.host.nowMs(), told: -1, fiber: null };
      held.set(id, d);
      go(inner, d);
    } else if (d.state === "failed") go(inner, d);
    return Effect.succeed({ download: shown(d) });
  }
  const id = need(p.id, "id");
  const d = held.get(id);
  if (c.action === "take") {
    if (d === undefined || d.state !== "ready") return Effect.succeed({ taken: false });
    held.delete(id);
    invalidate(inner);
    return Effect.succeed({ taken: true });
  }
  if (d === undefined) return Effect.succeed({});
  held.delete(id);
  invalidate(inner);
  if (d.fiber !== null) inner.runner.interrupt(d.fiber);
  return Effect.as(d.state === "ready" ? Effect.void : inner.driveKept.forget(id), {});
}

function owner(inner: Inner): Owner {
  return {
    owns: (topic: Topic) => topic.topic === "downloads",
    start: () => {},
    compute: () => ({ ok: downloadsView(inner) }),
  };
}

export function install(inner: Inner): void {
  handlers.download = (core, call) => run(core, call as Of);
  inner.router.owners.push(owner(inner));
}
