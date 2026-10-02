// The native mesh addon (native/mesh, docs/station-ts-native.md §3): what it offers, and where it is. A release has it
// beside the station's code (mesh.node); a checkout has it where cargo built it; STILLFAIL_MESH_NATIVE says otherwise.
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
};

export function loadMesh(): Mesh {
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
  return module.exports;
}
