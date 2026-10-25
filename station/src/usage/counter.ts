// What the agents spent, counted (the Rust station's usage.rs `Usage`): every model call their runtimes write to a transcript
// (Claude Code's message usage, Codex's token counts) is recorded once in the store (store/usage.ts), with the turn it
// was in and whom that turn worked for. The transcripts are read as they grow, from where the last read stopped: all of
// them the first time (what was spent before the station counted), then those of the sessions that ran since.
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
import { parseIso, sharedTranscripts, transcriptDir, transcriptPaths } from "../read/transcript.ts";
import type { SessionRow, Store, UsageCall, UsageFile, UsageFor } from "../store/store.ts";
import type { RuntimeKind } from "../agents/runtime.ts";

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
/// How much of a transcript is read, parsed and recorded at a time before the event loop is let through.
const CHUNK = 1 << 20;

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
      : runtime === "cursor" || runtime === "devin" || runtime === "hermes" ? line.includes('"type":"usage"')
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
    } else if (runtime === "cursor" || runtime === "devin" || runtime === "hermes") {
      // What the station's driver kept of each Cursor turn (agents/cursor-bridge.mjs): the SDK's counts, input apart
      // from the cache's, the whole run's (no context); of each Devin turn the same (agents/devin.ts), with how many
      // calls it made, the context it ended with and the model's window where Devin said them.
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

/// A part of a transcript: its whole lines from where the last part ended, and where they end in the file.
export type Part = { text: string; offset: number };

/// Whole lines of `bytes` (what follows `from` in the file), a part at most CHUNK long each where lines allow.
function* partsOf(bytes: Buffer, from: number): Generator<Part> {
  let at = 0;
  while (at < bytes.length) {
    const window = Math.min(bytes.length, at + CHUNK);
    let cut = bytes.lastIndexOf(0x0a, window - 1);
    if (cut < at) cut = bytes.indexOf(0x0a, window);
    if (cut < 0) return;
    yield { text: bytes.toString("utf8", at, cut + 1), offset: from + cut + 1 };
    at = cut + 1;
  }
}

/// A file put away, past `offset`, as `readFrom` says it: decompressed as it is read, never whole (one is hundreds of MB,
/// and every one is read again as the station starts). Shorter than `offset`: read again from its start.
async function* packedFrom(path: string, offset: number): AsyncGenerator<Part> {
  const raw = createReadStream(packed(path), { highWaterMark: CHUNK });
  const stream = raw.pipe(createZstdDecompress({ chunkSize: CHUNK }));
  raw.on("error", (error) => stream.destroy(error));
  // What is past `offset` and not given yet, from `start`.
  let held: Buffer[] = [];
  let heldBytes = 0;
  let start = offset;
  let total = 0;
  const give = function* (): Generator<Part> {
    const bytes = Buffer.concat(held, heldBytes);
    const cut = bytes.lastIndexOf(0x0a);
    if (cut < 0) return;
    yield* partsOf(bytes.subarray(0, cut + 1), start);
    const rest = Buffer.from(bytes.subarray(cut + 1));
    start += cut + 1;
    held = rest.length === 0 ? [] : [rest];
    heldBytes = rest.length;
  };
  try {
    for await (const chunk of stream as AsyncIterable<Buffer>) {
      const from = Math.max(0, offset - total);
      total += chunk.length;
      if (from >= chunk.length) continue;
      held.push(from === 0 ? chunk : chunk.subarray(from));
      heldBytes += chunk.length - from;
      if (heldBytes >= CHUNK) yield* give();
    }
  } catch {
    return;
  } finally {
    raw.destroy();
    stream.destroy();
  }
  if (total < offset) {
    yield* packedFrom(path, 0);
    return;
  }
  yield* give();
}

/// read_from: what a file holds past `offset`, up to its last whole line, in parts with where each ends. A file now
/// shorter than `offset` was written anew: it is read from its start (calls already recorded stay once). A file put
/// away (only its `.zst` there) is read decompressed.
/// Whether a transcript is put away: only its `.zst` there.
const putAway = async (path: string): Promise<boolean> => !(await exists(path)) && (await exists(packed(path)));

export async function* readFrom(path: string, offset: number): AsyncGenerator<Part> {
  if (await putAway(path)) {
    yield* packedFrom(path, offset);
    return;
  }
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
    let carry = Buffer.alloc(0);
    let start = pos;
    while (pos < size) {
      const buf = Buffer.allocUnsafe(Math.min(CHUNK, size - pos));
      const { bytesRead } = await file.read(buf, 0, buf.length, pos);
      if (bytesRead === 0) break;
      pos += bytesRead;
      const bytes = carry.length === 0 ? buf.subarray(0, bytesRead) : Buffer.concat([carry, buf.subarray(0, bytesRead)]);
      const cut = bytes.lastIndexOf(0x0a);
      if (cut < 0) {
        carry = bytes;
        continue;
      }
      yield { text: bytes.toString("utf8", 0, cut + 1), offset: start + cut + 1 };
      carry = bytes.subarray(cut + 1);
      start += cut + 1;
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

async function rolloutsIn(dir: string, out: string[]): Promise<void> {
  let names: string[];
  try {
    names = await readdir(dir);
  } catch {
    return;
  }
  for (const name of names.sort()) {
    let path = join(dir, name);
    if (extension(path) === "zst") path = path.slice(0, -".zst".length);
    if (await isDir(path)) await rolloutsIn(path, out);
    else if (name.startsWith("rollout-") && extension(path) === "jsonl") out.push(path);
  }
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

// ── the counter ──

export class UsageCounter {
  readonly #store: Store;
  readonly #config: () => UsageConfig;
  readonly #settleMs: number;
  readonly #safetyMs: number;
  /// When the last read started; 0 before the first.
  #last = 0;
  /// The first read (everything) is under way.
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
  /// The sessions the read under way recorded new calls of.
  #counted = new Set<string>();
  /// What was read of each transcript (usage_files): the store's at the first read, and what this counter wrote since.
  #files: Map<string, UsageFile> | null = null;

  constructor(options: UsageCounterOptions) {
    this.#store = options.store;
    this.#config = options.config;
    this.#settleMs = options.settleMs ?? SETTLE_MS;
    this.#safetyMs = options.safetyMs ?? SAFETY_MS;
    this.#clock = options.clock ?? liveClock;
  }

  /// Reads every transcript now, then those of sessions whose turn ended (shortly after), and all that ran every
  /// SAFETY_MS. Stopped by `stop`.
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

  /// Stops reading: the read under way stops at its next part (what it recorded stays).
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

  /// One read: the transcripts of every session the first time, then of those that ran since the last; `only`: of those
  /// sessions alone (it says nothing of when the last read was). How many calls were new. Reads queue behind one another.
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
    const wanted: Set<string> | null = only !== null ? new Set(only) : last === 0 ? null : new Set(store.usageActiveSessions(last - MARGIN_MS));
    // Every session the first time; then those that ran since, by their rows (a read comes every few seconds while
    // agents work: not every session ever).
    const sessions: SessionRow[] = wanted === null ? store.listSessions() : [...wanted].flatMap((key) => store.getSession(key) ?? []);
    // What was read of each transcript: as the store has it the first time, then as this counter wrote it (it alone does).
    const known = (this.#files ??= store.usageFiles());
    const config = this.#config();
    const homes = config.profiles.map((p) => p.home);
    let added = 0;
    this.#counted.clear();
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
    const readBefore = (path: string, runtime: Runtime): UsageFile | undefined => {
      const had = known.get(path);
      if (had !== undefined) return had;
      const roots = ways(runtime);
      const root = roots.find((r) => path.startsWith(r + sep));
      if (root === undefined) return undefined;
      for (const r of roots) {
        const was = known.get(r + path.slice(root.length));
        if (was !== undefined) return was;
      }
      return undefined;
    };
    const claudeRoots = await distinct(ways("claude"));
    const codexRoots = await distinct(ways("codex"));
    const seenFiles = new Set<string>();
    for (const s of sessions) {
      if (wanted !== null && !wanted.has(s.key)) continue;
      if (s.runtime !== "claude") continue;
      const project = claudeProject(s.cwd ?? s.workspace);
      const only = s.cwd !== null ? s.runtimeSessionId : null;
      if (s.cwd !== null && only === null) continue;
      for (const root of claudeRoots) {
        for (const [path, subagent] of await claudeFiles(join(root, project), only)) {
          const real = await canonical(path);
          if (seenFiles.has(real)) continue;
          seenFiles.add(real);
          added += await this.#readFile(path, "claude", subagent, s, readBefore(path, "claude"));
        }
      }
    }
    // Codex: its transcripts are kept by date, so each new one is matched to a session by its id, or by where it ran.
    // Read of a few sessions alone (every few seconds while they work), not every one is walked: those of their
    // runtime sessions, as read before or found by their ids.
    const found: string[] = [];
    if (only === null) for (const root of codexRoots) await rolloutsIn(root, found);
    else {
      const ids = sessions.filter((s) => s.runtime === "codex").flatMap((s) => store.runtimeSessions(s.key));
      if (ids.length > 0) {
        const readOf = new Map<string, string>();
        for (const [path, file] of known) if (file.session !== null && wanted!.has(file.session)) readOf.set(basename(path), path);
        for (const id of ids) {
          const had = [...readOf].find(([name]) => name.endsWith(`${id}.jsonl`))?.[1];
          const path = had ?? transcriptPaths("codex", config.dataDir, homes, [id]).paths[0];
          if (path !== undefined) found.push(path);
        }
      }
    }
    const rollouts = [...new Set(found)];
    if (rollouts.length > 0) {
      // A new one is matched among the sessions read, then (it may be one that ran before the last read) among every
      // Codex session, asked only then: one matched to none is passed over for good.
      let codex = sessions.filter((s) => s.runtime === "codex");
      let every = wanted === null;
      const match = (meta: [string | null, string | null]) => codex.find((s) => s.runtimeSessionId === meta[0] || (s.cwd === null && s.workspace === meta[1]))?.key ?? null;
      for (const path of rollouts) {
        const file = readBefore(path, "codex");
        let session: string | null;
        if (file !== undefined) session = file.session;
        else {
          const meta = await codexMeta(path);
          session = meta === null ? null : match(meta);
          if (session === null && meta !== null && !every) {
            codex = store.listSessions().filter((s) => s.runtime === "codex");
            every = true;
            session = match(meta);
          }
        }
        if (session === null) {
          if (file === undefined) {
            // None of the station's (a terminal's own): passed over from now on.
            let size = 0;
            try {
              size = (await stat(path)).size;
            } catch {}
            store.recordUsage(path, { session: null, offset: size, model: null }, "codex", []);
            known.set(path, { session: null, offset: size, model: null });
          }
          continue;
        }
        if (wanted !== null && !wanted.has(session) && file !== undefined) continue;
        const s = codex.find((c) => c.key === session);
        if (s === undefined) continue;
        added += await this.#readFile(path, "codex", false, s, file);
      }
    }
    // DeepSeek Harness: each runtime session's own file, found as its history finds it (dsh.ts); Grok Build: what the
    // station kept of its turns beside each one's transcript (grok.ts); Cursor and Devin: their transcripts, the
    // station's own (cursor.ts, devin.ts).
    for (const s of sessions) {
      if ((s.runtime !== "dsh" && s.runtime !== "grok" && s.runtime !== "cursor" && s.runtime !== "devin" && s.runtime !== "hermes") || (wanted !== null && !wanted.has(s.key))) continue;
      const runtime = s.runtime;
      for (const id of store.runtimeSessions(s.key)) {
        const transcript = transcriptPaths(runtime, config.dataDir, homes, [id]).paths[0];
        const path = transcript !== undefined && runtime === "grok" ? join(dirname(transcript), "stillfail-usage.jsonl") : transcript;
        if (path === undefined || (runtime === "grok" && !existsSync(path))) continue;
        const real = await canonical(path);
        if (seenFiles.has(real)) continue;
        seenFiles.add(real);
        added += await this.#readFile(path, runtime, false, s, readBefore(path, runtime));
      }
    }
    if (only === null) {
      this.#last = started;
      this.#first = false;
    }
    if (added > 0) {
      if (last === 0 && only === null) log.info("usage", "usage read from every transcript", { calls: added, ms: this.#clock.currentTimeMillisUnsafe() - started });
      store.usageChanged([...this.#counted]);
    }
    return added;
  }

  /// Reads one transcript of `session` on from where it was left, and records its calls, a part at a time.
  async #readFile(path: string, runtime: Runtime, subagent: boolean, session: SessionRow, was: UsageFile | undefined): Promise<number> {
    // A transcript put away (only its `.zst` there) was read before it was: its session is archived and idle, and it is
    // restored before its runtime writes in it again. Read again as the station starts, every one was decompressed
    // whole at each start (10.8 s on ccvm, 2026-10-24, the station slow to answer meanwhile). One never read is read once.
    if (this.#first && was !== undefined && (await putAway(path))) return 0;
    const before = was ?? { session: null, offset: 0, model: null };
    const state: CallState = { model: before.model, codexId: null };
    let added = 0;
    let first = true;
    for await (const part of readFrom(path, before.offset)) {
      if (this.#abort.signal.aborted) throw new Stopped();
      if (first) {
        // A Codex transcript's id is in its first line: read again for a file read on from the middle.
        if (runtime === "codex") state.codexId = (await codexMeta(path))?.[0] ?? null;
        first = false;
      }
      // What ran before the station had the session (a terminal's, continued here) is not the station's.
      const calls = callsOf(runtime, part.text, subagent, state).filter((c) => c.at >= session.createdAt - SKEW_MS);
      // The turns they were made in, those alone (store/usage.ts usageTurns).
      const of = calls.length === 0 ? [] : this.#store.usageTurns(session.key, calls.reduce((m, c) => Math.min(m, c.at), Infinity), calls.reduce((m, c) => Math.max(m, c.at), -Infinity));
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
      const recorded = this.#store.recordUsage(path, { session: session.key, offset: part.offset, model: state.model }, runtime, withFor);
      this.#files?.set(path, { session: session.key, offset: part.offset, model: state.model });
      if (recorded > 0) this.#counted.add(session.key);
      added += recorded;
      await breathe();
    }
    return added;
  }
}
