// Runs ember-mesh, which makes this station reachable through ember cloud.
// Once the station is enrolled (<dataDir>/mesh/cloud.json exists, written by
// `ember station enroll`), ember starts ember-mesh and keeps it running. It
// watches the mesh directory, so an enrollment made while ember runs is
// picked up as it is written, and the binary's directory, so a build made
// after enrolling starts it. Each start gets a fresh secret, which ember-mesh
// presents on every request it relays so the admin API can tell them from
// other local callers. With traces on, ember-mesh sends the admin API's spans
// with its own: they go to it on stdin, one JSON line each.
import { spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { EventEmitter } from "node:events";
import { existsSync, mkdirSync, readFileSync, watch, type FSWatcher } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { log } from "./log.ts";

export interface MeshStatus {
  /** off: not enrolled; missing: enrolled but no ember-mesh binary; running / restarting. */
  state: "off" | "missing" | "running" | "restarting";
  origin: string | null;
  station: string | null;
  workspace: string | null;
  name: string | null;
}

const REPO_BINARY = join(dirname(fileURLToPath(import.meta.url)), "..", "mesh", "target", "release", "ember-mesh");

export class MeshSupervisor {
  readonly #dataDir: string;
  readonly #binary: string;
  readonly #admin: string;
  readonly #traces: () => boolean;
  #secret: string | null = null;
  /** The running ember-mesh takes spans. */
  #tracing = false;
  #child: ChildProcess | null = null;
  #timer: ReturnType<typeof setTimeout> | null = null;
  #watchers: FSWatcher[] = [];
  #binaryWatched = false;
  #failures = 0;
  #stopped = false;
  /** Emits "change" whenever status() may say something new. */
  readonly changes = new EventEmitter();

  /** `traces`: whether the station's config turns traces on, asked at each start of ember-mesh. */
  constructor(options: { dataDir: string; admin: string; binary?: string; traces?: () => boolean }) {
    this.#dataDir = options.dataDir;
    this.#admin = options.admin;
    this.#traces = options.traces ?? (() => false);
    this.#binary = options.binary ?? process.env.EMBER_MESH_BIN ?? REPO_BINARY;
  }

  get #statePath(): string {
    return join(this.#dataDir, "mesh", "cloud.json");
  }

  secret(): string | null {
    return this.#child ? this.#secret : null;
  }

  /** A span of the admin API, for ember-mesh to send; dropped while traces are off or ember-mesh is not running. */
  span(span: object): void {
    if (this.#tracing && this.#child?.stdin?.writable) this.#child.stdin.write(`${JSON.stringify(span)}\n`);
  }

  status(): MeshStatus {
    let state: Record<string, string> = {};
    try {
      state = JSON.parse(readFileSync(this.#statePath, "utf8")) as Record<string, string>;
    } catch {
      return { state: "off", origin: null, station: null, workspace: null, name: null };
    }
    return {
      state: this.#child ? "running" : existsSync(this.#binary) ? "restarting" : "missing",
      origin: state.origin ?? null, station: state.station ?? null, workspace: state.workspace_name ?? null, name: state.name ?? null,
    };
  }

  start(): void {
    this.#stopped = false;
    const dir = dirname(this.#statePath);
    mkdirSync(dir, { recursive: true });
    this.#watch(dir, false, (file) => {
      if (file !== basename(this.#statePath)) return;
      this.changes.emit("change");
      this.#tick();
    });
    this.#tick();
  }

  /**
   * Waits for the binary to be built. Its directory may not exist before the
   * first build (mesh/target/release): the nearest of it and two parents that
   * does is watched, with what is below it.
   */
  #watchBinary(): void {
    if (this.#binaryWatched) return;
    let near = dirname(this.#binary);
    for (let up = 0; up < 2 && !existsSync(near); up++) near = dirname(near);
    if (!existsSync(near)) {
      log.warn("nothing to watch for the ember-mesh binary; restart ember once it is built", { binary: this.#binary });
      return;
    }
    this.#binaryWatched = true;
    this.#watch(near, near !== dirname(this.#binary), () => {
      if (existsSync(this.#binary) && !this.#child && !this.#timer) this.#tick();
    });
  }

  #watch(dir: string, recursive: boolean, onEvent: (file: string | null) => void): void {
    try {
      const watcher = watch(dir, { recursive, persistent: false }, (_event, file) => onEvent(file));
      watcher.on("error", (error) => log.warn("cannot watch for ember-mesh changes", { dir, error }));
      this.#watchers.push(watcher);
    } catch (error) {
      log.warn("cannot watch for ember-mesh changes", { dir, error });
    }
  }

  #tick(): void {
    if (this.#stopped || this.#child) return;
    if (!existsSync(this.#statePath)) return; // the mesh directory's watcher calls again on enrollment
    if (!existsSync(this.#binary)) {
      log.warn("station is enrolled but ember-mesh is not built; run `cargo build --release` in mesh/", { binary: this.#binary });
      this.changes.emit("change");
      this.#watchBinary(); // which calls again once it is built
      return;
    }
    this.#secret = randomBytes(32).toString("base64url");
    const tracing = this.#traces();
    const child = spawn(this.#binary, ["run", "--data", this.#dataDir, "--admin", this.#admin], {
      env: { ...process.env, EMBER_MESH_SECRET: this.#secret, RUST_LOG: process.env.RUST_LOG ?? "info,iroh=warn", ...(tracing ? { EMBER_MESH_TRACES: "1" } : {}) },
      stdio: [tracing ? "pipe" : "ignore", "pipe", "pipe"],
    });
    // A span written as it exits is lost, like any span that cannot be sent.
    child.stdin?.on("error", () => {});
    this.#child = child;
    this.#tracing = tracing;
    this.changes.emit("change");
    const started = Date.now();
    const relay = (chunk: Buffer) => {
      for (const line of chunk.toString("utf8").split("\n")) if (line.trim()) log.info("ember-mesh", { line: line.replace(/\x1b\[[0-9;]*m/g, "").slice(0, 500) });
    };
    child.stdout!.on("data", relay);
    child.stderr!.on("data", relay);
    child.on("error", (error) => log.error("ember-mesh failed to start", { error }));
    child.on("exit", (code, signal) => {
      this.#child = null;
      this.#secret = null;
      this.changes.emit("change");
      if (this.#stopped) return;
      this.#failures = Date.now() - started > 60_000 ? 0 : this.#failures + 1;
      const delay = Math.min(60_000, 1000 * 2 ** this.#failures);
      log.warn("ember-mesh exited; restarting", { code, signal, inMs: delay });
      this.#timer = setTimeout(() => {
        this.#timer = null;
        this.#tick();
      }, delay);
    });
    log.info("ember-mesh started", { binary: this.#binary });
  }

  async stop(): Promise<void> {
    this.#stopped = true;
    if (this.#timer) clearTimeout(this.#timer);
    for (const watcher of this.#watchers) watcher.close();
    this.#watchers = [];
    this.#binaryWatched = false;
    const child = this.#child;
    if (!child) return;
    await new Promise<void>((resolve) => {
      child.once("exit", () => resolve());
      child.kill("SIGTERM");
      setTimeout(() => { child.kill("SIGKILL"); resolve(); }, 5000).unref();
    });
  }
}
