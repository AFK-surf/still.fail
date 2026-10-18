// What the station's search index holds of the station's own data (docs/search.md), read from its store as the readers
// read it (read/store.ts, a read-only connection) and from the files beside it: each source's documents and the version
// they are of, for the index to tell what changed.
//
// - a thread (`t:<id>`): its chat (`c:<id>`) and each message as it reads now (`m:<id>:<n>`), an archived one's from its
//   file; indexed again from the last message indexed, an archived one whole once its file changes.
// - a session's transcript (`h:<key>`): its execution history (`h:<key>:<i>`, `i` as GET /sessions/:key/timeline numbers
//   them): what the agent said and thought, the calls it made (as a history names them) and the start of what they gave.
// - a session's jobs (`j:<key>`), each job (`j:<id>`).
// - a workspace's memory and skills (`k:<ws>`), the profiles (`p`).
import { readdirSync, statSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import * as store from "../read/store.ts";
import type { MessageRow, SessionRow, Store } from "../read/store.ts";
import { type ReadState, brief, timelineOf, transcriptPaths, type TimelineEntry } from "../read/transcript.ts";
import { readFrom } from "../usage/counter.ts";
import { memory } from "../read/memory.ts";
import { runtimeKind } from "../agents/runtime.ts";
import { STILLFAIL_SURFACE } from "../read/store.ts";
import type { Doc, Group } from "./index.ts";

/// The workspace documents of nothing in particular are in (`ws` null: the station's home one).
type Ws = string | null;

/// How much of what a call gave, and of a thought, the index keeps.
const RESULT_CHARS = 300;
const THOUGHT_CHARS = 1000;

const one = (s: Store, sql: string, ...args: any[]): any => s.db.prepare(sql).get(...args);
const all = (s: Store, sql: string, ...args: any[]): any[] => s.db.prepare(sql).all(...args);

const stamp = (path: string): string => {
  try {
    const st = statSync(path);
    return `${st.size}:${st.mtimeMs}`;
  } catch {
    return "none";
  }
};

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

export type Indexed = { version: string; docs: Doc[]; whole: boolean; removed?: string[] };

/**
 * A thread's documents since `had` (the version indexed before; null: none): its chat, and its messages, all of them
 * (`whole`) when it is archived or was not indexed as it is now, else those said or edited since.
 */
export function threadDocs(s: Store, id: number, had: string | null): Indexed | null {
  const row = store.getThread(s, id);
  if (row === null) return null;
  const { ws, chat, sessions } = chatOf(s, id);
  // Filed away (its entries in its archive file), or archived as people see it (by hand, or idle): out of the lists.
  const filed = store.isArchived(s, id);
  const archived = filed || row.hiddenAt !== null || (sessions.length > 0 && sessions.every((x) => x.archivedAt !== null));
  const surface = row.surface === STILLFAIL_SURFACE ? "stillfail" : "slack";
  let messages: MessageRow[];
  let version: string;
  let whole = true;
  if (filed) {
    version = `a:${stamp(join(s.archiveDir, "threads", `${id}.jsonl.zst`))}`;
    if (had === version) return { version, docs: [], whole: false };
    messages = store.messagesBefore(s, id, null, 1_000_000);
  } else {
    const last = store.lastEntry(s, id);
    // Archived or brought back: every message says so again.
    version = `n:${last}${archived ? ":x" : ""}`;
    const was = /^n:(\d+)(:x)?$/.exec(had ?? "");
    const since = was && (was[2] !== undefined) === archived ? Number(was[1]) : null;
    if (since !== null && Number.isFinite(since) && since <= last) {
      whole = false;
      // Those said since, and those an edit since changed.
      const edited = all(s, "SELECT DISTINCT target FROM entries WHERE thread = ? AND n > ? AND kind = 'edit' AND target IS NOT NULL", id, since).map((r) => r.target as number);
      const ns = new Set(edited);
      messages = all(s, "SELECT * FROM merged WHERE thread = ? AND n > ? ORDER BY n", id, since).map(toMessage);
      for (const n of ns) {
        if (messages.some((m) => m.n === n)) continue;
        const m = one(s, "SELECT * FROM merged WHERE thread = ? AND n = ?", id, n);
        if (m) messages.push(toMessage(m));
      }
    } else {
      messages = all(s, "SELECT * FROM merged WHERE thread = ? ORDER BY n", id).map(toMessage);
    }
  }
  const first = whole ? (messages.find((m) => m.authorKind === "person")?.text ?? messages[0]?.text ?? null) : null;
  const title = titleOf(row, first ?? (one(s, "SELECT text FROM merged WHERE thread = ? AND author_kind = 'person' ORDER BY n LIMIT 1", id)?.text ?? null));
  const lastAt = messages.length > 0 ? Math.max(...messages.map((m) => m.createdAt ?? 0)) : null;
  const ref = { thread: id, chat, surface, archived, ...(row.channel ? { channel: row.channel } : {}) };
  const docs: Doc[] = [];
  docs.push({
    key: `c:${id}`, kind: "chat", source: `t:${id}`, ws, title,
    body: [...sessions.map((x) => x.title ?? ""), ...sessions.map((x) => x.model ?? "")].filter((w) => w !== "").join("\n"),
    at: lastAt ?? row.createdAt ?? null, ref,
  });
  for (const m of messages) {
    const text = m.text ?? "";
    const files = m.attachments.map((a: any) => (typeof a?.name === "string" ? a.name : "")).filter((n: string) => n !== "");
    if (text.trim() === "" && files.length === 0) continue;
    docs.push({
      key: `m:${id}:${m.n}`, kind: "message", source: `t:${id}`, ws, title: "",
      body: files.length > 0 ? `${text}\n${files.join("\n")}` : text,
      at: m.createdAt ?? null,
      ref: { thread: id, seq: m.n, chat, chatTitle: title, surface, archived, authorKind: m.authorKind, author: m.author, ...(m.agentIdentity ? { agentIdentity: m.agentIdentity } : {}) },
    });
  }
  return { version, docs, whole };
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

/// What of a history entry is found: what was said, thought or done; null for what is not worth finding (a person's
/// message, which the chat has; the agent's posts, which are its messages).
function historyText(e: TimelineEntry): string | null {
  switch (e.kind) {
    case "assistant":
      return e.text;
    case "thinking":
      return firstChars(e.text, THOUGHT_CHARS);
    case "tool_call": {
      const tool = (e.tool ?? "").replace(/^(mcp__stillfail__|mcp__ember__)/, "");
      if (tool === "chat_post" || tool === "chat_state") return null;
      return `${tool}\n${brief(e).text}`;
    }
    case "tool_result":
      return e.text.trim() === "" ? null : firstChars(e.text, RESULT_CHARS);
    default:
      return null;
  }
}

/// A session's transcript files and the version of them all.
export function transcriptFiles(s: Store, session: SessionRow, profiles: Profiles): { paths: string[]; version: string; runtime: ReturnType<typeof runtimeKind> } | null {
  const profile = profiles.find((p) => p.id === session.profile);
  const runtime = runtimeKind(session.runtime) ?? null;
  if (!profile || runtime === null || session.runtimeSessionId === null) return null;
  const homes = [profile.home, ...profiles.map((p) => p.home).filter((h) => h !== profile.home)];
  const { paths } = transcriptPaths(runtime, homes, store.runtimeSessions(s, session.key));
  return { paths, runtime, version: paths.map((p) => `${p}=${stamp(p)}`).join("|") };
}

/// Where a transcript was read to (its whole lines), and the reading's state there.
type ReadAt = { offset: number; state: ReadState };

/// A transcript's entries past where `at` says it was read to, `at` moved on to its last whole line: read in parts (a
/// file put away decompressed as a stream), never the whole of it at once.
async function readOn(runtime: NonNullable<ReturnType<typeof runtimeKind>>, path: string, at: ReadAt): Promise<TimelineEntry[]> {
  const out: TimelineEntry[] = [];
  for await (const part of readFrom(path, at.offset)) {
    for (let line of part.text.split("\n")) {
      if (line.endsWith("\r")) line = line.slice(0, -1);
      if (line === "") continue;
      let record: unknown;
      try {
        record = JSON.parse(line);
      } catch {
        continue;
      }
      timelineOf(runtime, record, at.state, out);
    }
    at.offset = part.offset;
  }
  return out;
}

/// Where the transcripts of the sessions read lately were read to, to read on from there as they grow (a long one is
/// not read whole at each turn's end): the most recently read few.
export class Readings {
  #kept = new Map<string, { paths: string; at: ReadAt[]; count: number }>();
  readonly most: number;
  constructor(most = 16) {
    this.most = most;
  }
  get(key: string) {
    const v = this.#kept.get(key);
    if (v) {
      this.#kept.delete(key);
      this.#kept.set(key, v);
    }
    return v;
  }
  set(key: string, v: { paths: string; at: ReadAt[]; count: number }): void {
    this.#kept.delete(key);
    this.#kept.set(key, v);
    while (this.#kept.size > this.most) this.#kept.delete(this.#kept.keys().next().value!);
  }
  forget(key: string): void {
    this.#kept.delete(key);
  }
}

/// A session's execution history as documents (null: nothing to index; none when as indexed: `had`). A transcript only
/// grows: what was indexed of it stays, and only the entries after those are added, read on from where it was read to
/// when `readings` has it, else read whole; unless it is another now (a new runtime session, a file put away).
/// `reading`: told before a transcript is read whole.
export async function historyDocs(s: Store, key: string, profiles: Profiles, had: string | null, reading?: () => void, readings?: Readings): Promise<Indexed | null> {
  const session = store.getSession(s, key);
  if (session === null) return null;
  const files = transcriptFiles(s, session, profiles);
  if (files === null) return { version: "none", docs: [], whole: true };
  let before: { files: string; n: number } | null = null;
  try {
    before = had === null ? null : JSON.parse(had);
  } catch {}
  if (before?.files === files.version) return { version: had!, docs: [], whole: false };
  // One whose reading stopped the index's thread before (too large for it): not read again until it changes.
  if (had === READING || had === `${FAILED}${files.version}`) return { version: `${FAILED}${files.version}`, docs: [], whole: true };
  const runtime = files.runtime!;
  const paths = files.paths.join("|");
  const same = before !== null && typeof before.n === "number" && samePaths(before.files, files.version);
  const kept = readings?.get(key);
  let from: number;
  let entries: TimelineEntry[];
  let count: number;
  if (kept && same && kept.paths === paths && kept.count === before!.n) {
    entries = [];
    for (const [i, p] of files.paths.entries()) entries.push(...(await readOn(runtime, p, kept.at[i]!)));
    from = kept.count;
    count = kept.count + entries.length;
    kept.count = count;
  } else {
    reading?.();
    const at: ReadAt[] = files.paths.map(() => ({ offset: 0, state: { inner: new Map() } }));
    const all: TimelineEntry[] = [];
    for (const [i, p] of files.paths.entries()) all.push(...(await readOn(runtime, p, at[i]!)));
    from = same && all.length >= before!.n ? before!.n : 0;
    entries = all.slice(from);
    count = all.length;
    readings?.set(key, { paths, at, count });
  }
  const docs: Doc[] = [];
  entries.forEach((e, j) => {
    const i = from + j;
    const text = historyText(e);
    if (text === null || text.trim() === "") return;
    const at = e.at === null ? null : Date.parse(e.at);
    docs.push({
      key: `h:${key}:${i}`, kind: "history", source: `h:${key}`, ws: session.ws, title: "", body: text,
      at: at !== null && Number.isFinite(at) ? at : null,
      // Its chat not kept with each step (a fifth of the index's text): told as it is now when found (`historyChats`).
      ref: { session: key, index: i, entry: e.kind, ...(e.tool ? { tool: e.tool } : {}) },
    });
  });
  return { version: JSON.stringify({ files: files.version, n: count }), docs, whole: from === 0 };
}

/// The execution history found told with its chat as it is now: its key, title and thread.
export function historyChats(s: Store, groups: Group[]): void {
  const chats = new Map<string, Record<string, unknown>>();
  for (const g of groups) {
    if (g.kind !== "history") continue;
    for (const hit of g.hits) {
      const key = hit.session;
      if (typeof key !== "string") continue;
      let chat = chats.get(key);
      if (!chat) {
        const session = store.getSession(s, key);
        const thread = store.sessionThreads(s, key).find((t) => t.surface === STILLFAIL_SURFACE) ?? null;
        chat = { chat: key, chatTitle: session?.title ?? thread?.title ?? thread?.autoTitle ?? "", ...(thread ? { thread: thread.id } : {}) };
        chats.set(key, chat);
      }
      Object.assign(hit, chat);
    }
  }
}

/// A transcript's mark while it is read, and once its reading stopped the index's thread (with the version it was of).
export const READING = "reading";
export const FAILED = "failed:";

/// Whether two versions of a session's transcripts are of the same files (grown or not).
const samePaths = (a: string, b: string) => a.split("|").map((p) => p.slice(0, p.lastIndexOf("="))).join("|") === b.split("|").map((p) => p.slice(0, p.lastIndexOf("="))).join("|");

export const sessionKeys = (s: Store): string[] => all(s, "SELECT key FROM sessions").map((r) => r.key as string);

// ── jobs ──

/// A session's jobs (its services and tasks) as documents.
export function jobDocs(s: Store, key: string): Indexed {
  const session = store.getSession(s, key);
  const jobs = store.listJobs(s, key);
  const version = jobs.map((j) => `${j.id}:${j.state}:${j.name}:${j.port ?? ""}`).join("|");
  const thread = session ? (store.sessionThreads(s, key).find((t) => t.surface === STILLFAIL_SURFACE) ?? null) : null;
  return {
    version, whole: true,
    docs: jobs.map((j) => ({
      key: `j:${j.id}`, kind: "job", source: `j:${key}`, ws: session?.ws ?? null, title: j.name,
      body: [j.command, j.cwd ?? "", j.port !== null && j.port !== undefined ? `:${j.port}` : ""].filter((w) => w !== "").join("\n"),
      at: j.startedAt ?? null,
      ref: { job: j.id, session: key, chat: key, state: j.state, ...(j.port !== null && j.port !== undefined ? { port: j.port } : {}), ...(thread ? { thread: thread.id } : {}) },
    })),
  };
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
export function memoryDocs(dataDir: string, ws: Ws): Indexed {
  const m = memory(dataDir, ws ?? undefined) as any;
  const docs: Doc[] = [];
  const source = `k:${ws ?? ""}`;
  const text = typeof m?.global?.text === "string" ? m.global.text : "";
  if (text.trim() !== "") docs.push({ key: `k:${ws ?? ""}:`, kind: "memory", source, ws, title: "MEMORY.md", body: text, at: null, ref: { path: m.global.path } });
  for (const k of Array.isArray(m?.skills) ? m.skills : []) {
    const files = Array.isArray(k.files) ? k.files : [];
    docs.push({
      key: `k:${ws ?? ""}:${k.name}`, kind: "skill", source, ws, title: k.name,
      body: [k.description ?? "", k.text ?? "", ...files.map((f: any) => `${f.name}\n${f.text}`)].join("\n"),
      at: null, ref: { skill: k.name, description: k.description ?? "", builtin: k.builtin === true, project: k.project === true },
    });
  }
  return { version: JSON.stringify(docs.map((d) => [d.key, d.body.length, d.body.slice(0, 64)])), docs, whole: true };
}

/// The profiles as documents: every workspace's members see them (`*`).
export function profileDocs(profiles: Profiles): Indexed {
  const docs: Doc[] = profiles.map((p) => ({
    key: `p:${p.id}`, kind: "profile", source: "p", ws: "*", title: p.name ?? p.id,
    body: [p.id, p.runtime, p.model ?? "", typeof p.access?.kind === "string" ? p.access.kind : "", typeof p.access?.provider === "string" ? p.access.provider : ""].filter((w) => w !== "").join("\n"),
    at: null, ref: { profile: p.id, runtime: p.runtime },
  }));
  return { version: JSON.stringify(docs.map((d) => [d.key, d.title, d.body])), docs, whole: true };
}
