// What was opened and let go is brought whole all the same, after everything else (docs/core-ts.md, rule 6): a chat's
// file or a drive's video or song a viewer read a part of (drive-kept.ts `chat`, `played`) and let go of (a preview
// closed, a player gone elsewhere) goes on coming, a part at a time, kept as any read of it is, so that opened again it
// is here. It goes only while no request is waited on (status.ts Waited) and none has been for IDLE_MS, at the
// scheduler's lowest priority; one begun meanwhile stops the part (what came of it is kept) and it goes on after, so
// what a person opens has the link to itself. What is kept is the one record of what is left: nothing else is written
// down, and it goes on as the core starts again. Its station not reached, it waits for it; the file no longer there,
// what was kept of it goes. Not one past FILL_MAX, nor one whose rest its kind has no room for (it would push out what
// else is kept, then itself), nor one a download fetches.
import { Effect } from "effect";
import type { Inner } from "./core.ts";
import { handlers } from "./core/execute.ts";
import type { Call } from "./core/calls.ts";
import type { CoreError } from "./error.ts";
import { Beside } from "./protocol.ts";
import { Kind } from "./trace.ts";
import { Priority } from "./sync/scheduler.ts";
import { DOWNLOAD_PART } from "./views/downloads.ts";

/// The most a file is brought whole by itself.
export const FILL_MAX = 1024 * 1024 * 1024;
/// How long nothing must have been waited on before it goes (a player's next part is asked within this).
export const IDLE_MS = 3_000;

/// Not reached (the station, the mesh, a time out): tried again once it is.
const unreached = (e: CoreError) => e.status === undefined && (e.code === "host" || e.code === "mesh" || e.code === "timeout");

/// A kept file's part to bring: the call that reads it (with `keep`, `quiet`) and its station.
function partOf(f: { id: string; mtime: number; size: number; at: number; length: number }): Call | null {
  const length = Math.min(DOWNLOAD_PART, f.length);
  const [first, ...rest] = f.id.split("\n");
  // a chat's (chatKeptId): `chat`, its station, its session, its name
  if (first === "chat") {
    const [station, key, ...name] = rest;
    if (station === undefined || key === undefined || name.length === 0) return null;
    return { kind: "stationFilePart", station, key, name: name.join("\n"), offset: f.at, length, progress: false, stream: false, keep: f.size, quiet: true };
  }
  // a drive's (keptId): its station, its root, its path
  const [root, ...path] = rest;
  if (root === undefined || path.length === 0) return null;
  return { kind: "driveRead", station: first, root, path: path.join("\n"), offset: f.at, length, progress: false, stream: false, keep: "played", mtime: f.mtime, size: f.size, quiet: true };
}

export class Fill {
  readonly #inner: Inner;
  /// Stations not reached as a part was asked of them: none of theirs until they are (`stationBack`).
  readonly #away = new Set<string>();
  /// Files the station could not give for another reason: not again in this run.
  readonly #failed = new Set<string>();
  /// Waiting for a poke: what goes on.
  #poked: (() => void) | null = null;
  /// Poked since the files were last looked at.
  #dirty = false;
  #started = false;

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  /// On from now, in the core's own scope.
  start(): void {
    if (this.#started) return;
    this.#started = true;
    this.#inner.runner.fork(Effect.forever(this.#step()));
  }

  /// Something may have been let go (a viewer's read ended): looked at again.
  poke(): void {
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

  /// Once nothing has been waited on a while: the next part brought, or, none left, waited for a poke.
  #step(): Effect.Effect<void> {
    const inner = this.#inner;
    const self = this;
    return Effect.gen(function* () {
      yield* inner.waited.idle(IDLE_MS);
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
      // (one begun as it waited its turn: nothing; one begun as it goes stops it, what came kept: `ended` false)
      let ended = false;
      let answer: unknown = null;
      const part = Effect.suspend(() =>
        inner.waited.count > 0
          ? Effect.void
          : Effect.raceFirst(
              Effect.map(read(inner, call, () => {}, [0, 0], span.context), (got) => {
                [ended, answer] = [true, got];
              }),
              inner.waited.begun(),
            ),
      );
      const done = yield* Effect.result(inner.scheduler.ask(station, `${station} fill`, Priority.idle, part));
      span.end();
      if (done._tag === "Success") {
        // read through and still not kept (the station says it is another size than its message did): not again
        const said = (answer instanceof Beside ? answer.value : answer) as { total?: unknown } | null;
        if (ended && call.kind === "stationFilePart" && said?.total !== f.size) self.#failed.add(id);
        return;
      }
      const e = done.failure;
      if (unreached(e)) self.#away.add(station);
      // gone from the station: what was kept of it is of no use
      else if (e.status === 404) yield* inner.driveKept.forget(id);
      else self.#failed.add(id);
    });
  }

  /// The file to bring a part of next, and the call that reads it: the most lately read whose station is reached.
  #next(): Effect.Effect<[{ id: string; size: number }, Extract<Call, { kind: "stationFilePart" | "driveRead" }>] | null> {
    const inner = this.#inner;
    return Effect.map(inner.driveKept.unfinished(["chat", "played"]), (files) => {
      for (const f of files) {
        if (f.size > FILL_MAX || this.#failed.has(f.id) || inner.downloads.has(f.id)) continue;
        const call = partOf(f);
        if (call === null || (call.kind !== "stationFilePart" && call.kind !== "driveRead")) continue;
        if (this.#away.has(call.station) || inner.stations.link(call.station) === undefined || !inner.stations.reachable(call.station)) continue;
        return [f, call];
      }
      return null;
    });
  }
}

export function install(inner: Inner): void {
  inner.fill = new Fill(inner);
}
