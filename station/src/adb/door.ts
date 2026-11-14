// The door of a grant's adb server (2026-11-05): the port a chat's agent is given. The server itself
// serves any client on its socket and says nothing of who it is, so the phone's listener, which lets that server in
// (servers.ts `owner`), cannot tell one chat's `adb -P <port> shell` from another's. Here each connection's client is
// found among the machine's processes, and only the grant's session (and the station) is put through; the server
// listens on a socket in a directory of its own, named only in its environment.
import net from "node:net";
import { realpath } from "node:fs/promises";
import { wall } from "../ops/fibers.ts";
import type { ProcessInfo } from "../platform/index.ts";

/// Why these processes (those holding the client's end of a connection) may not use grant `id`'s server, or null.
export type Admit = (id: string, holders: number[]) => Promise<string | null>;

/// What adb's client shows of a server refusing it: its `FAIL`, with the message's length in four hex digits.
export function failure(message: string): string {
  const said = Buffer.from(message).subarray(0, 0xffff).toString();
  return `FAIL${Buffer.byteLength(said).toString(16).padStart(4, "0")}${said}`;
}

const REFUSING_MS = 5000;

/// The client told why, what it sent read so that its end gets the words rather than a reset.
function refuse(socket: net.Socket, message: string): void {
  socket.once("close", wall.after(REFUSING_MS, () => socket.destroy()));
  socket.resume();
  socket.end(failure(message));
}

/// Both ways until each has ended (adb half-closes), and whichever fails or closes takes the other with it.
function join(a: net.Socket, b: net.Socket): void {
  for (const [from, to] of [[a, b], [b, a]] as const) {
    from.once("error", () => to.destroy());
    from.once("close", () => to.destroy());
    from.pipe(to);
  }
}

/// A door on a free port of 127.0.0.1 to the server at `socketPath`.
export function openDoor(id: string, socketPath: string, holdersOf: (port: number) => Promise<number[]>, admit: Admit): Promise<{ port: number; close(): void }> {
  const door = net.createServer({ pauseOnConnect: true, allowHalfOpen: true }, (socket) => {
    socket.once("error", () => socket.destroy());
    const port = socket.remotePort;
    void (port === undefined ? Promise.resolve<number[]>([]) : holdersOf(port))
      .catch((): number[] => [])
      .then((holders) => admit(id, holders))
      .catch((error: Error) => `could not tell who asks: ${error.message}`)
      .then((why) => {
        if (socket.destroyed) return;
        if (why !== null) return refuse(socket, why);
        const server = net.connect({ path: socketPath, allowHalfOpen: true });
        const gone = () => refuse(socket, "this chat's adb server is gone: call phone_use again");
        server.once("error", gone);
        server.once("connect", () => {
          server.off("error", gone);
          join(socket, server);
          socket.resume();
        });
      });
  });
  return new Promise((resolve, reject) => {
    door.once("error", reject);
    door.listen({ host: "127.0.0.1", port: 0 }, () => {
      door.off("error", reject);
      resolve({ port: (door.address() as net.AddressInfo).port, close: () => void door.close() });
    });
  });
}

/// What the gate needs: the grant's session, the machine's processes, and what of them is whose.
export type GateDeps = {
  /// The session holding the grant, with its own directory (where it works may be a repository others work in too).
  session(id: string): { workspace: string | null } | null;
  table(): Promise<ProcessInfo[] | null>;
  /// The session's agent: the pids of its runner and the runtime it runs (a runtime shared by a profile's sessions is
  /// none's). What runs under them is the session's.
  runners(id: string): number[] | Promise<number[]>;
  /// The jobs running: what runs in a job's group is its session's.
  jobs(): { pgid: number; mine: (id: string) => boolean }[];
  cwds(pids: number[]): Promise<Map<number, string>>;
  /// This station's process: the adb it runs itself (connecting the phone, the chat's own screen) is its direct child.
  self: number;
  /// What a process of another chat is told (a phone's words when none given).
  elsewhere?: string;
};

const PHONE_ELSEWHERE = "this phone is granted to another chat: ask for it with phone_use in this chat";

/// Why `holders` may not use grant `id`'s server, or null: a process under the session's agent or in one of its jobs;
/// the station's own adb; else (a runtime shared by sessions, a script left running on its own) one working in the
/// session's own directory.
export async function gate(d: GateDeps, id: string, holders: number[]): Promise<string | null> {
  const ELSEWHERE = d.elsewhere ?? PHONE_ELSEWHERE;
  const session = d.session(id);
  if (session === null) return ELSEWHERE;
  const table = await d.table();
  if (table === null) return "could not tell who asks: the machine's processes were not read";
  const byPid = new Map(table.map((p) => [p.pid, p]));
  const jobs = d.jobs();
  const runners = new Set(await d.runners(id));
  for (const pid of holders) {
    const row = byPid.get(pid);
    if (row === undefined) continue;
    const job = jobs.find((j) => j.pgid === row.pgid);
    if (row.ppid === d.self && job === undefined) return null;
    for (let p: ProcessInfo | undefined = row, n = 0; p !== undefined && n < 256; p = byPid.get(p.ppid), n++) {
      if (runners.has(p.pid) || jobs.some((j) => j.pgid === p!.pgid && j.mine(id))) return null;
    }
  }
  if (session.workspace === null || session.workspace === "" || session.workspace === "/") return ELSEWHERE;
  const cwds = await d.cwds(holders);
  const own = await realpath(session.workspace).catch(() => session.workspace!);
  const inside = (dir: string) => dir === own || dir.startsWith(own.endsWith("/") ? own : `${own}/`);
  for (const pid of holders) {
    const cwd = cwds.get(pid);
    if (cwd !== undefined && inside(cwd)) return null;
  }
  return `${ELSEWHERE} (the chat holding it runs adb under its agent or from its own directory, ${session.workspace})`;
}
