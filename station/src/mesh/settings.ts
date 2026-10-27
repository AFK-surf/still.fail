// Advanced mesh settings, read when the station starts. An absent choice keeps the stable default.
export type Congestion = "cubic" | "bbr";
export function congestionOf(raw: any): Congestion {
  return raw?.network?.congestion === "bbr" ? "bbr" : "cubic";
}
export function checkNetwork(raw: any): void {
  if (raw === undefined || raw === null) return;
  if (typeof raw !== "object" || Array.isArray(raw)) throw new Error("network: expected an object");
  if (raw.congestion !== undefined && raw.congestion !== "cubic" && raw.congestion !== "bbr") throw new Error("network.congestion: expected cubic or bbr");
}
export const networkView = (raw: any) => ({ congestion: congestionOf(raw) });
