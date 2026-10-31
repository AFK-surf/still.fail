// What the pages ask of the hub, the jobs and the files (admin/mod.rs `route`, admin/files.rs): new chats and sessions,
// uploads, messages, adding a session to a chat, archiving, deleting, stopping, evicting, warming, a session's settings,
// clearing a chat's ended jobs, stopping a job. What is only written to the store is routes/marks.ts's; the reads are
// routes/chats.ts's and routes/sessions.ts's (GET /sessions/:key/files among them).
import { createHash, randomBytes, type Hash } from "node:crypto";
import { appendFileSync, constants as fsConstants, copyFileSync, mkdirSync, readdirSync, renameSync, rmSync, statSync, statfsSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { clean, fileName as nameOf, inside } from "../../ops/paths.ts";
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
import { relay, relayPeople, relayPlaces } from "../../sessions/relay.ts";
import { cc } from "../../sessions/cc.ts";
import { shown } from "../../jobs/jobs.ts";
import { withLock, workspaceFile } from "../../sessions/archive.ts";
import { roomOf } from "../../sessions/footprint.ts";
import { dir as thumbsDir, keep } from "../../drive/thumbs.ts";
import { shownFacts } from "../../sessions/image-size.ts";
import { wall } from "../../ops/fibers.ts";
import { sessionSeen } from "../seen.ts";
import { runtimeKind } from "../../agents/runtime.ts";

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

/// files.rs: the most an upload in one request takes; how long a staged upload waits for a message to take it.
const MAX_UPLOAD = 50 * 1024 * 1024;
/// An upload in parts (POST /uploads/parts): the most the whole file takes, and one part.
export const MAX_PARTS_UPLOAD = 1024 * 1024 * 1024;
const MAX_PART = 16 * 1024 * 1024;
/// Room left on the disk after an upload in parts.
const DISK_SPARE = 1024 * 1024 * 1024;
/// A part file's name in the uploads: never a file a message can send.
const PART_PREFIX = ".part-";
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

const exists = (path: string) => statSync(path, { throwIfNoEntry: false }) !== undefined;
/// Path::file_name.
const fileName = (path: string) => nameOf(path) ?? "";

/// files.rs `sweep_staged`: drops uploads that waited a day without a message taking them.
export function sweepStaged(dir: string, now = wall.now()) {
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

/// Where an upload named `name` is kept in `dir`: its name made safe, and a path of its own.
export function uploadPath(dir: string, name: string): { safe: string; path: string } {
  const base = name.replace(/\\/g, "/").split("/").at(-1) ?? "";
  const safe = chars([...base].map((c) => (c.codePointAt(0)! < 0x20 ? "_" : c)).join("").replace(/^\.+/, ""), 120) || "file";
  mkdirSync(dir, { recursive: true });
  const stamp = new Date(wall.now()).toISOString().slice(0, 19).replace(/[:.]/g, "-");
  const random = randomBytes(3).toString("hex");
  return { safe, path: join(dir, `${stamp}-${random}-${safe}`) };
}

/// files.rs `save_upload`: a request's body kept in `dir` under its name, made safe and unique.
function saveUpload(body: Buffer, dir: string, name: string, lang: Request["lang"]): Attachment {
  const { safe, path } = uploadPath(dir, name);
  if (body.length > MAX_UPLOAD) throw new Refused(413, tr(lang, "station.files.tooLarge"));
  writeFileSync(path, body, { flag: "wx" });
  known(dir, createHash("sha256").update(body).digest("hex"), path);
  return { name: safe, path, size: body.length };
}

/// What the uploads hold, by their content (SHA-256, hex), for each station's uploads folder: a file sent again (the
/// same picture to another chat) is copied from where it is kept now, and nothing of it comes again. Each where it is
/// now (a message takes it into its chat's uploads: `moved`), with its size and when it last changed, so one changed or
/// gone since is not taken for it. In memory only: one sent before the station started comes again.
const contents = new Map<string, Map<string, { path: string; size: number; mtimeMs: number }>>();
const CONTENTS_KEEP = 1000;
/// Uploads in parts named as their parts come, by id (one whose first part came before the station started is not).
const naming = new Map<string, Hash>();
const NAMING_KEEP = 100;

/// `path`, a whole upload in the uploads folder `dir`, is `sha256`.
function known(dir: string, sha256: string, path: string): void {
  const st = statSync(path, { throwIfNoEntry: false });
  if (!st) return;
  const key = clean(dir);
  let held = contents.get(key);
  if (!held) contents.set(key, (held = new Map()));
  held.delete(sha256);
  held.set(sha256, { path, size: st.size, mtimeMs: st.mtimeMs });
  for (const old of held.keys()) {
    if (held.size <= CONTENTS_KEEP) break;
    held.delete(old);
  }
}

/// An upload of `dir` moved (into a chat's uploads, as a message takes it): known there now.
export function movedUpload(dir: string, from: string, to: string): void {
  for (const e of contents.get(clean(dir))?.values() ?? []) if (e.path === from) e.path = to;
}

/// Where `dir`'s uploads keep a file of `size` bytes that is `sha256`, unchanged since: null when none is.
function kept(dir: string, sha256: string, size: number): string | null {
  const held = contents.get(clean(dir));
  const e = held?.get(sha256);
  if (!held || !e) return null;
  const st = statSync(e.path, { throwIfNoEntry: false });
  if (!st?.isFile() || st.size !== size || e.size !== size || st.mtimeMs !== e.mtimeMs) {
    held.delete(sha256);
    return null;
  }
  return e.path;
}

/// Uploads in parts that are whole, by their id: a part asked again after its file was put together gets the file.
const assembled = new Map<string, { at: number; file: Attachment }>();
const ASSEMBLED_KEEP_MS = 3600_000;

/// POST /uploads/parts?id=&name=&size=&offset=: a part of a file at `offset`, added to what came of it before (kept as
/// `.part-<id>` in the uploads). The answer is how much of it is here (`have`), and the file once it is whole. A part
/// that does not start where the file ends adds nothing: the caller goes on from `have` (one asked again after a lost
/// answer, or after a broken connection, is answered as the first was). With `sha256` and no bytes, before its first
/// part: a file the uploads hold already (sent before) is copied from there and answered whole, and nothing comes.
export function savePart(body: Buffer, dir: string, q: { id: string; name: string; size: number; offset: number; sha256?: string | undefined }, lang: Request["lang"]): { have: number; file?: Attachment } {
  const now = wall.now();
  for (const [k, v] of assembled) if (now - v.at > ASSEMBLED_KEEP_MS) assembled.delete(k);
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(q.id)) throw new Refused(400, "invalid upload id");
  if (!Number.isSafeInteger(q.size) || q.size < 0 || !Number.isSafeInteger(q.offset) || q.offset < 0 || q.offset > q.size) throw new Refused(400, "invalid upload size or offset");
  if (q.size > MAX_PARTS_UPLOAD) throw new Refused(413, tr(lang, "station.files.tooLargeParts"));
  if (body.length > MAX_PART || q.offset + body.length > q.size) throw new Refused(413, "upload part too large");
  if (q.sha256 !== undefined && !/^[0-9a-f]{64}$/.test(q.sha256)) throw new Refused(400, "invalid sha256");
  const done = assembled.get(q.id);
  if (done !== undefined) return { have: q.size, file: done.file };
  mkdirSync(dir, { recursive: true });
  const part = join(dir, `${PART_PREFIX}${q.id}`);
  const have = statSync(part, { throwIfNoEntry: false })?.size ?? 0;
  if (q.sha256 !== undefined && q.offset === 0 && body.length === 0 && have === 0) {
    const from = kept(dir, q.sha256, q.size);
    if (from !== null) {
      const { safe, path } = uploadPath(dir, q.name);
      // A copy of its own (a clone where the disk makes one): the chat it goes to may change it, the other not.
      copyFileSync(from, path, fsConstants.COPYFILE_FICLONE);
      known(dir, q.sha256, path);
      const file = { name: safe, path, size: q.size };
      assembled.set(q.id, { at: now, file });
      return { have: q.size, file };
    }
  }
  if (have > q.size) {
    rmSync(part, { force: true });
    throw new Refused(400, "invalid upload size");
  }
  if (have === 0 && q.offset === 0) {
    // A new file: refused at once when the disk cannot take it.
    try {
      const fs = statfsSync(dir);
      if (fs.bavail * fs.bsize < q.size + DISK_SPARE) throw new Refused(507, tr(lang, "station.files.noRoom"));
    } catch (e) {
      if (e instanceof Refused) throw e;
    }
  }
  // Only what follows the file's end is added: none of a part asked again, the rest of one that overlaps it.
  if (q.offset <= have && q.offset + body.length > have) {
    const added = body.subarray(have - q.offset);
    if (have === 0) {
      naming.set(q.id, createHash("sha256"));
      for (const old of naming.keys()) {
        if (naming.size <= NAMING_KEEP) break;
        naming.delete(old);
      }
    }
    appendFileSync(part, added);
    naming.get(q.id)?.update(added);
  }
  const got = statSync(part, { throwIfNoEntry: false })?.size ?? 0;
  if (got < q.size) return { have: got };
  const { safe, path } = uploadPath(dir, q.name);
  renameSync(part, path);
  const named = naming.get(q.id);
  naming.delete(q.id);
  if (named) known(dir, named.digest("hex"), path);
  const file = { name: safe, path, size: q.size };
  assembled.set(q.id, { at: now, file });
  return { have: q.size, file };
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

export const routes = (tools: Tools): Route[] => {
  const { read, store } = tools;
  /// Answered with the hub, its refusals as `{error}`; 503 while there is none (a station starting). The agents' side as it
  /// is when asked (made after the admin API: services.ts AgentsSide).
  const write = async (f: (s: Store, a: AgentsParts) => Promise<Answer> | Answer): Promise<Answer> => {
    const agents = tools.agents;
    if (store === undefined || agents === undefined) return error(503, "station starting");
    try {
      return await f(store, agents);
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      return error(500, (e as Error).message);
    }
  };
  /// A session there, and in the asker's workspace (one of another is none for them: api/seen.ts).
  const session = (s: Store, key: string, r: Request) => {
    if (s.getSession(key) === null || !sessionSeen(s, r.viewer, key)) throw new Refused(404, `unknown session ${key}`);
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
    const named = runtimeKind(text(i.runtime));
    if (named === undefined) throw new Refused(400, tr(r.lang, "station.admin.badRuntime"));
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
      if (inside(path, stagedDir) && fileName(path).startsWith(PART_PREFIX)) throw new Refused(400, tr(r.lang, "station.files.notUploaded"));
      if (inside(path, stagedDir) && first !== undefined) {
        const into = join(first.dir, fileName(path));
        // Sent again (a retry after the first try got here): it has moved already.
        if (exists(path)) {
          mkdirSync(first.dir, { recursive: true });
          renameSync(path, into);
          movedUpload(stagedDir, path, into);
        }
        path = into;
      }
      const owner = dirs.find((d) => inside(path, d.dir));
      if (!exists(path) && owner !== undefined) {
        // Packed with its archived workspace: read back out of its archive, under its lock.
        const workspace = dirname(owner.dir);
        const room = roomOf(a.hub.config().dataDir, workspace);
        if (room !== null) {
          const bytes = await withLock(room, () => workspaceFile(room, path.slice(workspace.length + 1)));
          if (bytes !== null) {
            mkdirSync(dirname(path), { recursive: true });
            writeFileSync(path, bytes);
          }
        }
      }
      if (owner === undefined || !exists(path)) throw new Refused(400, tr(r.lang, "station.files.notUploaded"));
      // Its size as the sender read it; else, for a picture or a film, as its header says (a sender that could not read
      // it: the desktop's could not, nor a phone's core a JPEG's or any film's, image-size.ts); a film's length and
      // frames as its header says.
      const read = [dimension(o.width), dimension(o.height)];
      const facts = shownFacts(path);
      const [width, height] = read[0] !== undefined && read[1] !== undefined ? read : (facts ? [facts.width, facts.height] : read);
      const name = str(o.name) ?? path.slice(owner.dir.length + 1);
      const size = typeof o.size === "number" && o.size > 0 ? Math.min(Math.trunc(o.size), Number.MAX_SAFE_INTEGER) : 0;
      const attachment: Attachment = { name: chars(name, 200), path, size };
      if (width !== undefined && height !== undefined) Object.assign(attachment, { width, height });
      if (facts?.duration !== undefined) attachment.duration = facts.duration;
      if (facts?.frames !== undefined) attachment.frames = facts.frames;
      out.push(attachment);
    }
    return out;
  };

  /// admin/mod.rs Input::text: JavaScript's String(x ?? "").
  const said = (v: unknown) => (v === undefined || v === null ? "" : typeof v === "string" ? v : JSON.stringify(v));
  /// A development station's (STILLFAIL_DEV=1, else EMBER_DEV=1): only there is /dev/inject a route.
  const dev = (process.env.STILLFAIL_DEV || process.env.EMBER_DEV) === "1";
  return [
    // Hands the station a chat message as if the connect had received it (development stations, for those who manage
    // them; anyone else finds no such route).
    ...(dev
      ? [
          {
            method: "POST",
            pattern: /^\/dev\/inject$/,
            handle: (r: Request) =>
              r.viewer.role !== "owner" && r.viewer.role !== "admin"
                ? Promise.resolve(error(404, `no route ${r.method} ${r.path}`))
                : write(async (_s, a) => {
                    const i = input(r);
                    const ts = said(i.ts);
                    await a.hub.accept(said(i.connect), {
                      channel: said(i.channel),
                      threadTs: typeof i.threadTs === "string" ? i.threadTs : ts,
                      ts,
                      user: said(i.user),
                      text: said(i.text),
                      addressed: i.addressed !== false,
                    });
                    return ok({ ok: true });
                  }),
          },
        ]
      : []),
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
                ws: r.viewer.workspace || null,
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
          // Only Claude Code's and Codex's terminal sessions are read (read/machine.ts).
          const found = kind === "dsh" || kind === "grok" || kind === "cursor" || kind === "devin" || kind === "hermes" ? null : findMachineSession(roots, kind, id);
          if (found === null) throw new Refused(404, tr(r.lang, "station.admin.noLocalSession", { id }));
          const [key, chat] = await as(400, () => continueMachineSession(a.hub, roots, found, r.viewer.email, r.lang, r.viewer.home === false ? r.viewer.workspace : null));
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
          session(s, key, r);
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
    // A file in parts (savePart): a big one goes up a piece at a time, and on from where it was after a broken connection.
    {
      method: "POST",
      pattern: /^\/uploads\/parts$/,
      handle: (r) =>
        write((_s, a) => {
          const dir = staged(a);
          sweepStaged(dir);
          const num = (name: string) => {
            const v = param(r, name);
            return v === undefined || !/^[0-9]+$/.test(v) ? -1 : Number(v);
          };
          return ok(savePart(r.body, dir, { id: param(r, "id") ?? "", name: param(r, "name") ?? "file", size: num("size"), offset: num("offset"), sha256: param(r, "sha256") }, r.lang));
        }),
    },
    // A session: deleted (DELETE); its ended jobs cleared.
    {
      method: "DELETE",
      pattern: /^\/*sessions\/+([^/]+)\/*$/,
      handle: (r, [k]) =>
        write(async (s, a) => {
          const key = segment(k!);
          session(s, key, r);
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
          session(s, key, r);
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
          write(async (s, a) => {
            const key = segment(k!);
            session(s, key, r);
            await archive(a.hub, key, method === "POST");
            return read(r, "summary", { key, lang: r.lang });
          }),
      }),
    ),
    {
      method: "POST",
      pattern: /^\/*sessions\/+([^/]+)\/+(stop|evict|warm|compact|clear|settings)(?:\/.*)?$/,
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
            // Its context compacted (begun: its end is said in its chat), or cleared (`readBack`: to go on afresh, its
            // cache over); refused while it runs.
            case "compact":
            case "clear": {
              session(s, key, r);
              const refused = await (action === "compact" ? a.hub.compact(key) : a.hub.clear(key, input(r).readBack === true));
              if (refused !== null) throw new Refused(409, refused);
              log.info("admin", `session ${action === "compact" ? "compacted" : "cleared"} from the admin page`, { session: key, by: r.viewer.email });
              return ok({ ok: true });
            }
            case "warm":
              session(s, key, r);
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
              // Given back to the station and its account picked again now.
              if (i.repick === true) change.repick = true;
              // Whether it goes on afresh once its cache is over: null gives it back to the station's setting.
              if ("afresh" in i) {
                if (i.afresh !== null && typeof i.afresh !== "boolean") throw new Refused(400, "afresh is true, false or null");
                change.afresh = i.afresh;
              }
              if ("fast" in i) {
                if (i.fast !== null && typeof i.fast !== "boolean") throw new Refused(400, tr(r.lang, "station.admin.badFast"));
                change.fast = i.fast;
              }
              await as(400, () => configure(a.hub, key, change, r.lang));
              // With the profile it runs on now (picked again: the one picked).
              return ok({ ok: true, profile: a.hub.store.getSession(key)?.profile ?? null });
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
          // Copied to the Slack and Feishu threads of the chat its sender picked (docs/relay.md "抄送"): after the answer,
          // not waited on.
          const ccTo = Array.isArray(i.cc) ? i.cc.filter((x: unknown): x is number => typeof x === "number") : [];
          if (ccTo.length > 0) void cc(a.hub, t.id, r.viewer.name.trim() || r.viewer.email, r.viewer.email, said, kept, ccTo);
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
          session(s, key, r);
          await as(400, () => addToThread(a.hub, t.id, key));
          return threadView(r, t.id);
        }),
    },
    // The people of where the chat would be relayed (`?connect=&channel=`, or `?link=` of a Slack message), for its note
    // to mention (docs/relay.md「附言里 @ 人」).
    {
      method: "GET",
      pattern: /^\/*threads\/+([^/]+)\/+relay\/+people\/*$/,
      handle: (r, [rawId]) =>
        write(async (s, a) => {
          const t = thread(s, segment(rawId!));
          const q = (name: string) => (r.query.find(([k]) => k === name)?.[1] ?? "").trim();
          const [connect, channel, link] = [q("connect"), q("channel"), q("link")];
          if (link === "" && (connect === "" || channel === "")) throw new Refused(400, tr(r.lang, "station.relay.pick"));
          const target = link !== "" ? { link, ...(connect !== "" ? { connect } : {}) } : { connect, channel };
          return ok({ people: await as(400, () => relayPeople(a.hub, t, target)) });
        }),
    },
    // Where the chat can be relayed (docs/relay.md): each connect's channels and groups its bot is in.
    {
      method: "GET",
      pattern: /^\/*threads\/+([^/]+)\/+relay(?:\/.*)?$/,
      handle: (_r, [rawId]) =>
        write(async (s, a) => {
          const t = thread(s, segment(rawId!));
          return ok({ connects: await as(400, () => relayPlaces(a.hub, t)) });
        }),
    },
    // The chat relayed to one of them (`{connect, channel}`), or to the Slack thread of a message's link (`{link}`), with
    // a `note`: where it went on.
    {
      method: "POST",
      pattern: /^\/*threads\/+([^/]+)\/+relay(?:\/.*)?$/,
      handle: (r, [rawId]) =>
        write(async (s, a) => {
          const t = thread(s, segment(rawId!));
          const i = input(r);
          const connect = text(i.connect).trim();
          const channel = text(i.channel).trim();
          const link = text(i.link).trim();
          if (link === "" && (connect === "" || channel === "")) throw new Refused(400, tr(r.lang, "station.relay.pick"));
          const by = { name: r.viewer.name.trim() || r.viewer.email, email: r.viewer.email };
          return ok(await as(400, () => relay(a.hub, t, by, link !== "" ? { link, ...(connect !== "" ? { connect } : {}) } : { connect, channel }, chars(text(i.note), 2000))));
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
