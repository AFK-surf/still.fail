// What the native launcher hands this process (docs/station-ts-native.md §2): `--launcher-fds a,b,c`: the MCP
// listener, the loopback listener (bound by the launcher, so a handover has no gap on them) and the control channel,
// one JSON line each way. Run without a launcher (a checkout), there is no channel and this process binds for itself.
import { Socket, createConnection } from "node:net";
import { log } from "./log.ts";
import { flag } from "./files.ts";

export type Control = {
  /// The MCP and loopback listeners' fds, when the launcher bound them.
  mcpFd?: number;
  loopbackFd?: number;
  ready(version: string): void;
  drained(how: "idle" | "timeout"): void;
  on(op: "handover" | "stop" | "drain" | "hup", f: () => void): void;
};

export function launcher(args: string[]): Control {
  const fds = flag(args, "--launcher-fds")?.split(",").map(Number);
  // Windows' launcher (native/launcher/src/run_windows.rs): no descriptors handed down, so this process binds its ports
  // itself; the control channel is a named pipe, the same lines on it.
  const pipe = flag(args, "--launcher-pipe");
  const handlers = new Map<string, (() => void)[]>();
  const on: Control["on"] = (op, f) => handlers.set(op, [...(handlers.get(op) ?? []), f]);
  const handed = fds && fds.length >= 3 && !fds.some((n) => !Number.isInteger(n));
  if (!handed && pipe === undefined) {
    // On its own: SIGTERM and ^C stop it, as they would through a launcher.
    for (const signal of ["SIGTERM", "SIGINT"] as const) process.on(signal, () => handlers.get("stop")?.forEach((f) => f()));
    return { ready() {}, drained() {}, on };
  }
  const [mcpFd, loopbackFd, controlFd] = handed ? fds : [undefined, undefined, undefined];
  const channel = controlFd !== undefined ? new Socket({ fd: controlFd, readable: true, writable: true }) : createConnection(pipe!);
  let carry = "";
  channel.on("data", (chunk) => {
    carry += chunk.toString();
    for (let at = carry.indexOf("\n"); at >= 0; at = carry.indexOf("\n")) {
      const line = carry.slice(0, at);
      carry = carry.slice(at + 1);
      try {
        const op = JSON.parse(line).op;
        handlers.get(op)?.forEach((f) => f());
      } catch {
        log.warn("launcher", "unreadable line from the launcher", { line });
      }
    }
  });
  // The launcher gone: nothing will hand this process over or stop it, so it stops.
  channel.on("close", () => handlers.get("stop")?.forEach((f) => f()));
  const say = (value: unknown) => channel.write(JSON.stringify(value) + "\n");
  // Signals reach the launcher; this process hears of them on the channel.
  for (const signal of ["SIGTERM", "SIGINT", "SIGHUP", "SIGUSR1", "SIGUSR2"] as const) process.on(signal, () => {});
  return {
    mcpFd,
    loopbackFd,
    ready: (version) => say({ ready: true, version }),
    drained: (how) => say({ drained: how }),
    on,
  };
}
