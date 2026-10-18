// The modules' lives (docs/station-modules.md): each one config.json names started beside the station once the station
// process before it is gone (at a handover two would share the module's data), with the station's local API (local.ts)
// listening for it; started again whenever it ends, a second after at first, at most a minute apart; ended as the
// station stops, or as config.json stops naming it (or names it otherwise: then started again as it now says, config.json
// read again as it changes). A module is a group of its own (what it starts ends with it), its output in
// <data>/modules/<id>/log, its stdin a pipe the station holds: closed, the station is gone (it crashed), and the module
// ends itself.
import { type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { closeSync, mkdirSync, openSync, renameSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { Cause, Clock, Effect, FiberMap, Layer, Option, Queue, Schedule, Stream } from "effect";
import { Modules, Paths, Previous, StationConfig, StationDrive } from "../services.ts";
import { dir as thumbsDir } from "../drive/thumbs.ts";
import { endCommand, startCommand } from "../ops/processes.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { type Module, type ModuleSet, modulesOf } from "./modules.ts";
import { ask } from "./forward.ts";
import { listen, localApi } from "./local.ts";
import type { Drive } from "../drive/drive.ts";
import type { ConfigFile } from "../ops/config.ts";

/// How soon a module that ended is started again: a second, then twice as long each time, at most a minute.
export const AGAIN = Schedule.min([Schedule.exponential("1 second"), Schedule.spaced("1 minute")]);
/// How often a module just started is asked for its manifest until it answers: soon, then at most every 2 seconds.
const LOOK = Schedule.min([Schedule.exponential("50 millis"), Schedule.spaced("2 seconds")]);
/// How long a module asked to end (SIGTERM) has before it is killed.
const ENDING = "5 seconds";
/// A log past this is moved to log.1 as the module starts.
const LOG_MOST = 10 * 1024 * 1024;

export type Life = {
  data: string;
  modules: ModuleSet;
  drive: Drive;
  config: ConfigFile;
  /// The station process before this one gone (a handover's).
  previousGone: Promise<void>;
};

/// How a module's process ended: its exit code or signal, or why it could not start.
const ended = (child: ChildProcess) =>
  Effect.callback<string>((resume) => {
    if (child.exitCode !== null || child.signalCode !== null) return resume(Effect.succeed(child.signalCode ?? `exit ${child.exitCode}`));
    const exit = (code: number | null, signal: string | null) => resume(Effect.succeed(signal ?? `exit ${code}`));
    const failed = (e: Error) => resume(Effect.succeed(e.message));
    child.once("exit", exit);
    child.once("error", failed);
    return Effect.sync(() => {
      child.off("exit", exit);
      child.off("error", failed);
    });
  });

/// A module's process ended, and all it started: asked (SIGTERM), then made to (SIGKILL).
const end = (child: ChildProcess) =>
  Effect.gen(function* () {
    child.stdin?.end();
    if (child.pid === undefined) return;
    endCommand(child, "SIGTERM");
    if (child.exitCode !== null || child.signalCode !== null) return;
    if (Option.isNone(yield* Effect.timeoutOption(ended(child), ENDING))) endCommand(child, "SIGKILL");
  });

/// The viewer writes a manifest says (`{viewerWrites: [regex source]}`), each a whole path after `/m/<id>`; one that is
/// not a regex is said and left out.
function manifestOf(id: string, body: Buffer): RegExp[] {
  let said: unknown;
  try {
    said = JSON.parse(body.toString("utf8"))?.viewerWrites;
  } catch {
    said = undefined;
  }
  const writes: RegExp[] = [];
  for (const source of Array.isArray(said) ? said : []) {
    try {
      if (typeof source !== "string") throw new Error("not a string");
      writes.push(new RegExp(`^(?:${source})$`));
    } catch (e) {
      log.warn("modules", "a module's viewer write is not a regex", { module: id, source: String(source), error: (e as Error).message });
    }
  }
  return writes;
}

/// Asked for its manifest until it answers (no manifest: no viewer writes), then running.
const ready = (life: Life, module: Module) =>
  Effect.tryPromise(() => ask(module.socket, "/manifest")).pipe(
    Effect.flatMap(({ status, body }) => (status === 200 ? Effect.succeed(manifestOf(module.spec.id, body)) : status === 404 ? Effect.succeed([]) : Effect.fail(new Error(`manifest: ${status}`)))),
    Effect.retry(LOOK),
    Effect.flatMap((writes) =>
      Effect.sync(() => {
        life.modules.setRunning(module, true, writes);
        log.info("modules", "module running", { module: module.spec.id, viewerWrites: writes.length });
      }),
    ),
  );

/// The module's process, started with what it is told; its output to its log.
function start(module: Module, stationSocket: string): ChildProcess {
  const path = join(module.dir, "log");
  if ((statSync(path, { throwIfNoEntry: false })?.size ?? 0) > LOG_MOST) renameSync(path, `${path}.1`);
  const out = openSync(path, "a", 0o600);
  try {
    const child = startCommand(module.spec.command, module.spec.args, {
      cwd: module.dir,
      env: {
        ...process.env,
        ...module.spec.env,
        STILLFAIL_MODULE_ID: module.spec.id,
        STILLFAIL_MODULE_DIR: module.dir,
        STILLFAIL_MODULE_SOCKET: module.socket,
        STILLFAIL_STATION_SOCKET: stationSocket,
        STILLFAIL_STATION_TOKEN: module.token,
      },
      stdio: ["pipe", out, out],
    });
    child.stdin?.on("error", () => {});
    return child;
  } finally {
    closeSync(out);
  }
}

/// One run of the module: started, its manifest asked for, until it ends (or is ended).
const once = (life: Life, module: Module) =>
  Effect.scoped(
    Effect.gen(function* () {
      module.token = randomBytes(32).toString("base64url");
      rmSync(module.socket, { force: true });
      const child = yield* Effect.acquireRelease(Effect.sync(() => start(module, module.station)), end);
      const at = yield* Clock.currentTimeMillis;
      yield* Effect.forkScoped(ready(life, module));
      const how = yield* ended(child);
      life.modules.setRunning(module, false);
      log.warn("modules", "module ended; it is started again", { module: module.spec.id, how, ranMs: (yield* Clock.currentTimeMillis) - at });
    }),
  );

/// A module's life: its folder and the station's socket for it, then run after run.
export const live = (life: Life, module: Module) =>
  Effect.gen(function* () {
    yield* Effect.promise(() => life.previousGone);
    mkdirSync(module.dir, { recursive: true, mode: 0o700 });
    yield* Effect.acquireRelease(
      Effect.promise(() => listen(module.station, localApi({ drive: life.drive, config: life.config, thumbs: thumbsDir(life.data), token: () => module.token }))),
      (server) => Effect.sync(() => (server.close(), server.closeAllConnections(), rmSync(module.station, { force: true }))),
    );
    yield* Effect.repeat(once(life, module), AGAIN);
  }).pipe(
    Effect.scoped,
    Effect.ensuring(Effect.sync(() => life.modules.setRunning(module, false))),
    Effect.tapCause((cause) => Effect.sync(() => {
      if (!Cause.hasInterruptsOnly(cause)) log.error("modules", "a module is not run", { module: module.spec.id, error: Cause.pretty(cause) });
    })),
  );

/// The modules config.json names, as it names them now: those no longer named (or named otherwise) ended, the others
/// started. Gives what follows them.
export const follow = (life: Life) =>
  Effect.gen(function* () {
    const running = yield* FiberMap.make<string>();
    // What each runs as (its spec, as JSON), and what was said of those not taken.
    const as = new Map<string, string>();
    let said = "";
    return Effect.gen(function* () {
      const { specs, refused } = modulesOf(life.config.raw());
      if (refused.join("\n") !== said) for (const why of refused) log.warn("modules", "a module is not started", { why });
      said = refused.join("\n");
      const wanted = new Map(specs.map((s) => [s.id, JSON.stringify(s)]));
      for (const [id, was] of as) {
        if (wanted.get(id) === was) continue;
        yield* FiberMap.remove(running, id);
        life.modules.remove(id);
        as.delete(id);
      }
      for (const spec of specs) {
        if (as.has(spec.id)) continue;
        as.set(spec.id, JSON.stringify(spec));
        yield* FiberMap.run(running, spec.id, live(life, life.modules.add(spec)));
      }
    });
  });

export const ModulesLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const modules = yield* Modules;
    const config = yield* StationConfig;
    const drive = yield* StationDrive;
    const life: Life = { data, modules, drive, config, previousGone: (yield* Previous).gone };
    // Sockets (unix domain) are how a module and the station talk: macOS and Linux.
    if (!platform.hasUnixSockets) {
      if (modulesOf(config.raw()).specs.length > 0) log.warn("modules", "modules run on macOS and Linux only; none is started here");
      return;
    }
    const again = yield* follow(life);
    yield* again;
    // config.json as it changes (an edit here, or the file's read again).
    const changes = Stream.callback<void>((queue) =>
      Effect.acquireRelease(
        Effect.sync(() => config.listen(() => void Queue.offerUnsafe(queue, undefined))),
        (unlisten) => Effect.sync(unlisten),
      ),
    );
    yield* Effect.forkScoped(Stream.runForEach(changes, () => again));
  }),
);
