// Components (docs/station-components.md): programs that an app carrying the station hands it to keep running on this
// machine, whatever workspace the station is in or none (Comma's desktop app hands it its connector, salix-connect).
// The app writes a declaration, <data>/components/<name>.json; the station runs each in a process group of its own,
// starts it again when it ends (at once after a steady run, else after a pause that grows, as a service job), replaces
// it when its declaration changes, and ends it when its declaration goes. Like jobs, they outlive the station: the next
// station (an update, a handover, a crash) takes up a group still running. What the station knows of each is in
// <data>/run/components/<name>.json, for the app to read.
import { type ChildProcess, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  type FSWatcher, closeSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, rmSync, statSync, watch,
  writeFileSync,
} from "node:fs";
import { isAbsolute, join } from "node:path";
import { type Clock, Effect, Schedule } from "effect";
import { endGroup, groupAlive, pidAlive, stillOurs } from "../jobs/group.ts";
import { readExit, restartPause } from "../jobs/jobs.ts";
import { Fibers, wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";

/// What an app declares: the program (an absolute path), its arguments and environment (added to the station's),
/// where it runs (the data directory when not given), and a version the app changes to have it started anew when the
/// program changed in place (an app update replacing the file).
export type Declaration = {
  command: string;
  args: string[];
  env: Record<string, string>;
  cwd: string | null;
  version: string | null;
};

/// What the station says of a component (run/components/<name>.json). `running`: its group is up; `waiting`: it ended
/// and is started again after a pause; `invalid`: its declaration is not one the station can run (`error` says why).
export type ComponentState = {
  name: string;
  state: "running" | "waiting" | "invalid";
  version: string | null;
  /// The declaration it runs, hashed: a declaration whose hash differs is a change.
  spec: string | null;
  pgid: number | null;
  /// When its group started, by the machine's clock (ms).
  startedAt: number | null;
  /// How many times it was started again since it last ran steadily.
  restarts: number;
  lastExit: { code: number | null; at: number } | null;
  error: string | null;
};

/// A component's name: its declaration's file name without `.json`.
export const COMPONENT_NAME = /^[a-z0-9][a-z0-9-]{0,63}$/;
/// What runs a component: its program, then its exit code written where the next station looks (its shell's end too).
const WRAPPER = `exit_file=$1; shift; "$@"; code=$?; printf '%s' "$code" > "$exit_file"; exit "$code"`;
/// How often a group an earlier station started is looked at (it has no exit event here).
const LOOK_MS = 1000;
/// How long a stop waits for a group to end before it is killed.
const STOP_GRACE_MS = 5000;
/// A burst of changes to the declarations (an app writing several) is taken in once, this long after the first.
const SETTLE_MS = 200;
/// A component's log is moved aside (to .1) when it starts past this size.
const LOG_LIMIT = 10 * 1024 * 1024;

/// A declaration's text, checked: what it declares, or why it cannot be run.
export function parseDeclaration(text: string): { ok: true; declaration: Declaration } | { ok: false; error: string } {
  let raw: any;
  try {
    raw = JSON.parse(text);
  } catch (error) {
    return { ok: false, error: `not JSON: ${(error as Error).message}` };
  }
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return { ok: false, error: "not a JSON object" };
  if (typeof raw.command !== "string" || !isAbsolute(raw.command)) return { ok: false, error: "command is not an absolute path" };
  const args = raw.args ?? [];
  if (!Array.isArray(args) || args.some((a: unknown) => typeof a !== "string")) return { ok: false, error: "args is not a list of strings" };
  const env = raw.env ?? {};
  if (env === null || typeof env !== "object" || Array.isArray(env) || Object.values(env).some((v) => typeof v !== "string")) {
    return { ok: false, error: "env is not an object of strings" };
  }
  const cwd = raw.cwd ?? null;
  if (cwd !== null && (typeof cwd !== "string" || !isAbsolute(cwd))) return { ok: false, error: "cwd is not an absolute path" };
  const version = raw.version ?? null;
  if (version !== null && typeof version !== "string") return { ok: false, error: "version is not a string" };
  return { ok: true, declaration: { command: raw.command, args, env, cwd, version } };
}

/// A declaration's hash: the same declaration, the same component.
export function specOf(d: Declaration): string {
  const env = Object.keys(d.env).sort().map((k) => [k, d.env[k]]);
  return createHash("sha256").update(JSON.stringify([d.command, d.args, env, d.cwd, d.version])).digest("hex").slice(0, 16);
}

type Live = {
  spec: string;
  version: string | null;
  pgid: number;
  startedAt: number;
  restarts: number;
  stopping: boolean;
  /// Resolves when its group's leader ended (and its end was taken in).
  ended: Promise<void>;
};

export type ComponentsOptions = { data: string; clock?: Clock.Clock };

export class Components {
  /// Where apps put declarations.
  readonly dir: string;
  /// Where the station says what runs (and each one's exit file).
  readonly runDir: string;
  readonly logDir: string;
  readonly #data: string;
  readonly #fibers: Fibers;
  readonly #live = new Map<string, Live>();
  /// Waiting to be started again, by name: what calls the wait off.
  readonly #waiting = new Map<string, () => void>();
  #watcher: FSWatcher | null = null;
  #closing = false;
  #settling = false;
  /// One reconcile at a time, in order.
  #turn: Promise<void> = Promise.resolve();

  constructor(options: ComponentsOptions) {
    this.#data = options.data;
    this.dir = join(options.data, "components");
    this.runDir = join(options.data, "run", "components");
    this.logDir = join(options.data, "logs", "components");
    for (const d of [this.dir, this.runDir, this.logDir]) mkdirSync(d, { recursive: true });
    this.#fibers = new Fibers("components", options.clock);
  }

  /// Takes up the groups an earlier station left running, brings what runs in line with the declarations, and follows
  /// their changes. Resolves once the first reconcile is done.
  start(): Promise<void> {
    for (const file of readdirSync(this.runDir)) {
      if (!file.endsWith(".json")) continue;
      const name = file.slice(0, -5);
      const state = this.read(name);
      if (state?.pgid != null && state.startedAt != null && state.spec !== null) {
        const entry = { pgid: state.pgid, startedAt: state.startedAt, runtime: "component", label: name };
        if (stillOurs(entry)) {
          this.follow(name, { spec: state.spec, version: state.version, pgid: state.pgid, startedAt: state.startedAt, restarts: state.restarts });
          log.info("components", "taken up from the previous station", { component: name, pgid: state.pgid });
        }
      }
    }
    try {
      this.#watcher = watch(this.dir, () => this.changed());
      this.#watcher.unref();
      this.#watcher.on("error", () => {});
    } catch (error) {
      log.warn("components", "declarations not watched; taken in at start only", { error: (error as Error).message });
    }
    return this.reconcile();
  }

  /// The station stopping: components go on without it, recorded for the next one to take up.
  async close(): Promise<void> {
    this.#closing = true;
    this.#watcher?.close();
    for (const stop of this.#waiting.values()) stop();
    this.#waiting.clear();
    await this.#fibers.close();
  }

  /// What the station says of each component now.
  list(): ComponentState[] {
    const names = readdirSync(this.runDir).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort();
    return names.map((n) => this.read(n)).filter((s): s is ComponentState => s !== null);
  }

  /// The declarations changed: taken in once the burst is over.
  private changed(): void {
    if (this.#settling || this.#closing) return;
    this.#settling = true;
    this.#fibers.after(SETTLE_MS, () => {
      this.#settling = false;
      void this.reconcile();
    });
  }

  /// Brings what runs in line with the declarations: started, replaced, ended.
  reconcile(): Promise<void> {
    const next = this.#turn.then(() => this.reconcileNow()).catch((error) => {
      log.error("components", "reconcile failed", { error: (error as Error).message });
    });
    this.#turn = next;
    return next;
  }

  private async reconcileNow(): Promise<void> {
    if (this.#closing) return;
    const declared = new Map<string, ReturnType<typeof parseDeclaration>>();
    for (const file of readdirSync(this.dir)) {
      if (!file.endsWith(".json") || file.startsWith(".")) continue;
      const name = file.slice(0, -5);
      if (!COMPONENT_NAME.test(name)) continue;
      let text: string;
      try {
        text = readFileSync(join(this.dir, file), "utf8");
      } catch {
        continue;
      }
      declared.set(name, parseDeclaration(text));
    }
    // Gone from the declarations: ended, and nothing more said of them.
    const known = new Set([...this.#live.keys(), ...this.#waiting.keys(), ...this.list().map((s) => s.name)]);
    for (const name of known) {
      if (declared.has(name)) continue;
      await this.stop(name);
      rmSync(this.stateFile(name), { force: true });
      rmSync(this.exitFile(name), { force: true });
      log.info("components", "ended: its declaration is gone", { component: name });
    }
    for (const [name, parsed] of declared) {
      if (this.#closing) return;
      if (!parsed.ok) {
        const now = this.read(name);
        if (now?.state === "invalid" && now.error === parsed.error && !this.#live.has(name)) continue;
        await this.stop(name);
        this.write({ ...this.blank(name), state: "invalid", error: parsed.error });
        log.warn("components", "declaration not run", { component: name, error: parsed.error });
        continue;
      }
      const spec = specOf(parsed.declaration);
      const live = this.#live.get(name);
      if (live && live.spec === spec) continue;
      if (!live && this.#waiting.has(name) && this.read(name)?.spec === spec) continue;
      if (live || this.#waiting.has(name)) {
        log.info("components", "replaced: its declaration changed", { component: name });
        await this.stop(name);
      }
      this.launch(name, parsed.declaration, spec, 0);
    }
  }

  /// Ends a component's group (SIGTERM, SIGKILL after the grace) and waits for its end; one waiting is called off.
  private async stop(name: string): Promise<void> {
    this.#waiting.get(name)?.();
    this.#waiting.delete(name);
    const live = this.#live.get(name);
    if (!live) return;
    live.stopping = true;
    await this.#fibers.run(endGroup(live.pgid, STOP_GRACE_MS));
    await live.ended;
  }

  /// Runs a component, and follows it to its end.
  private launch(name: string, d: Declaration, spec: string, restarts: number): void {
    const logFile = join(this.logDir, `${name}.log`);
    try {
      if (statSync(logFile).size > LOG_LIMIT) renameSync(logFile, `${logFile}.1`);
    } catch {}
    const exit = this.exitFile(name);
    rmSync(exit, { force: true });
    const out = openSync(logFile, "a");
    let child: ChildProcess;
    try {
      // detached: a session and process group of its own (pgid = its pid), not ended with the station.
      child = spawn("/bin/sh", ["-c", WRAPPER, `stillfail-component-${name}`, exit, d.command, ...d.args], {
        cwd: d.cwd ?? this.#data,
        env: { ...process.env, ...d.env },
        stdio: ["ignore", out, out],
        detached: true,
      });
    } finally {
      closeSync(out);
    }
    child.on("error", () => {});
    const pgid = child.pid;
    if (pgid === undefined) {
      this.write({ ...this.blank(name), state: "invalid", spec, version: d.version, error: "it could not be started" });
      return;
    }
    child.unref();
    const startedAt = wall.now();
    const exited = new Promise<number | null>((resolve) => child.once("exit", (code) => resolve(code)));
    this.track(name, { spec, version: d.version, pgid, startedAt, restarts }, exited);
    log.info("components", "started", { component: name, pgid, version: d.version, restarts });
  }

  /// Follows a group an earlier station started: its exit file appearing, or its leader gone, looked at once a second.
  private follow(name: string, live: Omit<Live, "stopping" | "ended">): void {
    const exit = this.exitFile(name);
    const gone = this.#fibers
      .run(
        Effect.sync(() => existsSync(exit) || !pidAlive(live.pgid)).pipe(
          Effect.repeat({ schedule: Schedule.spaced(LOOK_MS), until: (over) => over || this.#closing }),
        ),
      )
      .then(() => readExit(exit));
    this.track(name, live, gone);
  }

  private track(name: string, base: Omit<Live, "stopping" | "ended">, exited: Promise<number | null>): void {
    let done = () => {};
    const live: Live = { ...base, stopping: false, ended: new Promise<void>((resolve) => (done = resolve)) };
    this.#live.set(name, live);
    this.write({ ...this.blank(name), state: "running", spec: live.spec, version: live.version, pgid: live.pgid, startedAt: live.startedAt, restarts: live.restarts, lastExit: this.read(name)?.lastExit ?? null });
    void exited.then((code) => {
      try {
        this.ended(name, live, code);
      } finally {
        done();
      }
    });
  }

  /// A component's group ended: started again unless it was stopped or the station is closing.
  private ended(name: string, live: Live, code: number | null): void {
    // The station closing: left as it is on record, for the next one to find it ended (its exit file says how).
    if (this.#closing) return;
    if (this.#live.get(name) === live) this.#live.delete(name);
    // What it started itself goes with it.
    if (groupAlive(live.pgid)) void this.#fibers.run(endGroup(live.pgid, STOP_GRACE_MS));
    const at = wall.now();
    const lastExit = { code, at };
    if (live.stopping) {
      const state = this.read(name);
      if (state) this.write({ ...state, pgid: null, startedAt: null, lastExit });
      return;
    }
    const ranMs = at - live.startedAt;
    const pause = restartPause(live.restarts, ranMs);
    const restarts = pause === 0 ? 0 : live.restarts + 1;
    log.warn("components", "ended; started again", { component: name, code, pauseMs: pause, restarts });
    this.write({ ...this.blank(name), state: "waiting", spec: live.spec, version: live.version, restarts, lastExit });
    const again = () => {
      this.#waiting.delete(name);
      if (this.#closing) return;
      const parsed = this.declaration(name);
      // Changed or gone meanwhile: the reconcile its change brought takes it from here.
      if (!parsed?.ok || specOf(parsed.declaration) !== live.spec) return void this.reconcile();
      this.launch(name, parsed.declaration, live.spec, restarts);
    };
    this.#waiting.set(name, this.#fibers.after(pause, again));
  }

  private declaration(name: string): ReturnType<typeof parseDeclaration> | null {
    try {
      return parseDeclaration(readFileSync(join(this.dir, `${name}.json`), "utf8"));
    } catch {
      return null;
    }
  }

  private blank(name: string): ComponentState {
    return { name, state: "running", version: null, spec: null, pgid: null, startedAt: null, restarts: 0, lastExit: null, error: null };
  }

  private stateFile(name: string): string {
    return join(this.runDir, `${name}.json`);
  }

  exitFile(name: string): string {
    return join(this.runDir, `${name}.exit`);
  }

  private read(name: string): ComponentState | null {
    try {
      return JSON.parse(readFileSync(this.stateFile(name), "utf8")) as ComponentState;
    } catch {
      return null;
    }
  }

  /// Written whole (a temporary file renamed over it): an app reading it never sees half of one.
  private write(state: ComponentState): void {
    const file = this.stateFile(state.name);
    const temp = `${file}.${process.pid}.tmp`;
    writeFileSync(temp, `${JSON.stringify(state)}\n`);
    renameSync(temp, file);
  }
}
