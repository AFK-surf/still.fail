// What the core does to bring a file on a station onto this device and hand it to the system (docs/client-core.md,
// Downloads): a chat's file a message names, a file of a station's drive, or a folder of it (zipped on the station
// first, `drive.zip`), whatever page asked and whatever becomes of it (a preview closed, another opened, the app closed
// and opened again). It fetches the file a part at a time, each part kept as a reader of it keeps it (drive-kept.ts: a
// chat's `chat`, a drive's `file`), and goes on from what is kept: what a viewer read of it before, what a download
// stopped by the app's end had fetched (each download is written down until it is saved, and goes on as the core
// starts again). Every page shows how far each has come (a message's file, its preview, a drive's row); once all of it
// is here the app takes it (`download.take`, once), reads it a part at a time (`download.read`: off the device) into
// the system's downloads and says it is done (`download.done`, with where the system put it): where the app can read it
// back (Host.savedRead), the file saved is its copy on the device, what was kept of it let go (read from there until it
// is no longer there: drive-kept.ts `saved`); elsewhere (the web, iOS: out of reach) what was fetched stays kept, as
// it does when the download is called off: what came to this device is never asked of its station again.
// What is only to be had on this device (加载: a video to play) is not a download: fill.ts brings it (`fill.want`).
//
// Topic:
//   downloads {}                  this device's downloads, newest first: under way, waiting for their station, all
//                                 here to be saved, being saved, or failed; and (`keeping`) what was opened and let go,
//                                 being brought after everything else (fill.ts)
// Calls:
//   download.start {station, key, name, size, from?}
//                                 a chat's file (`from`: where it was opened, KeptFrom, listed with it) (its session `key`, its `name` at the station, its `size` as the message
//                                 says) fetched to be saved: one of it under way or ready is that one (a failed one, or
//                                 one waiting for its station, starts again); answers {download}
//   download.start {station, root, path, name, size, mtime}
//                                 a file of the station's drive, as its folder lists it
//   download.start {station, root, path, name, zip: true}
//                                 a folder of it, zipped on the station first (`name`: the zip's)
//   download.retry {id}           a failed one, or one waiting for its station, tried again now
//   download.take {id}            a ready one taken to be saved: {taken} true for the first to take it
//   download.read {id, offset, length}
//                                 bytes of one all here, as kept (from the station again only where what was kept is
//                                 gone): {type, total} and the bytes
//   download.done {id, at?}       saved (`at`: where the system put it), or the saving given up: out of the list (what
//                                 was kept of it let go where it is read back from `at`; else kept)
//   download.cancel {id}          stopped and out of the list, what was fetched for it kept
import { Effect, Fiber } from "effect";
import type { Inner, Progress } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { ClientId, RequestId } from "../protocol.ts";
import type { SpanContext } from "../trace.ts";
import type { Owner } from "../core/routing.ts";
import { chatKeptId, keptId } from "../drive-kept.ts";
import { CoreError, asCoreError } from "../error.ts";
import { bytes } from "../format.ts";
import { t } from "../i18n.ts";
import type { Topic } from "../protocol.ts";
import { StationAddr } from "../station/addr.ts";
import { request } from "../ops.ts";
import { conform } from "../conform.ts";
import { isObject } from "../util.ts";

type Of = Extract<Call, { kind: "download" }>;

/// A part fetched at a time (as the pages read a big file).
export const DOWNLOAD_PART = 4 * 1024 * 1024;
/// The most a station from before parts sends whole.
const WHOLE_MAX = 50 * 1024 * 1024;

/// `waiting`: its station not reached, it goes on once it is (the link back online).
type State = "going" | "waiting" | "ready" | "saving" | "failed";

/// What is fetched: a chat's file (its session `key`, its name at the station), a file of the drive (as its folder
/// lists it: `mtime`), or a folder of it zipped (`zip`; where the zip is once the station has made it).
type From =
  | { kind: "chat"; key: string; file: string }
  | { kind: "drive"; root: string; path: string; mtime: number }
  | { kind: "zip"; root: string; path: string; made: { root: string; path: string; mtime: number } | null };

type Download = {
  id: string;
  station: string;
  from: From;
  /// What it is called (a chat's file: its name at the station; a drive's: its name; a folder's: its zip's).
  name: string;
  size: number;
  loaded: number;
  state: State;
  error: string | null;
  /// When it was asked, in whole ms (the shapes' i64: a host's clock says fractions of one).
  startedAt: number;
  /// A chat's file's: where it was opened (KeptFrom), as the page that asked said it.
  opened?: unknown;
  /// The percent last told (the list is told again as it moves on a whole percent, not at every piece).
  told: number;
  fiber: Fiber.Fiber<void, never> | null;
};

/// What is written down of one (drive-kept.ts `download`): enough to go on with it as the core starts again (a
/// chat's from before drives were downloaded: `key`, no `from`; one only to be kept, from before fill.ts brought those:
/// `keep`).
type Noted = Pick<Download, "id" | "station" | "name" | "size" | "startedAt"> & { from?: From; key?: string; keep?: boolean; opened?: unknown };

/// The kept file a download fetches into and is read from: its id among those kept, its kind there, as it was (the
/// mtime a drive's folder said); null for a folder not zipped yet.
function kept(station: string, from: From): { id: string; kind: "chat" | "file"; mtime: number } | null {
  if (from.kind === "chat") return { id: chatKeptId(station, from.key, from.file), kind: "chat", mtime: 0 };
  if (from.kind === "drive") return { id: keptId(station, from.root, from.path), kind: "file", mtime: from.mtime };
  return from.made === null ? null : { id: keptId(station, from.made.root, from.made.path), kind: "file", mtime: from.made.mtime };
}

/// A download's own id: what it fetches for a file (a chat's, a drive's), the folder it zips for a folder.
function idOf(station: string, from: From): string {
  return from.kind === "zip" ? `zip\n${keptId(station, from.root, from.path)}` : kept(station, from)!.id;
}

/// Not reached (the station, the mesh, a time out), as the outbox takes it (views/calls.ts): tried again once it is.
const unreached = (e: CoreError) => e.status === undefined && (e.code === "host" || e.code === "mesh" || e.code === "timeout");
/// How long a part not answered while its station's link is up waits to be asked again.
export const AGAIN_MS = 5_000;

const percent = (d: Download) => (d.size > 0 ? Math.floor((d.loaded / d.size) * 100) : 100);

/// What a file is called to people: a file sent up as its sender named it, without what the station put before it
/// (station/src/api/routes/hub.ts uploadPath: the time and a mark).
export function titleOf(name: string): string {
  return name.replace(/^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-[0-9a-f]{6}-(?=.)/, "");
}

/// A download as the list shows it: `active` while it is not failed (its progress shown, it can be called off).
export function shown(d: Download): Record<string, unknown> {
  const statusText =
    d.state === "going" && d.from.kind === "zip" && d.from.made === null ? t("core-logic.download.zipping")
    : d.state === "going" ? t("core-logic.download.going", { percent: percent(d), total: bytes(d.size) })
    : d.state === "waiting" ? t("core-logic.download.waiting", { percent: percent(d) })
    : d.state === "ready" ? t("core-logic.download.ready", { total: bytes(d.size) })
    : d.state === "saving" ? t("core-logic.download.saving", { total: bytes(d.size) })
    : t("core-logic.download.failed", { error: d.error ?? "" });
  const from = d.from;
  return {
    id: d.id,
    station: d.station,
    ...(from.kind === "chat" ? { key: from.key, name: from.file, title: titleOf(from.file) } : { root: from.root, path: from.path, name: d.name, title: d.name, ...(from.kind === "zip" ? { zip: true } : {}) }),
    size: d.size,
    loaded: d.loaded,
    progress: d.size > 0 ? d.loaded / d.size : d.state === "going" || d.state === "waiting" ? 0 : 1,
    state: d.state,
    active: d.state !== "failed",
    statusText,
    ...(d.error !== null ? { error: d.error } : {}),
    startedAt: d.startedAt,
    ...(d.opened !== undefined ? { from: d.opened } : {}),
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
  view(): { downloads: Record<string, unknown>[]; keeping: Record<string, unknown>[] } {
    return { downloads: [...this.#held.values()].sort((a, b) => b.startedAt - a.startedAt).map(shown), keeping: this.#inner.fill?.shown() ?? [] };
  }

  /// How far it has come: told again as it moves on a whole percent.
  #moved(d: Download, loaded: number): void {
    d.loaded = Math.min(loaded, d.size);
    if (percent(d) === d.told) return;
    d.told = percent(d);
    this.#invalidate();
  }

  #note(d: Download): Effect.Effect<void> {
    const noted: Noted = { id: d.id, station: d.station, from: d.from, name: d.name, size: d.size, startedAt: d.startedAt, ...(d.opened !== undefined ? { opened: d.opened } : {}) };
    return this.#inner.driveKept.noteDownload(d.id, noted);
  }

  /// Out of the list and no longer written down; what was fetched for it stays kept (never asked of its station again).
  #drop(d: Download): Effect.Effect<void> {
    this.#held.delete(d.id);
    this.#invalidate();
    return this.#inner.driveKept.dropDownload(d.id);
  }

  /// The whole of it here, a part at a time: each part read as kept, or fetched and kept. A folder is zipped on the
  /// station first; a chat's file from a station from before parts comes whole (as long as it is not too big for that).
  #fetchAll(d: Download): Effect.Effect<void, CoreError> {
    const inner = this.#inner;
    const self = this;
    return Effect.gen(function* () {
      const addr = StationAddr.parse(d.station);
      const from = d.from;
      // (a zip the station made in this go: one not found then is not made again)
      const zipped = from.kind === "zip" && from.made === null;
      if (from.kind === "zip" && from.made === null) {
        const op = request("drive.zip", { station: d.station, root: from.root, path: from.path });
        if (op === null) return yield* Effect.fail(CoreError.invalid("drive.zip"));
        const z = (yield* inner.stations.perform(op, null)) as { root?: unknown; path?: unknown; name?: unknown; size?: unknown } | null;
        if (typeof z?.root !== "string" || typeof z.path !== "string" || typeof z.size !== "number") return yield* Effect.fail(new CoreError("io", t("station.core.fileUnreadable")));
        from.made = { root: z.root, path: z.path, mtime: 0 };
        if (typeof z.name === "string" && z.name !== "") d.name = z.name;
        d.size = z.size;
        d.told = -1;
        self.#moved(d, 0);
        yield* self.#note(d);
      }
      const file = kept(d.station, from)!;
      for (let at = 0; at < d.size;) {
        // what is kept from here on, however it came (a viewer's read, a player's ranges, what was loaded): taken
        // as it is, never asked again; only up to the next stretch kept asked of the station
        const until = yield* inner.driveKept.keptUntil(file.id, file.mtime, d.size, at, d.size);
        if (until > at) {
          at = until;
          self.#moved(d, at);
          continue;
        }
        const length = Math.min(DOWNLOAD_PART, (yield* inner.driveKept.nextKept(file.id, file.mtime, d.size, at, d.size)) - at);
        const was = at;
        const heard = (n: number) => self.#moved(d, was + n);
        if (from.kind === "chat") {
          const got = yield* Effect.result(inner.stations.requests.filePart(addr, from.key, from.file, at, length, null, heard));
          if (got._tag === "Failure") {
            if (at === 0 && got.failure.code === "unsupported" && d.size <= WHOLE_MAX) {
              const [type, whole] = yield* inner.stations.requests.file(addr, from.key, from.file, false, (loaded) => self.#moved(d, loaded), null);
              d.size = whole.length;
              yield* inner.driveKept.keep(file.id, "chat", 0, d.size, type, 0, whole);
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
          yield* inner.driveKept.keep(file.id, "chat", 0, d.size, part.type, at, part.bytes);
          at += part.bytes.length;
        } else {
          const where = from.kind === "drive" ? from : from.made!;
          const read = yield* Effect.result(inner.stations.requests.driveRead(addr, where.root, where.path, at, length, null, heard));
          // the station lets a zip go after an hour: one gone by the time this goes on (the app closed a while) is made again
          if (read._tag === "Failure" && from.kind === "zip" && !zipped && read.failure.status === 404) {
            yield* inner.driveKept.forget(file.id);
            from.made = null;
            yield* self.#note(d);
            return yield* self.#fetchAll(d);
          }
          if (read._tag === "Failure") return yield* Effect.fail(read.failure);
          const part = read.success;
          // changed on the station since its folder was read (or the zip's first part): what it is now, from its start
          if ((part.mtime !== null && part.mtime !== file.mtime) || part.total !== d.size) {
            if (where.mtime !== 0 || at > 0) yield* inner.driveKept.forget(file.id);
            where.mtime = part.mtime ?? 0;
            d.size = part.total;
            yield* self.#note(d);
            return yield* self.#fetchAll(d);
          }
          if (part.bytes.length === 0) {
            if (at < d.size) return yield* Effect.fail(new CoreError("io", t("station.core.fileUnreadable")));
            break;
          }
          yield* inner.driveKept.keep(file.id, "file", file.mtime, d.size, part.type, at, part.bytes);
          at += part.bytes.length;
        }
        self.#moved(d, at);
      }
    });
  }

  /// All of it here, a part not answered while its station's link is up (a slow network's time out: the station is
  /// reached, a viewer may be reading the same file from it) asked again after AGAIN_MS, not left waiting for a station
  /// that never went: only its link found down makes it wait (`waiting`), and `stationBack` is told as it comes up.
  #fetching(d: Download): Effect.Effect<void, CoreError> {
    return Effect.catch(this.#fetchAll(d), (e) =>
      unreached(e) && this.#inner.stations.online(d.station) ? Effect.andThen(Effect.sleep(AGAIN_MS), Effect.suspend(() => this.#fetching(d))) : Effect.fail(e));
  }

  /// Fetching it, in the core's own scope: on by itself until it is all here, has failed, its station is not reached,
  /// or it is called off.
  #go(d: Download): void {
    d.state = "going";
    d.error = null;
    d.told = -1;
    this.#moved(d, 0);
    d.fiber = this.#inner.runner.fork(
      Effect.flatMap(Effect.result(this.#fetching(d)), (r) => {
        d.fiber = null;
        if (this.#held.get(d.id) !== d) return Effect.void;
        if (r._tag === "Success") {
          d.state = "ready";
          d.loaded = d.size;
        } else if (unreached(r.failure)) d.state = "waiting";
        else {
          d.state = "failed";
          d.error = r.failure.message;
        }
        this.#invalidate();
        return Effect.void;
      }),
    );
  }

  /// Whether one fetches the kept file `id` (a chat's or a drive's file's download has its id): left to it (fill.ts).
  has(id: string): boolean {
    return this.#held.has(id);
  }

  /// What was asked and not yet saved when the core last stopped goes on (each written down as it was asked).
  resume(): void {
    this.#inner.runner.fork(
      Effect.map(this.#inner.driveKept.downloads(), (rows) => {
        for (const row of rows) {
          const n = row as Partial<Noted>;
          if (typeof n.id !== "string" || typeof n.station !== "string" || typeof n.name !== "string" || typeof n.size !== "number") continue;
          // (a chat's written down before drives were downloaded: its session and name)
          const from: From | null = n.from ?? (typeof n.key === "string" ? { kind: "chat", key: n.key, file: n.name } : null);
          if (from === null) continue;
          // (one only to be kept, written down before fill.ts brought those: brought by it, from what is kept)
          if (n.keep === true && from.kind === "chat") {
            this.#inner.runner.fork(Effect.andThen(this.#inner.fill.want(n.station, from.key, from.file, n.size, n.opened), this.#inner.driveKept.dropDownload(n.id)));
            continue;
          }
          // (asked again before this was read: that one)
          if (this.#held.has(n.id)) continue;
          const d: Download = { id: n.id, station: n.station, from, name: n.name, size: n.size, loaded: 0, state: "going", error: null, startedAt: Math.floor(n.startedAt ?? 0), told: -1, fiber: null, ...(n.opened !== undefined ? { opened: n.opened } : {}) };
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

  call(c: Of, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
    // (what is wrong with its params said as its failure)
    return Effect.flatten(Effect.try({ try: () => this.#asked(c, progress, at, ctx), catch: asCoreError }));
  }

  #asked(c: Of, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
    const p = c.params;
    const held = this.#held;
    const self = this;
    if (c.action === "start") {
      const station = need(p.station, "station");
      const name = need(p.name, "name");
      const count = (v: unknown) => (typeof v === "number" && Number.isSafeInteger(v) && v >= 0 ? v : null);
      const size = p.zip === true ? 0 : count(p.size);
      if (size === null) throw CoreError.invalid(t("core-misc.params.missing", { field: "size" }));
      StationAddr.parse(station);
      // a chat's file by its session; a drive's by where it is, as its folder said it is; a folder zipped
      const from: From = typeof p.key === "string" ? { kind: "chat", key: need(p.key, "key"), file: name }
        : p.zip === true ? { kind: "zip", root: need(p.root, "root"), path: need(p.path, "path"), made: null }
        : { kind: "drive", root: need(p.root, "root"), path: need(p.path, "path"), mtime: count(p.mtime) ?? 0 };
      const id = idOf(station, from);
      const that = (was: Download) => Effect.succeed({ download: shown(was) });
      // (a chat's file: where it was opened, KeptFrom, leading back there from the list)
      const shaped = from.kind === "chat" && isObject(p.from) ? conform("KeptFrom", p.from) : null;
      const opened = shaped !== null && "ok" in shaped ? shaped.ok : undefined;
      return Effect.gen(function* () {
        const was = held.get(id);
        if (was !== undefined) {
          if (was.state === "failed" || was.state === "waiting") self.#go(was);
          return yield* that(was);
        }
        const d: Download = { id, station, from, name, size, loaded: 0, state: "going", error: null, startedAt: Math.floor(self.#inner.host.nowMs()), told: -1, fiber: null, ...(opened !== undefined ? { opened } : {}) };
        held.set(id, d);
        yield* self.#note(d);
        self.#go(d);
        return { download: shown(d) };
      });
    }
    const id = need(p.id, "id");
    const d = held.get(id);
    if (c.action === "retry") {
      if (d !== undefined && (d.state === "failed" || d.state === "waiting")) this.#go(d);
      return Effect.succeed({});
    }
    if (c.action === "take") {
      if (d === undefined || d.state !== "ready") return Effect.succeed({ taken: false });
      d.state = "saving";
      this.#invalidate();
      return Effect.succeed({ taken: true });
    }
    if (c.action === "read") {
      // as its readers read it: what is kept answered, what is not fetched again and kept (`keep`)
      const file = d === undefined ? null : kept(d.station, d.from);
      if (d === undefined || file === null) return Effect.fail(new CoreError("not_found", t("station.core.fileUnreadable")));
      const offset = typeof p.offset === "number" ? p.offset : 0;
      const length = typeof p.length === "number" ? Math.min(p.length, DOWNLOAD_PART * 2) : DOWNLOAD_PART;
      const f = d.from;
      const call: Call = f.kind === "chat"
        ? { kind: "stationFilePart", station: d.station, key: f.key, name: f.file, offset, length, progress: false, stream: false, keep: d.size }
        : { kind: "driveRead", station: d.station, root: f.kind === "drive" ? f.root : f.made!.root, path: f.kind === "drive" ? f.path : f.made!.path, offset, length, progress: false, stream: false, keep: "file", mtime: file.mtime, size: d.size };
      const read = call.kind === "stationFilePart" ? handlers.stationFilePart : handlers.driveRead;
      return read === undefined ? Effect.fail(new CoreError("unsupported", "download.read")) : read(this.#inner, call, progress, at, ctx);
    }
    if (d === undefined) return Effect.succeed({});
    if (c.action === "done") {
      const where = typeof p.at === "string" ? p.at : "";
      const file = kept(d.station, d.from);
      // (where it can be read back from where it was saved, that is its copy: what was kept of it goes there)
      return Effect.as(Effect.andThen(where === "" || file === null ? Effect.void : this.#inner.driveKept.saved(file.id, where, d.size), this.#drop(d)), {});
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
  handlers.download = (core, call, progress, at, ctx) => core.downloads.call(call as Of, progress, at, ctx);
  inner.router.owners.push(inner.downloads.owner());
}
