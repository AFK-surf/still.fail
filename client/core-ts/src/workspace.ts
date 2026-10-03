// Workspaces: the units the core keeps apart (workspace.rs). What the core has of one workspace is its own: the account
// that reaches it, its stations (station.ts), what is waited on for them (status.ts), what its person hears of it
// (notices.ts) and what the core keeps in sync of it (sync.ts). What is the device's stays shared; what is an account's
// is kept by account.
import type { Host } from "./host.ts";
import type { Runner } from "./runtime.ts";
import { Status, type NameOf } from "./status.ts";

/// The workspace a station's address (`"<workspace>/<station>"`) is in.
export function ofAddress(address: string): string {
  const at = address.indexOf("/");
  return at >= 0 ? address.slice(0, at) : address;
}

export class Workspace {
  readonly id: string;
  /// The signed-in account that reaches it, as the latest `/v1/me` answers say; null while not known.
  owner: string | null = null;
  /// Its stations while any of their topics is live, by address (station.ts).
  readonly stations = new Map<string, unknown>();
  /// What is waited on for its stations.
  readonly status: Status;
  /// Per-module state the later parts keep here (preview loads, what was heard, what is synced).
  readonly own = new Map<string, unknown>();

  constructor(id: string, status: Status) {
    this.id = id;
    this.status = status;
  }

  /// A module's own part of this workspace, made the first time.
  part<T>(name: string, make: () => T): T {
    let p = this.own.get(name) as T | undefined;
    if (p === undefined) {
      p = make();
      this.own.set(name, p);
    }
    return p;
  }
}

/// Every workspace the core has had to do with this run, by id: made on first use, and kept.
export class Workspaces {
  readonly #host: Host;
  readonly #runner: Runner;
  readonly #all = new Map<string, Workspace>();
  #statusChanged: ((id: string) => void) | null = null;
  #names: NameOf | null = null;

  constructor(host: Host, runner: Runner) {
    this.#host = host;
    this.#runner = runner;
  }

  /// What a workspace's status changing calls, and the names its status says.
  wireStatus(changed: (id: string) => void, names: NameOf): void {
    this.#statusChanged = changed;
    this.#names = names;
    for (const w of this.all()) this.#wire(w);
  }

  #wire(w: Workspace): void {
    const changed = this.#statusChanged;
    if (changed) w.status.onChange(() => changed(w.id));
    if (this.#names) w.status.setNames(this.#names);
  }

  get(id: string): Workspace | undefined {
    return this.#all.get(id);
  }

  /// The workspace `id`, made the first time.
  of(id: string): Workspace {
    let w = this.#all.get(id);
    if (w) return w;
    w = new Workspace(id, new Status(this.#host, this.#runner));
    this.#wire(w);
    this.#all.set(id, w);
    return w;
  }

  ofStation(address: string): Workspace {
    return this.of(ofAddress(address));
  }

  /// In id order (a BTreeMap in the Rust core).
  all(): Workspace[] {
    return [...this.#all.keys()].sort().map((k) => this.#all.get(k)!);
  }

  /// Which account reaches each workspace: those it names get theirs, every other one none.
  setOwners(owners: Map<string, string>): void {
    for (const [id, sub] of owners) this.of(id).owner = sub;
    for (const w of this.all()) if (!owners.has(w.id)) w.owner = null;
  }

  owner(id: string): string | null {
    return this.get(id)?.owner ?? null;
  }

  /// The workspaces an account reaches: [id, owner].
  owned(): [string, string][] {
    return this.all().flatMap((w) => (w.owner !== null ? [[w.id, w.owner] as [string, string]] : []));
  }
}
