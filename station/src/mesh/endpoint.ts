// A mesh endpoint as the native addon gives it (native/mesh, iroh): binding one, its connections and their streams, and
// loading the addon from where it is said to be. All a program served by the wire and the door needs of the addon:
// whose addon it is, where that program keeps it and what else it offers (the station's: native.ts) are not here.
// scripts/mesh-base.ts keeps it so.
import { existsSync } from "node:fs";

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
  /// Where the endpoint is kept by a program of its own (front.ts): its id of this connection, which the streams it
  /// hands what answers a route (`Endpoint.route`) name it by.
  handed?: number;
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
  /// `additional`: protocols offered after `alpn` (the connection's `alpn()` says which one it speaks). `givenUp`:
  /// once it resolves, the handshake is given up (lib.rs `dial`); an addon from before goes on with it.
  connect(addr: Addr, alpn: Buffer, additional?: Buffer[], givenUp?: Promise<void>): Promise<Connection>;
  close(): Promise<void>;
  /// The requests asked on a stream after a connection's first, on a connection of protocol `alpn`, whose route (`"GET /path"`, the head line's method and
  /// path without its query) is among `routes` go to the Unix sockets at `to` in turn instead of `accept`'s connections,
  /// on the connections taken from now on (a stream's, not this process's: its acceptBi does not give them). Where the
  /// endpoint is kept by a program of its own (front.ts), and only one that does it.
  route?(alpn: Buffer, to: string[], routes: string[]): Promise<boolean>;
};
/// What an endpoint is bound with. `relayOnly`: through the relays alone, no IP transports (what measures the way
/// through a relay).
export type Bind = { secretKey: Buffer; alpns: Buffer[]; relayUrls: string[]; discovery?: boolean; bindAddr?: string; relayOnly?: boolean; congestion?: "cubic" | "bbr" };
/// What binds endpoints: the addon, or what stands in for it (a test's mesh in memory).
export type Endpoints = { bind(options: Bind): Promise<Endpoint> };

/// The addon at the first of `candidates` that is there (one not said, undefined or empty, is not looked at), loaded:
/// what it exports, which is `Endpoints` and whatever more the caller knows its addon to offer. Each call loads it;
/// who shares one keeps what this gave.
export function loadAddon<A extends Endpoints = Endpoints>(candidates: (string | undefined)[]): A {
  const path = candidates.find((p) => p && existsSync(p)); // sync: once, as the addon is first loaded
  if (!path) throw new Error(`the mesh addon is not there (looked at ${candidates.filter(Boolean).join(", ")})`);
  const module = { exports: {} as A };
  process.dlopen(module, path);
  return module.exports;
}
