// The local status: what the station is doing, in a summary for a program on this machine (a status display, the
// Monoid Machine's monoid-agent, which shows it as the machine's state): whether it is enrolled, how many agents are at
// work and how many there are, whether one waits for a person, and the tasks behind those numbers. It is this
// machine's alone, on a Unix socket in the data directory, <data>/run/status.sock (mode 0600, the station's user and
// root), never a port: it says chats' titles and what an agent asks of a person.
//
//   GET /v1/status          the status now (LocalStatus, JSON)
//   GET /v1/status?watch=1  a stream of them (NDJSON): one now, then one each time it changes (a session's turn
//                           starts or ends, the station joins or leaves its workspace), a burst said once
//   GET /healthz            200 once the station serves
//
// `curl --unix-socket "$STILLFAIL_DATA/run/status.sock" http://station/v1/status` reads it.
import { chmod, mkdir, rename, rm } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import { Effect, Layer } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { version } from "../ops/version.ts";
import { AgentsSide, ControlPlane, Paths, Store } from "../services.ts";

/// Where the socket is.
export const statusSocket = (data: string) => join(data, "run", "status.sock");

/// How far back a turn that asked for a person is looked at: one waiting longer than this is not counted (a reader
/// shows "needs you" while someone can still answer, not for a chat forgotten weeks ago).
export const WAITING_DAYS = 7;
/// The most tasks said (the counts are of all).
export const TASKS_MOST = 50;
/// A burst of changes is said once, this long after its first (timer: debounce).
export const SETTLE_MS = 500;

export type StatusTask = {
  /// The session's key: what the app and the admin API name it by.
  session: string;
  title: string | null;
  /// `working`: a turn is running; `waiting`: its last turn asked for a person and nobody has answered.
  state: "working" | "waiting";
  /// When it started working (its turn), or when it began to wait: ms since the epoch.
  since: number | null;
  /// What it asks of a person, in its words (`waiting` only).
  need: string | null;
};

export type LocalStatus = {
  version: string;
  /// In a workspace of the control plane at `origin` (cloud.json), and not removed from it.
  enrolled: boolean;
  origin: string | null;
  workspace: string | null;
  workspaceName: string | null;
  station: string | null;
  /// Whether it hears its control plane now.
  reached: boolean;
  agents: {
    /// Agents in a turn now.
    busy: number;
    /// Agents whose process is up, waiting for their next turn.
    warm: number;
    /// The agents there are now: at work, warm, or waiting for a person (each once).
    total: number;
  };
  /// Agents waiting for a person.
  waiting: number;
  /// The working ones first, then the waiting, each the latest first; at most TASKS_MOST.
  tasks: StatusTask[];
};

/// What the status is made of: the control plane's state, the running sessions (the store's `running`), each live
/// process's state (the hub's: `running` or `warm`), and the sessions waiting for a person.
export type StatusInput = {
  version: string;
  cloud: { origin?: string; workspace?: string; workspace_name?: string; station?: string; removed_at?: number } | null;
  reached: boolean;
  running: { key: string; title: string | null; since: number | null }[];
  processes: Map<string, string>;
  waiting: { key: string; title: string | null; need: string | null; endedAt: number }[];
};

export function statusOf(i: StatusInput): LocalStatus {
  const c = i.cloud;
  const enrolled = c !== null && !!c.workspace && c.removed_at === undefined;
  const busyKeys = new Set(i.running.map((r) => r.key));
  for (const [key, state] of i.processes) if (state === "running") busyKeys.add(key);
  const warmKeys = [...i.processes].filter(([key, state]) => state === "warm" && !busyKeys.has(key)).map(([key]) => key);
  // One that is at work again is not waiting, whatever its last turn said.
  const waiting = i.waiting.filter((w) => !busyKeys.has(w.key));
  const all = new Set([...busyKeys, ...warmKeys, ...waiting.map((w) => w.key)]);
  const working: StatusTask[] = [...i.running]
    .sort((a, b) => (b.since ?? 0) - (a.since ?? 0))
    .map((r) => ({ session: r.key, title: r.title, state: "working", since: r.since, need: null }));
  // A process in a turn the store does not say runs yet (a moment between them): counted, said without a title.
  for (const key of busyKeys) if (!i.running.some((r) => r.key === key)) working.push({ session: key, title: null, state: "working", since: null, need: null });
  const waits: StatusTask[] = waiting.map((w) => ({ session: w.key, title: w.title, state: "waiting", since: w.endedAt, need: w.need }));
  return {
    version: i.version,
    enrolled,
    origin: c?.origin || null,
    workspace: c?.workspace || null,
    workspaceName: c?.workspace_name || null,
    station: c?.station || null,
    reached: i.reached,
    agents: { busy: busyKeys.size, warm: warmKeys.length, total: all.size },
    waiting: waiting.length,
    tasks: [...working, ...waits].slice(0, TASKS_MOST),
  };
}

/// What a request on the socket is answered: the status, a stream of it, or nothing.
export type StatusRoute = "status" | "watch" | "health" | null;
export function routeOf(method: string | undefined, url: string | undefined): StatusRoute {
  if (method !== "GET") return null;
  const u = new URL(url ?? "/", "http://station");
  if (u.pathname === "/healthz") return "health";
  if (u.pathname !== "/v1/status") return null;
  const watch = u.searchParams.get("watch");
  return watch !== null && watch !== "0" && watch !== "false" ? "watch" : "status";
}

/// The socket's server: `now` makes the status; `changed` registers a listener for anything it is made of changing
/// (the store's, the control plane's) and gives back how to take it off; `time` the debounce's clock.
export function statusServer(now: () => LocalStatus, changed: (f: () => void) => () => void, time: Fibers) {
  const watchers = new Set<ServerResponse>();
  let last = "";
  let pending: (() => void) | null = null;
  const tell = () => {
    pending = null;
    if (watchers.size === 0) return;
    const text = JSON.stringify(now());
    if (text === last) return;
    last = text;
    for (const res of watchers) res.write(`${text}\n`);
  };
  const off = changed(() => {
    if (watchers.size === 0 || pending !== null) return;
    pending = time.after(SETTLE_MS, tell);
  });
  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
    const route = routeOf(req.method, req.url);
    if (route === null) return void res.writeHead(404, { "content-type": "application/json" }).end(`{"error":"not found"}`);
    if (route === "health") return void res.writeHead(200, { "content-type": "text/plain" }).end("ok\n");
    let text: string;
    try {
      text = JSON.stringify(now());
    } catch (e) {
      log.warn("status", "the local status was not made", { error: (e as Error).message });
      return void res.writeHead(503, { "content-type": "application/json" }).end(JSON.stringify({ error: "the station is starting; ask again" }));
    }
    if (route === "status") return void res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" }).end(`${text}\n`);
    res.writeHead(200, { "content-type": "application/x-ndjson", "cache-control": "no-store" });
    res.write(`${text}\n`);
    last = text;
    watchers.add(res);
    res.on("close", () => void watchers.delete(res));
  });
  return {
    server,
    close: () => {
      off();
      pending?.();
      for (const res of watchers) res.end();
      watchers.clear();
      server.close();
    },
  };
}

/// The local status's socket, for as long as the station runs.
export const StatusLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const plane = yield* ControlPlane;
    const side = yield* AgentsSide;
    const time = yield* Effect.acquireRelease(Effect.sync(() => new Fibers("status")), (t) => Effect.promise(() => t.close()));
    const now = () => statusOf({
      version: version(),
      cloud: plane.state.state,
      reached: plane.state.reached,
      running: store.runningSessions().map((r) => ({ key: r.key, title: r.title, since: r.lastActiveAt })),
      processes: side.current?.hub.processes() ?? new Map(),
      waiting: store.waitingForPeople(store.now() - WAITING_DAYS * 24 * 60 * 60_000, TASKS_MOST),
    });
    const changed = (f: () => void) => {
      const offStore = store.subscribe((c) => { if (c.type === "session" || c.type === "sessionRemoved") f(); });
      const offCloud = plane.state.listen(() => f());
      return () => { offStore(); offCloud(); };
    };
    const path = statusSocket(data);
    // Bound at a path of this process's own and renamed into place: at a handover the next process takes the name
    // while this one still serves, and Node, closing a server, unlinks the path it bound (this one's own, gone by then).
    const own = `${path}.${process.pid}`;
    yield* Effect.acquireRelease(
      Effect.promise(async () => {
        const s = statusServer(now, changed, time);
        await mkdir(join(data, "run"), { recursive: true });
        await rm(own, { force: true });
        await new Promise<void>((resolve) => {
          s.server.once("error", (e) => {
            log.warn("status", "the local status's socket is not had", { path, error: e.message });
            resolve();
          });
          s.server.listen(own, () => resolve()); // path: a Unix socket in the data directory, this machine's only
        });
        if (s.server.listening) {
          await chmod(own, 0o600);
          await rename(own, path);
          log.info("status", "local status on its socket", { path });
        }
        return s;
      }),
      (s) => Effect.sync(() => s.close()),
    );
  }),
);
