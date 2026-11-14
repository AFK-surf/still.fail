// What the agents spent, counted (the Rust station's usage.rs `Usage`): every model call their runtimes write to a transcript
// (Claude Code's message usage, Codex's token counts) is recorded once in the store (store/usage.ts), with the turn it
// was in and whom that turn worked for. The transcripts are read as they grow, from where the last read stopped: all of
// them as sessions run, from the counter's installation onward; older transcripts are not backfilled.
//
// Pushed rather than polled (the Rust reads every minute): a read when the counter starts, one shortly after a turn
// ends (the store's session changes say so), one of a session alone shortly after its transcript grew while it works
// (the live view says so: what a chat shows it spent goes on with each call), and a slow safety read for anything
// missed. Reads never overlap. The reading itself must not hold the main thread: files are read asynchronously in
// chunks cut at whole lines, each chunk parsed and recorded on its own, with the event loop let through between chunks.
// What is recorded is the one count of what was spent: a chat's usage and the usage page are both added up from it.
// The prices (what a call costs) are the usage page's: src/read/usage.ts.
import { Clock, Effect, Fiber, Queue } from "effect";
import { liveClock } from "../ops/fibers.ts";
import { createReadStream, existsSync } from "node:fs";
import { type FileHandle, open, readdir, realpath, stat } from "node:fs/promises";
import { basename, dirname, join, sep } from "node:path";
import { createZstdDecompress } from "node:zlib";
import { log } from "../ops/log.ts";
import { segmentsFrom, writtenLength } from "../read/packed.ts";
import { parseIso, sharedTranscripts, transcriptDir, transcriptPaths } from "../read/transcript.ts";
import type { SessionRow, Store, UsageCall, UsageFile, UsageFor, UsageTurn, UsageWrite } from "../store/store.ts";
import { runtimeKind, type RuntimeKind } from "../agents/runtime.ts";

/// Calls a little before a session was made (the runtime's clock against the station's) are still its own.
export const SKEW_MS = 5_000;
/// A later read takes the sessions with a turn running or ended this long before the last read began (the Rust's
/// EVERY, the margin it reads them again with).
const MARGIN_MS = 60_000;
/// How long after a turn ends, or a session at work wrote more, its transcript is read (its last lines written, other
/// turns ending with it, a burst of writes gathered).
export const SETTLE_MS = 2_000;
/// How often everything that ran is read anyway, for what no turn's end told.
export const SAFETY_MS = 10 * 60_000;
/// How much of a transcript is read and parsed at a time.
const CHUNK = 1 << 20;
/// Bytes before a saved position: a file can be replaced and grow past that position between reads.
const ANCHOR = 256;
/// How many calls are recorded in one transaction before the event loop is let through.
const WRITE_BATCH = 64;

type Runtime = RuntimeKind;

/// What the counter reads of the station's config: where its data is, and each profile's home (absolute).
export type UsageConfig = { dataDir: string; profiles: readonly { home: string }[] };

export type UsageCounterOptions = {
  store: Store;
  /// Read at every read, so profiles added since are read too.
  config: () => UsageConfig;
  settleMs?: number;
  safetyMs?: number;
  /// Its time (a TestClock in tests).
  clock?: Clock.Clock;
  /// The turns a part's calls were made in (store/usage.ts `usageTurns`), asked of a reader (none: of the store, here).
  turns?: (session: string, from: number, until: number) => Promise<UsageTurn[]>;
};

// ── reading transcripts ──

/// What reading a transcript carries from line to line and from read to read: the model it last named (Codex), its
/// session's id (Codex's first line), and the model's window as last told (dsh's request/context, before its calls).
export type CallState = { model: string | null; codexId: string | null; window?: number | null };

const get = (v: unknown, k: string): unknown =>
  v !== null && typeof v === "object" && !Array.isArray(v) && Object.hasOwn(v, k) ? (v as Record<string, unknown>)[k] : undefined;
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
/// serde_json's as_i64, or 0.
const n = (v: unknown): number => (typeof v === "number" && Number.isInteger(v) ? v : 0);

/// A count a turn's line tells apart (its context, the model's window): none when it says none.
const told = (v: unknown): number | null => (n(v) > 0 ? n(v) : null);

/// calls_of: a transcript's lines read into calls; `state` carries the model, Codex id and window on. The only place what
/// the agents spent is read from their transcripts: a chat's usage and the usage page are both what it records.
export function callsOf(runtime: Runtime, text: string, subagent: boolean, state: CallState): UsageCall[] {
  const out: UsageCall[] = [];
  const atIndex = new Map<string, number>();
  for (let line of text.split("\n")) {
    if (line.endsWith("\r")) line = line.slice(0, -1);
    // Most lines are something else: only those that may hold usage are parsed.
    const wanted =
      runtime === "claude" ? line.includes('"usage"')
      : runtime === "dsh" ? (line.startsWith('{"type":"assistant/message"') && line.includes('"usage"')) || line.startsWith('{"type":"request/context"')
      : runtime === "grok" ? line.startsWith('{"type":"stillfail/usage"')
      : runtime === "cursor" || runtime === "devin" || runtime === "hermes" || runtime === "agy" ? line.includes('"type":"usage"')
      : line.includes("token_count") || line.includes("turn_context") || line.includes("session_meta");
    if (!wanted) continue;
    let r: unknown;
    try {
      r = JSON.parse(line);
    } catch {
      continue;
    }
    const stamp = str(get(r, "timestamp"));
    const at = (stamp === null ? null : parseIso(stamp)) ?? 0;
    if (runtime === "grok") {
      // What the station kept of each Grok Build turn (agents/grok.ts usageLine): its counts already apart.
      const usage = get(r, "usage");
      const id = str(get(r, "id"));
      if (usage === undefined || usage === null || id === null) continue;
      const time = get(r, "time");
      out.push({
        id: `grok:${id}`, at: typeof time === "number" ? time : 0, model: str(get(r, "model")), subagent, fast: false,
        input: n(get(usage, "input")), cacheRead: n(get(usage, "cacheRead")), cacheWrite: n(get(usage, "cacheWrite")), cacheWriteLong: 0,
        output: n(get(usage, "output")), calls: Math.max(1, n(get(usage, "calls"))), context: told(get(r, "context")), window: told(get(r, "window")),
      });
    } else if (runtime === "cursor" || runtime === "devin" || runtime === "hermes" || runtime === "agy") {
      // What the station's driver kept of each Cursor turn (agents/cursor-bridge.mjs): the SDK's counts, input apart
      // from the cache's, the whole run's (no context); of each Devin call (or an earlier turn told at once,
      // agents/devin.ts), with how many calls it counts, the context it left and the model's window where Devin said them.
      const usage = get(r, "usage");
      const id = str(get(r, "run"));
      if (str(get(r, "type")) !== "usage" || usage === undefined || usage === null || id === null) continue;
      const time = get(r, "time");
      out.push({
        id: `${runtime}:${id}`, at: typeof time === "number" ? time : 0, model: str(get(r, "model")), subagent, fast: false,
        input: n(get(usage, "inputTokens")), cacheRead: n(get(usage, "cacheReadTokens")), cacheWrite: n(get(usage, "cacheWriteTokens")), cacheWriteLong: 0,
        output: n(get(usage, "outputTokens")), calls: Math.max(1, n(get(r, "calls"))), context: told(get(r, "context")), window: told(get(r, "window")),
      });
    } else if (runtime === "dsh") {
      // dsh's counts are apart: input is what was not cached. The model's window comes before a request's calls.
      const data = get(r, "data");
      if (str(get(r, "type")) === "request/context") {
        state.window = told(get(data, "contextWindow")) ?? state.window ?? null;
        continue;
      }
      const usage = get(data, "usage");
      const message = get(data, "message");
      const id = str(get(message, "id"));
      if (usage === undefined || usage === null || id === null) continue;
      const time = get(r, "time");
      const [input, cacheRead, cacheWrite] = [n(get(usage, "inputTokens")), n(get(usage, "cacheReadTokens")), n(get(usage, "cacheWriteTokens"))];
      out.push({
        id: `dsh:${id}`, at: typeof time === "number" ? time : 0, model: str(get(get(message, "source"), "model")), subagent, fast: false,
        input, cacheRead, cacheWrite, cacheWriteLong: 0, output: n(get(usage, "outputTokens")), calls: 1,
        context: subagent ? null : input + cacheRead + cacheWrite, window: state.window ?? null,
      });
    } else if (runtime === "claude") {
      if (str(get(r, "type")) !== "assistant") continue;
      const m = get(r, "message");
      if (m === undefined) continue;
      const usage = get(m, "usage");
      const id = str(get(m, "id"));
      if (usage === undefined || id === null) continue;
      const name = str(get(m, "model"));
      if (name === null || name === "<synthetic>") continue;
      const written = n(get(usage, "cache_creation_input_tokens"));
      const split = get(usage, "cache_creation");
      const long = split === undefined ? 0 : n(get(split, "ephemeral_1h_input_tokens"));
      const five = split === undefined ? null : n(get(split, "ephemeral_5m_input_tokens"));
      const short = five !== null && five + long === written ? five : written - long;
      const side = subagent || get(r, "isSidechain") === true;
      const input = n(get(usage, "input_tokens"));
      const cacheRead = n(get(usage, "cache_read_input_tokens"));
      // The main thread's prompt is its context; a subagent's is its own.
      const call: UsageCall = {
        id, at, model: name, subagent: side, fast: get(usage, "speed") === "fast", input, cacheRead, cacheWrite: short,
        cacheWriteLong: long, output: n(get(usage, "output_tokens")), calls: 1, context: side ? null : input + cacheRead + written, window: null,
      };
      // One response is written as several lines (a block each), each with its usage: counted once, at its fullest.
      const i = atIndex.get(id);
      if (i !== undefined) out[i]!.output = Math.max(out[i]!.output, call.output);
      else {
        atIndex.set(id, out.length);
        out.push(call);
      }
    } else {
      const p = get(r, "payload") ?? null;
      const type = str(get(r, "type"));
      if (type === "session_meta") state.codexId = str(get(p, "id")) ?? state.codexId;
      else if (type === "turn_context") state.model = str(get(p, "model")) ?? state.model;
      else if (type === "event_msg" && str(get(p, "type")) === "token_count") {
        const info = get(p, "info");
        const last = info === undefined || info === null ? undefined : get(info, "last_token_usage");
        if (last === undefined || last === null) continue;
        // Token counts are told again with rate limits; the running total tells a call from its repeat. Codex's input
        // has what was cached in it.
        const totals = get(info, "total_token_usage");
        const total = totals === undefined ? at : n(get(totals, "total_tokens"));
        const sent = n(get(last, "input_tokens"));
        const cached = Math.min(n(get(last, "cached_input_tokens")), sent);
        out.push({
          id: `codex:${state.codexId ?? ""}:${total}`, at, model: state.model, subagent, fast: false,
          input: sent - cached, cacheRead: cached, cacheWrite: 0, cacheWriteLong: 0, output: n(get(last, "output_tokens")), calls: 1,
          context: subagent ? null : sent, window: told(get(info, "model_context_window")),
        });
      }
    }
  }
  return out;
}

/// archive.rs `packed`: where a file is once put away.
const packed = (path: string) => `${path}.zst`;

async function isFile(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}

async function isDir(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}

async function exists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

const canonical = async (path: string) => {
  try {
    return await realpath(path);
  } catch {
    return path;
  }
};

/// Rust's Path::extension: after the name's last dot, none for a name that only begins with one.
function extension(path: string): string | null {
  const name = basename(path);
  const dot = name.lastIndexOf(".");
  return dot <= 0 ? null : name.slice(dot + 1);
}

/// A part of a transcript: its whole lines and their bounds in the file.
export type Part = { text: string; from: number; offset: number; bytes: Buffer };

/// Whole lines of `bytes` (what follows `from` in the file), a part at most CHUNK long each where lines allow.
function* partsOf(bytes: Buffer, from: number): Generator<Part> {
  let at = 0;
  while (at < bytes.length) {
    const window = Math.min(bytes.length, at + CHUNK);
    let cut = bytes.lastIndexOf(0x0a, window - 1);
    if (cut < at) cut = bytes.indexOf(0x0a, window);
    if (cut < 0) return;
    const part = bytes.subarray(at, cut + 1);
    yield { text: part.toString("utf8"), from: from + at, offset: from + cut + 1, bytes: part };
    at = cut + 1;
  }
}

/// A line already begun at the cutoff belongs to the old part; complete later lines belong to the followed suffix.
function sectionsOf(part: Part, cutoff: number): (Part & { followed: boolean })[] {
  if (part.offset <= cutoff) return [{ ...part, followed: false }];
  if (part.from >= cutoff) return [{ ...part, followed: true }];
  const at = cutoff - part.from;
  const end = part.bytes[at - 1] === 0x0a ? at : part.bytes.indexOf(0x0a, at) + 1;
  const old = part.bytes.subarray(0, end);
  const next = part.bytes.subarray(end);
  return [
    { text: old.toString("utf8"), bytes: old, from: part.from, offset: part.from + end, followed: false },
    ...(end < part.bytes.length ? [{ text: next.toString("utf8"), bytes: next, from: part.from + end, offset: part.offset, followed: true }] : []),
  ];
}

/// Keep unfinished lines as pieces and copy them only when a newline arrives, even if one line spans many chunks.
class Lines {
  #held: Buffer[] = [];
  #size = 0;
  #start: number;

  constructor(start: number) { this.#start = start; }

  *add(piece: Buffer): Generator<Part> {
    const cut = piece.lastIndexOf(0x0a);
    if (cut < 0) {
      if (piece.length) { this.#held.push(piece); this.#size += piece.length; }
      return;
    }
    const complete = piece.subarray(0, cut + 1);
    const bytes = this.#size === 0 ? complete : Buffer.concat([...this.#held, complete], this.#size + complete.length);
    yield* partsOf(bytes, this.#start);
    this.#start += bytes.length;
    const rest = piece.subarray(cut + 1);
    this.#held = rest.length ? [rest] : [];
    this.#size = rest.length;
  }
}

/// A file put away, past `offset`, as `readFrom` says it: decompressed as it is read, never whole (one is hundreds of MB,
/// and every one is read again as the station starts). Shorter than `offset`: read again from its start.
async function* packedFrom(path: string, offset: number, keep: () => boolean): AsyncGenerator<Part> {
  if (!keep()) return;
  // In segments (read/packed.ts): those from `offset` on alone.
  const length = await writtenLength(packed(path)).catch(() => null);
  if (!keep()) return;
  if (length !== null) {
    if (offset > length) {
      yield* packedFrom(path, 0, keep);
      return;
    }
    const segments = await segmentsFrom(packed(path), offset).catch(() => null);
    if (segments === null) return;
    const lines = new Lines(offset);
    try {
      for await (const piece of segments) {
        if (!keep()) return;
        yield* lines.add(piece);
      }
    } catch {
      return;
    }
    return;
  }
  const raw = createReadStream(packed(path), { highWaterMark: CHUNK });
  const stream = raw.pipe(createZstdDecompress({ chunkSize: CHUNK }));
  raw.on("error", (error) => stream.destroy(error));
  // What is past `offset` and not given yet.
  const lines = new Lines(offset);
  let total = 0;
  try {
    for await (const chunk of stream as AsyncIterable<Buffer>) {
      if (!keep()) return;
      const from = Math.max(0, offset - total);
      total += chunk.length;
      if (from >= chunk.length) continue;
      yield* lines.add(from === 0 ? chunk : chunk.subarray(from));
    }
  } catch {
    return;
  } finally {
    raw.destroy();
    stream.destroy();
  }
  if (total < offset) {
    yield* packedFrom(path, 0, keep);
    return;
  }
}

/// read_from: what a file holds past `offset`, up to its last whole line, in parts with where each ends. A file now
/// shorter than `offset` was written anew: it is read from its start (calls already recorded stay once). A file put
/// away (only its `.zst` there) is read decompressed.
/// Whether a transcript is put away: only its `.zst` there.
const putAway = async (path: string): Promise<boolean> => !(await exists(path)) && (await exists(packed(path)));

export async function* readFrom(path: string, offset: number, keep: () => boolean = () => true): AsyncGenerator<Part> {
  if (!keep()) return;
  if (await putAway(path)) {
    yield* packedFrom(path, offset, keep);
    return;
  }
  if (!keep()) return;
  let size: number;
  try {
    size = (await stat(path)).size;
  } catch {
    return;
  }
  let pos = size < offset ? 0 : offset;
  if (pos === size) return;
  let file: FileHandle;
  try {
    file = await open(path, "r");
  } catch {
    return;
  }
  try {
    // Up to the size it had: what is written meanwhile is the next read's.
    const lines = new Lines(pos);
    while (pos < size) {
      if (!keep()) return;
      const buf = Buffer.allocUnsafe(Math.min(CHUNK, size - pos));
      const { bytesRead } = await file.read(buf, 0, buf.length, pos);
      if (!keep()) return;
      if (bytesRead === 0) break;
      pos += bytesRead;
      yield* lines.add(buf.subarray(0, bytesRead));
    }
  } finally {
    await file.close();
  }
}

async function jsonlIn(dir: string): Promise<string[]> {
  let names: string[];
  try {
    names = await readdir(dir);
  } catch {
    return [];
  }
  const paths = new Set<string>();
  for (const name of names) {
    const p = join(dir, name);
    if (!(await isFile(p))) continue;
    const q = extension(p) === "zst" ? p.slice(0, -".zst".length) : p;
    if (extension(q) === "jsonl") paths.add(q);
  }
  return [...paths].sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
}

/// claude_files: a Claude Code session's transcripts in a project directory: its own, and its sub-agents' beside it
/// (`<id>/subagents/*.jsonl`); `subagent` says which. `only`: that runtime session's alone (a session continued from a
/// terminal shares its directory with the terminal's own).
export async function claudeFiles(dir: string, only: string | null): Promise<[string, boolean][]> {
  let own: string[];
  if (only !== null) {
    const p = join(dir, `${only}.jsonl`);
    own = (await isFile(p)) || (!(await exists(p)) && (await isFile(packed(p)))) ? [p] : [];
  } else own = await jsonlIn(dir);
  const out: [string, boolean][] = own.map((p) => [p, false]);
  for (const p of own) {
    const id = basename(p).slice(0, -".jsonl".length);
    for (const s of await jsonlIn(join(dir, id, "subagents"))) out.push([s, true]);
  }
  return out;
}

/// The first line of a file (or of its `.zst`), up to its end when it has no newline; null when it does not read.
async function firstLine(path: string): Promise<string | null> {
  const source = (await exists(path)) ? path : packed(path);
  if (!(await exists(source))) return null;
  return new Promise((resolve) => {
    const raw = createReadStream(source);
    const stream = source === path ? raw : raw.pipe(createZstdDecompress());
    const parts: Buffer[] = [];
    let done = false;
    const finish = (line: string | null) => {
      if (done) return;
      done = true;
      raw.destroy();
      if (stream !== raw) stream.destroy();
      resolve(line);
    };
    stream.on("data", (chunk: Buffer) => {
      const nl = chunk.indexOf(0x0a);
      if (nl < 0) parts.push(chunk);
      else {
        parts.push(chunk.subarray(0, nl + 1));
        finish(Buffer.concat(parts).toString("utf8"));
      }
    });
    stream.on("end", () => finish(Buffer.concat(parts).toString("utf8")));
    stream.on("error", () => finish(null));
    raw.on("error", () => finish(null));
  });
}

/// codex_meta: a Codex transcript's session id and the directory it ran in, from its first line.
export async function codexMeta(path: string): Promise<[string, string] | null> {
  const line = await firstLine(path);
  if (line === null) return null;
  let r: unknown;
  try {
    r = JSON.parse(line);
  } catch {
    return null;
  }
  const p = get(r, "payload");
  const [id, cwd] = [str(get(p, "id")), str(get(p, "cwd"))];
  return id !== null && cwd !== null ? [id, cwd] : null;
}

/// former.rs `claude_project`: Claude Code's directory name for where a session runs.
export const claudeProject = (path: string): string => Array.from(path, (c) => (/^[A-Za-z0-9]$/.test(c) ? c : "-")).join("");

/// Lets the event loop through (timers, I/O, requests) before going on.
const breathe = () => new Promise<void>((resolve) => setImmediate(resolve));

class Stopped extends Error {}

/// Old single-frame archives have no seek table. Count their uncompressed bytes as a stream when a recent session
/// needs one, so the following byte boundary is saved before any part is recorded.
async function unpackedLength(path: string, keep: () => boolean): Promise<number | null> {
  const raw = createReadStream(path, { highWaterMark: CHUNK });
  const stream = raw.pipe(createZstdDecompress({ chunkSize: CHUNK }));
  raw.on("error", (error) => stream.destroy(error));
  let size = 0;
  try {
    for await (const bytes of stream as AsyncIterable<Buffer>) {
      if (!keep()) throw new Stopped();
      size += bytes.length;
    }
    return size;
  } catch (error) {
    if (error instanceof Stopped) throw error;
    return null;
  } finally { raw.destroy(); stream.destroy(); }
}

/// Bytes immediately before a saved offset, from the raw transcript or the segment containing it.
async function anchorAt(path: string, offset: number, archived: boolean, keep: () => boolean): Promise<string | null> {
  const length = Math.min(ANCHOR, offset);
  if (length === 0) return "";
  const start = offset - length;
  if (!archived) {
    let file: FileHandle | undefined;
    try {
      file = await open(path, "r");
      const out = Buffer.alloc(length);
      const { bytesRead } = await file.read(out, 0, length, start);
      return bytesRead === length ? out.toString("hex") : null;
    } catch { return null; } finally { await file?.close(); }
  }
  let source: AsyncIterable<Buffer> | null;
  try { source = await segmentsFrom(packed(path), start); } catch { return null; }
  let raw: ReturnType<typeof createReadStream> | null = null;
  let stream: ReturnType<typeof createZstdDecompress> | null = null;
  let skip = 0;
  if (source === null) {
    raw = createReadStream(packed(path), { highWaterMark: CHUNK });
    stream = raw.pipe(createZstdDecompress({ chunkSize: CHUNK }));
    raw.on("error", (error) => stream!.destroy(error));
    source = stream as AsyncIterable<Buffer>;
    skip = start;
  }
  const pieces: Buffer[] = [];
  let got = 0;
  try {
    for await (const piece of source) {
      if (!keep()) throw new Stopped();
      if (skip >= piece.length) { skip -= piece.length; continue; }
      const bytes = piece.subarray(skip, skip + length - got);
      skip = 0;
      pieces.push(bytes);
      got += bytes.length;
      if (got === length) break;
    }
    return got === length ? Buffer.concat(pieces, length).toString("hex") : null;
  } catch (error) {
    if (error instanceof Stopped) throw error;
    return null;
  } finally { raw?.destroy(); stream?.destroy(); }
}

type CountedFile = UsageFile & { cutoff: number | null; anchor: string | null; path: string };

// ── the counter ──

export class UsageCounter {
  readonly #store: Store;
  readonly #config: () => UsageConfig;
  readonly #settleMs: number;
  readonly #safetyMs: number;
  /// When the last read started; 0 before the first.
  #last = 0;
  /// The first sweep is under way.
  #first = false;
  /// The read under way (reads queue behind it).
  #reading: Promise<unknown> = Promise.resolve();
  /// Sessions that changed since the loop last looked, and when each one's latest turn had ended when it last did.
  #changed = new Set<string>();
  #ended = new Map<string, number>();
  #startedAt = 0;
  #wake = Effect.runSync(Queue.dropping<void>(1));
  /// Sessions at work whose transcripts grew, to be read alone though no turn ended (`soon`).
  #asked = new Set<string>();
  #fiber: Fiber.Fiber<void> | null = null;
  #unsubscribe: (() => void) | null = null;
  #abort = new AbortController();
  #clock: Clock.Clock;
  /// The sessions the read under way recorded new calls of, and when the earliest of the calls it recorded was made.
  #counted = new Set<string>();
  #from = Infinity;
  /// Positions of transcripts this counter has needed, read from the store by path and kept as it writes them.
  #files: Map<string, CountedFile> | null = null;
  /// Codex's path for a runtime session, remembered by session rather than searched through all known files.
  #codexPaths = new Map<string, Map<string, string>>();
  /// What the read under way found and has not written yet: written together, in one transaction, once WRITE_BATCH calls
  /// gathered and as the read ends (`#flush`). Each part's transcript position is written with its calls, so a crash
  /// before then loses nothing: the next read reads that part again from the position the store has.
  #pending: { write: UsageWrite; session: string; position: CountedFile; changed: { from: number } }[] = [];
  #pendingCalls = 0;

  constructor(options: UsageCounterOptions) {
    this.#store = options.store;
    this.#config = options.config;
    this.#settleMs = options.settleMs ?? SETTLE_MS;
    this.#safetyMs = options.safetyMs ?? SAFETY_MS;
    this.#clock = options.clock ?? liveClock;
    this.#turns = options.turns ?? null;
  }
  readonly #turns: ((session: string, from: number, until: number) => Promise<UsageTurn[]>) | null;

  /// Reads sessions that ran since the previous sweep, then those whose turn ended (shortly after), and all that ran
  /// every SAFETY_MS. Stopped by `stop`.
  start(): void {
    if (this.#fiber !== null) return;
    this.#startedAt = this.#clock.currentTimeMillisUnsafe();
    this.#unsubscribe = this.#store.subscribe((change) => {
      if (change.type !== "session") return;
      this.#changed.add(change.key);
      Queue.offerUnsafe(this.#wake, undefined);
    });
    const me = this;
    const readNow = Effect.promise(() => me.#readLogged());
    // Whether a turn ended since the loop last looked, of the sessions that changed.
    const turnEnded = Effect.sync(() => {
      let ended = false;
      for (const key of me.#changed) {
        const at = me.#store.lastTurn(key)?.endedAt ?? null;
        if (at !== null && at > (me.#ended.get(key) ?? me.#startedAt)) {
          me.#ended.set(key, at);
          ended = true;
        }
      }
      me.#changed.clear();
      return ended;
    });
    // The sessions asked of alone.
    const readAsked = Effect.promise(() => {
      const only = new Set(me.#asked);
      me.#asked.clear();
      return me.#readLogged(only);
    });
    const loop = Effect.gen(function* () {
      yield* readNow;
      let due = (yield* Clock.currentTimeMillis) + me.#safetyMs;
      while (true) {
        const woken = yield* Effect.raceFirst(
          Queue.take(me.#wake).pipe(Effect.as(true)),
          Clock.currentTimeMillis.pipe(Effect.flatMap((now) => Effect.sleep(Math.max(1, due - now))), Effect.as(false)),
        );
        if (woken) {
          yield* Effect.sleep(me.#settleMs);
          yield* Queue.clear(me.#wake);
          if (!(yield* turnEnded) && (yield* Clock.currentTimeMillis) < due) {
            if (me.#asked.size > 0) yield* readAsked;
            continue;
          }
        }
        // Those at work are among those read.
        me.#asked.clear();
        yield* readNow;
        due = (yield* Clock.currentTimeMillis) + me.#safetyMs;
      }
    });
    this.#fiber = Effect.runFork(loop.pipe(Effect.provideService(Clock.Clock, this.#clock)));
  }

  /// Reads `key`'s transcripts shortly, though no turn ended: a session at work wrote more (live.ts).
  soon(key: string): void {
    this.#asked.add(key);
    Queue.offerUnsafe(this.#wake, undefined);
  }

  /// Stops reading: the read under way stops at its next batch (what it recorded stays).
  async stop(): Promise<void> {
    this.#unsubscribe?.();
    this.#unsubscribe = null;
    this.#abort.abort();
    if (this.#fiber !== null) await Effect.runPromise(Fiber.interrupt(this.#fiber));
    this.#fiber = null;
    await this.#reading.catch(() => {});
  }

  /// reading_all: whether everything is still being read for the first time.
  readingAll(): boolean {
    return this.#first || this.#last === 0;
  }

  async #readLogged(only?: ReadonlySet<string>): Promise<void> {
    try {
      await this.read(only);
    } catch (e) {
      if (!(e instanceof Stopped)) log.warn("usage", "usage not read", { error: (e as Error).message });
    }
  }

  /// One read: the transcripts of sessions that ran since the last sweep; `only`: of those sessions alone (it says
  /// nothing of when the last sweep was). How many calls were new. Reads queue behind one another.
  read(only?: ReadonlySet<string>): Promise<number> {
    const next = this.#reading.catch(() => {}).then(() => this.#read(only ?? null));
    this.#reading = next;
    return next;
  }

  async #read(only: ReadonlySet<string> | null): Promise<number> {
    const started = this.#clock.currentTimeMillisUnsafe();
    const last = this.#last;
    if (only === null) this.#first = last === 0;
    const store = this.#store;
    const cursor = store.usageCounter();
    const wanted = only !== null ? new Set(only) : new Set(store.usageActiveSessions(Math.max(cursor.since, (last || cursor.through) - MARGIN_MS)));
    const sessions: SessionRow[] = store.sessionsOf([...wanted]);
    const known = (this.#files ??= new Map<string, CountedFile>());
    const config = this.#config();
    const homes = config.profiles.map((p) => p.home);
    let added = 0;
    this.#counted.clear();
    this.#from = Infinity;
    // What a read before left unwritten (it failed or was stopped) is read again from the store's positions.
    this.#pending = [];
    this.#pendingCalls = 0;
    // Claude Code: each session's project directory (named after where it runs), in the shared transcripts and in any
    // profile's own.
    const distinct = async (roots: string[]) => {
      const seen = new Set<string>();
      const out: string[] = [];
      for (const r of roots) {
        if (!(await isDir(r))) continue;
        const real = await canonical(r);
        if (seen.has(real)) continue;
        seen.add(real);
        out.push(r);
      }
      return out;
    };
    // Where each runtime's transcripts are: the shared place, then each profile's home's.
    const ways = (runtime: Runtime) => [sharedTranscripts(config.dataDir, runtime), ...config.profiles.map((p) => join(p.home, transcriptDir(runtime)))];
    // How far a transcript was read, however it was reached then: one read through a home's own directory before is
    // reached through the shared place once that directory is a link there (sessions/agent-home.ts `linkTranscripts`).
    const readBefore = (path: string, runtime: Runtime): CountedFile | undefined => {
      const position = (name: string) => {
        const cached = known.get(name);
        if (cached !== undefined) return cached;
        const file = store.usageFile(name);
        const counter = store.usageCounterFile(name);
        if (file === undefined && counter === null) return undefined;
        const saved = { ...(file ?? { session: null, offset: 0, model: null }), cutoff: counter?.cutoff ?? null, anchor: counter?.anchor ?? null, path: name };
        known.set(name, saved);
        return saved;
      };
      const had = position(path);
      if (had !== undefined) return had;
      const roots = ways(runtime);
      const root = roots.find((r) => path.startsWith(r + sep));
      if (root === undefined) return undefined;
      for (const r of roots) {
        const was = position(r + path.slice(root.length));
        if (was !== undefined) return was;
      }
      return undefined;
    };
    const claudeRoots = await distinct(ways("claude"));
    const seenFiles = new Set<string>();
    // A chat may have left a runtime while its final turn was still writing. Count each earlier segment with the
    // runtime that wrote it, even when the session now runs on another one.
    for (const s of sessions) {
      if (wanted !== null && !wanted.has(s.key)) continue;
      for (const source of store.runtimeSessionSources(s.key, s)) {
        const runtime = runtimeKind(source.runtime);
        if (!runtime || runtime === s.runtime) continue;
        const transcript = transcriptPaths(runtime, config.dataDir, homes, [source.id]).paths[0];
        if (!transcript) continue;
        const files: [string, boolean][] = runtime === "claude" ? await claudeFiles(dirname(transcript), source.id) : [[runtime === "grok" ? join(dirname(transcript), "stillfail-usage.jsonl") : transcript, false]];
        for (const [path, subagent] of files) {
          if (runtime === "grok" && !existsSync(path)) continue;
          const real = await canonical(path);
          if (seenFiles.has(real)) continue;
          seenFiles.add(real);
          added += await this.#readFile(path, runtime, subagent, s, readBefore(path, runtime), cursor.since);
        }
      }
    }
    for (const s of sessions) {
      if (s.runtime !== "claude") continue;
      const project = claudeProject(s.cwd ?? s.workspace);
      const only = s.cwd !== null ? s.runtimeSessionId : null;
      if (s.cwd !== null && only === null) continue;
      for (const root of claudeRoots) {
        for (const [path, subagent] of await claudeFiles(join(root, project), only)) {
          const real = await canonical(path);
          if (seenFiles.has(real)) continue;
          seenFiles.add(real);
          added += await this.#readFile(path, "claude", subagent, s, readBefore(path, "claude"), cursor.since);
        }
      }
    }
    // Codex: its transcripts are kept by date, so each new one is matched to a session by its id, or by where it ran.
    // Read of a few sessions alone (every few seconds while they work), not every one is walked: those of their
    // runtime sessions, as read before or found by their ids.
    const codex = sessions.filter((s) => s.runtime === "codex");
    const found = new Map<string, SessionRow>();
    for (const s of codex) for (const { id } of store.runtimeSessionSources(s.key, s).filter((source) => source.runtime === "codex")) {
      const paths = this.#codexPaths.get(s.key) ?? new Map<string, string>();
      this.#codexPaths.set(s.key, paths);
      let had = paths.get(id);
      if (had !== undefined && !(await isFile(had)) && !(await isFile(packed(had)))) { paths.delete(id); had = undefined; }
      // A running thread can report its path before it creates the file; earlier threads can still search history.
      const path = had ?? transcriptPaths("codex", config.dataDir, homes, [id], [], { anywhere: !(s.running && s.runtimeSessionId === id) }).paths[0];
      if (path !== undefined) { paths.set(id, path); found.set(path, s); }
    }
    for (const [path, s] of found) {
      const file = readBefore(path, "codex");
      if (file !== undefined && file.session !== null && file.session !== s.key) continue;
      added += await this.#readFile(path, "codex", false, s, file, cursor.since);
    }
    // DeepSeek Harness: each runtime session's own file, found as its history finds it (dsh.ts); Grok Build: what the
    // station kept of its turns beside each one's transcript (grok.ts); Cursor and Devin: their transcripts, the
    // station's own (cursor.ts, devin.ts).
    for (const s of sessions) {
      if (s.runtime !== "dsh" && s.runtime !== "grok" && s.runtime !== "cursor" && s.runtime !== "devin" && s.runtime !== "hermes" && s.runtime !== "agy") continue;
      const runtime = s.runtime;
      for (const { id } of store.runtimeSessionSources(s.key, s).filter((source) => source.runtime === runtime)) {
        const transcript = transcriptPaths(runtime, config.dataDir, homes, [id]).paths[0];
        const path = transcript !== undefined && runtime === "grok" ? join(dirname(transcript), "stillfail-usage.jsonl") : transcript;
        if (path === undefined || (runtime === "grok" && !existsSync(path))) continue;
        const real = await canonical(path);
        if (seenFiles.has(real)) continue;
        seenFiles.add(real);
        added += await this.#readFile(path, runtime, false, s, readBefore(path, runtime), cursor.since);
      }
    }
    added += this.#flush();
    if (only === null) {
      if (wanted.size > 0) store.advanceUsageCounter(started);
      this.#last = started;
      this.#first = false;
    }
    if (this.#counted.size > 0) {
      if (last === 0 && only === null) log.info("usage", "usage read from recent transcripts", { calls: added, ms: this.#clock.currentTimeMillisUnsafe() - started });
      store.usageChanged([...this.#counted], Number.isFinite(this.#from) ? this.#from : undefined);
    }
    return added;
  }

  /// Writes what the read gathered (`#pending`), in one transaction; how many calls were new. Not written (a failure):
  /// the positions kept here are let go, so that the next read goes on from the store's.
  #flush(): number {
    const pending = this.#pending;
    this.#pending = [];
    this.#pendingCalls = 0;
    let recorded: number[];
    try {
      recorded = this.#store.recordUsageAll(pending.map((p) => p.write));
    } catch (error) {
      this.#files = null;
      throw error;
    }
    let added = 0;
    pending.forEach((p, i) => {
      this.#files?.set(p.write.path, p.position);
      if (Number.isFinite(p.changed.from)) {
        this.#counted.add(p.session);
        this.#from = Math.min(this.#from, p.changed.from);
      }
      added += recorded[i]!;
    });
    return added;
  }

  /// Reads one transcript of `session` on from where it was left, and records its calls, a part at a time.
  async #readFile(path: string, runtime: Runtime, subagent: boolean, session: SessionRow, was: CountedFile | undefined, since: number): Promise<number> {
    // A transcript may have been put away after its turn ended but before its last new calls were read. A seekable
    // archive tells its original size without decompression; an older archive is measured only for a wanted session.
    const archived = await putAway(path);
    let size: number | null;
    if (archived) {
      size = await writtenLength(packed(path)).catch(() => null)
        ?? await unpackedLength(packed(path), () => !this.#abort.signal.aborted);
      if (size === null) return 0;
    } else {
      try { size = (await stat(path)).size; } catch { return 0; }
    }
    let anchor = "";
    const shortened = was !== undefined && size < was.offset;
    if (!shortened && was !== undefined) {
      const found = await anchorAt(path, was.offset, archived, () => !this.#abort.signal.aborted);
      if (found === null) return 0;
      anchor = found;
    }
    const replaced = was !== undefined && (shortened || (was.anchor !== null && anchor !== was.anchor));
    const before = replaced ? { session: was.session, offset: 0, model: null } : (was ?? { session: null, offset: 0, model: null });
    if (replaced) anchor = "";
    let cutoff = was?.cutoff ?? null;
    if (replaced || cutoff === null || was?.anchor === null || was?.path !== path) {
      cutoff = this.#store.beginUsageCounterFile(path, before, { cutoff: replaced ? size : (cutoff ?? size), anchor }, replaced).cutoff;
    }
    this.#files?.set(path, { ...before, cutoff, anchor, path });
    if (archived && !replaced && size === before.offset) return 0;
    const state: CallState = { model: before.model, codexId: null };
    // A session created after the counter began can have its first call timestamped just before that boundary when
    // the runtime's clock is behind. Use the same clock-skew allowance already used to attribute calls to a session.
    const firstNewAt = session.createdAt >= since ? Math.min(since, session.createdAt - SKEW_MS) : since;
    let added = 0;
    let first = true;
    for await (const part of readFrom(path, before.offset)) {
      if (this.#abort.signal.aborted) throw new Stopped();
      if (first) {
        // A Codex transcript's id is in its first line: read again for a file read on from the middle.
        if (runtime === "codex") state.codexId = (await codexMeta(path))?.[0] ?? null;
        first = false;
      }
      for (const section of sectionsOf(part, cutoff)) {
        const nextAnchor = (section.bytes.length >= ANCHOR ? section.bytes.subarray(-ANCHOR)
          : Buffer.concat([Buffer.from(anchor, "hex"), section.bytes]).subarray(-ANCHOR)).toString("hex");
        // What ran before the station had the session (a terminal's, continued here) is not the station's.
        const modelBefore = state.model;
        const fromKnownSuffix = was !== undefined && !replaced && section.from >= before.offset;
        const calls = callsOf(runtime, section.text, subagent, state).filter((c) => c.at >= session.createdAt - SKEW_MS && (section.followed || c.at >= firstNewAt || fromKnownSuffix));
        // The turns they were made in, those alone (store/usage.ts usageTurns).
        const from = calls.reduce((m, c) => Math.min(m, c.at), Infinity);
        const until = calls.reduce((m, c) => Math.max(m, c.at), -Infinity);
        const of = calls.length === 0 ? [] : this.#turns !== null ? await this.#turns(session.key, from, until) : this.#store.usageTurns(session.key, from, until);
        const withFor: [UsageCall, UsageFor][] = calls.map((c) => {
          // The turn it was made in: the last to start before it (the first, for one before them all).
          let lo = 0;
          let hi = of.length;
          while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (of[mid]!.startedAt <= c.at) lo = mid + 1;
            else hi = mid;
          }
          return [c, of[Math.max(lo - 1, 0)]!.of];
        });
        // A dense part can contain thousands of calls. Save its starting position until all its calls are recorded: if
        // stopped between transactions, replaying the part is safe (the store keeps each call by id). `section.from` also
        // handles a transcript that was shortened and is being read again from zero.
        for (let i = 0; i < Math.max(1, withFor.length); i += WRITE_BATCH) {
          if (this.#abort.signal.aborted) throw new Stopped();
          const complete = i + WRITE_BATCH >= withFor.length;
          const file = { session: session.key, offset: complete ? section.offset : section.from, model: complete ? state.model : modelBefore };
          const batch = withFor.slice(i, i + WRITE_BATCH);
          const changed = { from: Infinity };
          const savedAnchor = complete ? nextAnchor : anchor;
          this.#pending.push({
            write: { path, file, runtime, calls: batch, options: { changed, counter: { cutoff, anchor: savedAnchor }, ...(section.followed ? {} : { minNewAt: firstNewAt }) } },
            session: session.key, position: { ...file, cutoff, anchor: savedAnchor, path }, changed,
          });
          this.#pendingCalls += batch.length;
          if (this.#pendingCalls >= WRITE_BATCH) {
            added += this.#flush();
            await breathe();
          }
        }
        anchor = nextAnchor;
      }
    }
    return added;
  }
}
