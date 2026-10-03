// The iroh surface a host gives the core (docs/core-ts.md, Hosts): an endpoint bound with a key, connections to
// stations, their streams, how each runs. Node has it from the native addon (station/native/mesh, hosts/node-iroh.ts);
// the browser from iroh's wasm build (relay only); Android from its JNI shell. The mesh (mesh.ts) is the core's own
// logic over it: links, credentials, renewals, races, measurements.
import type { Effect } from "effect";
import type { HostError } from "./error.ts";

/// Where an endpoint is: its id (hex), the relays it may be on, the addresses it may be at (`ip:port`).
export type IrohAddr = { id: string; relays?: string[]; ips?: string[] };

/// Why a connection went: the other end closed it saying `reason` (`application`), this end did (`local`), nothing was
/// heard (`timeout`), or something else (`other`, `reason` in words).
export type CloseReason = { kind: "application" | "local" | "timeout" | "other"; reason: string };

/// One way a connection can go now: through a relay (its URL) or direct; whether it is the one chosen, its round trip.
export type IrohPath = { selected: boolean; relay: string | null; rttMs: number };

/// What went over a connection since it opened.
export type IrohStats = { rxBytes: number; txBytes: number; txPackets: number; lostPackets: number };

/// A stream both ways (or one way: `read` then answers null at once).
export interface IrohStream {
  /// What came next; null at its end.
  read(): Effect.Effect<Uint8Array | null, HostError>;
  write(bytes: Uint8Array): Effect.Effect<void, HostError>;
  /// Nothing more goes out on it.
  finish(): Effect.Effect<void, HostError>;
  /// Once what was sent is acknowledged: null, or the code the other end stopped it with.
  stopped(): Effect.Effect<number | null, HostError>;
  /// Ends it at once, both ways.
  reset(code: number): void;
}

export interface IrohConnection {
  remoteId(): string;
  openBi(): Effect.Effect<IrohStream, HostError>;
  /// The next stream the other end opened; null once the connection is gone.
  acceptBi(): Effect.Effect<IrohStream | null>;
  openUni(): Effect.Effect<IrohStream, HostError>;
  close(code: number, reason: string): void;
  closeReason(): CloseReason | null;
  /// Succeeds when it is gone, with why.
  closed(): Effect.Effect<CloseReason>;
  paths(): IrohPath[];
  stats(): IrohStats;
}

export interface IrohEndpoint {
  /// Its id (hex): the public half of its key.
  id(): string;
  /// A connection offering `alpn` (and the `additional` ones, for a station from before a rename).
  connect(addr: IrohAddr, alpn: Uint8Array, additional: Uint8Array[]): Effect.Effect<IrohConnection, HostError>;
  /// Where an endpoint is, without looking it up (tests, a LAN with no relay).
  addAddr(addr: IrohAddr): void;
  /// The network changed: its sockets and relay connection looked at anew.
  networkChange(): Effect.Effect<void>;
  /// Its home relays, and whether it is connected to each now.
  relayStatus(): { url: string; connected: boolean }[];
  close(): Effect.Effect<void>;
}

export type BindOptions = {
  /// 32 bytes.
  secretKey: Uint8Array;
  /// still.fail's relays, its own first; none: relays off (tests on one machine).
  relayUrls: string[];
  /// Look stations up on the LAN and in the DHT (a client's: not announced itself).
  lookup: boolean;
  /// Relays alone, no IP transports (what measures a relay's way must not go direct).
  relayOnly: boolean;
};

export interface Iroh {
  bind(options: BindOptions): Effect.Effect<IrohEndpoint, HostError>;
}
