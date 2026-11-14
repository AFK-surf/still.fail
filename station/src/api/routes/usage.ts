// What the agents spent, the machine's own sessions, the agents' memory and the machine itself
// (admin/mod.rs: GET /usage, /machine-sessions, /machine-sessions/:runtime/:id, /memory, /host), and what
// still.fail uses of the machine (GET /resources, POST /resources/processes/:pid/end).
import { type Request, type Answer, error, json, param, Refused, segment } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { cpus, totalmem } from "node:os";
import { NotEndable, type ResourceWatch } from "../../resources/watch.ts";
import { log } from "../../ops/log.ts";
import { wall } from "../../ops/fibers.ts";
import type { InWorkspace } from "../../store/rows.ts";
import { USAGE_SUMMARY_PENDING, type UsageSummaryRange } from "../../store/usage-summary-blocks.ts";

const I64_MIN = -9223372036854775808n;
const I64_MAX = 9223372036854775807n;
const floorMinute = (n: bigint) => n >= 0n ? n / 60_000n : -1n - (-1n - n) / 60_000n;
const ceilMinute = (n: bigint) => -floorMinute(-n);

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

/// A page cursor is an exact SQLite i64. Going through a JavaScript number can skip rows above 2^53.
function cursorInteger(r: Request, name: string): bigint | null {
  const value = param(r, name);
  if (value === undefined) return null;
  if (!/^[+-]?\d{1,19}$/.test(value)) throw new Refused(400, `${name} must be an integer`);
  const n = BigInt(value);
  if (n < I64_MIN || n > I64_MAX) throw new Refused(400, `${name} is out of range`);
  return n;
}

/// A path segment (admin/mod.rs segment_decode): `+` stays itself there.

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
    // A member of a workspace the station joined sees that workspace's.
    {
      method: "GET",
      pattern: /^\/memory$/,
      handle: async (r: Request): Promise<Answer> => {
        if (r.viewer.home !== false) return read(r, "memory", {});
        if (!tools.agents) return error(503, "station starting");
        if (typeof r.viewer.workspace !== "string") return error(400, "not a workspace id");
        return read(r, "memory", { workspace: r.viewer.workspace });
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
  ];
};

/// GET /usage, the usage part's (usage/module.ts): `reading`, whether the counter is still reading what was spent.
export const usageRoutes = ({ read }: Tools, reading: () => boolean, wakeTotals: (viewer: InWorkspace | null) => void = () => {},
  waitSummary?: (viewer: InWorkspace | null, range: UsageSummaryRange, signal?: AbortSignal) => Promise<void>): Route[] => [
  // A bounded page of one session's original calls; aggregates remain a separate, statistics-only read.
  {
    method: "GET",
    pattern: /^\/usage\/calls\/([^/]+)\/?$/,
    handle: (r: Request, [session]: string[]) => read(r, "usageCalls", {
      session: segment(session!), from: String(cursorInteger(r, "from") ?? I64_MIN), to: String(cursorInteger(r, "to") ?? I64_MAX),
      beforeAt: String(cursorInteger(r, "beforeAt") ?? I64_MAX), beforeSeq: String(cursorInteger(r, "beforeSeq") ?? I64_MAX),
      limit: Number(number(r, "limit") ?? 100n), viewer: r.viewer,
    }),
  },
  // What the agents spent from `from` until `to` (ms), by day as the asker's clock has them (`tz`: minutes east of
  // UTC), with whom, where and on what; `history=1`, everything since counting began by day as well (a station from
  // before answers without it).
  {
    method: "GET",
    pattern: /^\/usage$/,
    handle: async (r: Request) => {
      const to = number(r, "to") ?? I64_MAX;
      const from = number(r, "from") ?? 0n;
      const tz = number(r, "tz") ?? 0n;
      const clamped = tz < -1440n ? -1440n : tz > 1440n ? 1440n : tz;
      const historyFrom = cursorInteger(r, "historyFrom"), historyTo = cursorInteger(r, "historyTo");
      if ((historyFrom === null) !== (historyTo === null)) throw new Refused(400, "history range needs both bounds");
      if (historyFrom !== null && historyTo !== null) {
        const localEnd = historyTo + clamped * 60_000n;
        if (historyFrom > historyTo || historyTo - historyFrom > 370n * 86_400_000n || historyFrom % 60_000n !== 0n
          || historyTo % 60_000n !== 0n || localEnd % 86_400_000n !== 0n
          || localEnd < -8_640_000_000_000_000n || localEnd > 8_640_000_000_000_000n) throw new Refused(400, "invalid history range");
        wakeTotals(r.viewer);
      }
      const history = param(r, "history") === "1";
      const allowPartial = history && param(r, "allowPartial") === "1";
      const args = { lang: r.lang, from: String(from), to: String(to), tz: String(clamped), reading: reading(), viewer: r.viewer, history,
        ...(waitSummary !== undefined ? { summaryStrict: true } : {}),
        ...(historyFrom !== null && historyTo !== null ? { historyRange: { from: String(historyFrom), to: String(historyTo) } } : {}) };
      const answer = async (request: Request, tell?: (answer: Answer) => void): Promise<Answer> => {
        let prepared = false;
        let partialTold = false;
        for (;;) {
          const result = await read(request, "usage", { ...args, ...(prepared ? { summaryPrepared: true } : {}) });
          let preparing = false;
          if (result.status === 503 && Buffer.isBuffer(result.body)) {
            try { preparing = JSON.parse(result.body.toString("utf8")).error === USAGE_SUMMARY_PENDING; } catch { /* An unrelated error. */ }
          }
          if (!preparing || waitSummary === undefined) return result;
          // Only clients that ask for a partial result know to keep its recent totals in a waiting state. Read the
          // independent history on a new snapshot, without falling back to a scan of the old minute or call tables.
          if (allowPartial && !partialTold) {
            const partial = await read(request, "usage", { ...args, detailsPreparing: true });
            if (tell === undefined || partial.status !== 200) return partial;
            tell(partial);
            partialTold = true;
          }
          // Release the reader while the existing background worker prepares the selected workspace, then read one
          // new snapshot. A device that leaves the page can cancel the wait.
          try {
            await waitSummary(r.viewer, { from: floorMinute(from), to: to === I64_MAX ? I64_MAX : ceilMinute(to) }, request.signal);
            prepared = true;
          }
          catch (cause) { return error(503, (cause as Error).message); }
        }
      };
      // Older clients request the whole history without its chart range. Their summary cache also needs the new
      // pending buckets to be accounted; otherwise every later read revisits them. Let the current read finish first,
      // then settle only this viewer's new statistics in the existing bounded background worker.
      const finish = (result: Answer) => {
        if (result.status === 200) wakeTotals(r.viewer);
        return result;
      };
      const run = async (request: Request, tell?: (answer: Answer) => void) => {
        const result = await answer(request, tell);
        return history && historyFrom === null ? finish(result) : result;
      };
      // Unlike a JSON request, a stream can stay open while a large range is prepared. It sends the history as soon
      // as it is available, then the completed answer from the same wait (and closes if the caller leaves).
      if ((r.headers["accept"] ?? "").includes("text/event-stream")) return followedUsage(r, run);
      return run(r);
    },
  },
];

/// A usage read may need many bounded conversion batches. An event stream keeps that wait and its cursor alive without
/// holding a reader, and its heartbeats let a client distinguish slow preparation from a lost connection.
function followedUsage(r: Request, run: (request: Request, tell: (answer: Answer) => void) => Promise<Answer>): Answer {
  const controller = new AbortController();
  const queue: Buffer[] = [];
  let wake: (() => void) | null = null;
  let closed = false;
  let finished = false;
  const notify = () => { const ready = wake; wake = null; ready?.(); };
  const tell = (answer: Answer) => {
    if (closed) return;
    if (answer.status === 200 && Buffer.isBuffer(answer.body)) {
      queue.push(Buffer.from(`event: usage\ndata: ${answer.body.toString("utf8")}\n\n`));
    } else {
      let body: unknown = {};
      if (Buffer.isBuffer(answer.body)) {
        try { body = JSON.parse(answer.body.toString("utf8")); } catch { /* A non-JSON failure. */ }
      }
      queue.push(Buffer.from(`event: error\ndata: ${JSON.stringify({ status: answer.status, body })}\n\n`));
    }
    notify();
  };
  const stopHeartbeat = wall.every(15_000, () => {
    if (!closed && !finished && queue.length === 0) { queue.push(Buffer.from(": ping\n\n")); notify(); }
  });
  const end = () => {
    if (closed) return;
    closed = true;
    stopHeartbeat();
    r.signal?.removeEventListener("abort", end);
    controller.abort();
    queue.length = 0;
    notify();
  };
  if (r.signal?.aborted) end();
  else r.signal?.addEventListener("abort", end, { once: true });
  void run({ ...r, signal: controller.signal }, tell).then(tell, (cause) => tell(error(500, (cause as Error).message))).finally(() => {
    finished = true;
    stopHeartbeat();
    r.signal?.removeEventListener("abort", end);
    notify();
  });
  const body: AsyncIterableIterator<Buffer> = {
    [Symbol.asyncIterator]: () => body,
    next: async () => {
      while (!closed && !finished && queue.length === 0) await new Promise<void>((resolve) => { wake = resolve; });
      if (queue.length > 0) return { done: false, value: queue.shift()! };
      end();
      return { done: true, value: undefined };
    },
    return: async () => { end(); return { done: true, value: undefined }; },
  };
  return { status: 200, headers: { "content-type": "text/event-stream", "cache-control": "no-store", "x-accel-buffering": "no" }, body };
}

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
