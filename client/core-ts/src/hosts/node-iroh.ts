// The iroh a Node host gives the core (iroh.ts): the native addon the station in TypeScript ships (station/native/mesh,
// `mesh.node`), which the client's endpoint shares. Where it is: STILLFAIL_MESH_NATIVE, beside the core's bundle
// (mesh.node), or where cargo built it in a checkout.
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { BindOptions, CloseReason, Iroh, IrohAddr } from "../iroh.ts";
import { type BoundEndpoint, wrapIroh } from "../iroh-bindings.ts";

type NStream = {
  read(): Promise<Buffer | null>;
  write(bytes: Buffer): Promise<void>;
  finish(): Promise<void>;
  stopped(): Promise<number | null | void>;
  reset?(code: number): Promise<void>;
};
type NConnection = {
  remoteId(): string;
  acceptBi(): Promise<NStream | null>;
  openBi(): Promise<NStream>;
  openUni(): Promise<NStream>;
  close(code: number, reason: string): void;
  closeReason(): CloseReason | null;
  closedInfo(): Promise<CloseReason>;
  paths(): { selected: boolean; relay?: string | null; rttMs: number }[];
  stats(): { rxBytes: number; txBytes: number; txPackets: number; lostPackets: number };
};
type NEndpoint = {
  id(): string;
  connect(addr: IrohAddr, alpn: Buffer, additional?: Buffer[]): Promise<NConnection>;
  addAddr(addr: IrohAddr): void;
  networkChange(): Promise<void>;
  relayStatus(): { url: string; connected: boolean }[];
  close(): Promise<void>;
};
type Addon = { bind(options: { secretKey: Buffer; alpns: Buffer[]; relayUrls: string[]; discovery?: boolean; lookup?: boolean; relayOnly?: boolean }): Promise<NEndpoint> };

let loaded: Addon | null | undefined;

/// The addon, if it is there.
export function loadAddon(): Addon | null {
  if (loaded !== undefined) return loaded;
  // In a CommonJS bundle (the desktop app's) there is no import.meta: there STILLFAIL_MESH_NATIVE says where it is.
  const here = typeof import.meta.url === "string" ? import.meta.url : null;
  const near = (path: string) => (here ? fileURLToPath(new URL(path, here)) : undefined);
  const candidates = [
    process.env.STILLFAIL_MESH_NATIVE,
    near("./mesh.node"),
    near("../../../../station/native/mesh/target/release/libstillfail_mesh.dylib"),
    near("../../../../station/native/mesh/target/release/libstillfail_mesh.so"),
  ];
  const path = candidates.find((p) => p !== undefined && existsSync(p));
  if (!path) {
    loaded = null;
    return null;
  }
  const module = { exports: {} as Addon };
  process.dlopen(module, path);
  loaded = module.exports;
  return loaded;
}

/// The iroh of the addon; null where there is none.
export function nodeIroh(): Iroh | null {
  const addon = loadAddon();
  if (addon === null) return null;
  return wrapIroh(
    (o: BindOptions) => addon.bind({ secretKey: Buffer.from(o.secretKey), alpns: [], relayUrls: o.relayUrls, discovery: false, lookup: o.lookup, relayOnly: o.relayOnly }) as Promise<BoundEndpoint>,
    (bytes) => Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength),
  );
}

/// A station-side endpoint for tests: accepts the client's ALPNs.
export function testStation(addon: Addon, secretKey: Uint8Array, alpns: Uint8Array[]) {
  return addon.bind({ secretKey: Buffer.from(secretKey), alpns: alpns.map((a) => Buffer.from(a)), relayUrls: [], discovery: false });
}
