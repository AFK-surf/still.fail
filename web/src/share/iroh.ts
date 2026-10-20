// A visit to a station from the share page: iroh's wasm build (client/iroh-wasm, the same the web core binds:
// hosts/web.ts) on the page itself, relay only, with a key of its own made for the visit and dropped after it, so the
// station knows nothing of who reads. Connected on ALPN `stillfail/guest/1`; what goes over it is guest.ts's. A visit
// is closed as soon as it has read what it came for (the relays are everyone's).
import initIroh, * as iroh from "../core/iroh-pkg/stillfail_iroh_wasm.js";
import type { BoundConnection, BoundEndpoint } from "../../../client/core-ts/src/iroh-bindings.ts";
import type { GuestConnection } from "./guest.ts";

const GUEST_ALPN = new TextEncoder().encode("stillfail/guest/1");
/** How long a station is given to answer before it is taken for offline (the core waits as long for a link). */
const CONNECT_MS = 20_000;

let loaded: Promise<typeof iroh> | null = null;
const load = () => (loaded ??= initIroh().then(() => iroh));

/** The station could not be reached: offline, or not on these relays, or from before the guest ALPN. */
export class Unreachable extends Error {}

export type Visit = { conn: GuestConnection; close(): Promise<void> };

/** A visit to the station (`station`, its id in hex) through `relays`. */
export async function visit(station: string, relays: string[]): Promise<Visit> {
  const module = await load();
  const endpoint = (await module.bind({ secretKey: crypto.getRandomValues(new Uint8Array(32)), relayUrls: relays })) as BoundEndpoint;
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const conn = await Promise.race([
      endpoint.connect({ id: station, relays }, GUEST_ALPN as never, []),
      new Promise<never>((_, fail) => { timer = setTimeout(() => fail(new Error("no answer")), CONNECT_MS); }),
    ]);
    return { conn: guest(conn), close: async () => { conn.close(0, "read"); await endpoint.close(); } };
  } catch (e) {
    // A connection made after all goes with the endpoint.
    void endpoint.close();
    throw new Unreachable(e instanceof Error ? e.message : String(e));
  } finally {
    clearTimeout(timer);
  }
}

function guest(conn: BoundConnection): GuestConnection {
  return {
    openBi: async () => {
      const s = await conn.openBi();
      return {
        read: async () => {
          const b = await s.read();
          return b === null || b === undefined ? null : new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
        },
        write: (bytes) => s.write(bytes as never),
        finish: () => s.finish(),
      };
    },
  };
}
