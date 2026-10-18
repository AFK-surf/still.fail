// macOS's Local Network for the app (docs/mesh-lan.md): whether it may reach the LAN it is on, and a station's LAN
// addresses, sending a byte to each (station/src/mesh/lan.ts). Not let, macOS refuses anything on the app's own subnet at
// once, and the core (its utility process, the app's) dials a station on its LAN only past the router or over a relay:
// on 2026-10-18 a MacBook on studio's Wi-Fi reached studio at its other subnet's address (12 ms, a fifth of the packets
// lost) and mini1 over Tailscale. Elsewhere there is no such thing: `unknown`, never kept.
import { lanKept, lanReach } from "../../../station/src/mesh/lan.ts";

export type LocalNetwork = "granted" | "denied" | "unknown";

export async function localNetwork(): Promise<LocalNetwork> {
  if (process.platform !== "darwin") return "unknown";
  return (await lanReach().catch(() => null)) ?? "unknown";
}

/// Whether macOS keeps the app from a station at `addrs` (its LAN addresses).
export async function kept(addrs: string[]): Promise<boolean> {
  if (process.platform !== "darwin") return false;
  return lanKept(addrs).catch(() => false);
}
