// Where a device on the station's LAN can dial it straight (docs/mesh-lan.md): the station's private IPv4 addresses, each
// at its mesh port. Told to a member as its credential checks out (serve.ts), the device dials them on an endpoint of its
// own, by address alone: a path iroh punches through to a station on the LAN stopped answering seconds after it opened
// (studio and a phone, 2026-10-17), one dialled by address kept working.
import { createSocket } from "node:dgram";
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

/// Whether `ip` is in Tailscale's IPv4 range (100.64.0.0/10, the shared address space it gives each machine of a tailnet).
export function tailnetV4(ip: string): boolean {
  const o = ip.split(".").map(Number);
  if (o.length !== 4 || o.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return false;
  return o[0] === 100 && o[1]! >= 64 && o[1]! <= 127;
}

/// `ip:port` of each Tailscale address the station has, at the port of its IPv4 socket (as `lanAddrs`): where a device
/// on the same tailnet dials it straight, Tailscale carrying it (docs/mesh-lan.md, Tailscale). Known by the address,
/// not the interface: Tailscale's is utun on macOS, tailscale0 on Linux, its own name on Windows.
export function tailnetAddrs(sockets: string[], interfaces: NodeJS.Dict<NetworkInterfaceInfo[]> = networkInterfaces()): string[] {
  const v4 = sockets.map((s) => /^(\d+\.\d+\.\d+\.\d+):(\d+)$/.exec(s)).find((m) => m !== null);
  if (!v4) return [];
  const [, bound, port] = v4;
  const out: string[] = [];
  for (const addrs of Object.values(interfaces)) {
    for (const a of addrs ?? []) {
      if (a.family !== "IPv4" || a.internal || !tailnetV4(a.address)) continue;
      if (bound !== "0.0.0.0" && bound !== a.address) continue;
      out.push(`${a.address}:${port}`);
    }
  }
  return [...new Set(out)];
}

const v4 =(ip: string) => ip.split(".").reduce((n, o) => (n * 256 + Number(o)) >>> 0, 0);
const dotted = (n: number) => [24, 16, 8, 0].map((s) => (n >>> s) & 255).join(".");

/// An address on each LAN the station is on, not its own: the subnet's first (its router, as a rule).
export function lanNeighbours(interfaces: NodeJS.Dict<NetworkInterfaceInfo[]> = networkInterfaces()): string[] {
  const out: string[] = [];
  for (const [name, addrs] of Object.entries(interfaces)) {
    if (NOT_LAN.test(name)) continue;
    for (const a of addrs ?? []) {
      if (a.family !== "IPv4" || a.internal || !privateV4(a.address) || !a.netmask) continue;
      const first = ((v4(a.address) & v4(a.netmask)) >>> 0) + 1;
      out.push(dotted(dotted(first) === a.address ? first + 1 : first));
    }
  }
  return [...new Set(out)];
}

/// Sends one byte to `ip`'s discard port: null once it is sent, else the error's code.
export function sendOne(ip: string): Promise<string | null> {
  return new Promise((resolve) => {
    const socket = createSocket("udp4");
    let done = false;
    const end = (e: Error | null | undefined) => {
      if (done) return;
      done = true;
      socket.close();
      resolve(e ? ((e as NodeJS.ErrnoException).code ?? "error") : null);
    };
    socket.on("error", end);
    socket.send(Buffer.alloc(1), 9, ip, end);
  });
}

/// Whether this process may reach the LAN it is on. macOS (15 on) refuses a process whose app was not let reach the
/// local network anything on its own subnet, the router too, at once ("No route to host", EHOSTUNREACH), and lets
/// through what goes past the router: on 2026-10-18 the desktop app on a MacBook on studio's Wi-Fi reached studio only at
/// its other subnet's address through the router (12 ms, a fifth of the packets lost) and mini1 only over Tailscale, and
/// its station could not ping the router. A firewall refusing the LAN (ccvm's) is told the same. `granted` once one of
/// its LANs takes a byte, `denied` when each refused it so, null with no LAN (or none of either).
export async function lanReach(neighbours = lanNeighbours(), send: (ip: string) => Promise<string | null> = sendOne): Promise<"granted" | "denied" | null> {
  const said = await Promise.all(neighbours.map(send));
  if (said.some((e) => e === null)) return "granted";
  return said.length > 0 && said.every((e) => e === "EHOSTUNREACH") ? "denied" : null;
}

/// System Settings' Local Network list, where an app is let reach the LAN (macOS asks once, as the app first reaches it;
/// refused then, it is switched on there).
export const LOCAL_NETWORK_SETTINGS = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork";

/// Whether macOS keeps this process from any of `addrs` (`ip:port`, where a station said it is on its LAN): one on the
/// subnet it is on refused at once. One past the router goes through either way; one not there is not told so at once.
export async function lanKept(addrs: string[], send: (ip: string) => Promise<string | null> = sendOne): Promise<boolean> {
  const ips = [...new Set(addrs.map((a) => /^(\d+\.\d+\.\d+\.\d+):\d+$/.exec(a)?.[1]).filter((ip): ip is string => ip !== undefined && privateV4(ip)))];
  const said = await Promise.all(ips.map(send));
  return said.some((e) => e === "EHOSTUNREACH");
}

/// What System Settings' Local Network list names the station by: the app it runs in (the desktop app's station runs on
/// its Node, `STILLFAIL_NODE`), else its launcher, which launchd starts and Node is part of.
export function localNetworkName(execPath = process.execPath): string {
  const app = /([^/]+)\.app\/Contents\//.exec(execPath);
  return app ? app[1]! : "stillfail-station";
}
