// What the agents spent, the machine's own sessions, the agents' memory, the machine itself, and the retired footprint
// (admin/mod.rs: GET /usage, /machine-sessions, /machine-sessions/:runtime/:id, /memory, /host, /footprint).
import { type Request, type Answer, error, json, param, percentDecode } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { memory } from "../../read/memory.ts";
import { cpus, totalmem } from "node:os";
import type { ResourceWatch } from "../../resources/watch.ts";

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
  // UTC), with whom, where and on what.
  {
    method: "GET",
    pattern: /^\/usage$/,
    handle: (r: Request) => {
      const to = number(r, "to") ?? I64_MAX;
      const from = number(r, "from") ?? 0n;
      const tz = number(r, "tz") ?? 0n;
      const clamped = tz < -1440n ? -1440n : tz > 1440n ? 1440n : tz;
      return read(r, "usage", { lang: r.lang, from: String(from), to: String(to), tz: String(clamped), reading: reading(), viewer: r.viewer });
    },
  },
];

/// GET /resources, the resources part's (resources/module.ts): what still.fail uses of this machine now, by whose and
/// process, the last minutes' totals and the last hours' joules (resources/watch.ts), the chats named. A chat the asker
/// does not see (another workspace's) is the agents'. Asked, the station looks often for a while. `watch`: none where
/// processes are not read (not macOS).
export const resourceRoutes = ({ read }: Tools, watch: ResourceWatch | null): Route[] => [
  {
    method: "GET",
    pattern: /^\/resources$/,
    handle: async (r: Request): Promise<Answer> => {
      await watch?.want();
      const shot = watch?.snapshot() ?? { at: null, everyMs: 0, counted: false, total: { cpu: 0, memory: 0, watts: 0, wakeups: 0 }, groups: [], history: [], hours: [] };
      const sessions = [...new Set([...shot.groups.flatMap((g) => (g.session ? [g.session] : [])), ...shot.hours.flatMap((h) => Object.keys(h.joules).filter((k) => k.startsWith("chat:")).map((k) => k.slice(5)))])];
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
          agents.watts += g.watts;
          agents.wakeups += g.wakeups;
          agents.processes = [...agents.processes, ...g.processes];
        } else groups.push({ ...g, key: "agents", kind: "agents", session: null });
      }
      const hours = shot.hours.map((h) => {
        const joules: Record<string, number> = {};
        for (const [k, j] of Object.entries(h.joules)) joules[seen(k) ? k : "agents"] = (joules[seen(k) ? k : "agents"] ?? 0) + j;
        return { at: h.at, joules };
      });
      const shown = Object.fromEntries(Object.entries(chats).filter(([, c]) => c != null));
      // The machine, for what is used to be said against.
      return json(200, JSON.stringify({ ...shot, groups, hours, chats: shown, machine: { cores: cpus().length, memory: totalmem() } }));
    },
  },
];
