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
  stopped(): Promise<void>;
  reset(code: number): Promise<void>;
};
export type Connection = {
  remoteId(): string;
  alpn(): Buffer;
  via(): string | null;
  acceptBi(): Promise<Stream | null>;
  openBi(): Promise<Stream>;
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
  accept(): Promise<Connection | null>;
  connect(addr: Addr, alpn: Buffer): Promise<Connection>;
  close(): Promise<void>;
};
export type Mesh = {
  bind(options: { secretKey: Buffer; alpns: Buffer[]; relayUrls: string[]; discovery?: boolean; bindAddr?: string }): Promise<Endpoint>;
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
};

/// Loaded once: the mesh (services.ts) and the thumbnails (sessions/thumbs.ts) share it.
let loaded: Mesh | undefined;

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
