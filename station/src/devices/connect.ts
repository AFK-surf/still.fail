// What a device is reached at from the machine it is attached to (设备, 2026-11-10): a connection whose bytes go to it
// as they are, carried to a chat's station over the mesh (mesh/peer-http.ts, a tunnel's `device`). An address and
// port its network reaches (`tcp`); this machine's adb server, which has the phone or board on its USB (`adb`: the
// chat names it with `-s <serial>`); a serial port, set raw at its speed (`serial`).
import { spawn } from "node:child_process";
import { close as closeFd, constants, createReadStream, createWriteStream, open } from "node:fs";
import { type Socket, connect } from "node:net";
import { Duplex } from "node:stream";
import type { Device } from "../../../client/core-ts/src/rig-form.ts";
import { wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";

/// How long a device's address has to take a connection.
const REACH_MS = 10_000;
/// The adb server a machine's own adb starts, where its USB phones are.
export const ADB_PORT = 5037;
/// A serial port's speed when none was given.
export const BAUD_DEFAULT = 115200;

/// A connection to `host:port`: paused, half-open (as peer-forward.ts's `reachLocal` gives one).
export function reachTcp(host: string, port: number): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const socket = connect({ host, port, allowHalfOpen: true });
    const stop = wall.after(REACH_MS, () => {
      socket.destroy();
      reject(new Error(`${host}:${port} took no connection within ${REACH_MS / 1000} s`));
    });
    socket.once("error", (error) => {
      stop();
      reject(error);
    });
    socket.once("connect", () => {
      stop();
      socket.removeAllListeners("error");
      socket.on("error", () => {});
      socket.pause();
      resolve(socket);
    });
  });
}

/// `host:port` (a bracketed IPv6 address too) split.
export function hostPort(target: string): { host: string; port: number } {
  const at = target.lastIndexOf(":");
  const host = target.slice(0, at).replace(/^\[(.*)\]$/, "$1");
  return { host, port: Number(target.slice(at + 1)) };
}

/// The serial port at `path` set raw at `baud` (stty: its flag for the device is -F on Linux, -f on a Mac).
function setRaw(path: string, baud: number): Promise<void> {
  const flag = platform.os === "macos" ? "-f" : "-F";
  return new Promise((resolve, reject) => {
    const child = spawn("stty", [flag, path, "raw", "-echo", String(baud)], { stdio: ["ignore", "ignore", "pipe"] });
    let said = "";
    child.stderr.on("data", (chunk: Buffer) => (said += chunk.toString()));
    child.once("error", reject);
    child.once("close", (code) => (code === 0 ? resolve() : reject(new Error(`stty ${path}: ${said.trim() || `exit ${code}`}`))));
  });
}

/// The serial port at `path`, both ways, as one stream: paused, as a socket from `reachTcp` is.
async function reachSerial(path: string, baud: number): Promise<Duplex> {
  if (platform.os === "windows") throw new Error("serial ports are not reached on Windows stations yet");
  await setRaw(path, baud);
  const fd = await new Promise<number>((resolve, reject) => open(path, constants.O_RDWR | constants.O_NOCTTY, (error, fd) => (error ? reject(error) : resolve(fd))));
  const readable = createReadStream("", { fd, autoClose: false });
  const writable = createWriteStream("", { fd, autoClose: false });
  const both = Duplex.from({ readable, writable });
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    readable.destroy();
    writable.destroy();
    closeFd(fd, () => {});
  };
  both.once("close", close);
  both.on("error", () => {});
  both.pause();
  return both;
}

/// A connection to device `d` from this machine.
export async function reachDevice(d: Device): Promise<Duplex> {
  switch (d.kind) {
    case "tcp": {
      const { host, port } = hostPort(d.target);
      return reachTcp(host, port);
    }
    case "adb":
      return reachTcp("127.0.0.1", ADB_PORT);
    case "serial":
      return reachSerial(d.target, d.baud ?? BAUD_DEFAULT);
  }
}
