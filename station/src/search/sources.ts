// What a search looks through of the station's own data, read as it is asked for from its store as
// the readers read it (read/store.ts, a read-only connection) and from the files beside it:
//
// - a thread: its chat (`c:<id>`) and each message as it reads now (`m:<id>:<n>`), an archived one's from its file.
// - a session's transcript: its execution history (`h:<key>:<i>`, `i` as GET /sessions/:key/timeline numbers them),
//   what the agent said and thought, the calls it made and what they gave, its files looked through newest first.
// - a session's jobs (`j:<id>`), a workspace's memory and skills, the profiles.
import { createReadStream, existsSync, readdirSync } from "node:fs";
import { open } from "node:fs/promises";
import { isAbsolute, join } from "node:path";
import { createZstdDecompress } from "node:zlib";
import { segmentsFrom } from "../read/packed.ts";
import * as store from "../read/store.ts";
import type { JobRow, MessageRow, SessionRow, Store } from "../read/store.ts";
import { type ReadState, sessionPlaces, timelineOf, transcriptSources, type TimelineEntry } from "../read/transcript.ts";
import { readFrom } from "../usage/counter.ts";
import { agentHomeOf, memory } from "../read/memory.ts";
import { runtimeKind } from "../agents/runtime.ts";
import { STILLFAIL_SURFACE } from "../read/store.ts";
import { given, titleOf } from "../read/views.ts";
import { type Asker, type Doc, type Group, type Hit, excerpt, has, sees } from "./match.ts";
import { readSearchScopePage } from "./scope-read.ts";
import { smallJobScope } from "./job-scope.ts";

/// The workspace documents of nothing in particular are in (`ws` null: the station's home one).
type Ws = string | null;

const all = (s: Store, sql: string, ...args: any[]): any[] => s.db.prepare(sql).all(...args);


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


const MESSAGE_BATCH = 256;

/// The next message numbers, in order, before the end captured for this search. The two indexes are merged before
/// fetching the messages and their edits, so a batch does not walk intervening edits. As with LAST_MESSAGE, a missing
/// entries_letters index or old letter metadata on non-messages can make the legacy lookup walk more entries.
const searchMessageKeys = (range: string, limit: string, legacy = false) => `
  SELECT n FROM ${legacy ? "legacy_said" : "entries INDEXED BY entries_said"}
    WHERE thread = ?1 AND ${range}${legacy ? "" : " AND kind = 'message' AND letter IS NULL"}
  UNION ALL
  SELECT n FROM entries
    WHERE thread = ?1 AND ${range} AND kind = 'message' AND letter IS NOT NULL
  ORDER BY n LIMIT ${limit}`;
const searchMessages = (range: string, limit: string, legacy = false) =>
  `SELECT * FROM merged WHERE thread = ?1 AND n IN (${searchMessageKeys(range, limit, legacy)}\n) ORDER BY n`;
const searchMessageTimes = (range: string, limit: string, legacy = false) =>
  `SELECT n, at FROM entries WHERE thread = ?1 AND kind = 'message' AND n IN (${searchMessageKeys(range, limit, legacy)}\n) ORDER BY n`;
export const SEARCH_FIRST_MESSAGES = searchMessages("n <= ?2", "?3");
export const SEARCH_NEXT_MESSAGES = searchMessages("n > ?2 AND n <= ?3", "?4");
export const LEGACY_SEARCH_FIRST_MESSAGES = searchMessages("n <= ?2", "?3", true);
export const LEGACY_SEARCH_NEXT_MESSAGES = searchMessages("n > ?2 AND n <= ?3", "?4", true);
export const SEARCH_FIRST_MESSAGE_TIMES = searchMessageTimes("n <= ?2", "?3");
export const SEARCH_NEXT_MESSAGE_TIMES = searchMessageTimes("n > ?2 AND n <= ?3", "?4");
export const LEGACY_SEARCH_FIRST_MESSAGE_TIMES = searchMessageTimes("n <= ?2", "?3", true);
export const LEGACY_SEARCH_NEXT_MESSAGE_TIMES = searchMessageTimes("n > ?2 AND n <= ?3", "?4", true);

/// A thread's documents, with a yield after each batch even when none of its messages is searchable.
function* threadDocSteps(s: Store, id: number, asker?: Asker, kinds: Set<string> | null = null, onlyArchived = false,
  words?: string[]): Generator<Doc | undefined> {
  const row = store.getThread(s, id);
  if (row === null) return;
  const { ws, chat, sessions } = chatOf(s, id);
  if (asker && !sees({ ws }, asker)) return;
  // Archived as people see it (by hand, or idle): out of the lists.
  const archived = row.hiddenAt !== null || (sessions.length > 0 && sessions.every((x) => x.archivedAt !== null));
  if (onlyArchived && !archived) return;
  const surface = row.surface === STILLFAIL_SURFACE ? "stillfail" : "slack";
  const firstText = (s.db.prepare("SELECT m.text FROM thread_state t JOIN merged m ON m.thread = t.thread AND m.n = t.person_n WHERE t.thread = ?").get(id) as { text: string | null } | undefined)?.text ?? null;
  // As the chat list calls it (read/views.ts titleOf).
  const title = titleOf(row, firstText, null);
  const wantsMessages = kinds === null || kinds.has("message");
  const wantsChat = kinds === null || kinds.has("chat");
  const body = wantsChat ? [...sessions.map((x) => x.title ?? ""), ...sessions.map((x) => x.model ?? "")].filter((w) => w !== "").join("\n") : "";
  const ref = { thread: id, chat, surface, archived, ...(row.channel ? { channel: row.channel } : {}) };
  let lastAt: number | null = null;
  // A chat's text does not include its messages. Only matches need their message times for ranking.
  if (!wantsMessages && words !== undefined && !has(`${title}\n${body}`, words)) return;
  const end = (s.db.prepare("SELECT MAX(n) AS n FROM entries WHERE thread = ?").get(id) as { n: number | null }).n;
  let after: number | null = null;
  const origins = new Map<string, string | null>();
  for (;;) {
    const first = wantsMessages ? (s.legacySaid ? LEGACY_SEARCH_FIRST_MESSAGES : SEARCH_FIRST_MESSAGES)
      : (s.legacySaid ? LEGACY_SEARCH_FIRST_MESSAGE_TIMES : SEARCH_FIRST_MESSAGE_TIMES);
    const next = wantsMessages ? (s.legacySaid ? LEGACY_SEARCH_NEXT_MESSAGES : SEARCH_NEXT_MESSAGES)
      : (s.legacySaid ? LEGACY_SEARCH_NEXT_MESSAGE_TIMES : SEARCH_NEXT_MESSAGE_TIMES);
    const rows = end === null ? [] : after === null ? all(s, first, id, end, MESSAGE_BATCH) : all(s, next, id, after, end, MESSAGE_BATCH);
    const messages: Pick<MessageRow, "n" | "createdAt">[] = wantsMessages ? rows.map(toMessage)
      : rows.map((r) => ({ n: r.n, createdAt: r.at }));
    if (messages.length === 0) break;
    for (const message of messages) {
      const at = message.createdAt ?? 0;
      lastAt = lastAt === null ? at : Math.max(lastAt, at);
      if (!wantsMessages) continue;
      const m = message as MessageRow;
      const text = m.text ?? "";
      const files = m.attachments.map((a: any) => (typeof a?.name === "string" ? a.name : "")).filter((n: string) => n !== "");
      if (text.trim() === "" && files.length === 0) continue;
      let identity = m.agentIdentity;
      if (m.authorKind === "agent" && typeof identity?.runtime !== "string") {
        if (!origins.has(m.author)) origins.set(m.author, store.originalRuntime(s, m.author) ?? sessions.find((x) => x.key === m.author)?.runtime ?? null);
        const runtime = origins.get(m.author);
        if (runtime) identity = { ...(identity ?? {}), runtime };
      }
      yield {
        key: `m:${id}:${m.n}`, kind: "message", ws, title: "",
        body: files.length > 0 ? `${text}\n${files.join("\n")}` : text,
        at: m.createdAt ?? null,
        ref: { thread: id, seq: m.n, chat, chatTitle: title, surface, archived, authorKind: m.authorKind, author: m.author, ...(identity ? { agentIdentity: identity } : {}) },
      };
    }
    after = messages.at(-1)!.n;
    yield undefined;
    if (messages.length < MESSAGE_BATCH) break;
  }
  if (wantsChat) yield {
    key: `c:${id}`, kind: "chat", ws, title,
    body,
    at: lastAt ?? row.createdAt ?? null, ref,
  };
}

/// A thread's documents: its chat, then its messages (an archived one's read from its file).
export function threadDocs(s: Store, id: number): Doc[] {
  const docs = [...threadDocSteps(s, id)].filter((d): d is Doc => d !== undefined);
  const chat = docs.pop();
  return chat === undefined ? docs : [chat, ...docs];
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
export async function transcriptFiles(s: Store, session: Pick<SessionRow, "key" | "workspace" | "cwd">, profiles: Profiles,
  keep: () => boolean = () => true, afterYield: () => void = () => {}): Promise<{ paths: { path: string; runtime: NonNullable<ReturnType<typeof runtimeKind>> }[] } | null> {
  const sources = store.historyRuntimeSources(s, session.key);
  const paths: { path: string; runtime: NonNullable<ReturnType<typeof runtimeKind>> }[] = [];
  let visited = 0, any = false;
  try {
    for (const source of sources) {
      if (!keep()) return null;
      if (source !== null) { any = true; paths.push(...transcriptSources(s.dataDir, profiles, [source], sessionPlaces(session)).paths); }
      if (++visited % 64 === 0) {
        await new Promise<void>((resolve) => setImmediate(resolve));
        if (!keep()) return null;
        afterYield();
      }
    }
  } finally { sources.close(); }
  return any ? { paths } : null;
}

/// A transcript's entries, each given to `each` as it is read: in parts (a file put away decompressed as a stream), never
/// the whole of it at once.
async function entriesOf(runtime: NonNullable<ReturnType<typeof runtimeKind>>, path: string, state: ReadState, each: (e: TimelineEntry) => void, keep: () => boolean): Promise<void> {
  const out: TimelineEntry[] = [];
  for await (const part of readFrom(path, 0, keep)) {
    for (let line of part.text.split("\n")) {
      if (!keep()) return;
      if (line.endsWith("\r")) line = line.slice(0, -1);
      if (line === "") continue;
      let record: unknown;
      try {
        record = JSON.parse(line);
      } catch {
        continue;
      }
      timelineOf(runtime, record, state, out);
      for (const e of out) {
        if (!keep()) return;
        each(e);
      }
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
export async function mentions(path: string, words: string[], keep: () => boolean = () => true): Promise<boolean> {
  const finds = words.map(finder);
  const left = new Set(finds);
  const look = (bytes: Buffer) => {
    for (const f of left) if (f(bytes)) left.delete(f);
    return left.size === 0;
  };
  if (!keep()) return false;
  if (existsSync(path)) {
    const buf = Buffer.allocUnsafe(CHUNK + OVERLAP);
    const file = await open(path, "r");
    try {
      let pos = 0;
      let kept = 0;
      for (;;) {
        if (!keep()) return false;
        const { bytesRead: n } = await file.read(buf, kept, CHUNK, pos);
        if (!keep()) return false;
        if (n <= 0) return false;
        const view = buf.subarray(0, kept + n);
        const found = look(view);
        if (!keep()) return false;
        if (found) return true;
        pos += n;
        kept = Math.min(OVERLAP, view.length);
        view.copy(buf, 0, view.length - kept);
        await new Promise<void>((resolve) => setImmediate(resolve));
      }
    } finally {
      await file.close();
    }
  }
  if (!existsSync(`${path}.zst`)) return false;
  let tail: Buffer = Buffer.alloc(0);
  const through = async (chunks: AsyncIterable<Buffer>): Promise<boolean> => {
    for await (const chunk of chunks) {
      if (!keep()) return false;
      const view = tail.length > 0 ? Buffer.concat([tail, chunk]) : chunk;
      const found = look(view);
      if (!keep()) return false;
      if (found) return true;
      tail = Buffer.from(view.subarray(Math.max(0, view.length - OVERLAP)));
      await new Promise<void>((resolve) => setImmediate(resolve));
    }
    return false;
  };
  // In segments (read/packed.ts): each decompressed on its own.
  const segments = await segmentsFrom(`${path}.zst`, 0).catch(() => null);
  if (segments !== null) {
    try {
      return await through(segments);
    } catch {
      return false;
    } finally {
      await segments.return(undefined);
    }
  }
  const raw = createReadStream(`${path}.zst`, { highWaterMark: 1 << 20 });
  const stream = raw.pipe(createZstdDecompress({ chunkSize: 4 << 20 }));
  raw.on("error", (error) => stream.destroy(error));
  try {
    return await through(stream as AsyncIterable<Buffer>);
  } catch {
    // Unreadable: not found there.
    return false;
  } finally {
    raw.destroy();
    stream.destroy();
  }
}

export type HistoryFound = { hits: Hit[]; more: boolean; /** Sessions not looked through, the time being up. */ left: number };

/// Even with no hits, a stopped search must tell its caller that some histories were not searched.
export function historyGroup(found: HistoryFound): Group | null {
  if (!found.hits.length && !found.left) return null;
  return { kind: "history", hits: found.hits, more: found.more, ...(found.left > 0 ? { left: found.left } : {}) };
}

/**
 * What the words find in the execution histories `asker` may see, the most recently active sessions first and each one's
 * latest steps first, until `offset + limit` and one more are found or `ms` is up. A session's files are read (its
 * entries numbered as its history page numbers them) only when they have every word.
 */
export async function historyHits(s: Store, profiles: Profiles, words: string[], asker: Asker, options: { limit: number; offset: number; ms: number; now: () => number; cancelled?: () => boolean }): Promise<HistoryFound> {
  const want = options.offset + options.limit + 1;
  const until = options.now() + options.ms;
  const found: Hit[] = [];
  if (options.cancelled?.()) throw new Error("the search took too long");
  const sessions = store.historySessionSnapshot(s, asker);
  try {
    // A search yields while it reads files, and sessions can move or be removed in the meantime. Check before looking at
    // a session's files and once more before returning any hits accumulated from it (including a timed-out page).
    const workspaceOf = s.db.prepare("SELECT ws FROM sessions WHERE key = ?");
    const workspacesOf = s.db.prepare("SELECT s.key, s.ws FROM json_each(?) j LEFT JOIN sessions s ON s.key = j.value");
    const hitSessions = new Set<string>();
    const checkVisible = (key: string) => {
      const row = workspaceOf.get(key) as { ws: string | null } | undefined;
      if (!row || !sees({ ws: row.ws ?? null }, asker)) throw new Error("the session changed while searching; search again");
    };
    const finish = (result: HistoryFound): HistoryFound => {
      if (hitSessions.size > 0) {
        const rows = workspacesOf.all(JSON.stringify([...hitSessions])) as { key: string | null; ws: string | null }[];
        if (rows.some((row) => row.key === null || !sees({ ws: row.ws ?? null }, asker)))
          throw new Error("the session changed while searching; search again");
      }
      return result;
    };
    let looked = 0;
    let cancelled = false;
    let expired = false;
    const keep = () => {
      if (cancelled || expired) return false;
      if (options.cancelled?.()) cancelled = true;
      else if (options.now() > until) expired = true;
      return !cancelled && !expired;
    };
    const partial = (current: string): HistoryFound => {
      if (cancelled) throw new Error("the search took too long");
      checkVisible(current);
      return finish({ hits: found.slice(options.offset, options.offset + options.limit), more: true, left: sessions.length - looked });
    };
    for (const session of sessions) {
      if (found.length >= want) break;
      if (!keep()) return partial(session.key);
      // Let through: a search asked meanwhile is answered between sessions.
      await new Promise<void>((resolve) => setImmediate(resolve));
      if (!keep()) return partial(session.key);
      checkVisible(session.key);
      const files = await transcriptFiles(s, session, profiles, keep, () => checkVisible(session.key));
      if (!keep()) return partial(session.key);
      if (files === null) { looked++; continue; }
      let any = false;
      for (const p of files.paths) {
        if (await mentions(p.path, words, keep)) any = true;
        if (!keep()) return partial(session.key);
        checkVisible(session.key);
        if (any) break;
      }
      if (!any) { looked++; continue; }
      // Its latest steps that have the words, as many as may still be wanted (numbered as they are read).
      const room = want - found.length;
      // Keep excerpts, not entire matching entries: one history step can itself contain a very large tool result.
      const latest: { i: number; entry: TimelineEntry["kind"]; tool: TimelineEntry["tool"]; at: number | null; text: string }[] = [];
      let oldest = 0;
      let i = 0;
      for (const p of files.paths) {
        await entriesOf(p.runtime, p.path, { inner: new Map() }, (e) => {
          const text = historyText(e);
          if (text !== null && has(text, words)) {
            const time = e.at === null ? null : Date.parse(e.at);
            const item = { i, entry: e.kind, tool: e.tool, at: time !== null && Number.isFinite(time) ? time : null, text: excerpt(text, words) };
            if (latest.length < room) latest.push(item);
            else { latest[oldest] = item; oldest = (oldest + 1) % room; }
          }
          i++;
        }, keep);
        if (!keep()) return partial(session.key);
        checkVisible(session.key);
      }
      const thread = store.sessionThreads(s, session.key, STILLFAIL_SURFACE, 1)[0] ?? null;
      const chatTitle = (thread !== null ? given(thread) : null) ?? (session.title?.trim() || "");
      const ordered = latest.length < room ? latest : [...latest.slice(oldest), ...latest.slice(0, oldest)];
      if (ordered.length > 0) hitSessions.add(session.key);
      for (const { i, entry, tool, at, text } of ordered.reverse()) {
        found.push({
          session: session.key, index: i, entry, ...(tool ? { tool } : {}), chat: session.key, chatTitle, ...(thread ? { thread: thread.id } : {}),
          key: `h:${session.key}:${i}`, kind: "history", title: "", text, at,
        });
      }
      looked++;
      if (found.length >= want) break;
    }
    return finish({ hits: found.slice(options.offset, options.offset + options.limit), more: found.length > options.offset + options.limit, left: 0 });
  } finally { sessions.close(); }
}

export const sessionKeys = (s: Store): string[] => all(s, "SELECT key FROM sessions").map((r) => r.key as string);

// ── jobs ──

/// A session's jobs (its services and tasks) as documents.
export function jobDocs(s: Store, key: string): Doc[] {
  const session = store.getSession(s, key);
  const jobs = store.listJobs(s, key);
  const thread = session ? (store.sessionThreads(s, key, STILLFAIL_SURFACE, 1)[0] ?? null) : null;
  return jobs.map((j) => jobDoc(j, key, session, thread));
}

function jobDoc(j: Pick<JobRow, "id" | "name" | "command" | "cwd" | "port" | "state" | "startedAt">,
  key: string, session: SessionRow | null, thread: ReturnType<typeof store.sessionThreads>[number] | null): Doc {
  return {
    key: `j:${j.id}`, kind: "job", ws: session?.ws ?? null, title: j.name,
    body: [j.command, j.cwd ?? "", j.port !== null && j.port !== undefined ? `:${j.port}` : ""].filter((w) => w !== "").join("\n"),
    at: j.startedAt ?? null,
    ref: { job: j.id, session: key, chat: key, state: j.state, ...(j.port !== null && j.port !== undefined ? { port: j.port } : {}), ...(thread ? { thread: thread.id } : {}) },
  };
}

type JobSessionPosition = { session_key: string; bytes: Uint8Array; storage: string };
const JOB_SESSION_POSITION = "session_key, CAST(session_key AS BLOB) AS bytes, typeof(session_key) AS storage";
// Some Node SQLite readers truncate text at an embedded NUL. Keep the original bytes for the ordered cursor; when they
// are valid UTF-8, use the full decoded key for session and job lookups as well.
function jobSessionKey(row: JobSessionPosition): string {
  if (row.storage !== "text") return row.session_key;
  const bytes = Buffer.from(row.bytes), decoded = bytes.toString("utf8");
  return Buffer.from(decoded, "utf8").equals(bytes) ? decoded : row.session_key;
}
const jobSessionBound = (row: JobSessionPosition, parameter: string) => row.storage === "text" ? `CAST(${parameter} AS TEXT)` : parameter;
const jobSessionValue = (row: JobSessionPosition) => row.storage === "text" ? row.bytes : row.session_key;

/// Read a session's jobs by their rowid, which jobs_by_session orders after the session key. `pick` ranks by startedAt;
/// rowid order preserves the old stable order for ties while avoiding a sort and an array of all the session's jobs.
function* jobDocSteps(s: Store, key: string, session: SessionRow, asker?: Asker): Generator<Doc | undefined> {
  const end = (s.db.prepare("SELECT MAX(rowid) AS n FROM jobs INDEXED BY jobs_by_session WHERE session_key = ?").get(key) as { n: number | null }).n;
  if (end === null) return;
  const thread = store.sessionThreads(s, key, STILLFAIL_SURFACE, 1)[0] ?? null;
  let current = session;
  let after: number | null = null;
  for (;;) {
    const rows = after === null
      ? all(s, "SELECT rowid AS seq, id, name, command, cwd, port, state, started_at FROM jobs WHERE session_key = ? AND rowid <= ? ORDER BY rowid LIMIT ?", key, end, MESSAGE_BATCH)
      : all(s, "SELECT rowid AS seq, id, name, command, cwd, port, state, started_at FROM jobs WHERE session_key = ? AND rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?", key, after, end, MESSAGE_BATCH);
    if (rows.length === 0) return;
    for (const r of rows) yield jobDoc({ id: r.id, name: r.name, command: r.command, cwd: r.cwd, port: r.port, state: r.state, startedAt: r.started_at }, key, current, thread);
    after = rows.at(-1)!.seq as number;
    yield undefined;
    // A session can move or go while another search is running between batches. Never read its next batch for its old
    // workspace, nor return an apparently complete result assembled before access changed.
    const latest = store.getSession(s, key);
    if (!latest || (asker && !sees({ ws: latest.ws }, asker))) throw new Error("the session changed while searching; search again");
    if (rows.length < MESSAGE_BATCH) return;
    current = latest;
  }
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

/// The documents of the kinds asked for; undefined gives the worker a chance to handle another request. When words
/// are supplied, a nonmatching chat may be omitted before its message times are read.
export function* stationDocSteps(s: Store, data: string, config: unknown, kinds: Set<string> | null, asker?: Asker,
  onlyArchived = false, words?: string[], onScopeUnavailable?: () => void, onSessionListPending?: () => void): Generator<Doc | undefined> {
  const wants = (k: string) => kinds === null || kinds.has(k);
  if (wants("chat") || wants("message")) {
    const end = (s.db.prepare("SELECT MAX(id) AS id FROM threads").get() as { id: number | null }).id;
    let after: number | null = null;
    while (end !== null) {
      const scoped = asker ? readSearchScopePage(s.db, asker, after, end, MESSAGE_BATCH) : null;
      if (asker && scoped === null) onScopeUnavailable?.();
      const rows = scoped !== null ? scoped.map((id) => ({ id })) : after === null
        ? all(s, "SELECT id FROM threads WHERE id <= ? ORDER BY id LIMIT ?", end, MESSAGE_BATCH)
        : all(s, "SELECT id FROM threads WHERE id > ? AND id <= ? ORDER BY id LIMIT ?", after, end, MESSAGE_BATCH);
      if (rows.length === 0) break;
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i]!;
        try {
          yield* threadDocSteps(s, r.id, asker, kinds, onlyArchived, words);
        } catch (error) {
          // A thread moved to the archive while it was read: found the next time.
          if (!(error instanceof Error && /no such|archive|ENOENT/.test(error.message))) throw error;
        }
        // A chat filtered out before its messages produces no document for the search loop to yield on.
        if ((i + 1) % 128 === 0 && i + 1 < rows.length) yield undefined;
      }
      after = rows.at(-1)!.id as number;
      yield undefined;
      // A ready page can become dirty while its chats are read. Check again before ending, and resume the original
      // walk from this cursor if a concurrent membership or session change needs repair.
      if (scoped === null && rows.length < MESSAGE_BATCH) break;
    }
  }
  if (wants("job")) {
    // Seek to the next session in the jobs index, rather than visiting every session without a job or counting a
    // session once for each of its jobs. The saved end keeps newly created sessions from extending a search forever.
    const end = s.db.prepare(`SELECT ${JOB_SESSION_POSITION} FROM jobs INDEXED BY jobs_by_session
      ORDER BY session_key DESC LIMIT 1`).get() as JobSessionPosition | undefined;
    const scoped = end && asker ? smallJobScope(s.db, asker, jobSessionKey(end), onSessionListPending) : null;
    if (scoped !== null) {
      const hasJobs = s.db.prepare("SELECT 1 FROM jobs INDEXED BY jobs_by_session WHERE session_key = ? LIMIT 1");
      for (let i = 0; i < scoped.length; i++) {
        const key = scoped[i]!;
        if (hasJobs.get(key) !== undefined) {
          const session = store.getSession(s, key);
          if (session && (!asker || sees({ ws: session.ws }, asker))) yield* jobDocSteps(s, key, session, asker);
        }
        if ((i + 1) % 32 === 0) yield undefined;
      }
    } else {
      let after: JobSessionPosition | null = null;
      while (end !== undefined) {
        const row = (after === null
          ? s.db.prepare(`SELECT ${JOB_SESSION_POSITION} FROM jobs INDEXED BY jobs_by_session
              WHERE session_key <= ${jobSessionBound(end, "?1")} ORDER BY session_key LIMIT 1`).get(jobSessionValue(end))
          : s.db.prepare(`SELECT ${JOB_SESSION_POSITION} FROM jobs INDEXED BY jobs_by_session
              WHERE session_key > ${jobSessionBound(after, "?1")} AND session_key <= ${jobSessionBound(end, "?2")}
              ORDER BY session_key LIMIT 1`).get(jobSessionValue(after), jobSessionValue(end))) as JobSessionPosition | undefined;
        if (!row) break;
        const key = jobSessionKey(row);
        after = row;
        const session = store.getSession(s, key);
        if (session && (!asker || sees({ ws: session.ws }, asker))) yield* jobDocSteps(s, key, session, asker);
        yield undefined;
      }
    }
  }
  if (wants("skill") || wants("memory")) {
    for (const ws of [null, ...memoryWorkspaces(agentHomeOf(data))]) {
      if (!asker || sees({ ws }, asker)) for (const d of memoryDocs(data, ws)) if (wants(d.kind)) yield d;
      yield undefined;
    }
  }
  if (wants("profile")) yield* profileDocs(profilesOf(config, data));
}

/// The same documents for synchronous callers.
export function* stationDocs(s: Store, data: string, config: unknown, kinds: Set<string> | null, asker?: Asker): Generator<Doc> {
  for (const d of stationDocSteps(s, data, config, kinds, asker)) if (d !== undefined) yield d;
}
