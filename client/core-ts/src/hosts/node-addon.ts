// The iroh a Node host gives a program (iroh.ts): a native addon with these calls, loaded from where the program
// says it is (the still.fail core's: hosts/node-iroh.ts, the addon its station ships).
import { existsSync } from "node:fs";
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
  paths(): { id: string; selected: boolean; relay?: string | null; ip?: string | null; rttMs?: number | null; txPackets: number; lostPackets: number }[];
  stats(): { rxBytes: number; txBytes: number };
};
type NEndpoint = {
  id(): string;
  connect(addr: IrohAddr, alpn: Buffer, additional?: Buffer[]): Promise<NConnection>;
  accept(): Promise<(NConnection & { alpn(): Buffer }) | null>;
  addAddr(addr: IrohAddr): void;
  networkChange(): Promise<void>;
  relayStatus(): { url: string; connected: boolean }[];
  close(): Promise<void>;
};
export type Addon = { bind(options: { secretKey: Buffer; alpns: Buffer[]; relayUrls: string[]; relayEntries?: { entry: string; relay: string }[]; discovery?: boolean; lookup?: boolean; dht?: boolean; relayOnly?: boolean }): Promise<NEndpoint> };

/// The addon at the first of `paths` that is there (undefined: a place there is none to say); null where none is.
export function addonAt(paths: readonly (string | undefined)[]): Addon | null {
  const path = paths.find((p) => p !== undefined && existsSync(p));
  if (!path) return null;
  const module = { exports: {} as Addon };
  process.dlopen(module, path);
  return module.exports;
}

/// The iroh of an addon.
export function addonIroh(addon: Addon): Iroh {
  return wrapIroh(
    (o: BindOptions) =>
      addon.bind({ secretKey: Buffer.from(o.secretKey), alpns: (o.alpns ?? []).map((a) => Buffer.from(a)), relayUrls: o.relayUrls, ...(o.relayEntries ? { relayEntries: o.relayEntries } : {}), discovery: false, lookup: o.lookup, ...(o.dht === false ? { dht: false } : {}), relayOnly: o.relayOnly }) as Promise<BoundEndpoint>,
    (bytes) => Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength),
  );
}
