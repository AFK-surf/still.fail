// The iroh a host binds (iroh.ts) from a binding's promises: station/native/mesh's napi addon on Node
// (hosts/node-iroh.ts), client/iroh-wasm in a browser (hosts/web.ts). Both have the same calls; this makes them the
// core's Effects.
import { Effect } from "effect";
import { HostError } from "./error.ts";
import type { BindOptions, CloseReason, Iroh, IrohAddr, IrohConnection, IrohEndpoint, IrohStream } from "./iroh.ts";

export type BoundStream = {
  read(): Promise<Uint8Array | null>;
  write(bytes: never): Promise<void>;
  finish(): Promise<void>;
  stopped(): Promise<number | null | void>;
  reset?(code: number): Promise<void> | void;
};
export type BoundConnection = {
  remoteId(): string;
  acceptBi(): Promise<BoundStream | null>;
  openBi(): Promise<BoundStream>;
  openUni(): Promise<BoundStream>;
  close(code: number, reason: string): void;
  closeReason(): CloseReason | null | undefined;
  closedInfo(): Promise<CloseReason>;
  paths(): { id: string; selected: boolean; relay?: string | null; ip?: string | null; rttMs?: number | null; txPackets: number; lostPackets: number }[];
  stats(): { rxBytes: number; txBytes: number };
};
export type BoundEndpoint = {
  id(): string;
  connect(addr: IrohAddr, alpn: never, additional: never[]): Promise<BoundConnection>;
  /// The addon's alone (iroh-wasm takes no connections): the next one coming, its handshake done, and the ALPN agreed.
  accept?(): Promise<(BoundConnection & { alpn(): Uint8Array }) | null>;
  addAddr(addr: IrohAddr): void;
  networkChange(): Promise<void>;
  relayStatus(): { url: string; connected: boolean; access?: string }[];
  setRelayEntries?(entries: { entry: string; relay: string }[]): Promise<void>;
  close(): Promise<void>;
};

const host = (e: unknown) => new HostError(e instanceof Error ? e.message : String(e));
const call = <A>(f: () => Promise<A>): Effect.Effect<A, HostError> => Effect.tryPromise({ try: f, catch: host });
/// The binding's bytes (a Buffer) as plain ones, not copied.
const view = (b: Uint8Array) => new Uint8Array(b.buffer, b.byteOffset, b.byteLength);

/// The path's relay is its logical server; show the address actually carrying that server's connection.
export function accessOf(relay: string | null, statuses: { url: string; access?: string }[]): string | null {
  if (relay === null) return null;
  const key = (url: string) => {
    try { return new URL(url).href; } catch { return url; }
  };
  return statuses.find((s) => key(s.url) === key(relay))?.access ?? relay;
}

/// `bind` the binding's; `bytes` makes bytes as it takes them (Node's addon: a Buffer).
export function wrapIroh(bind: (o: BindOptions) => Promise<BoundEndpoint>, bytes: (b: Uint8Array) => unknown): Iroh {
  const out = (b: Uint8Array) => bytes(b) as never;
  const stream = (s: BoundStream): IrohStream => ({
    read: () =>
      call(async () => {
        const b = await s.read();
        return b === null || b === undefined ? null : view(b);
      }),
    write: (b) => call(() => s.write(out(b))),
    finish: () => call(() => s.finish()),
    stopped: () =>
      call(async () => {
        const code = await s.stopped();
        return typeof code === "number" ? code : null;
      }),
    reset: (code) => void Promise.resolve(s.reset?.(code)).catch(() => {}),
  });
  const connection = (c: BoundConnection, e: BoundEndpoint): IrohConnection => ({
    remoteId: () => c.remoteId(),
    openBi: () => Effect.map(call(() => c.openBi()), stream),
    acceptBi: () => Effect.orElseSucceed(Effect.map(call(() => c.acceptBi()), (s) => (s === null ? null : stream(s))), () => null),
    openUni: () => Effect.map(call(() => c.openUni()), stream),
    close: (code, reason) => c.close(code, reason),
    closeReason: () => c.closeReason() ?? null,
    closed: () => Effect.promise(() => c.closedInfo()),
    paths: () => {
      const statuses = e.relayStatus();
      return c.paths().map((p) => ({ id: p.id, selected: p.selected, relay: accessOf(p.relay ?? null, statuses), ip: p.ip ?? null, rttMs: p.rttMs ?? null, txPackets: p.txPackets, lostPackets: p.lostPackets }));
    },
    stats: () => c.stats(),
  });
  const endpoint = (e: BoundEndpoint): IrohEndpoint => {
    const accept = e.accept?.bind(e);
    return {
      id: () => e.id(),
      connect: (addr, alpn, additional) => Effect.map(call(() => e.connect(addr, out(alpn), additional.map(out))), (c) => connection(c, e)),
      // Only where the binding takes connections: a host without has no `accept` (iroh.ts).
      ...(accept && {
        accept: () => Effect.orElseSucceed(Effect.map(call(accept), (c) => (c === null ? null : { connection: connection(c, e), alpn: view(c.alpn()) })), () => null),
      }),
      addAddr: (addr) => e.addAddr(addr),
      networkChange: () => Effect.promise(() => e.networkChange()),
      relayStatus: () => e.relayStatus(),
      ...(e.setRelayEntries && { setRelayEntries: (entries: { entry: string; relay: string }[]) => call(() => e.setRelayEntries!(entries)) }),
      close: () => Effect.promise(() => e.close()),
    };
  };
  return { bind: (o) => Effect.map(call(() => bind(o)), endpoint) };
}
