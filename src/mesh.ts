// The station's way into ember cloud is the process that runs this one: ember-station (mesh/station), which relays
// clients' requests here, each with the secret it gave this process (EMBER_MESH_SECRET) and the viewer it verified.
// What it knows of the workspace is in <dataDir>/mesh/cloud.json (written by `ember station enroll`, kept up to date
// by ember cloud); this reads it, and watches it, so an enrollment or a rename shows at once. With traces on, the
// admin API's spans go to ember-station on fd 3, one JSON line each, and it sends them with its own.
import { EventEmitter } from "node:events";
import { createWriteStream, mkdirSync, readFileSync, watch, type FSWatcher, type WriteStream } from "node:fs";
import { basename, join } from "node:path";
import { log } from "./log.ts";

export interface MeshStatus {
  /** off: not in a workspace; running: in one, reachable through ember cloud while this station runs. */
  state: "off" | "running";
  origin: string | null;
  station: string | null;
  /** The workspace's name, as it was when the station joined. */
  workspace: string | null;
  workspaceId: string | null;
  name: string | null;
}

export class MeshLink {
  readonly #dataDir: string;
  readonly #secret: string | null;
  readonly #traces: () => boolean;
  #spans: WriteStream | null = null;
  #watcher: FSWatcher | null = null;
  /** Emits "change" whenever status() may say something new. */
  readonly changes = new EventEmitter();

  /** `traces`: whether the station's config turns traces on, asked for each span. */
  constructor(options: { dataDir: string; secret?: string | null; traces?: () => boolean }) {
    this.#dataDir = options.dataDir;
    this.#secret = options.secret ?? process.env.EMBER_MESH_SECRET ?? null;
    this.#traces = options.traces ?? (() => false);
  }

  get #statePath(): string {
    return join(this.#dataDir, "mesh", "cloud.json");
  }

  /** What ember-station presents on the requests it relays; null when none runs this process. */
  secret(): string | null {
    return this.#secret;
  }

  /** A span of the admin API, for ember-station to send; dropped while traces are off. */
  span(span: object): void {
    if (this.#spans && this.#traces()) this.#spans.write(`${JSON.stringify(span)}\n`);
  }

  status(): MeshStatus {
    let state: Record<string, string>;
    try {
      state = JSON.parse(readFileSync(this.#statePath, "utf8")) as Record<string, string>;
    } catch {
      return { state: "off", origin: null, station: null, workspace: null, workspaceId: null, name: null };
    }
    return {
      state: "running",
      origin: state.origin ?? null, station: state.station ?? null, workspace: state.workspace_name ?? null, workspaceId: state.workspace ?? null, name: state.name ?? null,
    };
  }

  start(): void {
    const dir = join(this.#dataDir, "mesh");
    mkdirSync(dir, { recursive: true });
    try {
      this.#watcher = watch(dir, { persistent: false }, (_event, file) => {
        if (file === basename(this.#statePath)) this.changes.emit("change");
      });
      this.#watcher.on("error", (error) => log.warn("cannot watch the mesh directory", { error }));
    } catch (error) {
      log.warn("cannot watch the mesh directory", { error });
    }
    // Run by ember-station, fd 3 is its pipe for spans.
    if (this.#secret) {
      this.#spans = createWriteStream("", { fd: 3 });
      this.#spans.on("error", (error) => {
        log.warn("cannot hand spans to ember-station", { error });
        this.#spans = null;
      });
    }
  }

  stop(): void {
    this.#watcher?.close();
    this.#watcher = null;
    this.#spans?.end();
    this.#spans = null;
  }
}
