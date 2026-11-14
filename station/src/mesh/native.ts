// The station's native mesh addon (native/mesh §3): what it offers besides the endpoint (endpoint.ts: iroh), which is
// the image codecs of the thumbnails and the rest below, and where it is. A release has it beside the station's code
// (mesh.node); a checkout has it where cargo built it; STILLFAIL_MESH_NATIVE says otherwise.
import { fileURLToPath } from "node:url";
import { type Bind, type Endpoint, type Endpoints, loadAddon } from "./endpoint.ts";

export type { Addr, Connection, Endpoint, Stream, Traffic } from "./endpoint.ts";

export type Mesh = Endpoints & {
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
  /// verify.rs `verify`: whether the signature is the key's over the message, by libcrux (formally verified). Absent from
  /// an addon from before.
  verify?(alg: "Ed25519" | "ES256" | "ES256-der", key: Buffer, signature: Buffer, message: Buffer): boolean;
  processUsage?(pids: number[]): ({ cpuNs: number; footprint: number; wakeups: number; energyNj: number; diskRead?: number; diskWritten?: number } | null)[];
};

/// Loaded once: the mesh (services.ts) and the thumbnails (drive/thumbs.ts) share it.
let loaded: Mesh | undefined;

/// A fixed UDP address lets an operator admit LAN connections through an egress firewall. The native bind rejects
/// invalid or occupied addresses; never fall back to a random port when an address was explicitly configured.
export function bindStation(mesh: Endpoints, options: Bind, env: NodeJS.ProcessEnv = process.env): Promise<Endpoint> {
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
  loaded = loadAddon<Mesh>(candidates);
  return loaded;
}
