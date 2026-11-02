// What the agents spent, the machine's own sessions, the agents' memory, the machine itself, and the retired footprint
// (admin/mod.rs: GET /usage, /machine-sessions, /machine-sessions/:runtime/:id, /memory, /host, /footprint), and what
// still.fail uses of the machine (GET /resources, POST /resources/processes/:pid/end).
import { type Request, type Answer, error, json, param, percentDecode } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { memory } from "../../read/memory.ts";
import { cpus, totalmem } from "node:os";
import { NotEndable, type ResourceWatch } from "../../resources/watch.ts";
import { log } from "../../ops/log.ts";

const I64_MIN = -9223372036854775808n;
const I64_MAX = 9223372036854775807n;

/// `v.parse::<f64>().ok().map(|v| v as i64)`: Rust's float syntax (inf, infinity and nan too, any case), then as an i64
/// (NaN 0, beyond its range its ends, the fraction dropped). None when it does not read.
function number(r: Request, name: string): bigint | null {
  const v = param(r, name);
  if (v === undefined || !/^[+-]?(?:inf|infinity|nan|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)$/i.test(v)) return null;
  const body = v.replace(/^[+-]/, "").toLowerCase();
  const x = body === "nan" ? NaN : body === "inf" || body === "infinity" ? (v.startsWith("-") ? -Infinity : Infinity) : Number(v);
  if (Number.isNaN(x)) return 0n;
  if (x >= 2 ** 63) return I64_MAX;
  if (x < -(2 ** 63)) return I64_MIN;
  return BigInt(Math.trunc(x));
}

/// A path segment (admin/mod.rs segment_decode): `+` stays itself there.
const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));

/// The Rust's `/footprint` for clients from before footprint statistics were retired (admin/footprint.rs `retired`).
const RETIRED = JSON.stringify({
  checkedAt: null, tookMs: null, scanning: false, manage: false,
  disk: { totalBytes: 0, freeBytes: 0 },
  parts: [], elsewhere: [], chats: [],
  unseen: { count: 0, bytes: 0 },
  memory: { totalBytes: 0, usedBytes: 0, stationBytes: 0 },
  processes: [],
});

export const routes = (tools: Tools): Route[] => {
  const { read, host } = tools;
  return [
    // Sessions this machine's own Claude Code and Codex kept (in a terminal), to go on with one in a chat.
    { method: "GET", pattern: /^\/machine-sessions$/, handle: async (r: Request) => read(r, "machineSessions", {}) },
    // One of them, to look at before going on with it: what was said, the latest `limit`. As the Rust matches its
    // segments (empty ones dropped, any after the third ignored).
    {
      method: "GET",
      pattern: /^\/+machine-sessions\/+([^/]+)\/+([^/]+)(?:\/.*)?$/,
      handle: async (r: Request, [runtime, id]: string[]) =>
        read(r, "machineSession", { lang: r.lang, runtime: segment(runtime!), id: segment(id!), limit: param(r, "limit") }),
    },
    // The agents' memory, for the pages to show: the global one, and the shared skills (projects' memories among them).
    // A member of a workspace the station joined sees that workspace's (docs/multi-workspace.md).
    {
      method: "GET",
      pattern: /^\/memory$/,
      handle: async (r: Request): Promise<Answer> => {
        if (r.viewer.home !== false) return read(r, "memory", {});
        const agents = tools.agents;
        if (!agents) return error(503, "station starting");
        try {
          return json(200, JSON.stringify(memory(agents.config.data, r.viewer.workspace)));
        } catch (e) {
          return error(400, (e as Error).message);
        }
      },
    },
    // The machine's state, at most ten seconds old.
    {
      method: "GET",
      pattern: /^\/host$/,
      handle: async (r: Request): Promise<Answer> => {
        try {
          return json(200, JSON.stringify(await host.sample(r.lang)));
        } catch (e) {
          return error(500, (e as Error).message);
        }
      },
    },
    // Retired: old clients' route kept, without scanning.
    { method: "GET", pattern: /^\/footprint$/, handle: async () => json(200, RETIRED) },
  ];
};

/// GET /usage, the usage part's (usage/module.ts): `reading`, whether the counter is still reading what was spent.
export const usageRoutes = ({ read }: Tools, reading: () => boolean): Route[] => [
  // What the agents spent from `from` until `to` (ms), by day as the asker's clock has them (`tz`: minutes east of
  // UTC), with whom, where and on what; `history=1`, everything since counting began by day as well (a station from
  // before answers without it).
  {
    method: "GET",
    pattern: /^\/usage$/,
    handle: (r: Request) => {
      const to = number(r, "to") ?? I64_MAX;
      const from = number(r, "from") ?? 0n;
      const tz = number(r, "tz") ?? 0n;
      const clamped = tz < -1440n ? -1440n : tz > 1440n ? 1440n : tz;
      return read(r, "usage", { lang: r.lang, from: String(from), to: String(to), tz: String(clamped), reading: reading(), viewer: r.viewer, history: param(r, "history") === "1" });
    },
  },
];

/// What still.fail uses of this machine now as `r`'s asker sees it (GET /resources): by whose and process, and the
/// last minutes' totals (resources/watch.ts), the chats named. A chat the asker does not see (another workspace's) is
/// the agents', none of its processes endable.
async function shownTo(r: Request, read: Tools["read"], watch: ResourceWatch | null): Promise<Answer> {
  const shot = watch?.snapshot() ?? { at: null, everyMs: 0, counted: false, net: false, disk: false, total: { cpu: 0, memory: 0, netIn: 0, netOut: 0, diskRead: 0, diskWrite: 0 }, groups: [], history: [] };
  const sessions = [...new Set(shot.groups.flatMap((g) => (g.session ? [g.session] : [])))];
  const named = await read(r, "resourceChats", { sessions, viewer: r.viewer });
  if (named.status !== 200) return named;
  const chats = JSON.parse((named.body as Buffer).toString("utf8")) as Record<string, { thread: number | null; title: string | null } | null>;
  const seen = (key: string) => !key.startsWith("chat:") || chats[key.slice(5)] != null;
  // Chats not seen: the agents' (their processes together).
  const groups: typeof shot.groups = [];
  for (const g of shot.groups) {
    if (seen(g.key)) {
      groups.push(g);
      continue;
    }
    const agents = groups.find((d) => d.key === "agents");
    if (agents) {
      agents.cpu += g.cpu;
      agents.memory += g.memory;
      agents.netIn += g.netIn;
      agents.netOut += g.netOut;
      agents.diskRead += g.diskRead;
      agents.diskWrite += g.diskWrite;
      agents.processes = [...agents.processes, ...g.processes.map((p) => ({ ...p, endable: false }))];
    } else groups.push({ ...g, key: "agents", kind: "agents", session: null, processes: g.processes.map((p) => ({ ...p, endable: false })) });
  }
  const shown = Object.fromEntries(Object.entries(chats).filter(([, c]) => c != null));
  // The machine, for what is used to be said against.
  return json(200, JSON.stringify({ ...shot, groups, chats: shown, machine: { cores: cpus().length, memory: totalmem() } }));
}

/// GET /resources as events (asked with `accept: text/event-stream`): a `resources` event, what GET /resources answers,
/// after each look while the stream is open; the station looks for as long. A client from before asks GET /resources
/// again and again, and is answered as before.
function followed(r: Request, read: Tools["read"], watch: ResourceWatch | null): Answer {
  const queue: string[] = [];
  let wake: (() => void) | null = null;
  let closed = false;
  // One telling at a time, the latest look's: a look while one is being read is told once that is.
  let telling = false;
  let again = false;
  const tell = async () => {
    if (telling) return void (again = true);
    telling = true;
    try {
      do {
        again = false;
        const a = await shownTo(r, read, watch).catch(() => null);
        if (closed || a === null || a.status !== 200) continue;
        queue.push(`event: resources\ndata: ${(a.body as Buffer).toString("utf8")}\n\n`);
        wake?.();
      } while (again && !closed);
    } finally {
      telling = false;
    }
  };
  // Where processes are not read: what there is, once.
  const stop = watch ? watch.follow(() => void tell()) : (void tell(), () => {});
  const end = () => {
    if (closed) return;
    closed = true;
    stop();
    wake?.();
  };
  const body: AsyncIterableIterator<Buffer> = {
    [Symbol.asyncIterator]: () => body,
    next: async () => {
      while (!closed && queue.length === 0) await new Promise<void>((resolve) => (wake = resolve));
      wake = null;
      if (queue.length === 0) return { done: true, value: undefined };
      return { done: false, value: Buffer.from(queue.shift()!) };
    },
    return: async () => {
      end();
      return { done: true, value: undefined };
    },
  };
  return { status: 200, headers: { "content-type": "text/event-stream", "cache-control": "no-store", "x-accel-buffering": "no" }, body };
}

/// GET /resources, the resources part's (resources/module.ts): what still.fail uses of this machine now (`shownTo`);
/// asked, the station looks often for a while. Asked as events, it is told as it looks (`followed`). POST
/// /resources/processes/:pid/end ({session}): ends a process of a chat the asker sees (watch.ts `end`).
/// `watch`: none where processes are not read (not macOS).
export const resourceRoutes = ({ read }: Tools, watch: ResourceWatch | null): Route[] => [
  {
    method: "GET",
    pattern: /^\/resources$/,
    handle: async (r: Request): Promise<Answer> => {
      if ((r.headers["accept"] ?? "").includes("text/event-stream")) return followed(r, read, watch);
      await watch?.want();
      return shownTo(r, read, watch);
    },
  },
  {
    method: "POST",
    pattern: /^\/resources\/processes\/(\d+)\/end$/,
    handle: async (r: Request, [rawPid]: string[]): Promise<Answer> => {
      if (!watch) return error(404, "processes are not read here");
      let session: unknown;
      try {
        session = r.body.length > 0 ? (JSON.parse(r.body.toString("utf8")) as { session?: unknown }).session : undefined;
      } catch {
        return error(400, "invalid JSON");
      }
      if (typeof session !== "string" || session === "") return error(400, "session required");
      // Its chat as the asker sees it: none (another workspace's), no such process for them.
      const named = await read(r, "resourceChats", { sessions: [session], viewer: r.viewer });
      if (named.status !== 200) return named;
      const chats = JSON.parse((named.body as Buffer).toString("utf8")) as Record<string, unknown>;
      if (chats[session] == null) return error(404, "no such process");
      const pid = Number(rawPid);
      try {
        const ended = await watch.end(pid, session);
        log.info("resources", "a chat's process ended from its station's page", { pid, name: ended.name, session, by: r.viewer.email });
        return json(200, JSON.stringify({ pid, ...ended }));
      } catch (e) {
        if (e instanceof NotEndable) return error(409, e.message);
        throw e;
      }
    },
  },
];
