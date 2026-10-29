// Advanced mesh settings, read when the station starts. An absent choice keeps the stable default.
export type Congestion = "cubic" | "bbr";
export function congestionOf(raw: any): Congestion {
  return raw?.network?.congestion === "bbr" ? "bbr" : "cubic";
}
/// Whether the station asks its relays for their UDP way (iroh's `relay_udp`): off unless turned on.
export function relayUdpOf(raw: any): boolean {
  return raw?.network?.relayUdp === true;
}
export function checkNetwork(raw: any): void {
  if (raw === undefined || raw === null) return;
  if (typeof raw !== "object" || Array.isArray(raw)) throw new Error("network: expected an object");
  if (raw.congestion !== undefined && raw.congestion !== "cubic" && raw.congestion !== "bbr") throw new Error("network.congestion: expected cubic or bbr");
  if (raw.relayUdp !== undefined && typeof raw.relayUdp !== "boolean") throw new Error("network.relayUdp: expected a boolean");
}
export const networkView = (raw: any) => ({ congestion: congestionOf(raw), relayUdp: relayUdpOf(raw) });
