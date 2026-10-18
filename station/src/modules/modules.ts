// Modules (docs/station-modules.md): programs beside the station, each its own process, that add to what members reach
// on it without being part of it (a media library, say). config.json `modules` names them (by a command, or by a
// package the station installs itself: modules/packages.ts); the station starts each
// (modules/live.ts), passes it the admin API's `/m/<id>/…` with who asks (modules/forward.ts), lets a viewer make the
// writes it declares of its own, and answers its own local API (modules/local.ts) for the drive. What is here: which
// modules there are, each as it is now, and what the admin API asks of them.
import { join } from "node:path";
import type { Answer, Request } from "../api/request.ts";
import { error } from "../api/request.ts";
import type { Viewer } from "../mesh/credential.ts";
import { forward } from "./forward.ts";

/// A module as it is run: `{ id, command, args?, env?, enabled? }` as config.json names it, or one the station installed
/// itself (`package`: modules/packages.ts), then run by the station's own Node, with the build it runs.
export type ModuleSpec = { id: string; command: string; args: string[]; env: Record<string, string>; installed?: { package: string; build: number } };

/// A module config.json names by its package (`{ id, package, args?, env?, enabled? }`): the station installs it, and
/// runs it once it is (modules/packages.ts).
export type PackageSpec = { id: string; package: string; args: string[]; env: Record<string, string> };

/// A module's id: what its path, its folder and its sockets are named by. A package's name is one too. As the client
/// core names its modules (client/core-ts/src/module.ts).
export const MODULE_ID = /^[a-z][a-z0-9]{0,31}$/;
/// A module's part of the admin API: `/m/<id>`, then its own path (and the query).
const MODULE_PATH = /^\/m\/([a-z][a-z0-9]{0,31})(\/[^?]*)?(?:\?.*)?$/;

/// The modules config.json names (`modules`), those turned off (`enabled: false`) left out; and what is wrong with any
/// that cannot be taken (each said, then left out). Each is run by its command, or installed as its package: one of
/// the two.
export function modulesOf(raw: any): { specs: (ModuleSpec | PackageSpec)[]; refused: string[] } {
  const specs: (ModuleSpec | PackageSpec)[] = [];
  const refused: string[] = [];
  for (const m of Array.isArray(raw?.modules) ? raw.modules : []) {
    const id = typeof m?.id === "string" ? m.id : "";
    const why =
      !MODULE_ID.test(id) ? `a module's id is a-z and 0-9, starting with a letter, at most 32: ${JSON.stringify(m?.id)}`
      : specs.some((s) => s.id === id) ? `module ${id} is named twice`
      : (m.command === undefined) === (m.package === undefined) ? `module ${id}: either a command or a package, one of them`
      : m.command !== undefined && (typeof m.command !== "string" || m.command === "") ? `module ${id}: command is a program`
      : m.package !== undefined && (typeof m.package !== "string" || !MODULE_ID.test(m.package)) ? `module ${id}: package is a package's name (a-z and 0-9, starting with a letter)`
      : m.args !== undefined && (!Array.isArray(m.args) || m.args.some((a: unknown) => typeof a !== "string")) ? `module ${id}: args are strings`
      : m.env !== undefined && (m.env === null || typeof m.env !== "object" || Array.isArray(m.env) || Object.values(m.env).some((v) => typeof v !== "string")) ? `module ${id}: env is an object of strings`
      : null;
    if (why !== null) refused.push(why);
    else if (m.enabled !== false && m.package !== undefined) specs.push({ id, package: m.package, args: m.args ?? [], env: m.env ?? {} });
    else if (m.enabled !== false) specs.push({ id, command: m.command, args: m.args ?? [], env: m.env ?? {} });
  }
  return { specs, refused };
}

export const isPackage = (spec: ModuleSpec | PackageSpec): spec is PackageSpec => "package" in spec;

/// The module a path of the admin API (after /admin/api) is for, and the path it asks of it ("/" for its root); null for
/// none.
export function moduleOf(path: string): { id: string; path: string } | null {
  const found = MODULE_PATH.exec(path);
  return found === null ? null : { id: found[1]!, path: found[2] || "/" };
}

/// Whether a path of the admin API (after /admin/api, its query too) is a module's.
export const isModulePath = (path: string) => MODULE_PATH.test(path);

/// The member a module acts for, as it is told (`stillfail-viewer`): who, their role in which workspace, and whether
/// that is the station's home one. JSON, its characters past ASCII escaped (`\uXXXX`) so it is a header's value.
export type ModuleViewer = { sub: string; email: string; name: string; role: string; workspace: string; home: boolean };

export const VIEWER_HEADER = "stillfail-viewer";

export function viewerHeader(viewer: Viewer): string {
  const told: ModuleViewer = { sub: viewer.sub, email: viewer.email, name: viewer.name, role: viewer.role, workspace: viewer.workspace, home: viewer.home !== false };
  return JSON.stringify(told).replace(/[\u007f-￿]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);
}

/// The viewer a module says it acts for (its `stillfail-viewer`, as it was told), or null when it is not one.
export function viewerOfHeader(value: string | undefined): Viewer | null {
  if (value === undefined) return null;
  let v: any;
  try {
    v = JSON.parse(value);
  } catch {
    return null;
  }
  const text = (k: string) => (typeof v?.[k] === "string" ? v[k] : null);
  const [sub, email, name, role, workspace] = ["sub", "email", "name", "role", "workspace"].map(text);
  if (sub === null || email === null || name === null || role === null || role === "" || workspace === null || typeof v.home !== "boolean") return null;
  return { sub, email, name, role, workspace, device: "", home: v.home };
}

/// A module as the station has it now: where it is, how it is reached and reaches the station, and what it said of
/// itself once it answered (its manifest).
export type Module = {
  readonly spec: ModuleSpec;
  /// `<data>/modules/<id>`: its own (STILLFAIL_MODULE_DIR), with its log, and the two sockets.
  readonly dir: string;
  /// Where it listens (STILLFAIL_MODULE_SOCKET), HTTP/1.1.
  readonly socket: string;
  /// Where the station answers it (STILLFAIL_STATION_SOCKET, modules/local.ts).
  readonly station: string;
  /// What it says to the station's socket (STILLFAIL_STATION_TOKEN): new each time it is started.
  token: string;
  /// Started and answering (its manifest read).
  running: boolean;
  /// The requests besides reads a viewer may make of it (`viewerWrites`, whole paths after `/m/<id>`).
  viewerWrites: RegExp[];
};

/// The modules there are, each as it is now (modules/live.ts starts, stops and changes them), and what the admin API
/// asks of them.
export class ModuleSet {
  readonly #by = new Map<string, Module>();
  readonly #data: string;
  readonly #changed: () => void;

  /// `changed`: told when what the overview says of them changes.
  constructor(data: string, changed: () => void = () => {}) {
    this.#data = data;
    this.#changed = changed;
  }

  /// Where a module's own things are.
  dirOf(id: string): string {
    return join(this.#data, "modules", id);
  }

  /// A module now named, not running yet.
  add(spec: ModuleSpec): Module {
    const dir = this.dirOf(spec.id);
    const module: Module = { spec, dir, socket: join(dir, "module.sock"), station: join(dir, "station.sock"), token: "", running: false, viewerWrites: [] };
    this.#by.set(spec.id, module);
    this.#changed();
    return module;
  }

  /// A module no longer named (stopped first).
  remove(id: string) {
    if (this.#by.delete(id)) this.#changed();
  }

  get(id: string): Module | undefined {
    return this.#by.get(id);
  }

  /// A module answering, with what it says a viewer may change; or not (gone, being started again).
  setRunning(module: Module, running: boolean, viewerWrites: RegExp[] = []) {
    const was = module.running;
    module.running = running;
    module.viewerWrites = running ? viewerWrites : [];
    if (was !== running && this.#by.get(module.spec.id) === module) this.#changed();
  }

  /// What the overview says of them: each one named, and whether it runs now.
  listed(): { id: string; running: boolean }[] {
    return [...this.#by.values()].map((m) => ({ id: m.spec.id, running: m.running }));
  }

  /// Whether a viewer may make `r` (not a read): one its module says a viewer may (its manifest's `viewerWrites`).
  viewerMay(r: { method: string; path: string }): boolean {
    const at = moduleOf(r.path);
    if (at === null) return false;
    const module = this.#by.get(at.id);
    return module !== undefined && module.running && module.viewerWrites.some((w) => w.test(at.path));
  }

  /// `r` passed on to its module, its answer as it comes: 404 for a module not named, 503 for one not running or not
  /// answering.
  async forward(r: Request, at: { id: string; path: string }): Promise<Answer> {
    const module = this.#by.get(at.id);
    if (module === undefined) return error(404, `no module ${at.id}`);
    if (!module.running) return error(503, `module ${at.id} is not running`);
    try {
      return await forward(module.socket, { method: r.method, path: at.path + (r.search ?? ""), headers: r.headers, body: r.upload ?? r.body }, viewerHeader(r.viewer));
    } catch (e) {
      return error(503, `module ${at.id} did not answer: ${(e as Error).message}`);
    }
  }
}
