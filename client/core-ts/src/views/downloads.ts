// A chat's files downloaded to this device (docs/client-core.md, Downloads): what the core does to bring a file a
// message names onto this device and hand it to the system, whatever page asked and whatever becomes of it (a preview
// closed, another opened, the app closed and opened again). It fetches the file a part at a time, each part kept with
// its chat as it comes (drive-kept.ts `chat`), and goes on from what is kept: what a viewer read of it before, what a
// download stopped by the app's end had fetched (each download is written down until it is saved, and goes on as the
// core starts again). Every page shows how far each has come (a message's file, its preview); once all of it is here
// the app takes it (`download.take`, once), reads it off the device a part at a time into the system's downloads
// (`station.file.part` with `keep` and its size) and says it is done (`download.done`, with where the system put it):
// where the app can read it back (Host.savedRead), the file saved is its copy on the device, what was kept of it let
// go (read from there until it is no longer there: drive-kept.ts `saved`); elsewhere (the web, iOS: out of reach) the
// device keeps of it what it kept before it was asked (nothing, if it kept none of it), not a second copy.
//
// Topic:
//   downloads {}                  this device's downloads, newest first: under way, waiting for their station, all
//                                 here to be saved, being saved, or failed
// Calls:
//   download.start {station, key, name, size}
//                                 the file a message names fetched to be saved: one of it under way or ready is that one
//                                 (a failed one, or one waiting for its station, starts again); answers {download}
//   download.take {id}            a ready one taken to be saved: {taken} true for the first to take it
//   download.done {id, at?}       saved (`at`: where the system put it), or the saving given up: out of the list, what
//                                 was fetched for it let go (all of it, where it is read back from `at`)
//   download.cancel {id}          stopped and out of the list, what was fetched for it let go
import { Effect, Fiber } from "effect";
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

/// `waiting`: its station not reached, it goes on once it is (the link back online).
type State = "going" | "waiting" | "ready" | "saving" | "failed";

type Download = {
  id: string;
  station: string;
  key: string;
  name: string;
  size: number;
  loaded: number;
  state: State;
  error: string | null;
  /// When it was asked, in whole ms (the shapes' i64: a host's clock says fractions of one).
  startedAt: number;
  /// Whether the device kept any of the file before it was asked (a viewer's): kept so once it is saved.
  keptBefore: boolean;
  /// The percent last told (the list is told again as it moves on a whole percent, not at every piece).
  told: number;
  fiber: Fiber.Fiber<void, never> | null;
};

/// What is written down of one (drive-kept.ts `download`): enough to go on with it as the core starts again.
type Noted = Pick<Download, "id" | "station" | "key" | "name" | "size" | "keptBefore" | "startedAt">;

/// Not reached (the station, the mesh, a time out), as the outbox takes it (views/calls.ts): tried again once it is.
const unreached = (e: CoreError) => e.status === undefined && (e.code === "host" || e.code === "mesh" || e.code === "timeout");

const percent = (d: Download) => (d.size > 0 ? Math.floor((d.loaded / d.size) * 100) : 100);

/// A download as the list shows it: `active` while it is not failed (its progress shown, it can be called off).
export function shown(d: Download): Record<string, unknown> {
  const statusText =
    d.state === "going" ? t("core-logic.download.going", { percent: percent(d), total: bytes(d.size) })
    : d.state === "waiting" ? t("core-logic.download.waiting", { percent: percent(d) })
    : d.state === "ready" ? t("core-logic.download.ready", { total: bytes(d.size) })
    : d.state === "saving" ? t("core-logic.download.saving", { total: bytes(d.size) })
    : t("core-logic.download.failed", { error: d.error ?? "" });
  return {
    id: d.id,
    station: d.station,
    key: d.key,
    name: d.name,
    size: d.size,
    loaded: d.loaded,
    progress: d.size > 0 ? d.loaded / d.size : d.state === "going" || d.state === "waiting" ? 0 : 1,
    state: d.state,
    active: d.state !== "failed",
    statusText,
    ...(d.error !== null ? { error: d.error } : {}),
    startedAt: d.startedAt,
  };
}

const need = (v: unknown, field: string): string => {
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
  return v;
};

/// This device's downloads (Inner.downloads).
export class Downloads {
  readonly #inner: Inner;
  readonly #held = new Map<string, Download>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  #invalidate(): void {
    this.#inner.store.invalidateAll((topic) => topic.topic === "downloads");
  }

  /// The `downloads` topic: newest first.
  view(): { downloads: Record<string, unknown>[] } {
    return { downloads: [...this.#held.values()].sort((a, b) => b.startedAt - a.startedAt).map(shown) };
  }

  /// How far it has come: told again as it moves on a whole percent.
  #moved(d: Download, loaded: number): void {
    d.loaded = Math.min(loaded, d.size);
    if (percent(d) === d.told) return;
    d.told = percent(d);
    this.#invalidate();
  }

  #note(d: Download): Effect.Effect<void> {
    const noted: Noted = { id: d.id, station: d.station, key: d.key, name: d.name, size: d.size, keptBefore: d.keptBefore, startedAt: d.startedAt };
    return this.#inner.driveKept.noteDownload(d.id, noted);
  }

  /// Out of the list and no longer written down; what was fetched for it let go (what the device kept of the file
  /// before it was asked stays).
  #drop(d: Download): Effect.Effect<void> {
    this.#held.delete(d.id);
    this.#invalidate();
    const kept = this.#inner.driveKept;
    return Effect.andThen(kept.dropDownload(d.id), d.keptBefore ? Effect.void : kept.forget(d.id));
  }

  /// The whole of it here, a part at a time: each part read as kept, or fetched and kept. A station from before parts
  /// sends it whole (as long as it is not too big for that).
  #fetchAll(d: Download): Effect.Effect<void, CoreError> {
    const inner = this.#inner;
    const self = this;
    return Effect.gen(function* () {
      const addr = StationAddr.parse(d.station);
      for (let at = 0; at < d.size;) {
        const length = Math.min(DOWNLOAD_PART, d.size - at);
        const held = yield* inner.driveKept.read(d.id, 0, d.size, at, length);
        if (held !== null && held.bytes.length > 0) {
          at += held.bytes.length;
          self.#moved(d, at);
          continue;
        }
        const from = at;
        const got = yield* Effect.result(inner.stations.requests.filePart(addr, d.key, d.name, at, length, null, (n) => self.#moved(d, from + n)));
        if (got._tag === "Failure") {
          if (at === 0 && got.failure.code === "unsupported" && d.size <= WHOLE_MAX) {
            const [type, whole] = yield* inner.stations.requests.file(addr, d.key, d.name, false, (loaded) => self.#moved(d, loaded), null);
            d.size = whole.length;
            yield* inner.driveKept.keep(d.id, "chat", 0, d.size, type, 0, whole);
            self.#moved(d, d.size);
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
        self.#moved(d, at);
      }
    });
  }

  /// Fetching it, in the core's own scope: on by itself until it is all here, has failed, its station is not reached,
  /// or it is called off.
  #go(d: Download): void {
    d.state = "going";
    d.error = null;
    d.told = -1;
    this.#moved(d, 0);
    d.fiber = this.#inner.runner.fork(
      Effect.map(Effect.result(this.#fetchAll(d)), (r) => {
        d.fiber = null;
        if (this.#held.get(d.id) !== d) return;
        if (r._tag === "Success") {
          d.state = "ready";
          d.loaded = d.size;
        } else if (unreached(r.failure)) d.state = "waiting";
        else {
          d.state = "failed";
          d.error = r.failure.message;
        }
        this.#invalidate();
      }),
    );
  }

  /// What was asked and not yet saved when the core last stopped goes on (each written down as it was asked).
  resume(): void {
    this.#inner.runner.fork(
      Effect.map(this.#inner.driveKept.downloads(), (rows) => {
        for (const row of rows) {
          const n = row as Partial<Noted>;
          if (typeof n.id !== "string" || typeof n.station !== "string" || typeof n.key !== "string" || typeof n.name !== "string" || typeof n.size !== "number") continue;
          // (asked again before this was read: that one)
          if (this.#held.has(n.id)) continue;
          const d: Download = { id: n.id, station: n.station, key: n.key, name: n.name, size: n.size, loaded: 0, state: "going", error: null, startedAt: Math.floor(n.startedAt ?? 0), keptBefore: n.keptBefore === true, told: -1, fiber: null };
          this.#held.set(d.id, d);
          this.#go(d);
        }
      }),
    );
  }

  /// Its station reached again (station/link.ts): those waiting for it go on.
  stationBack(station: string): void {
    for (const d of this.#held.values()) if (d.station === station && d.state === "waiting") this.#go(d);
  }

  call(c: Of): Effect.Effect<unknown, CoreError> {
    // (what is wrong with its params said as its failure)
    return Effect.flatten(Effect.try({ try: () => this.#asked(c), catch: asCoreError }));
  }

  #asked(c: Of): Effect.Effect<unknown, CoreError> {
    const p = c.params;
    const held = this.#held;
    const self = this;
    if (c.action === "start") {
      const station = need(p.station, "station");
      const key = need(p.key, "key");
      const name = need(p.name, "name");
      const size = typeof p.size === "number" && Number.isSafeInteger(p.size) && p.size >= 0 ? p.size : null;
      if (size === null) throw CoreError.invalid(t("core-misc.params.missing", { field: "size" }));
      StationAddr.parse(station);
      const id = chatKeptId(station, key, name);
      return Effect.gen(function* () {
        const was = held.get(id);
        if (was !== undefined) {
          if (was.state === "failed" || was.state === "waiting") self.#go(was);
          return { download: shown(was) };
        }
        const keptBefore = yield* self.#inner.driveKept.has(id);
        // (asked again while that was read: the one made then)
        const again = held.get(id);
        if (again !== undefined) return { download: shown(again) };
        const d: Download = { id, station, key, name, size, loaded: 0, state: "going", error: null, startedAt: Math.floor(self.#inner.host.nowMs()), keptBefore, told: -1, fiber: null };
        held.set(id, d);
        yield* self.#note(d);
        self.#go(d);
        return { download: shown(d) };
      });
    }
    const id = need(p.id, "id");
    const d = held.get(id);
    if (c.action === "take") {
      if (d === undefined || d.state !== "ready") return Effect.succeed({ taken: false });
      d.state = "saving";
      this.#invalidate();
      return Effect.succeed({ taken: true });
    }
    if (d === undefined) return Effect.succeed({});
    if (c.action === "done") {
      const at = typeof p.at === "string" ? p.at : "";
      // (where it can be read back from where it was saved, that is its copy: what was kept of it goes there)
      return Effect.as(Effect.andThen(at === "" ? Effect.void : this.#inner.driveKept.saved(id, at, d.size), this.#drop(d)), {});
    }
    // called off: stopped (its part being kept written whole first), then let go
    const fiber = d.fiber;
    d.fiber = null;
    this.#held.delete(id);
    this.#invalidate();
    return Effect.as(Effect.andThen(fiber === null ? Effect.void : Fiber.interrupt(fiber), this.#drop(d)), {});
  }

  /// The topic's owner.
  owner(): Owner {
    return {
      owns: (topic: Topic) => topic.topic === "downloads",
      start: () => {},
      compute: () => ({ ok: this.view() }),
    };
  }
}

export function install(inner: Inner): void {
  inner.downloads = new Downloads(inner);
  handlers.download = (core, call) => core.downloads.call(call as Of);
  inner.router.owners.push(inner.downloads.owner());
}
