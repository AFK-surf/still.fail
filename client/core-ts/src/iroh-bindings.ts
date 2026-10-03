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
  paths(): { selected: boolean; relay?: string | null; rttMs: number }[];
  stats(): { rxBytes: number; txBytes: number; txPackets: number; lostPackets: number };
};
export type BoundEndpoint = {
  id(): string;
  connect(addr: IrohAddr, alpn: never, additional: never[]): Promise<BoundConnection>;
  addAddr(addr: IrohAddr): void;
  networkChange(): Promise<void>;
  relayStatus(): { url: string; connected: boolean }[];
  close(): Promise<void>;
};

const host = (e: unknown) => new HostError(e instanceof Error ? e.message : String(e));
const call = <A>(f: () => Promise<A>): Effect.Effect<A, HostError> => Effect.tryPromise({ try: f, catch: host });

/// `bind` the binding's; `bytes` makes bytes as it takes them (Node's addon: a Buffer).
export function wrapIroh(bind: (o: BindOptions) => Promise<BoundEndpoint>, bytes: (b: Uint8Array) => unknown): Iroh {
  const out = (b: Uint8Array) => bytes(b) as never;
  const stream = (s: BoundStream): IrohStream => ({
    read: () =>
      call(async () => {
        const b = await s.read();
        return b === null || b === undefined ? null : new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
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
  const connection = (c: BoundConnection): IrohConnection => ({
    remoteId: () => c.remoteId(),
    openBi: () => Effect.map(call(() => c.openBi()), stream),
    acceptBi: () => Effect.orElseSucceed(Effect.map(call(() => c.acceptBi()), (s) => (s === null ? null : stream(s))), () => null),
    openUni: () => Effect.map(call(() => c.openUni()), stream),
    close: (code, reason) => c.close(code, reason),
    closeReason: () => c.closeReason() ?? null,
    closed: () => Effect.promise(() => c.closedInfo()),
    paths: () => c.paths().map((p) => ({ selected: p.selected, relay: p.relay ?? null, rttMs: p.rttMs })),
    stats: () => c.stats(),
  });
  const endpoint = (e: BoundEndpoint): IrohEndpoint => ({
    id: () => e.id(),
    connect: (addr, alpn, additional) => Effect.map(call(() => e.connect(addr, out(alpn), additional.map(out))), connection),
    addAddr: (addr) => e.addAddr(addr),
    networkChange: () => Effect.promise(() => e.networkChange()),
    relayStatus: () => e.relayStatus(),
    close: () => Effect.promise(() => e.close()),
  });
  return { bind: (o) => Effect.map(call(() => bind(o)), endpoint) };
}
