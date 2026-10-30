// The native mesh addon (native/mesh, docs/station-ts-native.md §3): what it offers (iroh, and the image codecs of the
// thumbnails), and where it is. A release has it beside the station's code (mesh.node); a checkout has it where cargo
// built it; STILLFAIL_MESH_NATIVE says otherwise.
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

export type Addr = { id: string; relays?: string[]; ips?: string[] };
export type Stream = {
  read(): Promise<Buffer | null>;
  write(bytes: Buffer): Promise<void>;
  finish(): Promise<void>;
  /// Once what was sent is acknowledged: null, or the code the other end stopped reading with (an addon from before
  /// 2026-10-28: nothing).
  stopped(): Promise<number | null | void>;
  reset(code: number): Promise<void>;
};
/// What went over a connection since it opened (native/mesh `Stats`): bytes; and from the addon of 2026-10-19 on,
/// packets and the frames in them, those that carry nothing (pings, ACK requests, ACKs) and those that carry data.
export type Traffic = {
  rxBytes: number;
  txBytes: number;
  rxPackets?: number;
  txPackets?: number;
  rxPings?: number;
  txPings?: number;
  rxAckRequests?: number;
  txAckRequests?: number;
  rxAcks?: number;
  txAcks?: number;
  rxData?: number;
  txData?: number;
};
export type Connection = {
  remoteId(): string;
  alpn(): Buffer;
  via(): string | null;
  /// Every way it can go now (the native connection's; a test's may have none).
  paths?(): { selected: boolean; relay?: string | null; ip?: string | null; rttMs?: number | null; txPackets: number; lostPackets: number; cwnd?: number; congestionEvents?: number }[];
  acceptBi(): Promise<Stream | null>;
  openBi(): Promise<Stream>;
  /// Whether the other end is still there: true once anything is heard from it within `withinMs` (superseded.ts).
  /// A mesh addon from before it has none.
  answers?(withinMs: number): Promise<boolean>;
  /// What went over it (a test's may have none).
  stats?(): Traffic;
  close(code: number, reason: string): void;
  isClosed(): boolean;
  closed(): Promise<string>;
};
export type Endpoint = {
  id(): string;
  sockets(): string[];
  online(): Promise<void>;
  home(): string | null;
  insertRelay(url: string): Promise<void>;
  removeRelay(url: string): Promise<void>;
  publicRelays(on: boolean): Promise<void>;
  keep(urls: string[]): void;
  /// The advanced network setting changed while running (lib.rs): the controller of the connections made from now
  /// on. Absent from an addon from before.
  setCongestion?(congestion: "cubic" | "bbr"): void;
  accept(): Promise<Connection | null>;
  /// `additional`: protocols offered after `alpn` (the connection's `alpn()` says which one it speaks).
  connect(addr: Addr, alpn: Buffer, additional?: Buffer[]): Promise<Connection>;
  close(): Promise<void>;
};
export type Mesh = {
  /// `relayOnly`: through the relays alone, no IP transports (what measures the way through a relay).
  bind(options: { secretKey: Buffer; alpns: Buffer[]; relayUrls: string[]; discovery?: boolean; bindAddr?: string; relayOnly?: boolean; congestion?: "cubic" | "bbr" }): Promise<Endpoint>;
  /// thumbs.rs `thumbnail` (native/mesh/src/thumbs.rs): the image's thumbnail in `dir`, made if not there yet; null when
  /// the image is shown itself.
  thumbnail(image: string, dir: string): Promise<{ path: string; type: string } | null>;
  /// thumbs.rs `keep` for one image: its ThumbHash (base64) and its size as seen; with `dir`, its thumbnail made after
  /// (not waited for) when it is over 24 KiB. Null when it is not readable as an image.
  thumbhash(image: string, dir?: string | null): Promise<{ hash: string; width: number; height: number } | null>;
  /// archive.rs `file_lock` (native/mesh/src/local.rs): an exclusive flock on the file, across processes.
  fileLock(path: string): Promise<{ release(): void }>;
  /// local_links.rs `prepare`: the text with local links made attachments, and the attachments' paths; throws its refusal.
  prepareLocalLinks(text: string, paths: string[], workspace: string): { text: string; paths: string[] };
  /// usage.rs `process_usage`: what each pid has used so far, null where not read. Absent from an addon from before.
  /// local.rs `peer_process`: the process at the other end of a connected Unix socket (its pid; on macOS its audit token,
  /// hex), null when the system does not say. Absent from an addon from before.
  peerProcess?(fd: number): { pid: number; auditToken: string | null } | null;
  processUsage?(pids: number[]): ({ cpuNs: number; footprint: number; wakeups: number; energyNj: number; diskRead?: number; diskWritten?: number } | null)[];
};

/// Loaded once: the mesh (services.ts) and the thumbnails (drive/thumbs.ts) share it.
let loaded: Mesh | undefined;

/// A fixed UDP address lets an operator admit LAN connections through an egress firewall. The native bind rejects
/// invalid or occupied addresses; never fall back to a random port when an address was explicitly configured.
export function bindStation(mesh: Mesh, options: Parameters<Mesh["bind"]>[0], env: NodeJS.ProcessEnv = process.env): Promise<Endpoint> {
  return mesh.bind({ ...options, bindAddr: env.STILLFAIL_MESH_BIND_ADDR });
}

export function loadMesh(): Mesh {
  if (loaded !== undefined) return loaded;
  const candidates = [
    process.env.STILLFAIL_MESH_NATIVE,
    fileURLToPath(new URL("./mesh.node", import.meta.url)),
    fileURLToPath(new URL("../../native/mesh/target/release/libstillfail_mesh.dylib", import.meta.url)),
    fileURLToPath(new URL("../../native/mesh/target/release/libstillfail_mesh.so", import.meta.url)),
  ];
  const path = candidates.find((p) => p && existsSync(p));
  if (!path) throw new Error(`the mesh addon is not there (looked at ${candidates.filter(Boolean).join(", ")})`);
  const module = { exports: {} as Mesh };
  process.dlopen(module, path);
  loaded = module.exports;
  return loaded;
}
