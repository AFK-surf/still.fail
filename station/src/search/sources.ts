// What a search looks through of the station's own data (docs/search.md), read as it is asked for from its store as
// the readers read it (read/store.ts, a read-only connection) and from the files beside it:
//
// - a thread: its chat (`c:<id>`) and each message as it reads now (`m:<id>:<n>`), an archived one's from its file.
// - a session's transcript: its execution history (`h:<key>:<i>`, `i` as GET /sessions/:key/timeline numbers them),
//   what the agent said and thought, the calls it made and what they gave, its files looked through newest first.
// - a session's jobs (`j:<id>`), a workspace's memory and skills, the profiles.
import { closeSync, createReadStream, existsSync, openSync, readSync, readdirSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { createZstdDecompress } from "node:zlib";
import * as store from "../read/store.ts";
import type { MessageRow, SessionRow, Store } from "../read/store.ts";
import { type ReadState, timelineOf, transcriptPaths, type TimelineEntry } from "../read/transcript.ts";
import { readFrom } from "../usage/counter.ts";
import { agentHomeOf, memory } from "../read/memory.ts";
import { runtimeKind } from "../agents/runtime.ts";
import { STILLFAIL_SURFACE } from "../read/store.ts";
import { type Asker, type Doc, type Hit, has, hitOf, sees } from "./match.ts";

/// The workspace documents of nothing in particular are in (`ws` null: the station's home one).
type Ws = string | null;

const all = (s: Store, sql: string, ...args: any[]): any[] => s.db.prepare(sql).all(...args);

const firstChars = (text: string, n: number) => (text.length <= n ? text : Array.from(text).slice(0, n).join(""));

// ── threads ──

/// A thread's chat: the workspace it is in (its home session's, else its first one's; none: the home one) and its key in
/// the station's list (as /chats has it: its first agent's session key).
export function chatOf(s: Store, thread: number): { ws: Ws; chat: string | null; sessions: SessionRow[] } {
  const members = store.threadSessions(s, thread);
  const row = store.getThread(s, thread);
  const sessions = members.map((m) => store.getSession(s, m.session)).filter((x): x is SessionRow => x !== null);
  const home = sessions.find((x) => x.key === row?.home) ?? sessions[0] ?? null;
  return { ws: home?.ws ?? null, chat: sessions[0]?.key ?? null, sessions };
}

/// The words a chat is called by, as lists name it: its title, else what its agent called it, else the first thing said.
function titleOf(row: store.ThreadRow, first: string | null): string {
  const named = row.title?.trim() || row.autoTitle?.trim();
  if (named) return named;
  return first ? firstChars(first.replace(/\s+/gu, " ").trim(), 80) : "";
}

/// A thread's documents: its chat, and its messages (an archived one's read from its file).
export function threadDocs(s: Store, id: number): Doc[] {
  const row = store.getThread(s, id);
  if (row === null) return [];
  const { ws, chat, sessions } = chatOf(s, id);
  // Filed away (its entries in its archive file), or archived as people see it (by hand, or idle): out of the lists.
  const filed = store.isArchived(s, id);
  const archived = filed || row.hiddenAt !== null || (sessions.length > 0 && sessions.every((x) => x.archivedAt !== null));
  const surface = row.surface === STILLFAIL_SURFACE ? "stillfail" : "slack";
  const messages: MessageRow[] = filed ? store.messagesBefore(s, id, null, 1_000_000) : all(s, "SELECT * FROM merged WHERE thread = ? ORDER BY n", id).map(toMessage);
  const title = titleOf(row, messages.find((m) => m.authorKind === "person")?.text ?? messages[0]?.text ?? null);
  const lastAt = messages.length > 0 ? Math.max(...messages.map((m) => m.createdAt ?? 0)) : null;
  const ref = { thread: id, chat, surface, archived, ...(row.channel ? { channel: row.channel } : {}) };
  const docs: Doc[] = [];
  docs.push({
    key: `c:${id}`, kind: "chat", ws, title,
    body: [...sessions.map((x) => x.title ?? ""), ...sessions.map((x) => x.model ?? "")].filter((w) => w !== "").join("\n"),
    at: lastAt ?? row.createdAt ?? null, ref,
  });
  for (const m of messages) {
    const text = m.text ?? "";
    const files = m.attachments.map((a: any) => (typeof a?.name === "string" ? a.name : "")).filter((n: string) => n !== "");
    if (text.trim() === "" && files.length === 0) continue;
    docs.push({
      key: `m:${id}:${m.n}`, kind: "message", ws, title: "",
      body: files.length > 0 ? `${text}\n${files.join("\n")}` : text,
      at: m.createdAt ?? null,
      ref: { thread: id, seq: m.n, chat, chatTitle: title, surface, archived, authorKind: m.authorKind, author: m.author, ...(m.agentIdentity ? { agentIdentity: m.agentIdentity } : {}) },
    });
  }
  return docs;
}

/// A row of `merged` as the readers read it.
function toMessage(r: any): MessageRow {
  let attachments: unknown[] = [];
  try {
    attachments = r.attachments ? JSON.parse(r.attachments) : [];
  } catch {}
  let agentIdentity: unknown = null;
  try {
    agentIdentity = r.agent_identity ? JSON.parse(r.agent_identity) : null;
  } catch {}
  return {
    agentIdentity, thread: r.thread, n: r.n, ts: r.ts ?? "", authorKind: r.author_kind, author: r.author, text: r.text ?? "",
    attachments: Array.isArray(attachments) ? attachments : [], quotes: [], declared: r.declared ?? null, client: r.client ?? null,
    createdAt: r.created_at, editedAt: r.edited_at ?? null,
  } as MessageRow;
}

/// Every thread's id.
export const threadIds = (s: Store): number[] => all(s, "SELECT id FROM threads").map((r) => r.id as number);

// ── transcripts ──

type Profiles = { id: string; home: string; runtime: string; model?: string; access?: any; name?: string }[];

/// The profiles config.json names, their homes under the data directory when relative (config.rs `under`).
export function profilesOf(raw: any, dataDir: string): Profiles {
  const out: Profiles = [];
  for (const p of Array.isArray(raw?.profiles) ? raw.profiles : []) {
    if (typeof p?.id !== "string" || typeof p?.home !== "string") continue;
    out.push({ id: p.id, home: isAbsolute(p.home) ? p.home : join(dataDir, p.home), runtime: typeof p.runtime === "string" ? p.runtime : "", model: typeof p.model === "string" ? p.model : undefined, access: p.access, name: typeof p.name === "string" ? p.name : undefined });
  }
  return out;
}

/// What of a history entry is looked through: what was said, thought or done; null for what is not (a person's message,
/// which the chat has; the agent's posts, which are its messages).
function historyText(e: TimelineEntry): string | null {
  switch (e.kind) {
    case "assistant":
    case "thinking":
      return e.text;
    case "tool_call": {
      const tool = (e.tool ?? "").replace(/^(mcp__stillfail__|mcp__ember__)/, "");
      if (tool === "chat_post" || tool === "chat_state") return null;
      return `${tool}\n${e.text}`;
    }
    case "tool_result":
      return e.text.trim() === "" ? null : e.text;
    default:
      return null;
  }
}

/// A session's transcript files, and the runtime that wrote them.
export function transcriptFiles(s: Store, session: SessionRow, profiles: Profiles): { paths: string[]; runtime: NonNullable<ReturnType<typeof runtimeKind>> } | null {
  const profile = profiles.find((p) => p.id === session.profile);
  const runtime = runtimeKind(session.runtime) ?? null;
  if (!profile || runtime === null || session.runtimeSessionId === null) return null;
  const homes = [profile.home, ...profiles.map((p) => p.home).filter((h) => h !== profile.home)];
  const { paths } = transcriptPaths(runtime, homes, store.runtimeSessions(s, session.key));
  return { paths, runtime };
}

/// A transcript's entries, each given to `each` as it is read: in parts (a file put away decompressed as a stream), never
/// the whole of it at once.
async function entriesOf(runtime: NonNullable<ReturnType<typeof runtimeKind>>, path: string, state: ReadState, each: (e: TimelineEntry) => void): Promise<void> {
  const out: TimelineEntry[] = [];
  for await (const part of readFrom(path, 0)) {
    for (let line of part.text.split("\n")) {
      if (line.endsWith("\r")) line = line.slice(0, -1);
      if (line === "") continue;
      let record: unknown;
      try {
        record = JSON.parse(line);
      } catch {
        continue;
      }
      timelineOf(runtime, record, state, out);
      for (const e of out) each(e);
      out.length = 0;
    }
  }
}

/// How much of a file is looked through at a time, and kept of the part before (a word across the two is found).
const CHUNK = 8 << 20;
const OVERLAP = 1024;

/// What finds a word in a file's bytes: as it is, and as JSON writes it (quotes and backslashes escaped). ASCII's case
/// aside; other scripts' as written (a word with cased letters beyond ASCII is found by its entries, `mentions` false
/// only where none of its forms is there).
function finder(word: string): (bytes: Buffer) => boolean {
  const forms = [...new Set([word, JSON.stringify(word).slice(1, -1)])];
  if (/^[\x00-\x7f]*$/u.test(word)) {
    const re = new RegExp(forms.map((f) => f.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&")).join("|"), "i");
    return (bytes) => re.test(bytes.toString("latin1"));
  }
  if (Array.from(word).some((c) => c.toUpperCase() !== c.toLowerCase())) return () => true;
  const raw = forms.map((f) => Buffer.from(f, "utf8"));
  return (bytes) => raw.some((r) => bytes.indexOf(r) >= 0);
}

/// Whether a transcript file has every word anywhere in it (its entries are read only then): looked through as bytes,
/// a file put away decompressed as a stream.
export async function mentions(path: string, words: string[]): Promise<boolean> {
  const finds = words.map(finder);
  const left = new Set(finds);
  const look = (bytes: Buffer) => {
    for (const f of left) if (f(bytes)) left.delete(f);
    return left.size === 0;
  };
  if (existsSync(path)) {
    const buf = Buffer.allocUnsafe(CHUNK + OVERLAP);
    const fd = openSync(path, "r");
    try {
      let pos = 0;
      let kept = 0;
      for (;;) {
        const n = readSync(fd, buf, kept, CHUNK, pos);
        if (n <= 0) return false;
        const view = buf.subarray(0, kept + n);
        if (look(view)) return true;
        pos += n;
        kept = Math.min(OVERLAP, view.length);
        view.copy(buf, 0, view.length - kept);
      }
    } finally {
      closeSync(fd);
    }
  }
  if (!existsSync(`${path}.zst`)) return false;
  const raw = createReadStream(`${path}.zst`, { highWaterMark: 1 << 20 });
  const stream = raw.pipe(createZstdDecompress({ chunkSize: 4 << 20 }));
  raw.on("error", (error) => stream.destroy(error));
  let tail: Buffer = Buffer.alloc(0);
  try {
    for await (const chunk of stream as AsyncIterable<Buffer>) {
      const view = tail.length > 0 ? Buffer.concat([tail, chunk]) : chunk;
      if (look(view)) return true;
      tail = Buffer.from(view.subarray(Math.max(0, view.length - OVERLAP)));
    }
  } catch {
    // Unreadable: not found there.
  } finally {
    raw.destroy();
    stream.destroy();
  }
  return false;
}

export type HistoryFound = { hits: Hit[]; more: boolean; /** Sessions not looked through, the time being up. */ left: number };

/**
 * What the words find in the execution histories `asker` may see, the most recently active sessions first and each one's
 * latest steps first, until `offset + limit` and one more are found or `ms` is up. A session's files are read (its
 * entries numbered as its history page numbers them) only when they have every word.
 */
export async function historyHits(s: Store, profiles: Profiles, words: string[], asker: Asker, options: { limit: number; offset: number; ms: number; now: () => number }): Promise<HistoryFound> {
  const want = options.offset + options.limit + 1;
  const until = options.now() + options.ms;
  const found: Hit[] = [];
  const sessions = store.listSessions(s).filter((x) => sees({ ws: x.ws }, asker));
  let looked = 0;
  for (const session of sessions) {
    if (found.length >= want) break;
    if (options.now() > until) return { hits: found.slice(options.offset, options.offset + options.limit), more: true, left: sessions.length - looked };
    looked++;
    // Let through: a search asked meanwhile is answered between sessions.
    await new Promise<void>((resolve) => setImmediate(resolve));
    const files = transcriptFiles(s, session, profiles);
    if (files === null) continue;
    let any = false;
    for (const p of files.paths) if (await mentions(p, words)) any = true;
    if (!any) continue;
    // Its latest steps that have the words, as many as may still be wanted (numbered as they are read).
    const state: ReadState = { inner: new Map() };
    const room = want - found.length;
    const latest: { i: number; e: TimelineEntry; text: string }[] = [];
    let i = 0;
    for (const p of files.paths) {
      await entriesOf(files.runtime, p, state, (e) => {
        const text = historyText(e);
        if (text !== null && has(text, words)) {
          latest.push({ i, e, text });
          if (latest.length > room) latest.shift();
        }
        i++;
      });
    }
    const thread = store.sessionThreads(s, session.key).find((t) => t.surface === STILLFAIL_SURFACE) ?? null;
    const chatTitle = session.title ?? thread?.title ?? thread?.autoTitle ?? "";
    for (const { i, e, text } of latest.reverse()) {
      const at = e.at === null ? null : Date.parse(e.at);
      found.push(hitOf({
        key: `h:${session.key}:${i}`, kind: "history", ws: session.ws, title: "", body: text,
        at: at !== null && Number.isFinite(at) ? at : null,
        ref: { session: session.key, index: i, entry: e.kind, ...(e.tool ? { tool: e.tool } : {}), chat: session.key, chatTitle, ...(thread ? { thread: thread.id } : {}) },
      }, words));
    }
  }
  return { hits: found.slice(options.offset, options.offset + options.limit), more: found.length > options.offset + options.limit, left: 0 };
}

export const sessionKeys = (s: Store): string[] => all(s, "SELECT key FROM sessions").map((r) => r.key as string);

// ── jobs ──

/// A session's jobs (its services and tasks) as documents.
export function jobDocs(s: Store, key: string): Doc[] {
  const session = store.getSession(s, key);
  const jobs = store.listJobs(s, key);
  const thread = session ? (store.sessionThreads(s, key).find((t) => t.surface === STILLFAIL_SURFACE) ?? null) : null;
  return jobs.map((j) => ({
    key: `j:${j.id}`, kind: "job", ws: session?.ws ?? null, title: j.name,
    body: [j.command, j.cwd ?? "", j.port !== null && j.port !== undefined ? `:${j.port}` : ""].filter((w) => w !== "").join("\n"),
    at: j.startedAt ?? null,
    ref: { job: j.id, session: key, chat: key, state: j.state, ...(j.port !== null && j.port !== undefined ? { port: j.port } : {}), ...(thread ? { thread: thread.id } : {}) },
  }));
}

// ── memory, skills, profiles ──

/// The workspaces the station joined that have memory of their own (<agent home>/workspaces/<ws>).
export function memoryWorkspaces(agentHome: string): string[] {
  try {
    return readdirSync(join(agentHome, "workspaces")).filter((n) => /^[0-9A-Za-z_-]{1,128}$/.test(n));
  } catch {
    return [];
  }
}

/// A workspace's memory and skills as documents (`ws` null: the home workspace's).
export function memoryDocs(dataDir: string, ws: Ws): Doc[] {
  const m = memory(dataDir, ws ?? undefined) as any;
  const docs: Doc[] = [];
  const text = typeof m?.global?.text === "string" ? m.global.text : "";
  if (text.trim() !== "") docs.push({ key: `k:${ws ?? ""}:`, kind: "memory", ws, title: "MEMORY.md", body: text, at: null, ref: { path: m.global.path } });
  for (const k of Array.isArray(m?.skills) ? m.skills : []) {
    const files = Array.isArray(k.files) ? k.files : [];
    docs.push({
      key: `k:${ws ?? ""}:${k.name}`, kind: "skill", ws, title: k.name,
      body: [k.description ?? "", k.text ?? "", ...files.map((f: any) => `${f.name}\n${f.text}`)].join("\n"),
      at: null, ref: { skill: k.name, description: k.description ?? "", builtin: k.builtin === true, project: k.project === true },
    });
  }
  return docs;
}

/// The profiles as documents: every workspace's members see them (`*`).
export function profileDocs(profiles: Profiles): Doc[] {
  return profiles.map((p) => ({
    key: `p:${p.id}`, kind: "profile", ws: "*", title: p.name ?? p.id,
    body: [p.id, p.runtime, p.model ?? "", typeof p.access?.kind === "string" ? p.access.kind : "", typeof p.access?.provider === "string" ? p.access.provider : ""].filter((w) => w !== "").join("\n"),
    at: null, ref: { profile: p.id, runtime: p.runtime },
  }));
}

// ── all of them ──

/// The documents of the kinds asked for (all but the execution history's), as the station's data is now.
export function* stationDocs(s: Store, data: string, config: unknown, kinds: Set<string> | null): Generator<Doc> {
  const wants = (k: string) => kinds === null || kinds.has(k);
  if (wants("chat") || wants("message")) {
    for (const id of threadIds(s)) {
      try {
        for (const d of threadDocs(s, id)) if (wants(d.kind)) yield d;
      } catch (error) {
        // A thread moved to the archive while it was read: found the next time.
        if (!(error instanceof Error && /no such|archive|ENOENT/.test(error.message))) throw error;
      }
    }
  }
  if (wants("job")) for (const key of sessionKeys(s)) yield* jobDocs(s, key);
  if (wants("skill") || wants("memory")) {
    for (const ws of [null, ...memoryWorkspaces(agentHomeOf(data))]) for (const d of memoryDocs(data, ws)) if (wants(d.kind)) yield d;
  }
  if (wants("profile")) yield* profileDocs(profilesOf(config, data));
}
