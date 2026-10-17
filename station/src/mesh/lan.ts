// Where a device on the station's LAN can dial it straight (docs/mesh-lan.md): the station's private IPv4 addresses, each
// at its mesh port. Told to a member as its credential checks out (serve.ts), the device dials them on an endpoint of its
// own, by address alone: a path iroh punches through to a station on the LAN stopped answering seconds after it opened
// (studio and a phone, 2026-10-17), one dialled by address kept working.
import { networkInterfaces, type NetworkInterfaceInfo } from "node:os";

/// Interfaces no device on the LAN reaches the station through: VM and container bridges (OrbStack's own 192.168.139.x
/// on two Macs at once), tunnels, Apple's peer-to-peer links.
const NOT_LAN = /^(bridge|utun|vmnet|vboxnet|docker|veth|br-|llw|awdl|anpi|ap\d|gif|stf|lo)/;

/// Whether `ip` is a private IPv4 address (RFC 1918).
export function privateV4(ip: string): boolean {
  const o = ip.split(".").map(Number);
  if (o.length !== 4 || o.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return false;
  return o[0] === 10 || (o[0] === 172 && o[1]! >= 16 && o[1]! <= 31) || (o[0] === 192 && o[1] === 168);
}

/// `ip:port` of each private IPv4 address the station has on a LAN interface, at the port of its IPv4 socket (`sockets`,
/// as the endpoint gives them); none when that socket is not at an address of every interface (`0.0.0.0`) or a fixed one.
export function lanAddrs(sockets: string[], interfaces: NodeJS.Dict<NetworkInterfaceInfo[]> = networkInterfaces()): string[] {
  const v4 = sockets.map((s) => /^(\d+\.\d+\.\d+\.\d+):(\d+)$/.exec(s)).find((m) => m !== null);
  if (!v4) return [];
  const [, bound, port] = v4;
  const out: string[] = [];
  for (const [name, addrs] of Object.entries(interfaces)) {
    if (NOT_LAN.test(name)) continue;
    for (const a of addrs ?? []) {
      if (a.family !== "IPv4" || a.internal || !privateV4(a.address)) continue;
      if (bound !== "0.0.0.0" && bound !== a.address) continue;
      out.push(`${a.address}:${port}`);
    }
  }
  return [...new Set(out)];
}
