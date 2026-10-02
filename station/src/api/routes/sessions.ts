// Sessions, threads and jobs as the pages read them (admin/mod.rs `route`): GET /sessions, /sessions/:key and its
// timeline, files and widget-state; GET /threads, /threads/:id; GET /jobs, /jobs/:id, /jobs/:id/log. As the Rust
// splits a path, its parts are those between slashes that are not empty, each percent-decoded (a `+` stays itself),
// and parts after the third do not count.
import { type Answer, type Request, error, param, percentDecode } from "../request.ts";
import type { Route, Tools } from "../admin.ts";

/// admin/mod.rs `segment_decode`.
const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));
/// What the Rust answers a path it has no route for.
const noRoute = (r: Request) => error(404, `no route ${r.method} ${r.path}`);

/// The bytes of a file read (`sessionFile`), answered as files.rs does; an error as it came.
async function file(read: Tools["read"], r: Request, args: unknown): Promise<Answer> {
  const answer = await read(r, "sessionFile", args);
  if (answer.status !== 200 || !Buffer.isBuffer(answer.body)) return answer;
  const { contentType, base64 } = JSON.parse(answer.body.toString("utf8")) as { contentType: string; base64: string };
  return { status: 200, headers: { "content-type": contentType, "cache-control": "private, max-age=3600" }, body: Buffer.from(base64, "base64") };
}

export const routes = ({ read }: Tools): Route[] => [
  {
    method: "GET",
    pattern: /^\/sessions$/,
    handle: (r) => read(r, "sessions", { connect: param(r, "connect") ?? null, archived: param(r, "archived") === "1", lang: r.lang }),
  },
  {
    method: "GET",
    pattern: /^\/*sessions\/+([^/]+)(?:\/+([^/]+))?(?:\/.*)?$/,
    handle: async (r, [rawKey, rawAction]) => {
      const key = segment(rawKey!);
      const action = rawAction === undefined ? undefined : segment(rawAction);
      if (action === undefined) return read(r, "session", { key, viewer: r.viewer, lang: r.lang });
      if (action === "timeline") return read(r, "timeline", { key, before: param(r, "before"), limit: param(r, "limit"), lang: r.lang });
      if (action === "files") return file(read, r, { key, name: param(r, "name") ?? "", thumb: param(r, "thumb") === "1", lang: r.lang });
      if (action === "widget-state") return read(r, "widgetState", { key, path: param(r, "path"), lang: r.lang });
      return noRoute(r);
    },
  },
  { method: "GET", pattern: /^\/threads$/, handle: (r) => read(r, "threads", { viewer: r.viewer, session: param(r, "session") ?? null, lang: r.lang }) },
  {
    // GET /threads/:id/entries is the chats' (routes/chats.ts); any other action is none, once the thread is there.
    method: "GET",
    pattern: /^\/*threads\/+([^/]+)(?:\/+(?!entries(?:\/|$))([^/]+)(?:\/.*)?|\/*)$/,
    handle: async (r, [rawId, rawAction]) => {
      const id = segment(rawId!);
      const answer = await read(r, "thread", { id, viewer: r.viewer, lang: r.lang });
      if (rawAction === undefined || answer.status !== 200) return answer;
      if (segment(rawAction) === "entries") return read(r, "entries", { viewer: r.viewer, thread: Number(id), params: r.query });
      return noRoute(r);
    },
  },
  { method: "GET", pattern: /^\/jobs$/, handle: (r) => read(r, "openJobs", { viewer: r.viewer, lang: r.lang }) },
  {
    method: "GET",
    pattern: /^\/*jobs\/+([^/]+)(?:\/+([^/]+))?(?:\/.*)?$/,
    handle: async (r, [rawId, rawAction]) => {
      const id = segment(rawId!);
      const action = rawAction === undefined ? undefined : segment(rawAction);
      if (action === undefined) return read(r, "job", { id });
      if (action === "log") return read(r, "jobLog", { id, lines: param(r, "lines") });
      return noRoute(r);
    },
  },
];
