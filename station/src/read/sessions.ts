// Sessions and threads as the pages read them, ported from the Rust station's admin/views.rs (`summary`, `sessions`, `session`,
// `threads`, `thread`, `thread_view`) and admin/mod.rs (GET /sessions/:key/timeline, /widget-state), with the same JSON,
// field for field and in serde_json's order. A file sent in a chat is found by its route, not read here
// (api/routes/sessions.ts `uploaded`).
//
// What the Rust station keeps outside the database is taken as views.ts takes it (a station with none of it):
// - the hub: no session has a runtime process (`process` "cold"); no transcript is watched, so a timeline is read from
//   the transcript's file each time, as the Rust does for a session nobody follows;
// - Slack names: as the names book has them (slack-known.ts), never waiting on Slack (a Slack user
//   goes by their id, with no email);
// - the cloud's names: those of the members who asked since the station started (`Store.names`).
import { knownChannel } from "./slack-known.ts";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { basename, join, isAbsolute } from "node:path";
import { clean, cleanPosix, within } from "../ops/paths.ts";
import type { Viewer } from "../mesh/credential.ts";
import type { Lang } from "../ops/i18n.ts";
import { type InWorkspace, sees } from "../store/rows.ts";
import { watching } from "./store.ts";
import * as store from "./store.ts";
import type { Json, SessionRow, Store, ThreadRow, ThreadSummary } from "./store.ts";
import { setLang, tr } from "./spoken.ts";
import { sessionPlaces, transcriptSources } from "./transcript.ts";
import { type Read, chainOf, entriesOf, lengthOf, marksDir, stateOf } from "./transcripts.ts";
import { log } from "../ops/log.ts";
import { HttpError, apiOf, authorNames as authorNamesOf, creator as creatorOf, messageView, people as peopleOf, useNames } from "./views.ts";
import { parseUsize } from "./jobs.ts";
import { agentHomeOf } from "./memory.ts";
import { shown } from "./jobs.ts";
import { type RuntimeKind, runtimeKind } from "../agents/runtime.ts";
import { protectedPlace } from "../drive/fs.ts";
import { realOutside } from "../ops/places.ts";
import { platform } from "../platform/index.ts";
import { STILLFAIL_CONNECT } from "../store/rows.ts";


// ---- the config: its connects' names and its profiles' homes (config.rs) ----

type Config = { connects: { id: string; name: string }[]; profiles: { id: string; home: string }[] };
const configs = new WeakMap<Store, { stamp: string; config: Config }>();

/// The station's config.json, as far as these reads need it (read again when it changed); none of it when it does not
/// read.
function configOf(s: Store): Config {
  let stamp = "none";
  try {
    const st = statSync(join(s.dataDir, "config.json"));
    stamp = `${st.size}:${st.mtimeMs}:${st.ino}`;
  } catch {}
  let config = configs.get(s)?.stamp === stamp ? configs.get(s)!.config : undefined;
  if (!config) {
    config = { connects: [], profiles: [] };
    try {
      const raw = JSON.parse(readFileSync(join(s.dataDir, "config.json"), "utf8"));
      for (const c of Array.isArray(raw.connects) ? raw.connects : []) {
        // Connect::name: its bot's name, else its id.
        const bot = typeof c?.slack?.botName === "string" && c.slack.botName !== "" ? c.slack.botName : undefined;
        if (typeof c?.id === "string") config.connects.push({ id: c.id, name: bot ?? c.id });
      }
      for (const p of Array.isArray(raw.profiles) ? raw.profiles : []) {
        // A profile's home, under the data directory when it is relative (config.rs `under`).
        if (typeof p?.id === "string" && typeof p?.home === "string") config.profiles.push({ id: p.id, home: isAbsolute(p.home) ? p.home : join(s.dataDir, p.home) });
      }
    } catch {
      // No config: none.
    }
    configs.set(s, { stamp, config });
  }
  return config;
}

// ---- people: views.ts's own, for this store ----

/// A creator reference in words: who, and their email where known.
const creator = (s: Store, reference: string | null): Json | null => (useNames(s), creatorOf(reference));

/// Several people, once each (by email, else id).
const people = (s: Store, refs: string[]): Json[] => (useNames(s), peopleOf(refs));

/// Who wrote in a thread, in words, each author asked once.
const authorNames = (s: Store, thread: number) => (useNames(s), authorNamesOf(apiOf(s), thread));

// ---- sessions ----

/// SessionRow as serde writes it: the token skipped, `cwd` left out when none.
function sessionJson(r: SessionRow): Json {
  const v: Json = {
    key: r.key, connect: r.connect, scope: r.scope, title: r.title, createdBy: r.createdBy, runtime: r.runtime, profile: r.profile,
    profilePinned: r.profilePinned, model: r.model, effort: r.effort, fast: r.fast, afresh: r.afresh, runtimeSessionId: r.runtimeSessionId, workspace: r.workspace,
  };
  if (r.cwd !== null) v.cwd = r.cwd;
  if (r.profiles != null && r.profiles.length > 0) v.profiles = r.profiles;
  // The most context it runs with (sessions/context-cap.ts): none, the model's whole window.
  if (r.context !== null) v.context = r.context;
  // Held over it until compacted: what it ran with till now (0: the model's whole window).
  if (r.contextBefore !== null) v.contextBefore = r.contextBefore;
  Object.assign(v, { running: r.running, createdAt: r.createdAt, lastActiveAt: r.lastActiveAt, archivedAt: r.archivedAt, archivedBy: r.archivedBy, shownAt: r.shownAt });
  return v;
}

/// admin/mod.rs `session_row`: the session, or 404.
function sessionRow(s: Store, key: string): SessionRow {
  const row = store.getSession(s, key);
  if (row === null) throw new HttpError(404, `unknown session ${key}`);
  return row;
}

type Lists = { stats: Map<string, store.SessionStats>; bindings: Map<string, string[]>; participants: Map<string, string[]>; watches: Map<string, Json>; lengths: Map<string, number>; usages: Map<string, Json> };

/// views.rs `summary_with`: a session for lists and events: its row (without the token), process state, counts and people.
function summaryWith(s: Store, key: string, l: Lists): Json {
  const row = sessionRow(s, key);
  const v = sessionJson(row);
  v.boundTo = l.bindings.get(key) ?? [];
  // The hub's, as given with the read.
  v.process = s.processes.get(key) ?? "cold";
  const stat = l.stats.get(key);
  v.turns = stat?.turns ?? 0;
  // How long its ended turns ran, all added up: the work a device shows with how many turns, without reading them; null
  // for a session with turns that ended before that was kept (it shows its turns alone).
  v.workMs = stat === undefined ? null : stat.workMs;
  v.pending = stat?.pending ?? 0;
  v.firstText = stat?.firstText ?? null;
  v.lastTurn = stat?.lastTurn ?? null;
  v.creator = creator(s, row.createdBy);
  v.participants = people(s, l.participants.get(key) ?? []);
  // What can be done to its context by hand (POST /sessions/:key/compact, /clear): its runtime's (agents/runtime.ts
  // `compact`). None from a station from before.
  v.contextActions = row.runtime === "claude" || row.runtime === "codex" ? ["compact", "clear"] : ["clear"];
  // Keeping watch (jobs::watching): the pages say so.
  const watch = l.watches.get(key);
  if (watch !== undefined) v.watch = watch;
  // How many entries its transcript has (GET /sessions/:key/timeline numbers them from 0): a device that holds fewer of
  // the latest knows what it missed. None until the station has read it at work since it began to say so.
  const length = l.lengths.get(key);
  if (length !== undefined) v.transcriptLength = length;
  // What its calls used (read/usage.ts SessionUsage): as the usage counter recorded them, kept as more are, so a device
  // knows it of one at rest. None before a call.
  const usage = l.usages.get(key);
  if (usage !== undefined) v.usage = usage;
  return v;
}

/// views.rs `summary`: one session's.
export function summary(s: Store, key: string): Json {
  const bindings = store.listBindings(s, [key]);
  return summaryWith(s, key, { stats: store.sessionStats(s, key), bindings, participants: store.participants(s, key), watches: watching(s, [key]), lengths: store.transcriptLengths(s, key), usages: store.sessionUsages(s, key) });
}

/// GET /sessions: the sessions shown in lists, or only the archived ones; those of one connect;
/// those of the viewer's workspace (all of them for a read made for no one).
export function sessions(s: Store, connect: string | null, archived: boolean, lang: Lang, viewer: InWorkspace | null = null): Json[] {
  setLang(lang);
  const rows = store.listedSessions(s, connect, archived, viewer);
  const keys = rows.map((row) => row.key);
  const bindings = store.listBindings(s, keys);
  const l: Lists = { stats: store.sessionStats(s, keys), bindings, participants: store.participants(s, keys), watches: watching(s, keys), lengths: store.transcriptLengths(s, keys), usages: store.sessionUsages(s, keys) };
  return rows.map((x) => summaryWith(s, x.key, l));
}

/// GET /sessions/:key: the session, its threads, turns and jobs (newest first). `turns`: only that
/// many of its latest turns (`?turns=`), for a device that knows how many it had and how long they ran from its summary
/// (`turns`, `workMs`): all of them were read for that, many of one session in 25 s on a station (2026-11-03).
/// `now`: only its jobs that may matter now (`jobsNow`, `?jobs=now`), not its every one.
export function session(s: Store, key: string, viewer: Viewer, lang: Lang, turns: number | null = null, now = false): Json {
  setLang(lang);
  // One of another workspace is none.
  const row = store.getSession(s, key);
  if (row !== null && !sees(viewer, row.ws)) throw new HttpError(404, `unknown session ${key}`);
  const listed = store.listTurns(s, key, turns);
  const jobs = (now ? store.jobsNow(s, key) : store.listJobs(s, key)).map((j) => shown(s, j));
  return { session: summary(s, key), threads: threadViews(s, viewer, key), turns: listed, jobs };
}

// ---- threads ----

/// ThreadRow as serde writes it: auto_title, home, hidden_at, hidden_by and shown_at left out when none.
function threadJson(t: ThreadRow): Json {
  const v: Json = { id: t.id, surface: t.surface, channel: t.channel, threadTs: t.threadTs, title: t.title };
  if (t.autoTitle !== null) v.autoTitle = t.autoTitle;
  v.createdBy = t.createdBy;
  v.createdAt = t.createdAt;
  if (t.home !== null) v.home = t.home;
  if (t.hiddenAt !== null) v.hiddenAt = t.hiddenAt;
  if (t.hiddenBy !== null) v.hiddenBy = t.hiddenBy;
  if (t.shownAt !== null) v.shownAt = t.shownAt;
  return v;
}

/// views.rs `thread_view`: a thread with its sessions, last entry and message, what the viewer read, who wrote. Of one
/// thread (what is told of it as it changes, for each viewer), its own shares alone.
function threadView(
  s: Store,
  t: ThreadSummary,
  shares: ReturnType<typeof store.chatShares> = store.chatShares(s, [t.thread.home ?? t.sessions[0]?.session ?? ""]),
): Json {
  const names = authorNames(s, t.thread.id);
  const v = threadJson(t.thread);
  v.sessions = t.sessions.map((m) => ({ thread: m.thread, session: m.session, connect: m.connect, joinedAt: m.joinedAt }));
  v.last = t.last;
  v.lastMessage = t.lastMessage === null ? null : messageView(t.lastMessage, names, s);
  v.read = t.read;
  v.unread = t.unread;
  v.people = people(s, t.people);
  v.firstText = t.firstText;
  // What its agents and other chats' wrote each other (store/rows.ts Letter), shown apart from it: how many.
  if (t.letters > 0) v.letters = t.letters;
  // How far its own log of them goes (store/schema.ts LETTERS: GET /threads/:id/letters), what clients bring of it.
  if (t.lettersLast > 0) v.lettersLast = t.lettersLast;
  // A Slack channel's name, as far as known.
  v.channelName = t.thread.surface === store.STILLFAIL_SURFACE ? null : knownChannel(s, t.sessions.map((m) => m.connect).find((c) => c !== STILLFAIL_CONNECT) ?? null, t.thread.channel);
  v.creator = creator(s, t.thread.createdBy);
  // A still.fail chat's Slack and Feishu threads, where what people send can be copied, the one
  // said in last first; left out when none.
  if (t.thread.surface === store.STILLFAIL_SURFACE) {
    const to = store.ccThreads(s, t.thread.id);
    if (to.length > 0) v.cc = to.map((o) => ({ thread: o.thread.id, surface: o.thread.surface, channel: o.thread.channel, threadTs: o.thread.threadTs, channelName: knownChannel(s, o.connect, o.thread.channel) }));
  }
  // Which other workspaces it is shared with, by the session key its link names.
  const shared = shares.get(t.thread.home ?? t.sessions[0]?.session ?? "");
  v.xshare = shared === undefined ? null : shared;
  return v;
}

/// The threads of the viewer's workspace (of one session).
function threadViews(s: Store, viewer: Viewer, session: string | null): Json[] {
  const visible = store.listThreads(s, viewer.email, session, null, "count", viewer);
  // A pending chat would otherwise make the reader rebuild this whole list once for each unprepared session.
  store.requireCcSessions(s, visible.flatMap((t) => t.thread.surface === store.STILLFAIL_SURFACE
    ? t.sessions.map((m) => m.session) : []));
  const shares = store.chatShares(s, visible.map((t) => t.thread.home ?? t.sessions[0]?.session ?? ""));
  return visible.map((t) => threadView(s, t, shares));
}

/// GET /threads?session=: the threads (of one session).
export function threads(s: Store, viewer: Viewer, session: string | null, lang: Lang): Json[] {
  setLang(lang);
  return threadViews(s, viewer, session);
}

/// GET /threads/:id (admin/mod.rs): the id an i64, the thread there.
export function thread(s: Store, viewer: Viewer, id: string, lang: Lang): Json {
  setLang(lang);
  const n = parseI64(id);
  if (n === null || store.getThread(s, n) === null || !store.seesThread(s, viewer, n)) throw new HttpError(404, `unknown thread ${id}`);
  const found = store.listThreads(s, viewer.email, null, n)[0];
  if (found === undefined) throw new HttpError(404, `unknown thread ${n}`);
  return threadView(s, found);
}

/// `str::parse::<i64>`: digits with a sign at most, within an i64.
export function parseI64(text: string): number | null {
  if (!/^[+-]?\d+$/.test(text)) return null;
  const n = BigInt(text);
  return n > 9223372036854775807n || n < -9223372036854775808n ? null : Number(n);
}

// ---- a session's timeline and widgets ----

/// GET /sessions/:key/timeline: transcript entries before those a page was sent: up to `limit` (200, from 1 to 1000)
/// before entry `before` (0), and the index of the first; in brief (transcript.ts `brief`) with
/// `brief=1`. `after` instead: up to `limit` entries just after entry `after` (what a device that holds up to there has yet
/// to have). `from` and `to` instead: those entries (both included, at most 1000), whole unless `brief=1`, as one in brief
/// is read again when it is opened. `end`: how many entries the transcript has. The transcript is found through the
/// session's profile; none found: nothing.
export function timeline(s: Store, key: string, beforeParam: string | undefined, limitParam: string | undefined, lang: Lang, fromParam?: string, toParam?: string, briefParam?: string, afterParam?: string): Json {
  setLang(lang);
  const before = parseUsize(beforeParam) ?? 0;
  const limit = Math.min(Math.max(parseUsize(limitParam) ?? 200, 1), 1000);
  const started = performance.now();
  const found = transcriptsOf(s, key);
  if (found === null) return { start: 0, entries: [], end: 0 };
  const { runtime, paths } = found;
  const looked = performance.now();
  // Read on to where they are written now, each stretch from the mark before it (read/transcripts.ts).
  const chain = chainOf(runtime, paths, marksDir(s.dataDir));
  const end = lengthOf(chain);
  const readOnAt = performance.now();
  // What a slow one spent where, and read how much: the pages of a history took 2 to 4 s each on a station (2026-11-03),
  // unsaid where.
  const read: Read = { bytes: 0, lines: 0, packed: 0 };
  const between = (a: number, b: number) => {
    const entries = entriesOf(runtime, chain, a, b, briefParam === "1", read);
    const ms = Math.round(performance.now() - started);
    if (ms >= 1_000) log.warn("readers", "a timeline read's stages", { ms, found: Math.round(looked - started), readOn: Math.round(readOnAt - looked), runtime, transcripts: paths.length, end, from: a, to: b, entries: entries.length, ...read });
    return entries;
  };
  const from = parseUsize(fromParam);
  const to = parseUsize(toParam);
  if (from !== null && to !== null) return { start: from, entries: between(from, Math.min(to, from + 999) + 1), end };
  const after = parseUsize(afterParam);
  if (after !== null) {
    const start = Math.min(after + 1, end);
    return { start, entries: between(start, start + limit), end };
  }
  const upto = Math.min(before, end);
  const start = Math.max(0, upto - limit);
  return { start, entries: between(start, upto), end };
}

/// A session's transcripts: those of the runtime sessions it ran in before first (sessions/afresh.ts),
/// and none now (its context cleared) still reads those it ran in; found whatever profile it is on now, if any. Null:
/// none found.
function transcriptsOf(s: Store, key: string): { runtime: RuntimeKind; paths: { path: string; runtime: RuntimeKind }[] } | null {
  const row = sessionRow(s, key);
  const runtime = runtimeKind(row.runtime) ?? null;
  const sources = store.runtimeSessionSources(s, key);
  if (runtime === null || sources.length === 0) return null;
  return { runtime, paths: transcriptSources(s.dataDir, configOf(s).profiles, sources, sessionPlaces(row)).paths };
}

/// Where the reading of a session's transcripts stands (read/transcripts.ts `stateOf`), for its live view to go on from
/// (sessions/live.ts): no read of the transcripts' past on the station's main thread. `states` null: none found.
export function transcriptState(s: Store, key: string): Json {
  const found = transcriptsOf(s, key);
  return { states: found === null ? null : stateOf(found.runtime, found.paths, marksDir(s.dataDir)) };
}

/// GET /sessions/:key/transcript: where its runtime keeps the session's transcript on this machine (the current runtime
/// session's, found as `timeline` finds it), for a person to open or hand to another tool; null before it is written.
export function transcriptFile(s: Store, key: string, lang: Lang): Json {
  setLang(lang);
  const row = sessionRow(s, key);
  if (row.runtimeSessionId === null) return { path: null };
  const source = store.runtimeSessionSource(s, key, row.runtimeSessionId);
  if (!source) return { path: null };
  const { paths, current } = transcriptSources(s.dataDir, configOf(s).profiles, [source], sessionPlaces(row));
  return { path: current ? paths.at(-1)!.path : null };
}

/// GET /sessions/:key/widget-state?path: what a widget in one of the session's messages holds, null when nothing or
/// what is kept does not read as JSON.
export function widgetState(s: Store, key: string, path: string | undefined, lang: Lang): Json {
  setLang(lang);
  sessionRow(s, key);
  const kept = store.widgetState(s, key, path ?? "");
  let state: Json = null;
  if (kept !== null) {
    try {
      state = JSON.parse(kept);
    } catch {
      state = null;
    }
  }
  return { state };
}

// ---- a session's files ----

/// files.rs `mime`: by the file's extension.
export function mime(path: string): string {
  const name = basename(path);
  const dot = name.lastIndexOf(".");
  // Path::extension: none for a name with no dot, or only the one it starts with.
  const ext = dot <= 0 ? null : name.slice(dot + 1).toLowerCase();
  const kinds: Record<string, string> = {
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", svg: "image/svg+xml",
    pdf: "application/pdf", txt: "text/plain; charset=utf-8", md: "text/markdown; charset=utf-8", json: "application/json",
  };
  return (ext !== null && Object.hasOwn(kinds, ext) ? kinds[ext] : undefined) ?? "application/octet-stream";
}

const canonical = (path: string): string | null => {
  try {
    return realpathSync(path);
  } catch {
    return null;
  }
};

/// std::io::Error as anyhow shows it.
export function ioMessage(e: NodeJS.ErrnoException): string {
  const said: Record<string, string> = { ENOENT: "No such file or directory", EACCES: "Permission denied", EISDIR: "Is a directory", EPERM: "Operation not permitted" };
  return e.code && said[e.code] && typeof e.errno === "number" ? `${said[e.code]} (os error ${-e.errno})` : e.message;
}

/// GET /sessions/:key/peek and /open (src/api/routes/sessions.ts): a file or directory a message names by its path, for
/// its preview: absolute (`~/` the home), or under the session's working directory. Only within the session's own
/// directories (its workspace, the directory it was continued in), the station's repositories (<data>/repos) and the
/// agents' home (their memory and skills, which they name as much as their own files), its
/// links followed first: a page reads what the session works on, not the rest of the machine. What it is, for the
/// route to read.
export function sessionPlace(s: Store, key: string, given: string, lang: Lang): Json {
  setLang(lang);
  const row = sessionRow(s, key);
  const notFound = () => new HttpError(404, tr("station.files.notFound"));
  const asked = given.trim();
  if (asked === "" || asked.includes("\0")) throw notFound();
  const base = row.cwd ?? row.workspace;
  const home = process.env.HOME ?? "";
  const tilde = asked.startsWith("~/") && home !== "";
  const relative = !tilde && !isAbsolute(asked);
  const full = tilde ? join(home, asked.slice(2)) : relative ? join(base, asked) : asked;
  // Nothing in a folder macOS protects is looked at here (its links followed up to one, ops/places.ts): that would hold
  // this reader on a prompt for the station's launcher, and the pages with it.
  const outside = realOutside(clean(full));
  if (outside !== null && protectedPlace(outside) !== null && platform.hasFolderPermissions) throw new HttpError(403, tr("station.files.protected"));
  const path = outside ?? (relative ? inRepositories([row.workspace, row.cwd], asked) ?? inRepositories([join(s.dataDir, "repos")], asked, true) : null);
  if (path === null) throw notFound();
  const roots = [row.workspace, row.cwd, join(s.dataDir, "repos"), agentHomeOf(s.dataDir)].flatMap((r) => (r ? [realOutside(r)] : [])).filter((r): r is string => r !== null);
  if (!roots.some((r) => within(path, r))) throw new HttpError(403, tr("station.files.outside"));
  let st;
  try {
    st = statSync(path);
  } catch {
    throw notFound();
  }
  return { path, name: basename(path), dir: st.isDirectory(), size: st.size, mtime: Math.round(st.mtimeMs), contentType: mime(path) };
}

/// The files git has of each repository, by its directory, as last listed (kept a minute).
const listed = new Map<string, { at: number; files: string[] }>();

/// A relative path not under the working directory, as agents write one from inside a repository (`ifc/a.ex` for
/// `<workspace>/cue/apps/x/lib/ifc/a.ex`): the file of a repository in `dirs` (one of them, or two levels below)
/// whose path ends with it, or a directory of one (git lists only files); the shortest, when several do. Null when none
/// does. `latest`: of several repositories that have it, the one last fetched or checked out (the station's clones,
/// <data>/repos: an old copy of a project beside the one worked on has the same files).
function inRepositories(dirs: (string | null)[], given: string, latest = false): string | null {
  // As git lists them: `/` between the parts, whatever this machine uses.
  const tail = cleanPosix(given).slice(1);
  if (tail === "") return null;
  const names = naming(tail);
  const repos = new Set<string>();
  const look = (dir: string, depth: number) => {
    if (existsSync(join(dir, ".git"))) return void repos.add(dir);
    if (depth === 0) return;
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) if (e.isDirectory() && !e.name.startsWith(".") && e.name !== "node_modules") look(join(dir, e.name), depth - 1);
  };
  for (const dir of dirs) if (dir && !(platform.hasFolderPermissions && protectedPlace(realOutside(dir) ?? dir) !== null)) look(dir, 2);
  let best: string | null = null;
  let bestAt = -1;
  for (const repo of repos) {
    let seen = listed.get(repo);
    if (!seen || store.nowMs() - seen.at > 60_000) {
      try {
        const out = execFileSync("git", ["-C", repo, "ls-files", "-z"], { maxBuffer: 64 << 20, timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
        seen = { at: store.nowMs(), files: out.toString("utf8").split("\0").filter(Boolean) };
      } catch {
        seen = { at: store.nowMs(), files: [] };
      }
      listed.set(repo, seen);
    }
    const at = latest ? touched(repo) : 0;
    for (const f of seen.files) {
      const m = names.exec(f);
      if (m === null) continue;
      const path = join(repo, f.slice(0, m.index + m[0].length));
      if (best === null || at > bestAt || (at === bestAt && path.length < best.length)) [best, bestAt] = [path, at];
    }
  }
  return best === null ? null : canonical(best);
}

/// What finds a path named by `tail` (its parts between `/`) in a file's path as git lists it: the file, or the directory
/// of it the tail ends at. A part `...` or `…` is any directories, as agents shorten a long path in the middle.
function naming(tail: string): RegExp {
  const parts = tail.split("/").map((p) => (p === "..." || p === "…" ? ".+" : p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  return new RegExp(`(?:^|/)${parts.join("/")}(?=/|$)`);
}

/// When a repository was last fetched, checked out or committed to (its git directory's files), in ms.
function touched(repo: string): number {
  let at = 0;
  for (const f of ["FETCH_HEAD", "HEAD", "index"]) {
    try {
      at = Math.max(at, statSync(join(repo, ".git", f)).mtimeMs);
    } catch {
      // Not there (a repository never fetched).
    }
  }
  return at;
}
