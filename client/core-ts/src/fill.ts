// What was opened and let go is brought whole all the same, after everything else (docs/core-ts.md, rule 6): a chat's
// file or a drive's video or song a viewer read a part of (drive-kept.ts `chat`, `played`), saying where it was opened
// (`from`: written down beside it, `origin`; a still read off a film in its message says none, and is not brought),
// and let go of (a preview
// closed, a player gone elsewhere) goes on coming, a part at a time, kept as any read of it is, so that opened again it
// is here. It goes only while no request is waited on (status.ts Waited) and none has been for IDLE_MS, at the
// scheduler's lowest priority; one begun meanwhile stops the part (what came of it is kept) and it goes on after, so
// what a person opens has the link to itself. What is kept is the one record of what is left: nothing else is written
// down, and it goes on as the core starts again. Its station not reached, it waits for it; the file no longer there,
// what was kept of it goes. Not one past FILL_MAX, nor one whose rest its kind has no room for (it would push out what
// else is kept, then itself), nor one a download fetches, nor one last read before FILL_RECENT_MS ago (what was opened
// lately, not every file ever let go of: those kept before this went on would all come at once).
// A chat's file a person asked to load (加载, `fill.want`: a video to play from here) is brought the same way, before
// all else and at once: not after what is waited on, not bound by the prefs, whether or not any of it was read. It is
// one thing whichever way it began: what was read of it, what was brought of it, however sparse, is never asked again;
// only what is not kept is. Stopped (`fill.stop`), it is no longer brought; what came of it stays kept.
import { Effect } from "effect";
import type { Inner } from "./core.ts";
import { handlers } from "./core/execute.ts";
import type { Call } from "./core/calls.ts";
import { CoreError } from "./error.ts";
import { Beside } from "./protocol.ts";
import { Kind } from "./trace.ts";
import { Priority } from "./sync/scheduler.ts";
import { AGAIN_MS, DOWNLOAD_PART, titleOf } from "./views/downloads.ts";
import { chatKeptId, type Unfinished } from "./drive-kept.ts";
import { bytes } from "./format.ts";
import { t } from "./i18n.ts";
import { get, isObject } from "./util.ts";
import { conform } from "./conform.ts";

/// The most a file is brought whole by itself, unless the prefs say otherwise (`fillMax`).
export const FILL_MAX = 1024 * 1024 * 1024;
/// How lately a file must have been read to be brought whole.
export const FILL_RECENT_MS = 3 * 24 * 3600_000;
/// How long nothing must have been waited on before it goes (a player's next part is asked within this).
export const IDLE_MS = 3_000;

/// Not reached (the station, the mesh, a time out): tried again once it is.
const unreached = (e: CoreError) => e.status === undefined && (e.code === "host" || e.code === "mesh" || e.code === "timeout");

/// A kept file's part to bring: the call that reads it (with `keep`, `quiet`) and its station.
function partOf(f: Unfinished): Extract<Call, { kind: "stationFilePart" | "driveRead" }> | null {
  const length = Math.min(DOWNLOAD_PART, f.length);
  const [first, ...rest] = f.id.split("\n");
  // a chat's (chatKeptId): `chat`, its station, its session, its name
  if (first === "chat") {
    const [station, key, ...name] = rest;
    if (station === undefined || key === undefined || name.length === 0) return null;
    return { kind: "stationFilePart", station, key, name: name.join("\n"), offset: f.at, length, progress: true, stream: false, keep: f.size, quiet: true };
  }
  // a drive's (keptId): its station, its root, its path
  const [root, ...path] = rest;
  if (root === undefined || path.length === 0) return null;
  return { kind: "driveRead", station: first, root, path: path.join("\n"), offset: f.at, length, progress: false, stream: false, keep: "played", mtime: f.mtime, size: f.size, quiet: true };
}

/// One being brought, as the pages list it (`downloads`' `keeping`): coming now, given way to what a person waits on,
/// waiting for its station, or after the others (`wanted`: a person asked to load it, never given way).
type KeepingState = "going" | "yielding" | "waiting" | "queued";

/// How sure a file is to be brought: on (`prefs.fillOff` not so) and up to how big (`prefs.fillMax`: 0 none).
function bounds(inner: Inner): { on: boolean; most: number } {
  const prefs = inner.data.get({ topic: "prefs" });
  const most = get(prefs, "fillMax");
  return { on: get(prefs, "fillOff") !== true, most: typeof most === "number" && Number.isSafeInteger(most) && most >= 0 ? (most === 0 ? Number.POSITIVE_INFINITY : most) : FILL_MAX };
}

export class Fill {
  readonly #inner: Inner;
  /// Stations not reached as a part was asked of them: none of theirs until they are (`stationBack`).
  readonly #away = new Set<string>();
  /// Files the station could not give for another reason: not again in this run.
  readonly #failed = new Set<string>();
  /// Files whose part was not answered while their station's link was up (a slow network's time out): their station is
  /// reached, and nothing tells of it coming back, so they are asked again after AGAIN_MS, not left waiting for it.
  readonly #later = new Set<string>();
  /// Waiting for a poke: what goes on.
  #poked: (() => void) | null = null;
  /// Waiting for nothing to be waited on a while: what goes on at once (one asked to load).
  #wake: (() => void) | null = null;
  /// Poked since the files were last looked at.
  #dirty = false;
  #started = false;
  /// What is left to bring, as last looked at, in its order; where each was opened (a chat's file's, as its viewer
  /// said it: drive-kept.ts `origin`).
  #list: Unfinished[] = [];
  #from = new Map<string, unknown>();
  /// The one coming now, and how much of it is here; given way to what is waited on (`yielding`).
  #going: { id: string; loaded: number } | null = null;
  #yielding = false;
  /// Stopped as it came (`stop`): let go once its part has stopped.
  readonly #stopping = new Set<string>();
  #stop: (() => void) | null = null;
  /// The percents last told, by file.
  readonly #told = new Map<string, number>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  /// On from now, in the core's own scope.
  start(): void {
    if (this.#started) return;
    this.#started = true;
    this.#inner.runner.fork(Effect.forever(this.#step()));
  }

  /// Something may have been let go (a viewer's read ended), or the prefs changed: looked at again.
  poke(): void {
    // (listed at once, whether or not it may come now)
    if (this.#started) this.#inner.runner.fork(Effect.asVoid(this.#look()));
    this.#dirty = true;
    const poked = this.#poked;
    this.#poked = null;
    poked?.();
  }

  /// Its station reached again (station/link.ts): its files go on.
  stationBack(station: string): void {
    this.#away.delete(station);
    this.poke();
  }

  /// What is left to bring as the pages list it, the one coming first (`downloads`' `keeping`).
  shown(): Record<string, unknown>[] {
    const out: Record<string, unknown>[] = [];
    for (const f of this.#list) {
      const going = this.#going?.id === f.id ? this.#going : null;
      const loaded = Math.min(f.size, going?.loaded ?? f.have);
      const call = partOf(f);
      const station = call?.station ?? "";
      const state: KeepingState = going !== null ? (this.#yielding && !f.wanted ? "yielding" : "going")
        : this.#away.has(station) || !this.#reached(station) ? "waiting"
        : this.#yielding && out.length === 0 && !f.wanted ? "yielding"
        : "queued";
      const percent = f.size > 0 ? Math.floor((loaded / f.size) * 100) : 0;
      const statusText = f.wanted && state !== "waiting" ? t("core-logic.download.loading", { percent, total: bytes(f.size) })
        : state === "going" ? t("core-logic.keeping.going", { percent, total: bytes(f.size) })
        : state === "yielding" ? t("core-logic.keeping.yielding", { percent })
        : state === "waiting" ? t("core-logic.keeping.waiting", { percent })
        : t("core-logic.keeping.queued", { percent });
      const where = call === null ? {} : call.kind === "stationFilePart" ? { key: call.key } : { root: call.root, path: call.path };
      const name = call === null ? f.id : call.kind === "stationFilePart" ? call.name : (call.path.split("/").pop() ?? call.path);
      const from = this.#from.get(f.id);
      out.push({ id: f.id, station, ...where, name, title: call?.kind === "stationFilePart" ? titleOf(name) : name, size: f.size, loaded, progress: f.size > 0 ? loaded / f.size : 0, state, statusText, ...(f.wanted ? { wanted: true } : {}), ...(from !== undefined ? { from } : {}) });
    }
    // what comes now first
    return out.sort((a, b) => Number(b.state === "going" || b.state === "yielding") - Number(a.state === "going" || a.state === "yielding"));
  }

  /// The chat's file (its `station`, session `key`, `name`, `size` as its message says) to be loaded (加载): brought
  /// before everything else, at once, from what is kept of it; `from`: where it was asked (KeptFrom), listed with it.
  want(station: string, key: string, name: string, size: number, from: unknown): Effect.Effect<void> {
    const id = chatKeptId(station, key, name);
    const kept = this.#inner.driveKept;
    return Effect.gen({ self: this }, function* () {
      if (from !== undefined && from !== null) yield* kept.noteFrom(id, from);
      // all of it here already: nothing to bring
      if (yield* kept.whole(id, size)) return;
      yield* kept.want(id, "chat", size);
      this.#failed.delete(id);
      const wake = this.#wake;
      this.#wake = null;
      wake?.();
      this.poke();
    });
  }

  /// Not brought any more, what was kept of it kept (`fill.stop`); all of them (`fill.stopAll`).
  stop(ids: string[] | null): Effect.Effect<void> {
    const self = this;
    return Effect.gen(function* () {
      for (const id of ids ?? self.#list.map((f) => f.id)) {
        if (self.#going?.id === id) {
          self.#stopping.add(id);
          self.#stop?.();
        }
        yield* self.#inner.driveKept.unwant(id);
        self.#list = self.#list.filter((f) => f.id !== id);
      }
      self.#told.clear();
      self.#changed();
      self.poke();
    });
  }

  #changed(): void {
    this.#inner.store.invalidateAll((topic) => topic.topic === "downloads");
  }

  /// Told again as one moves on a whole percent, or what it is doing changes.
  #moved(id: string, loaded: number, size: number): void {
    if (this.#going?.id === id) this.#going.loaded = loaded;
    const percent = size > 0 ? Math.floor((loaded / size) * 100) : 0;
    if (this.#told.get(id) === percent) return;
    this.#told.set(id, percent);
    this.#changed();
  }

  #again(id: string): void {
    this.#later.add(id);
    this.#inner.runner.fork(Effect.andThen(Effect.sleep(AGAIN_MS), Effect.sync(() => {
      this.#later.delete(id);
      this.poke();
    })));
  }

  #reached(station: string): boolean {
    const stations = this.#inner.stations;
    return stations.link(station) !== undefined && stations.reachable(station);
  }

  #yield(yielding: boolean): void {
    if (this.#yielding === yielding) return;
    this.#yielding = yielding;
    this.#changed();
  }

  /// Once nothing has been waited on a while: the next part brought, or, none left, waited for a poke.
  #step(): Effect.Effect<void> {
    const inner = this.#inner;
    const self = this;
    return Effect.gen(function* () {
      // (one a person asked to load and can be had now: at once, not after what is waited on)
      const urgent = (yield* self.#look()).some((f) => f.wanted && self.#ready(f));
      if (!urgent) {
        if (inner.waited.count > 0 && self.#list.length > 0) self.#yield(true);
        yield* Effect.raceFirst(inner.waited.idle(IDLE_MS), Effect.callback<void>((resume) => {
          self.#wake = () => resume(Effect.void);
        }));
        self.#wake = null;
        self.#yield(false);
      }
      self.#dirty = false;
      const next = yield* self.#next();
      if (next === null) {
        if (self.#dirty) return;
        yield* Effect.callback<void>((resume) => {
          self.#poked = () => resume(Effect.void);
        });
        return;
      }
      const [f, call] = next;
      const id = f.id;
      const station = call.station;
      const read = handlers[call.kind]!;
      const span = inner.tracer.span("file.fill", Kind.Internal, null);
      span.set("stillfail.station", station);
      // (one begun as it waited its turn: nothing; one begun as it goes stops it, what came kept: `ended` false; so
      // does its being stopped here)
      let ended = false;
      let answer: unknown = null;
      self.#going = { id, loaded: f.have };
      self.#changed();
      const stopped = Effect.callback<void>((resume) => {
        self.#stop = () => resume(Effect.void);
      });
      const heard = (v: unknown) => {
        const loaded = isObject(v) && typeof v.loaded === "number" ? v.loaded : 0;
        self.#moved(id, f.have + loaded, f.size);
      };
      const reading = Effect.map(read(inner, call, heard, [0, 0], span.context), (got) => {
        [ended, answer] = [true, got];
      });
      // (one asked to load is what a person waits on itself: nothing else stops it but its being stopped)
      const part = Effect.suspend(() =>
        f.wanted ? Effect.raceFirst(reading, stopped)
        : inner.waited.count > 0 ? Effect.void
        : Effect.raceFirst(reading, Effect.raceFirst(inner.waited.begun(), stopped)),
      );
      const done = yield* Effect.result(inner.scheduler.ask(station, `${station} fill`, f.wanted ? Priority.asked : Priority.idle, part));
      span.end();
      self.#going = null;
      self.#stop = null;
      if (self.#stopping.delete(id)) return;
      if (done._tag === "Success") {
        // read through and still not kept (the station says it is another size than its message did): not again
        const said = (answer instanceof Beside ? answer.value : answer) as { total?: unknown } | null;
        if (ended && call.kind === "stationFilePart" && said?.total !== f.size) {
          self.#failed.add(id);
          if (f.wanted) yield* inner.driveKept.loaded(id);
        } else if (f.wanted && (yield* inner.driveKept.whole(id, f.size))) yield* inner.driveKept.loaded(id);
        return;
      }
      const e = done.failure;
      if (unreached(e) && inner.stations.online(station)) self.#again(id);
      else if (unreached(e)) self.#away.add(station);
      // gone from the station: what was kept of it is of no use
      else if (e.status === 404) yield* inner.driveKept.forget(id);
      else {
        self.#failed.add(id);
        if (f.wanted) yield* inner.driveKept.loaded(id);
      }
    });
  }

  /// What is left to bring looked at again: `#list`, told where it changed.
  #look(): Effect.Effect<Unfinished[]> {
    const inner = this.#inner;
    const read = Effect.flatMap(inner.driveKept.unfinished(["chat", "played"], inner.host.nowMs() - FILL_RECENT_MS), (files) =>
      Effect.map(inner.driveKept.fromOf(files.map((f) => f.id)), (from) => [files, from] as const));
    return Effect.map(read, ([files, from]) => {
      const fromChanged = [...from].some(([id, v]) => JSON.stringify(this.#from.get(id)) !== JSON.stringify(v));
      this.#from = from;
      if (fromChanged) this.#changed();
      const { on, most } = bounds(inner);
      // (only what was opened: a viewer said where; a still read off a film in its message, none)
      // (one asked to load whatever the prefs say; others only what was opened, within the prefs' bound)
      const list = files.filter((f) => (f.wanted || (on && from.has(f.id) && f.size <= most)) && !this.#failed.has(f.id) && !this.#stopping.has(f.id) && !inner.downloads.has(f.id) && partOf(f) !== null);
      // the one coming no longer to be (turned off, past the bound now): its part stops, what came of it kept
      if (this.#going !== null && !list.some((f) => f.id === this.#going?.id)) this.#stop?.();
      const was = this.#list;
      this.#list = list;
      if (was.length !== list.length || was.some((f, i) => f.id !== list[i].id || f.have !== list[i].have || f.wanted !== list[i].wanted)) this.#changed();
      return list;
    });
  }

  /// The file to bring a part of next, and the call that reads it: the most lately read whose station is reached.
  #next(): Effect.Effect<[Unfinished, Extract<Call, { kind: "stationFilePart" | "driveRead" }>] | null> {
    return Effect.map(this.#look(), (list) => {
      for (const f of list) {
        const call = partOf(f);
        if (call === null || !this.#ready(f)) continue;
        return [f, call];
      }
      return null;
    });
  }

  /// Whether a part of it can be asked now: its station reached, it not waiting to be asked again.
  #ready(f: Unfinished): boolean {
    const call = partOf(f);
    return call !== null && !this.#away.has(call.station) && this.#reached(call.station) && !this.#later.has(f.id);
  }
}

export function install(inner: Inner): void {
  inner.fill = new Fill(inner);
  handlers.fill = (core, call) => {
    const c = call as Extract<Call, { kind: "fill" }>;
    if (c.action === "want") {
      const p = c.params;
      const size = p.size;
      for (const field of ["station", "key", "name"] as const) {
        if (typeof p[field] !== "string" || p[field] === "") return Effect.fail(CoreError.invalid(t("core-misc.params.missing", { field })));
      }
      if (typeof size !== "number" || !Number.isSafeInteger(size) || size <= 0) return Effect.fail(CoreError.invalid(t("core-misc.params.missing", { field: "size" })));
      // (where it was asked, KeptFrom, leading back there from the list; one not of that shape left out)
      const shaped = isObject(p.from) ? conform("KeptFrom", p.from) : null;
      return Effect.as(core.fill.want(p.station as string, p.key as string, p.name as string, size, shaped !== null && "ok" in shaped ? shaped.ok : undefined), {});
    }
    const id = c.params.id;
    if (c.action === "stop" && (typeof id !== "string" || id === "")) return Effect.fail(CoreError.invalid(t("core-misc.params.missing", { field: "id" })));
    return Effect.as(core.fill.stop(c.action === "stop" ? [id as string] : null), {});
  };
}
