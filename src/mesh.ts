// Runs ember-mesh, which makes this station reachable through ember cloud.
// Once the station is enrolled (<dataDir>/mesh/cloud.json exists, written by
// `ember station enroll`), ember starts ember-mesh and keeps it running; it
// picks up an enrollment made while ember is running within seconds. Each
// start gets a fresh secret, which ember-mesh presents on every request it
// relays so the admin API can tell them from other local callers.
import { spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
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
  #secret: string | null = null;
  #child: ChildProcess | null = null;
  #timer: ReturnType<typeof setTimeout> | null = null;
  #failures = 0;
  #stopped = false;

  constructor(options: { dataDir: string; admin: string; binary?: string }) {
    this.#dataDir = options.dataDir;
    this.#admin = options.admin;
    this.#binary = options.binary ?? process.env.EMBER_MESH_BIN ?? REPO_BINARY;
  }

  get #statePath(): string {
    return join(this.#dataDir, "mesh", "cloud.json");
  }

  secret(): string | null {
    return this.#child ? this.#secret : null;
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
    this.#tick();
  }

  #tick(): void {
    if (this.#stopped || this.#child) return;
    if (!existsSync(this.#statePath)) {
      this.#timer = setTimeout(() => this.#tick(), 10_000);
      return;
    }
    if (!existsSync(this.#binary)) {
      log.warn("station is enrolled but ember-mesh is not built; run `cargo build --release` in mesh/", { binary: this.#binary });
      this.#timer = setTimeout(() => this.#tick(), 60_000);
      return;
    }
    this.#secret = randomBytes(32).toString("base64url");
    const child = spawn(this.#binary, ["run", "--data", this.#dataDir, "--admin", this.#admin], {
      env: { ...process.env, EMBER_MESH_SECRET: this.#secret, RUST_LOG: process.env.RUST_LOG ?? "info,iroh=warn" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    this.#child = child;
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
      if (this.#stopped) return;
      this.#failures = Date.now() - started > 60_000 ? 0 : this.#failures + 1;
      const delay = Math.min(60_000, 1000 * 2 ** this.#failures);
      log.warn("ember-mesh exited; restarting", { code, signal, inMs: delay });
      this.#timer = setTimeout(() => this.#tick(), delay);
    });
    log.info("ember-mesh started", { binary: this.#binary });
  }

  async stop(): Promise<void> {
    this.#stopped = true;
    if (this.#timer) clearTimeout(this.#timer);
    const child = this.#child;
    if (!child) return;
    await new Promise<void>((resolve) => {
      child.once("exit", () => resolve());
      child.kill("SIGTERM");
      setTimeout(() => { child.kill("SIGKILL"); resolve(); }, 5000).unref();
    });
  }
}
