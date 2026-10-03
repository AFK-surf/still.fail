// What the pages ask of the hub, the jobs and the files (admin/mod.rs `route`, admin/files.rs): new chats and sessions,
// uploads, messages, adding a session to a chat, archiving, deleting, stopping, evicting, warming, a session's settings,
// clearing a chat's ended jobs, stopping a job. What is only written to the store is routes/marks.ts's; the reads are
// routes/chats.ts's and routes/sessions.ts's (GET /sessions/:key/files among them).
import { randomBytes } from "node:crypto";
import { mkdirSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Answer, type Request, error, json, param, percentDecode } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { tr } from "../../ops/i18n.ts";
import { log } from "../../ops/log.ts";
import { find as findMachineSession, roots as machineRoots } from "../../read/machine.ts";
import { STILLFAIL_SURFACE } from "../../store/rows.ts";
import type { Attachment, Quote } from "../../store/rows.ts";
import type { Store } from "../../store/store.ts";
import type { AgentsParts } from "../../sessions/agents.ts";
import type { SessionChange } from "../../sessions/accounts.ts";
import {
  addToThread,
  archive,
  archiveChat,
  configure,
  continueMachineSession,
  deleteSession,
  newSession,
  openChat,
  say,
} from "../../sessions/lifecycle.ts";
import { shown } from "../../jobs/jobs.ts";
import { dir as thumbsDir, keep } from "../../sessions/thumbs.ts";

const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));
const ok = (value: unknown, status = 200) => json(status, JSON.stringify(value));
class Refused extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}
/// A hub error the Rust maps to a status (`map_err(|e| http_error(status, e.to_string()))`).
async function as<T>(status: number, f: () => T | Promise<T>): Promise<T> {
  try {
    return await f();
  } catch (e) {
    if (e instanceof Refused) throw e;
    throw new Refused(status, (e as Error).message);
  }
}

/// files.rs: the most an upload takes; how long a staged upload waits for a message to take it.
const MAX_UPLOAD = 50 * 1024 * 1024;
const STAGED_FOR_MS = 24 * 3600 * 1000;

/// A request's JSON object (`read_json`): nothing is `{}`, as is anything not an object; more than a megabyte refused.
function input(r: Request): Record<string, unknown> {
  if (r.body.length > 1_000_000) throw new Refused(413, "request too large");
  if (r.body.length === 0) return {};
  let value: unknown;
  try {
    value = JSON.parse(r.body.toString("utf8"));
  } catch {
    throw new Refused(400, "invalid JSON");
  }
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

/// `Input::text`: JavaScript's String(x ?? "") as serde writes it.
const text = (v: unknown): string => (v === undefined || v === null ? "" : typeof v === "string" ? v : JSON.stringify(v));
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const chars = (s: string, max: number) => [...s].slice(0, max).join("");

/// files.rs `clean`: a path absolute, with `.` and `..` worked out (no link followed).
function clean(path: string): string {
  const out: string[] = [];
  for (const part of path.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") out.pop();
    else out.push(part);
  }
  return `/${out.join("/")}`;
}
/// Path::starts_with, component by component, and not the directory itself.
const inside = (path: string, dir: string) => path !== dir && (dir === "/" || path.startsWith(`${dir}/`));
const exists = (path: string) => statSync(path, { throwIfNoEntry: false }) !== undefined;
/// Path::file_name.
const fileName = (path: string) => path.split("/").filter((p) => p !== "").at(-1) ?? "";

/// files.rs `sweep_staged`: drops uploads that waited a day without a message taking them.
export function sweepStaged(dir: string, now = Date.now()) {
  let names: string[];
  try {
    names = readdirSync(dir);
  } catch {
    return;
  }
  for (const name of names) {
    const st = statSync(join(dir, name), { throwIfNoEntry: false });
    if (st?.isFile() && now - st.mtimeMs > STAGED_FOR_MS) rmSync(join(dir, name), { force: true });
  }
}

/// files.rs `save_upload`: a request's body kept in `dir` under its name, made safe and unique.
function saveUpload(body: Buffer, dir: string, name: string, lang: Request["lang"]): Attachment {
  const base = name.replace(/\\/g, "/").split("/").at(-1) ?? "";
  const safe = chars([...base].map((c) => (c.codePointAt(0)! < 0x20 ? "_" : c)).join("").replace(/^\.+/, ""), 120) || "file";
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().slice(0, 19).replace(/[:.]/g, "-");
  const random = randomBytes(3).toString("hex");
  const path = join(dir, `${stamp}-${random}-${safe}`);
  if (body.length > MAX_UPLOAD) throw new Refused(413, tr(lang, "station.files.tooLarge"));
  writeFileSync(path, body, { flag: "wx" });
  return { name: safe, path, size: body.length };
}

/// files.rs `quotes_of`: quotes as the page sends them, bounded.
export function quotesOf(given: unknown): Quote[] {
  if (!Array.isArray(given)) return [];
  const field = (q: any, k: string, fallback: string, max: number) => {
    const v = q !== null && typeof q === "object" ? q[k] : undefined;
    return v === undefined || v === null ? fallback : chars(typeof v === "string" ? v : JSON.stringify(v), max);
  };
  const out: Quote[] = [];
  for (const q of given.slice(0, 20)) {
    const o = q !== null && typeof q === "object" && !Array.isArray(q) ? (q as Record<string, unknown>) : {};
    const quote: Quote = { author: field(o, "author", "消息", 100), text: field(o, "text", "", 4000), comment: field(o, "comment", "", 4000) };
    if (typeof o.ts === "string" && /^[0-9]+\.[0-9]+$/.test(o.ts)) quote.ts = o.ts;
    if (typeof o.role === "string" && ["agent", "person", "page", "image"].includes(o.role)) quote.role = o.role;
    if (typeof o.file === "string" && o.file !== "") quote.file = chars(o.file, 200);
    if (quote.text.trim() !== "") out.push(quote);
  }
  return out;
}

/// A whole dimension (`as_f64`, no fraction, 0 < v < 100000).
const dimension = (v: unknown) => (typeof v === "number" && Number.isInteger(v) && v > 0 && v < 100_000 ? v : undefined);

export const routes = ({ read, store, agents }: Tools): Route[] => {
  /// Answered with the hub, its refusals as `{error}`; 503 while there is none (a station starting).
  const write = async (f: (s: Store, a: AgentsParts) => Promise<Answer> | Answer): Promise<Answer> => {
    if (store === undefined || agents === undefined) return error(503, "station starting");
    try {
      return await f(store, agents);
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      return error(500, (e as Error).message);
    }
  };
  const session = (s: Store, key: string) => {
    if (s.getSession(key) === null) throw new Refused(404, `unknown session ${key}`);
  };
  const thread = (s: Store, id: string) => {
    const n = /^[+-]?\d+$/.test(id) ? Number(id) : NaN;
    const found = Number.isSafeInteger(n) ? s.getThread(n) : null;
    if (found === null) throw new Refused(404, `unknown thread ${id}`);
    return found;
  };
  const threadView = (r: Request, id: number) => read(r, "thread", { id: String(id), viewer: r.viewer, lang: r.lang });
  /// `{key, thread}`: a session made with its chat, the chat as GET /threads/:id has it.
  const made = async (r: Request, key: string, id: number) => {
    const view = await threadView(r, id);
    if (view.status !== 200) return view;
    return json(200, `{"key":${JSON.stringify(key)},"thread":${view.body.toString()}}`);
  };
  const runtime = (r: Request, i: Record<string, unknown>) => {
    const named = text(i.runtime);
    if (named !== "claude" && named !== "codex") throw new Refused(400, tr(r.lang, "station.admin.badRuntime"));
    return named;
  };
  /// Where uploaded files wait for the message that sends them.
  const staged = (a: AgentsParts) => join(a.hub.config().dataDir, "uploads");

  /// files.rs `attachments`: files named in a message: ones waiting in the uploads (they move into the upload
  /// directory of the chat's first session, where its agents read them), or ones already in the upload directory of
  /// one of its sessions (taken out of its archive when it was packed).
  const attachments = async (r: Request, s: Store, a: AgentsParts, id: number, given: unknown): Promise<Attachment[]> => {
    const dirs = s
      .threadSessions(id)
      .map((m) => s.getSession(m.session))
      .filter((row) => row !== null)
      .map((row) => ({ key: row.key, dir: clean(join(row.workspace, "uploads")) }));
    const stagedDir = clean(staged(a));
    const out: Attachment[] = [];
    for (const item of Array.isArray(given) ? given.slice(0, 20) : []) {
      const o = item !== null && typeof item === "object" && !Array.isArray(item) ? (item as Record<string, unknown>) : {};
      let path = clean(str(o.path) ?? "");
      const first = dirs[0];
      if (inside(path, stagedDir) && first !== undefined) {
        const into = join(first.dir, fileName(path));
        // Sent again (a retry after the first try got here): it has moved already.
        if (exists(path)) {
          mkdirSync(first.dir, { recursive: true });
          renameSync(path, into);
        }
        path = into;
      }
      const owner = dirs.find((d) => inside(path, d.dir));
      if (!exists(path) && owner !== undefined && path.slice(owner.dir.length + 1).indexOf("/") < 0) {
        // Packed with its archived workspace: read back out of it (the readers know how).
        const found = await read(r, "sessionFile", { key: owner.key, name: fileName(path), thumb: false, lang: r.lang });
        if (found.status === 200 && Buffer.isBuffer(found.body)) {
          mkdirSync(owner.dir, { recursive: true });
          writeFileSync(path, Buffer.from(JSON.parse(found.body.toString("utf8")).base64, "base64"));
        }
      }
      if (owner === undefined || !exists(path)) throw new Refused(400, tr(r.lang, "station.files.notUploaded"));
      const [width, height] = [dimension(o.width), dimension(o.height)];
      const name = str(o.name) ?? path.slice(owner.dir.length + 1);
      const size = typeof o.size === "number" && o.size > 0 ? Math.min(Math.trunc(o.size), Number.MAX_SAFE_INTEGER) : 0;
      const attachment: Attachment = { name: chars(name, 200), path, size };
      if (width !== undefined && height !== undefined) Object.assign(attachment, { width, height });
      out.push(attachment);
    }
    return out;
  };

  return [
    // A new chat: its session and its thread are made first, so files can be uploaded into it before the first message.
    {
      method: "POST",
      pattern: /^\/sessions$/,
      handle: (r) =>
        write(async (_s, a) => {
          const i = input(r);
          const given = (k: string) => (typeof i[k] === "string" && i[k] !== "" ? (i[k] as string) : null);
          const [key, chat] = await as(400, () =>
            newSession(
              a.hub,
              {
                runtime: runtime(r, i),
                profile: given("profile"),
                model: given("model"),
                effort: given("effort"),
                fast: typeof i.fast === "boolean" ? i.fast : null,
                title: typeof i.title === "string" ? chars(i.title, 120) : null,
                createdBy: r.viewer.email,
                clientKey: given("clientKey"),
              },
              r.lang,
            ),
          );
          return made(r, key, chat.id);
        }),
    },
    // Going on in a chat with a session this machine's own Claude Code or Codex kept.
    {
      method: "POST",
      pattern: /^\/machine-sessions$/,
      handle: (r) =>
        write(async (_s, a) => {
          const i = input(r);
          const kind = runtime(r, i);
          const id = text(i.id);
          const roots = machineRoots();
          const found = findMachineSession(roots, kind, id);
          if (found === null) throw new Refused(404, tr(r.lang, "station.admin.noLocalSession", { id }));
          const [key, chat] = await as(400, () => continueMachineSession(a.hub, roots, found, r.viewer.email, r.lang));
          log.info("admin", "machine session continued from the admin page", { session: key, from: id, by: r.viewer.email });
          return made(r, key, chat.id);
        }),
    },
    // Another chat on the pages with a session in it.
    {
      method: "POST",
      pattern: /^\/threads$/,
      handle: (r) =>
        write((s, a) => {
          const i = input(r);
          const key = text(i.session);
          session(s, key);
          const t = typeof i.title === "string" ? i.title.trim() : "";
          const chat = openChat(a.hub, key, r.viewer.email, t === "" ? null : chars(t, 80));
          return threadView(r, chat.id);
        }),
    },
    // Files wait here, in no chat, until a message takes them into its chat: choosing a file for a new chat makes nothing.
    {
      method: "POST",
      pattern: /^\/uploads$/,
      handle: (r) =>
        write((_s, a) => {
          const dir = staged(a);
          sweepStaged(dir);
          return ok(saveUpload(r.body, dir, param(r, "name") ?? "file", r.lang));
        }),
    },
    // A session: deleted (DELETE); its ended jobs cleared.
    {
      method: "DELETE",
      pattern: /^\/*sessions\/+([^/]+)\/*$/,
      handle: (r, [k]) =>
        write(async (s, a) => {
          const key = segment(k!);
          session(s, key);
          await deleteSession(a.hub, key);
          log.info("admin", "session deleted from the admin page", { session: key, by: r.viewer.email });
          return ok({ ok: true });
        }),
    },
    {
      method: "DELETE",
      pattern: /^\/*sessions\/+([^/]+)\/+jobs(?:\/.*)?$/,
      handle: (r, [k]) =>
        write((s, a) => {
          const key = segment(k!);
          session(s, key);
          const removed = a.jobs.clearEnded(key);
          log.info("admin", "ended jobs cleared from the admin page", { session: key, by: r.viewer.email, count: removed.length });
          return ok({ removed });
        }),
    },
    // A session archived (POST) or shown again (DELETE): answered with its summary.
    ...["POST", "DELETE"].map(
      (method): Route => ({
        method,
        pattern: /^\/*sessions\/+([^/]+)\/+archive(?:\/.*)?$/,
        handle: (r, [k]) =>
          write((s, a) => {
            const key = segment(k!);
            session(s, key);
            archive(a.hub, key, method === "POST");
            return read(r, "summary", { key, lang: r.lang });
          }),
      }),
    ),
    {
      method: "POST",
      pattern: /^\/*sessions\/+([^/]+)\/+(stop|evict|warm|settings)(?:\/.*)?$/,
      handle: (r, [k, action]) =>
        write(async (s, a) => {
          const key = segment(k!);
          switch (action) {
            case "stop":
              await a.hub.stop(key);
              return ok({ ok: true });
            case "evict":
              await a.hub.evict(key);
              return ok({ ok: true });
            case "warm":
              session(s, key);
              a.hub.warm(key).catch((e) => log.warn("admin", "warming failed", { session: key, error: (e as Error).message }));
              return ok({ ok: true }, 202);
            // How the session runs from its next turn on: its profile, model, effort (configure).
            default: {
              const i = input(r);
              const pick = (name: string): string | null | undefined => (!(name in i) ? undefined : i[name] === null ? null : text(i[name]));
              const change: SessionChange = {};
              const model = pick("model");
              const effort = pick("effort");
              if (model !== undefined) change.model = model;
              if (effort !== undefined) change.effort = effort;
              // A profile's id keeps the session to it; null gives the choice back to the station.
              if (typeof i.profile === "string" || i.profile === null) change.profile = i.profile;
              if ("fast" in i) {
                if (i.fast !== null && typeof i.fast !== "boolean") throw new Refused(400, tr(r.lang, "station.admin.badFast"));
                change.fast = i.fast;
              }
              await as(400, () => configure(a.hub, key, change, r.lang));
              return ok({ ok: true });
            }
          }
        }),
    },
    // A background job stopped from the pages, as its agent's job_stop does.
    {
      method: "POST",
      pattern: /^\/*jobs\/+([^/]+)\/+stop(?:\/.*)?$/,
      handle: (r, [id]) =>
        write(async (s, a) => {
          const job = await a.jobs.stopFor(segment(id!), r.viewer.email);
          log.info("admin", "job stopped from the admin page", { job: job.id, by: r.viewer.email });
          return ok(shown(s, job));
        }),
    },
    // A person's message in a chat on the pages, with its files and quotes.
    {
      method: "POST",
      pattern: /^\/*threads\/+([^/]+)\/+messages(?:\/.*)?$/,
      handle: (r, [rawId]) =>
        write(async (s, a) => {
          const t = thread(s, segment(rawId!));
          if (t.surface !== STILLFAIL_SURFACE) throw new Refused(400, tr(r.lang, "station.admin.postOnlyStillfail"));
          const i = input(r);
          const said = text(i.text).trim();
          const files = await attachments(r, s, a, t.id, i.attachments);
          const quotes = quotesOf(i.quotes);
          if (said === "" && files.length === 0 && quotes.length === 0) throw new Refused(400, tr(r.lang, "station.admin.emptyMessage"));
          let answeredCard: number | null = null;
          const pending = s.pendingCard(t.id);
          if (pending !== null) {
            const [asked, card] = pending;
            const options: unknown[] = Array.isArray(card?.options) ? card.options : [];
            const selected = options.some((o: any) => o !== null && typeof o === "object" && o.label === said && o.action === "close");
            const quoted = Array.isArray(i.quotes) && i.quotes.some((q: any) => q !== null && typeof q === "object" && q.ts === asked.ts);
            if (files.length === 0 && selected && quoted) throw new Refused(409, tr(r.lang, "station.admin.updateClientForOption"));
            if (quoted) answeredCard = asked.n;
          }
          // Which app sent it ("android 0.1.1123"): for its agent, never shown. Older apps say nothing.
          const client = typeof i.client === "string" ? chars([...i.client.trim()].filter((c) => !/\p{Cc}/u.test(c)).join(""), 80) : "";
          const kept = await keep(files, thumbsDir(a.hub.config().dataDir));
          const n = say(a.hub, t.id, r.viewer.email, said, kept, quotes, client === "" ? null : client);
          // Answering from the decisions page means the question was read, even without opening its chat. Stop at that
          // card: later messages may not have been seen.
          if (answeredCard !== null) s.setRead(r.viewer.email, t.id, answeredCard);
          return ok({ n });
        }),
    },
    // Another session brought into a chat.
    {
      method: "POST",
      pattern: /^\/*threads\/+([^/]+)\/+sessions(?:\/.*)?$/,
      handle: (r, [rawId]) =>
        write(async (s, a) => {
          const t = thread(s, segment(rawId!));
          const key = text(input(r).session);
          session(s, key);
          await as(400, () => addToThread(a.hub, t.id, key));
          return threadView(r, t.id);
        }),
    },
    // A chat archived or shown again: with its session when it is that session's own.
    ...["POST", "DELETE"].map(
      (method): Route => ({
        method,
        pattern: /^\/*threads\/+([^/]+)\/+archive(?:\/.*)?$/,
        handle: (r, [rawId]) =>
          write(async (s, a) => {
            const t = thread(s, segment(rawId!));
            await as(400, () => archiveChat(a.hub, t.id, method === "POST"));
            return threadView(r, t.id);
          }),
      }),
    ),
  ];
};
