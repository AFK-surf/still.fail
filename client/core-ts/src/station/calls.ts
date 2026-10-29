// The station calls (core/execute.rs, the station's part): operations, a chat's pages and place, what is read,
// files, uploads and previews.
import { Deferred, Effect, Scope } from "effect";
import type { Inner, Progress } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { base64, fromBase64 } from "../util.ts";
import { Beside } from "../protocol.ts";
import { chatKeptId, keptId, sentKeptId } from "../drive-kept.ts";
import { folderOf } from "../ops.ts";
import * as looks from "../looks.ts";
import { machineMeta } from "../views/models.ts";
import { chatTitle } from "../views/views.ts";
import { StationAddr } from "./addr.ts";
import { readAll, replyHeader, takeFrames, encodeFrame, type Frame } from "./wire.ts";
import type { SpanContext } from "../trace.ts";
import { DOWNLOAD_PART } from "../views/downloads.ts";
import * as logins from "./machine-logins.ts";

const parse = (station: string) => Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError });

/// A part read's answer: its bytes beside `said`, or none when they went as they came (`stream`).
function partAnswer(c: { stream: boolean }, said: Record<string, unknown>, bytes: Uint8Array): unknown {
  return c.stream ? said : new Beside(said, bytes);
}

/// What is kept small on the device (base64 there), its bytes beside `{ type, held }`: `held`, the device had it (what
/// shows it shows it as it is, as it would what was there already, not as what was waited for from the station).
function keptBeside(kept: { type: string; bytes: string }): Beside {
  return new Beside({ type: kept.type, held: true }, fromBase64(kept.bytes) ?? new Uint8Array());
}

/// A whole file being read from its station, and those waiting for it: each told how far it has come.
type Going = { done: Deferred.Deferred<Beside, CoreError>; heard: Set<Progress>; last: unknown };
const goingOf = new WeakMap<Inner, Map<string, Going>>();

/// `read` once for every asker of the same file at once: one asked again while it is coming (its preview closed and
/// opened again, its image put up anew) waits for the read going, told how far it has come, not brought again beside
/// it. A whole file's read runs to its end whoever waits; each asked anew began another, and on a desktop app six images
/// were coming fifteen times at once, each at a fifteenth of the line, until the app was restarted (ccvm, 2026-10-28).
function once(inner: Inner, key: string, progress: Progress, read: (progress: Progress) => Effect.Effect<Beside, CoreError>): Effect.Effect<Beside, CoreError> {
  return Effect.suspend(() => {
    let all = goingOf.get(inner);
    if (all === undefined) goingOf.set(inner, (all = new Map()));
    const going = all;
    let g = going.get(key);
    if (g === undefined) {
      const made: Going = { done: Deferred.makeUnsafe<Beside, CoreError>(), heard: new Set([progress]), last: undefined };
      g = made;
      going.set(key, made);
      const tell: Progress = (value) => {
        made.last = value;
        for (const heard of made.heard) heard(value);
      };
      inner.runner.fork(
        Effect.flatMap(Effect.exit(read(tell)), (exit) =>
          Effect.sync(() => {
            if (going.get(key) === made) going.delete(key);
            Deferred.doneUnsafe(made.done, exit);
          }),
        ),
      );
    } else {
      g.heard.add(progress);
      if (g.last !== undefined) progress(g.last);
    }
    const it = g;
    return Effect.ensuring(Deferred.await(it.done), Effect.sync(() => it.heard.delete(progress)));
  });
}

/// Pieces one after another.
function joined(pieces: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(pieces.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of pieces) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

/// What a part read says as it comes: with `stream`, each piece of its bytes beside `{ loaded }`; else with `progress`,
/// `{ loaded }` alone now and then.
function partProgress(c: { progress: boolean; stream: boolean }, progress: Progress): [((loaded: number) => void) | undefined, ((piece: Uint8Array) => void) | undefined] {
  if (c.stream) {
    let loaded = 0;
    return [undefined, (piece) => progress({ loaded: (loaded += piece.length) }, piece)];
  }
  return [c.progress ? (loaded) => progress({ loaded }) : undefined, undefined];
}

/// A part read with `keep` (`c`: from its offset, its length, of a file `size` long), first from what is kept of it
/// from that offset on (`kept`, as DriveKept.from has it: all of it, the first of it, or null), then the rest from the
/// station, asked from where what is kept stops (`read(at, length, before, take, said)`: `before` bytes of the part
/// had already, its bytes to `take` as they come, what the station says it is to `said` as its answer begins). What is
/// kept goes on first, as the station's bytes would (to `sink`, else counted to `heard`). What comes from the station
/// is kept (`keep(head, at, bytes)`, where the station's head says it is the file it was) as the read ends, and as it
/// stops short (an error, or let go of: a player gone elsewhere, a view closed): what came is not read again. The
/// station saying the file is another than the one kept (`same` not so: changed there since its folder was read), what
/// was kept is not put before what it brings: the part read again whole from the station, or (its first bytes gone to
/// `sink` already) not had. The part whole (none with `sink`), what it is, and the station's answer (null: all of it
/// was kept).
export function keptFirst<H extends { type: string; total: number }, G extends H>(
  inner: Inner,
  c: { offset: number; length: number; quiet?: boolean },
  size: number,
  kept: { type: string; bytes: Uint8Array } | null,
  heard: ((loaded: number) => void) | undefined,
  sink: ((piece: Uint8Array) => void) | undefined,
  read: (at: number, length: number, before: number, take: (piece: Uint8Array) => void, said: (head: H) => void) => Effect.Effect<G, CoreError>,
  keep: (head: H, at: number, bytes: Uint8Array) => Effect.Effect<void>,
  same: (head: H) => boolean,
): Effect.Effect<{ type: string; bytes: Uint8Array; got: G | null }, CoreError> {
  const have = kept?.bytes ?? new Uint8Array(0);
  if (have.length > 0) {
    if (sink) sink(have);
    else heard?.(have.length);
  }
  const want = Math.max(0, Math.min(c.offset + c.length, size) - c.offset);
  if (kept !== null && have.length >= want) return Effect.succeed({ type: kept.type, bytes: sink ? new Uint8Array(0) : have, got: null });
  const at = c.offset + have.length;
  const pieces: Uint8Array[] = [];
  let head: H | null = null;
  return read(at, c.offset + c.length - at, have.length, (piece) => {
    pieces.push(piece);
    sink?.(piece);
  }, (h) => {
    head = h;
  }).pipe(
    Effect.onExit((exit) =>
      Effect.suspend(() => {
        const came = joined(pieces);
        const said: H | null = exit._tag === "Success" ? exit.value : head;
        if (said === null || came.length === 0) return Effect.void;
        // (the core's own read, `quiet`, has it kept before it ends: what it looks at next is past it)
        if (c.quiet === true) return keep(said, at, came);
        inner.runner.fork(keep(said, at, came));
        return Effect.void;
      }),
    ),
    Effect.flatMap((got) => {
      if (have.length === 0 || same(got)) return Effect.succeed({ type: got.type, bytes: sink ? new Uint8Array(0) : joined([have, joined(pieces)]), got });
      if (sink) return Effect.fail(new CoreError("changed", t("station.core.fileUnreadable")));
      const whole: Uint8Array[] = [];
      return Effect.map(
        read(c.offset, c.length, 0, (piece) => whole.push(piece), () => {}),
        (again) => ({ type: again.type, bytes: joined(whole), got: again }),
      );
    }),
  );
}

/// Preview sockets open, by client and the name its UI gave each: where `preview.socket.send` puts the page's messages.
const sockets = new Map<string, (frame: Frame) => void>();

export function install(): void {
  handlers.op = (inner, call, _progress, _at, ctx) => {
    const c = call as Extract<Call, { kind: "op" }>;
    const op = c.op;
    return Effect.andThen(
      parse((op.target as { station: string }).station),
      Effect.map(inner.stations.perform(op, ctx), (answer) => {
        // The machine's own sessions, each in a line (choose.rs `machine_meta`).
        if (op.method === "GET" && op.path.startsWith("/machine-sessions") && answer !== null && typeof answer === "object") {
          const now = inner.host.nowMs();
          const a = answer as { sessions?: unknown; session?: unknown };
          if (Array.isArray(a.sessions)) a.sessions = a.sessions.map((s) => machineMeta(s, now));
          if (a.session !== undefined) a.session = machineMeta(a.session, now);
        }
        // What the clients show of it, put in here.
        looks.answer(op.method, op.path, answer);
        return answer;
      }),
    );
  };
  // What a visualization's widget kept: kept on the device too (as a thumbnail is: AccountDb.keptFile), so its page
  // is drawn with it at once; what its station says after kept for the next time, unless it was kept here meanwhile.
  handlers.widgetState = (inner, call, progress, at, ctx) => {
    const c = call as Extract<Call, { kind: "widgetState" }>;
    const station = (c.op.target as { station: string }).station;
    const kept = () => inner.data.keptFile(station, c.key, c.path, "widget")?.bytes ?? null;
    const keep = (state: unknown) => inner.data.keepFile(station, c.key, c.path, "widget", "application/json", JSON.stringify(state ?? null));
    const ask = handlers.op!(inner, { kind: "op", op: c.op }, progress, at, ctx);
    if (c.state !== undefined) {
      keep(c.state);
      return ask;
    }
    const was = kept();
    const read = Effect.tap(ask, (answer) =>
      Effect.sync(() => {
        if (kept() === was) keep((answer as { state?: unknown } | null)?.state);
      }),
    );
    if (was === null) return read;
    inner.runner.fork(Effect.ignore(read, { log: "Unhandled", message: "station read" }));
    return Effect.succeed({ state: JSON.parse(was) as unknown });
  };
  handlers.chatOlder = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatOlder" }>;
    return Effect.andThen(parse(c.station), Effect.map(inner.stationTopics.older(c.station, c.thread), (more) => ({ more })));
  };
  handlers.chatNewer = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatNewer" }>;
    return Effect.andThen(parse(c.station), Effect.map(inner.stationTopics.newer(c.station, c.thread), (more) => ({ more })));
  };
  handlers.chatLatest = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatLatest" }>;
    return Effect.andThen(parse(c.station), Effect.as(inner.stationTopics.latest(c.station, c.thread), null));
  };
  handlers.chatPlace = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatPlace" }>;
    inner.stationTopics.place(c.station, c.thread, c.seq, c.offset);
    return Effect.succeed(null);
  };
  handlers.chatAround = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatAround" }>;
    return Effect.andThen(parse(c.station), Effect.as(inner.stationTopics.around(c.station, c.thread, c.seq), null));
  };
  handlers.chatFind = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatFind" }>;
    return Effect.andThen(parse(c.station), inner.stationTopics.find(c.station, c.thread, c.query, c.bring));
  };
  handlers.historyOlder = (inner, call) => {
    const c = call as Extract<Call, { kind: "historyOlder" }>;
    return Effect.andThen(parse(c.station), Effect.map(inner.stationTopics.historyOlder(c.station, c.key), (more) => ({ more })));
  };
  handlers.historyDetail = (inner, call) => {
    const c = call as Extract<Call, { kind: "historyDetail" }>;
    return Effect.andThen(parse(c.station), Effect.as(inner.stationTopics.historyDetail(c.station, c.key, c.from, c.to), null));
  };
  handlers.chatRead = (inner, call, _p, _a, ctx) => {
    const c = call as Extract<Call, { kind: "chatRead" }>;
    return Effect.andThen(parse(c.station), Effect.as(inner.stations.read(c.station, c.thread, c.seq, ctx), null));
  };
  handlers.stationMeasure = (inner, call) => {
    const c = call as Extract<Call, { kind: "stationMeasure" }>;
    return Effect.flatMap(parse(c.station), (addr) => Effect.as(inner.stations.wire.measure ? inner.stations.wire.measure(addr) : Effect.fail(new CoreError("unsupported", t("station.core.oneWay"))), null));
  };
  handlers.stationUpload = (inner, call, _p, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationUpload" }>;
    return inner.stations.upload(c.station, c.name, c.bytes, ctx);
  };
  // `progress`: the bytes of the part gone so far, as they go (a part is megabytes: its end alone is too seldom to show).
  handlers.stationUploadPart = (inner, call, progress, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationUploadPart" }>;
    return Effect.flatMap(parse(c.station), (addr) => inner.stations.requests.uploadPart(addr, c, c.bytes, ctx, c.progress ? (sent) => progress({ sent }) : undefined));
  };
  handlers.stationFile = (inner, call, asked, at_, ctx) => {
    const c = call as Extract<Call, { kind: "stationFile" }>;
    // A thumbnail is kept on the device: a file sent never changes (AccountDb.keptFile).
    // Its bytes beside its answer `{ type }` (kept as base64, small).
    const kept = c.thumb ? inner.data.keptFile(c.station, c.key, c.name, "thumb") : null;
    if (kept !== null) return Effect.succeed(keptBeside(kept));
    // (each told how far it has come only if it asked so)
    const heard: Progress = (v, b) => {
      if (c.progress) asked(v, b);
    };
    return once(inner, JSON.stringify([c.station, c.key, c.name, c.thumb, c.keep]), heard, (progress) => {
      const read = Effect.flatMap(parse(c.station), (addr) =>
        Effect.map(
          inner.stations.requests.file(addr, c.key, c.name, c.thumb, (loaded, total) => progress({ loaded, total }), ctx),
          ([type, bytes]) => {
            if (c.thumb) inner.data.keepFile(c.station, c.key, c.name, "thumb", type, base64(bytes));
            return [type, bytes] as const;
          },
        ),
      );
      const station = () => {
        if (c.keep === null) return Effect.map(read, ([type, bytes]) => new Beside({ type }, bytes));
        // With `keep`: what is kept of it answered whole without asking the station; else read a part at a time as its
        // parts are (`station.file.part` with `keep`), each kept with its chat as it comes (drive-kept.ts `chat`), one
        // stopped short too: let go of (a preview closed), what came is not read again, and the rest is brought all the
        // same (fill.ts). A station from before parts, or one saying it is another size than its message did: read whole,
        // kept once answered at that size.
        const [size, id] = [c.keep, chatKeptId(c.station, c.key, c.name)];
        const whole = Effect.map(read, ([type, bytes]) => {
          if (bytes.length === size) inner.runner.fork(inner.driveKept.keep(id, "chat", 0, size, type, 0, bytes));
          return new Beside({ type }, bytes);
        });
        return Effect.gen(function* () {
          const held = yield* inner.driveKept.read(id, 0, size, 0, size);
          if (held !== null) {
            progress({ loaded: size, total: size });
            return new Beside({ type: held.type }, held.bytes);
          }
          const pieces: Uint8Array[] = [];
          let type = "";
          for (let at = 0; at < size;) {
            const from = at;
            const part: Extract<Call, { kind: "stationFilePart" }> = { kind: "stationFilePart", station: c.station, key: c.key, name: c.name, offset: at, length: Math.min(DOWNLOAD_PART, size - at), progress: true, stream: false, keep: size, ...(c.from !== undefined ? { from: c.from } : {}) };
            const got = yield* Effect.result(handlers.stationFilePart!(inner, part, (v) => progress({ loaded: from + ((v as { loaded: number }).loaded ?? 0), total: size }), at_, ctx));
            if (got._tag === "Failure") {
              if (at === 0 && got.failure.code === "unsupported") return yield* whole;
              return yield* Effect.fail(got.failure);
            }
            const said = got.success as Beside;
            const head = said.value as { type: string; total: number };
            if (head.total !== size) return yield* whole;
            if (said.bytes.length === 0) return yield* Effect.fail(new CoreError("io", t("station.core.fileUnreadable")));
            type = head.type;
            pieces.push(said.bytes);
            at += said.bytes.length;
            progress({ loaded: at, total: size });
          }
          return new Beside({ type }, joined(pieces));
        });
      };
      // One sent up from here is answered as it went, for its thumbnail too (drive-kept.ts `sent`): not read back from the
      // station it went to.
      return Effect.flatMap(inner.driveKept.held(sentKeptId(c.station, c.name)), (sent) => {
        if (sent === null) return station();
        progress({ loaded: sent.size, total: sent.size });
        return Effect.succeed(new Beside({ type: sent.type }, sent.bytes));
      });
    });
  };
  // `progress`: the bytes of the part so far, as they come (a part is megabytes: its end alone is too seldom to show).
  // Its bytes beside its answer `{ type, total }`; with `stream`, beside values `{ loaded }` as they come instead (what
  // takes them writes each where it goes, and nothing waits for the whole part).
  // With `keep`: as `drive.read`'s, a chat's file kept by its size alone (a file sent never changes).
  // With `keep`, one a viewer opened (`from`: where) and let go of before all of it was kept is brought all the same
  // (fill.ts), unless `quiet` (that bringing itself).
  handlers.stationFilePart = (inner, call, progress, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationFilePart" }>;
    // (where it was opened, written down beside what is kept of it)
    if (c.keep !== null && c.from !== undefined) inner.runner.fork(inner.driveKept.noteFrom(chatKeptId(c.station, c.key, c.name), c.from));
    return c.keep !== null && c.quiet !== true ? Effect.ensuring(chatPart(inner, c, progress, ctx), Effect.sync(() => inner.fill.poke())) : chatPart(inner, c, progress, ctx);
  };
  const chatPart = (inner: Inner, c: Extract<Call, { kind: "stationFilePart" }>, progress: Progress, ctx: SpanContext) => {
    const quiet = c.quiet === true;
    const [heard, sink] = partProgress(c, progress);
    // What is kept here of it, answered as the station would.
    const here = (got: { type: string; bytes: Uint8Array }, total: number) => {
      if (sink) sink(got.bytes);
      else heard?.(got.bytes.length);
      return partAnswer(c, { type: got.type, total }, got.bytes);
    };
    const station = () => {
      if (c.keep === null) {
        return Effect.map(
          Effect.flatMap(parse(c.station), (addr) => inner.stations.requests.filePart(addr, c.key, c.name, c.offset, c.length, ctx, heard, sink, undefined, quiet)),
          (got) => partAnswer(c, { type: got.type, total: got.total }, got.bytes),
        );
      }
      // With `keep`: what is kept of it from its offset, the rest from the station (keptFirst), kept as it comes.
      const [size, id] = [c.keep, chatKeptId(c.station, c.key, c.name)];
      return Effect.gen(function* () {
        const kept = yield* inner.driveKept.from(id, 0, size, c.offset, c.length);
        const part = yield* keptFirst<{ type: string; total: number }, { type: string; total: number; bytes: Uint8Array }>(
          inner,
          c,
          size,
          kept,
          heard,
          sink,
          (at, length, before, take, said) =>
            Effect.flatMap(parse(c.station), (addr) =>
              inner.stations.requests.filePart(addr, c.key, c.name, at, length, ctx, heard && ((loaded) => heard(before + loaded)), take, said, quiet),
            ),
          (head, at, bytes) => (head.total === size ? inner.driveKept.keep(id, "chat", 0, size, head.type, at, bytes) : Effect.void),
          (head) => head.total === size,
        );
        return partAnswer(c, { type: part.type, total: part.got?.total ?? size }, part.bytes);
      });
    };
    // One sent up from here: as `station.file`'s.
    return Effect.flatMap(inner.driveKept.held(sentKeptId(c.station, c.name), c.offset, c.length), (sent) => (sent === null ? station() : Effect.succeed(here(sent, sent.size))));
  };
  handlers.stationPoster = (inner, call, _p, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationPoster" }>;
    // Kept on the device as a thumbnail is.
    const kept = inner.data.keptFile(c.station, c.key, c.name, "poster");
    if (kept !== null) return Effect.succeed(keptBeside(kept));
    return Effect.flatMap(parse(c.station), (addr) =>
      Effect.map(inner.stations.requests.poster(addr, c.key, c.name, ctx), (bytes) => {
        if (bytes === null) return null;
        inner.data.keepFile(c.station, c.key, c.name, "poster", "image/jpeg", base64(bytes));
        return new Beside({ type: "image/jpeg" }, bytes);
      }),
    );
  };
  handlers.fileOpen = (inner, call, _p, _a, ctx) => {
    const c = call as Extract<Call, { kind: "fileOpen" }>;
    return Effect.flatMap(parse(c.station), (addr) =>
      Effect.map(inner.stations.requests.fileOpen(addr, c.key, c.path, c.range, ctx), (got) => new Beside({ name: got.name, path: got.path, type: got.type, size: got.size }, got.bytes)),
    );
  };
  // With `keep`: what is kept of the file as its folder said it is answered as the station would (a stream's bytes in
  // one piece), not asked of it again, and only what is not kept from the part's offset on asked of the station; what
  // comes is kept as it comes, a read stopped short too (keptFirst). Read as other than that (changed on the station
  // since its folder was read), what was kept of it goes and nothing is kept.
  // A video's or song's (`played`) let go of before all of it was kept is brought all the same, as a chat's file is.
  handlers.driveRead = (inner, call, progress, _a, ctx) => {
    const c = call as Extract<Call, { kind: "driveRead" }>;
    if (c.keep === "played" && c.from !== undefined) inner.runner.fork(inner.driveKept.noteFrom(keptId(c.station, c.root, c.path), c.from));
    return c.keep === "played" && c.quiet !== true ? Effect.ensuring(drivePart(inner, c, progress, ctx), Effect.sync(() => inner.fill.poke())) : drivePart(inner, c, progress, ctx);
  };
  const drivePart = (inner: Inner, c: Extract<Call, { kind: "driveRead" }>, progress: Progress, ctx: SpanContext) => {
    const quiet = c.quiet === true;
    const [heard, sink] = partProgress(c, progress);
    const id = keptId(c.station, c.root, c.path);
    if (c.keep === null || c.mtime === null || c.size === null) {
      return Effect.map(
        Effect.flatMap(parse(c.station), (addr) => inner.stations.requests.driveRead(addr, c.root, c.path, c.offset, c.length, ctx, heard, sink, undefined, quiet)),
        (got) => partAnswer(c, { type: got.type, total: got.total, mtime: got.mtime }, got.bytes),
      );
    }
    const [keep, mtime, size] = [c.keep, c.mtime, c.size];
    return Effect.gen(function* () {
      const kept = yield* inner.driveKept.from(id, mtime, size, c.offset, c.length);
      const part = yield* keptFirst<{ type: string; total: number; mtime: number | null }, { type: string; total: number; mtime: number | null; bytes: Uint8Array }>(
        inner,
        c,
        size,
        kept,
        heard,
        sink,
        (at, length, before, take, said) =>
          Effect.flatMap(parse(c.station), (addr) =>
            inner.stations.requests.driveRead(addr, c.root, c.path, at, length, ctx, heard && ((loaded) => heard(before + loaded)), take, said, quiet),
          ),
        // (kept as the folder said it is; the station's says it changed: what was kept of it goes)
        (head, at, bytes) => (head.total === size && head.mtime === mtime ? inner.driveKept.keep(id, keep, mtime, size, head.type, at, bytes) : inner.driveKept.forget(id)),
        (head) => head.total === size && head.mtime === mtime,
      );
      return partAnswer(c, { type: part.type, total: part.got?.total ?? size, mtime: part.got === null ? mtime : part.got.mtime }, part.bytes);
    });
  };
  handlers.driveKeptClear = (inner) => Effect.as(inner.driveKept.clear(), null);
  handlers.cacheFileClear = (inner, call) => {
    const c = call as Extract<Call, { kind: "cacheFileClear" }>;
    return Effect.as(inner.driveKept.forget(chatKeptId(c.station, c.key, c.name)), null);
  };
  handlers.driveUploadPart = (inner, call, _p, _a, ctx) => {
    const c = call as Extract<Call, { kind: "driveUploadPart" }>;
    return Effect.flatMap(parse(c.station), (addr) =>
      Effect.tap(inner.stations.requests.driveUploadPart(addr, c, c.bytes, ctx), (got) =>
        // Whole: the folder it went into, as it is now, before the call answers.
        got.entry !== null ? inner.stations.afterWrite(c.station, { kind: "drive", root: c.root, paths: [folderOf(c.path)] }, got) : Effect.void,
      ),
    );
  };
  handlers.driveRefresh = (inner, call) => {
    const c = call as Extract<Call, { kind: "driveRefresh" }>;
    return Effect.andThen(parse(c.station), Effect.as(inner.stations.driveRefresh(c.station, c.root, c.path), null));
  };
  // A login's page to open (docs/remote-login.md): its device code's page, the page to open, or a loopback login's,
  // whose callback this device listens for first (on a host that can: the desktop app), unless the station is this
  // machine. Answers what to open; fails (the port taken here) before anything is.
  handlers.machineLoginOpen = (inner, call) => {
    const c = call as Extract<Call, { kind: "machineLoginOpen" }>;
    return Effect.gen(function* () {
      yield* parse(c.station);
      const login = logins.held(inner.stations.link(c.station)).logins.find((l) => l.id === c.id);
      if (login === undefined) return yield* Effect.fail(new CoreError("http_404", t("core-logic.machineLogin.gone"), 404));
      const page = (v: unknown) => (typeof v === "string" && v.startsWith("https://") ? v : null);
      const url = page(login.codeUrl) ?? page(login.url);
      if (url === null) return yield* Effect.fail(CoreError.invalid(t("core-logic.machineLogin.noPage")));
      const expect = logins.expectOf(login);
      if (login.step === "loopback" && expect !== null && !c.here && typeof login.endedAt !== "number") yield* inner.stations.relays.start(c.station, c.id, expect);
      return { url };
    });
  };
  handlers.drivePlace = (inner, call) => {
    const c = call as Extract<Call, { kind: "drivePlace" }>;
    return Effect.sync(() => {
      // Whole ms (DrivePlace.changed is an integer): a host's clock can have a fraction (Android's does).
      inner.data.set({ topic: "drivePlace", station: c.station, root: c.root, path: c.path }, { at: c.at, of: c.of, changed: Math.floor(inner.host.nowMs()) }, false);
      return null;
    });
  };
  // Each chat, called as the chats' list calls it, with the files of its sessions kept (`files`, the most lately read
  // first), the one keeping most first; those of no chat known apart (`loose`: its sessions' chats let go, or never
  // held here).
  handlers.cacheUsage = (inner) =>
    Effect.gen(function* () {
      const drive = yield* inner.driveKept.usage();
      const kept = yield* inner.driveKept.chatFiles();
      const chats = inner.data.cacheUsage().map(({ view, ...chat }) => ({ ...chat, title: view === null ? null : chatTitle(view), files: [] as { bytes: number }[] }));
      const loose: unknown[] = [];
      for (const f of kept) {
        const shown = { key: f.key, name: f.name, size: f.size, bytes: f.bytes, opened: f.used };
        const chat = chats.find((x) => x.station === f.station && x.sessions.includes(f.key));
        if (chat !== undefined) chat.files.push(shown);
        else loose.push({ station: f.station, ...shown });
      }
      const all = (x: (typeof chats)[number]) => x.files.reduce((n, f) => n + f.bytes, x.bytes);
      chats.sort((a, b) => all(b) - all(a));
      return { chats, drive, loose };
    });
  // A chat's files kept go with what is kept of its messages.
  handlers.cacheClear = (inner, call) => {
    const c = call as Extract<Call, { kind: "cacheClear" }>;
    return Effect.gen(function* () {
      const sessions = inner.data.cacheUsage().find((x) => x.station === c.station && x.thread === c.thread)?.sessions ?? [];
      inner.data.forgetChat(c.station, c.thread);
      yield* inner.driveKept.forgetChat(c.station, sessions);
      return null;
    });
  };
  handlers.stationPreview = (inner, call, progress, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationPreview" }>;
    return Effect.flatMap(parse(c.station), (addr) => {
      if (!c.stream) return Effect.map(inner.stations.requests.preview(addr, c.port, c.method, c.path, c.headers, c.body, ctx), (r) => new Beside({ status: r.status, headers: r.headers }, r.body));
      // As it comes: its head, then each piece of its body (`{ chunk: true }`, the piece beside it); null at its end.
      // Cancelling the call stops it.
      return Effect.scoped(
        Effect.gen(function* () {
          const reply = yield* inner.stations.requests.previewStream(addr, c.port, c.method, c.path, c.headers, c.body, ctx);
          progress({ head: { status: reply.status, headers: reply.headers } });
          for (;;) {
            const chunk = yield* Effect.mapError(reply.body.take, asCoreError);
            if (chunk === null) return null;
            progress({ chunk: true }, chunk);
          }
        }),
      );
    });
  };
  handlers.previewSocket = (inner, call, progress, at, ctx) => {
    const c = call as Extract<Call, { kind: "previewSocket" }>;
    const name = `${at[0]}\u0000${c.socket}`;
    if (sockets.has(name)) return Effect.fail(CoreError.invalid(t("core-misc.call.socket_open")));
    return Effect.scoped(
      Effect.gen(function* () {
        // Named before it opens: what the page sends meanwhile waits, and goes once it is open.
        const held: Frame[] = [];
        let send: ((frame: Frame) => void) | null = null;
        let closing: [number, string] | null = null;
        // The page's close before it opened: the open is let go (an older station takes the socket for a request and
        // never answers).
        const closedFirst = Deferred.makeUnsafe<[number, string]>();
        sockets.set(name, (frame) => {
          if (send) return send(frame);
          if ("close" in frame) Deferred.doneUnsafe(closedFirst, Effect.succeed(frame.close));
          else held.push(frame);
        });
        yield* Effect.addFinalizer(() => Effect.sync(() => sockets.delete(name)));
        const addr = yield* parse(c.station);
        const opened = yield* Effect.raceFirst(
          Effect.map(inner.stations.requests.previewSocket(addr, c.port, c.path, c.headers, ctx), (socket) => ({ socket }) as const),
          Effect.map(Deferred.await(closedFirst), (close) => ({ close }) as const),
        );
        if ("close" in opened) return { code: opened.close[0], reason: opened.close[1] };
        const socket = opened.socket;
        progress({ open: { protocol: replyHeader(socket.reply, "sec-websocket-protocol") ?? "" } });
        const out = socket.send;
        send = (frame) => {
          if ("close" in frame) closing = frame.close;
          inner.runner.fork(Effect.ignore(out.write(encodeFrame(frame)), { log: "Unhandled", message: "frame sent" }));
        };
        for (const f of held.splice(0)) send(f);
        let buf: Uint8Array = new Uint8Array();
        for (;;) {
          const chunk = yield* Effect.result(Effect.mapError(socket.reply.body.take, asCoreError));
          if (chunk._tag === "Failure" || chunk.success === null) {
            const [code, reason] = closing ?? [1006, ""];
            return { code, reason };
          }
          const joined = new Uint8Array(buf.length + chunk.success.length);
          joined.set(buf);
          joined.set(chunk.success, buf.length);
          const [frames, rest] = takeFrames(joined);
          buf = rest;
          for (const frame of frames) {
            if ("text" in frame) progress({ text: frame.text });
            else if ("binary" in frame) progress({ binary: true }, frame.binary);
            else return { code: frame.close[0], reason: frame.close[1] };
          }
        }
      }),
    );
  };
  handlers.previewSocketSend = (_inner, call, _p, at) => {
    const c = call as Extract<Call, { kind: "previewSocketSend" }>;
    const send = sockets.get(`${at[0]}\u0000${c.socket}`);
    if (!send) return Effect.fail(new CoreError("not_found", t("core-misc.call.socket_closed")));
    send(c.frame as Frame);
    return Effect.succeed(null);
  };
}

export { readAll, Scope };
export type { Inner };
