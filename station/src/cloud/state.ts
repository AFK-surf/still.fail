// Where the station stands with still.fail cloud: <data>/mesh/cloud.json (its fields, mode and pretty JSON as the Rust
// station writes them: the desktop app and `bin/stillfail` read it too). One copy in memory, written through on every
// change and told to whoever listens; the file is watched only for `enroll` writing it from another process.
import { existsSync, readFileSync, watch } from "node:fs";
import { join } from "node:path";
import { writePrivate } from "../ops/files.ts";

export type Revocation = { kind: string; id: string; at: number };

export type CloudState = {
  origin: string;
  station: string;
  workspace: string;
  workspace_name: string;
  name: string;
  relay_url: string;
  /// Every relay, still.fail's (`relay_url`) first; missing from files of before there were several.
  relay_urls: string[];
  grant_keys: any;
  /// The workspace's stations this one may call (peer RPC); none from old clouds.
  peers: any[];
  revocations: Revocation[];
  /// When the cloud said the station was removed from its workspace (unix seconds), and how (4004 / 404).
  removed_at?: number;
  removed_code?: number;
};

export const meshDir = (data: string) => join(data, "mesh");
const statePath = (data: string) => join(meshDir(data), "cloud.json");

/// The state as the file has it, its optional parts filled as the Rust station's serde defaults fill them.
export function readState(data: string): CloudState | null {
  if (!existsSync(statePath(data))) return null;
  const raw = JSON.parse(readFileSync(statePath(data), "utf8"));
  return { ...raw, relay_urls: raw.relay_urls ?? [], peers: raw.peers ?? [], revocations: raw.revocations ?? [] };
}

/// Pretty JSON, field order as the Rust struct's, the removal only while there is one.
export function writeState(data: string, s: CloudState) {
  const out: Record<string, unknown> = {
    origin: s.origin, station: s.station, workspace: s.workspace, workspace_name: s.workspace_name, name: s.name,
    relay_url: s.relay_url, relay_urls: s.relay_urls, grant_keys: s.grant_keys, peers: s.peers, revocations: s.revocations,
  };
  if (s.removed_at !== undefined) out.removed_at = s.removed_at;
  if (s.removed_code !== undefined) out.removed_code = s.removed_code;
  writePrivate(statePath(data), JSON.stringify(out, null, 2));
}

/// The state in memory, and who wants to hear of its changes.
export class Cloud {
  state: CloudState | null;
  /// Whether `peers` is the cloud's roster as of the current presence socket (fail closed until a `state` frame says so).
  peersCurrent = false;
  private listeners = new Set<(s: CloudState | null) => void>();
  private writing = false;
  readonly data: string;

  constructor(data: string) {
    this.data = data;
    this.state = readState(data);
    // `enroll` from another process, or an older tool editing the file.
    try {
      watch(meshDir(data), { persistent: false }, (_, name) => {
        if (name === "cloud.json" && !this.writing) this.reload();
      });
    } catch {
      // No mesh directory yet: `enroll` makes it, and the station is started anew after.
    }
  }

  reload() {
    const next = readState(this.data);
    if (JSON.stringify(next) !== JSON.stringify(this.state)) {
      this.state = next;
      this.tell();
    }
  }

  /// Changes the state, writes it, tells the listeners.
  update(change: (s: CloudState) => void) {
    if (!this.state) return;
    change(this.state);
    this.writing = true;
    try {
      writeState(this.data, this.state);
    } finally {
      setTimeout(() => (this.writing = false), 100);
    }
    this.tell();
  }

  removed(): boolean {
    return this.state?.removed_at !== undefined;
  }

  /// still.fail's relays, ours first, as `relays()` in the Rust station: `relay_urls`, else `relay_url`; what is no URL
  /// left out.
  relays(): string[] {
    const s = this.state;
    if (!s) return [];
    return (s.relay_urls.length > 0 ? s.relay_urls : [s.relay_url]).filter((u) => URL.canParse(u));
  }

  listen(f: (s: CloudState | null) => void): () => void {
    this.listeners.add(f);
    return () => this.listeners.delete(f);
  }

  private tell() {
    for (const f of this.listeners) f(this.state);
  }
}
