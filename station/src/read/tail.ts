// A session's transcripts read as they grow (transcript.rs TranscriptTail): by the live view as its sessions work
// (sessions/live.ts), and by the readers for the pages of a history (read/transcripts.ts). Each read goes on from where
// the last left off.
import { closeSync, existsSync, openSync, readFileSync, readSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { zstdDecompressSync } from "node:zlib";
import type { RuntimeKind } from "../agents/runtime.ts";
import { type ReadState, type TimelineEntry, timelineOf, utf8 } from "./transcript.ts";

type Json = any;

/// What a session's calls used, and since later: the prompt its last call sent (the context it carries on with) and the
/// model's window when the runtime tells it (Codex). Once the usage counter has counted the session, the calls are as
/// it counts them (its subagents' too) with what they would cost at API prices: `Counted`, the usage page's.
export type TranscriptUsage = {
  modelCalls: number; inputTokens: number; cachedTokens: number; outputTokens: number; model: string | null;
  contextTokens: number; contextWindow: number | null; cost?: number; unpricedCalls?: number;
};


export const noUsage = (): TranscriptUsage => ({
  modelCalls: 0, inputTokens: 0, cachedTokens: 0, outputTokens: 0, model: null, contextTokens: 0, contextWindow: null,
});

/// How much of a transcript is read at a time.
export const PIECE = 4 << 20;

/// A place in a transcript a read can start from (read/transcripts.ts): the end of a line (`offset`, in its bytes as
/// written), the index of the entry the next line's first is, and what reading keeps between lines there (`inner`).
export type Mark = { offset: number; index: number; inner: [string, number][] };

/// A mark is taken once at least this many entries came after the last, or this many bytes with at least one entry: a
/// read from the mark before an entry reads no more than that before it.
export const MARK_EVERY = 256;
export const MARK_BYTES = 8 << 20;

/// Where a transcript's reading stands (`snapshot`): where its next read goes on from and what it keeps between reads,
/// without the entries read. A tail made from it (`TranscriptTail.from`) reads on as the one it was taken of would: what
/// one thread read, another goes on from.
export type TailState = {
  path: string; offset: number; partial: string; count: number; usage: TranscriptUsage; seen: [string, number][]; totals: number[];
  inner: [string, number][]; packedStamp: string | null; grokRead: number;
};

/// Reads a transcript as it grows (transcript.rs TranscriptTail): each read gives the timeline entries of the lines
/// written since the last one, and the usage so far. Everything read is kept (as `shape` makes it), so watchers joining
/// later are served from memory. What is new is read a PIECE at a time: a long transcript read from its start is never
/// one buffer and one string.
export class TranscriptTail {
  readonly runtime: RuntimeKind;
  readonly path: string;
  private offset = 0;
  private packedStamp: string | null = null;
  private partial = Buffer.alloc(0);
  entries: TimelineEntry[] = [];
  usage: TranscriptUsage = noUsage();
  /// Each Claude response counted, with the output counted of it: one response is written as several lines, its output
  /// at its fullest on the last.
  private seen = new Map<string, number>();
  /// Codex's running totals counted: token counts are told again with rate limits.
  private totals = new Set<number>();
  private state: ReadState = { inner: new Map() };
  /// Grok Build's usage file as last read (its size): what the driver keeps of each turn beside the transcript.
  private grokRead = -1;
  /// What each entry is kept and given as (null: as read; read/transcripts.ts keeps them in brief).
  private readonly shape: ((e: TimelineEntry) => TimelineEntry) | null;
  /// Whether what is read is kept (`entries`), or only counted: one that follows a transcript to tell what is new
  /// (sessions/live.ts) needs none of what came before.
  readonly keeps: boolean;
  private count = 0;
  /// The marks taken as it reads (`marking`: it then gives no entries, only counts them), the first first: none until
  /// MARK_EVERY entries were read.
  marks: Mark[] = [];
  private readonly marking: boolean;
  /// Whether a read found it written anew and read it again from its start.
  anew = false;

  constructor(runtime: RuntimeKind, path: string, shape: ((e: TimelineEntry) => TimelineEntry) | null = null, keeps = true, marking = false) {
    this.runtime = runtime;
    this.path = path;
    this.shape = shape;
    this.keeps = keeps;
    this.marking = marking;
  }

  /// How many entries it has read.
  get length(): number {
    return this.keeps ? this.entries.length : this.count;
  }

  /// Where its reading stands, to go on from in another thread.
  snapshot(): TailState {
    return {
      path: this.path, offset: this.offset, partial: this.partial.toString("base64"), count: this.length, usage: { ...this.usage },
      seen: [...this.seen], totals: [...this.totals], inner: [...this.state.inner], packedStamp: this.packedStamp, grokRead: this.grokRead,
    };
  }

  /// A tail that goes on from where another's reading stood: it keeps none of what that one read, only counts it; with
  /// `marks` (those taken before), it takes marks on as it reads.
  static from(runtime: RuntimeKind, state: TailState, marks: Mark[] | null = null): TranscriptTail {
    const tail = new TranscriptTail(runtime, state.path, null, false, marks !== null);
    if (marks !== null) tail.marks = [...marks];
    tail.offset = state.offset;
    tail.partial = Buffer.from(state.partial, "base64");
    tail.count = state.count;
    tail.usage = { ...state.usage };
    tail.seen = new Map(state.seen);
    tail.totals = new Set(state.totals);
    tail.state = { inner: new Map(state.inner) };
    tail.packedStamp = state.packedStamp;
    tail.grokRead = state.grokRead;
    return tail;
  }

  /// New entries since the last read, with the index of the first (marking: none, only counted).
  read(): [number, TimelineEntry[]] {
    if (this.runtime === "grok") this.grokUsage();
    let start = this.length;
    const compressed = !existsSync(this.path);
    const disk = compressed ? `${this.path}.zst` : this.path;
    let meta;
    try {
      meta = statSync(disk);
    } catch {
      return [start, []];
    }
    const stamp = `${meta.size}:${meta.mtimeMs}`;
    if (compressed && this.packedStamp === stamp) return [start, []];
    let unpacked: Buffer | null = null;
    if (compressed) {
      try {
        unpacked = zstdDecompressSync(readFileSync(disk));
      } catch {
        return [start, []];
      }
    }
    const size = unpacked ? unpacked.length : meta.size;
    this.packedStamp = compressed ? stamp : null;
    if (size < this.offset) {
      // Rewritten: start over.
      this.anew = true;
      this.offset = 0;
      this.partial = Buffer.alloc(0);
      this.entries = [];
      this.count = 0;
      this.marks = [];
    }
    start = this.length;
    if (size === this.offset) return [start, []];
    const out: TimelineEntry[] = [];
    const had = this.length;
    let read = 0;
    // A piece of what came (it ends at `offset`): its whole lines read, a line still being written waiting for the next
    // read. Marking, each line is read on its own, so a mark falls at the end of one.
    const take = (piece: Buffer) => {
      const bytes = this.partial.length > 0 ? Buffer.concat([this.partial, piece]) : piece;
      const cut = bytes.lastIndexOf(0x0a) + 1;
      this.partial = Buffer.from(bytes.subarray(cut));
      if (cut === 0) return;
      const base = this.offset - bytes.length;
      const lines = this.marking ? linesOf(bytes, cut) : [cut];
      let from = 0;
      for (const end of lines) {
        const records: Json[] = [];
        for (const line of utf8.decode(bytes.subarray(from, end)).split("\n")) {
          const record = recordOf(line);
          if (record !== undefined) records.push(record);
        }
        from = end;
        this.addUsage(records);
        const entries: TimelineEntry[] = [];
        for (const r of records) timelineOf(this.runtime, r, this.state, entries);
        read += entries.length;
        if (!this.marking) {
          for (const e of entries) out.push(this.shape ? this.shape(e) : e);
          continue;
        }
        const index = had + read;
        const last = this.marks.at(-1) ?? { offset: 0, index: 0 };
        if (index - last.index >= MARK_EVERY || (index > last.index && base + end - last.offset >= MARK_BYTES)) this.marks.push({ offset: base + end, index, inner: [...this.state.inner] });
      }
    };
    if (unpacked) {
      for (let at = this.offset; at < size; at += PIECE) {
        const piece = unpacked.subarray(at, Math.min(size, at + PIECE));
        this.offset = at + piece.length;
        take(piece);
      }
      this.offset = size;
    } else {
      try {
        const file = openSync(this.path, "r");
        try {
          const piece = Buffer.alloc(Math.min(PIECE, size - this.offset));
          while (this.offset < size) {
            const n = readSync(file, piece, 0, Math.min(piece.length, size - this.offset), this.offset);
            if (n === 0) break;
            this.offset += n;
            take(piece.subarray(0, n));
          }
        } finally {
          closeSync(file);
        }
      } catch {
        // What could be read is kept; the rest is read next time.
      }
    }
    if (this.keeps) for (const e of out) this.entries.push(e);
    else this.count += read;
    return [start, out];
  }

  /// Grok Build's transcript says no counts: the usage is what the driver kept of each turn beside it (agents/grok.ts
  /// usageLine), read whole again when it grew; the context is the last turn's.
  private grokUsage() {
    const file = join(dirname(this.path), "stillfail-usage.jsonl");
    let text: string;
    try {
      text = readFileSync(file, "utf8");
    } catch {
      return;
    }
    if (text.length === this.grokRead) return;
    this.grokRead = text.length;
    const n = (v: Json) => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : 0);
    const usage = noUsage();
    for (const line of text.split("\n")) {
      let r: Json;
      try {
        r = JSON.parse(line);
      } catch {
        continue;
      }
      const u = r?.usage;
      if (r?.type !== "stillfail/usage" || !u) continue;
      usage.modelCalls += Math.max(1, n(u.calls));
      usage.inputTokens += n(u.input) + n(u.cacheRead) + n(u.cacheWrite);
      usage.cachedTokens += n(u.cacheRead);
      usage.outputTokens += n(u.output);
      if (typeof r.model === "string") usage.model = r.model;
      if (n(r.context) > 0) usage.contextTokens = n(r.context);
      if (n(r.window) > 0) usage.contextWindow = n(r.window);
    }
    this.usage = usage;
  }

  private addUsage(records: Json[]) {
    const n = (v: Json) => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : 0);
    const usage = this.usage;
    for (const r of records) {
      if (this.runtime === "claude") {
        const m = r?.type === "assistant" ? r.message : undefined;
        if (!m || m.usage === undefined || typeof m.id !== "string") continue;
        const u = m.usage;
        const output = n(u?.output_tokens);
        const known = this.seen.get(m.id);
        if (known !== undefined) {
          if (output > known) {
            usage.outputTokens += output - known;
            this.seen.set(m.id, output);
          }
          continue;
        }
        this.seen.set(m.id, output);
        const read = n(u?.cache_read_input_tokens);
        const written = n(u?.cache_creation_input_tokens);
        const input = n(u?.input_tokens);
        usage.modelCalls++;
        usage.inputTokens += input + read + written;
        usage.cachedTokens += read;
        usage.outputTokens += output;
        if (typeof m.model === "string" && m.model !== "<synthetic>") usage.model = m.model;
        // The main thread's prompt is the context; a subagent's is its own.
        if (r.isSidechain !== true) usage.contextTokens = input + read + written;
      } else if (this.runtime === "dsh") {
        // dsh's counts are apart: input is what was not cached, the cache's read and written beside it.
        if (r?.type === "request/context" && n(r.data?.contextWindow) > 0) usage.contextWindow = n(r.data.contextWindow);
        const u = r?.type === "assistant/message" ? r.data?.usage : undefined;
        if (u === undefined || u === null) continue;
        const read = n(u.cacheReadTokens);
        const input = n(u.inputTokens) + read + n(u.cacheWriteTokens);
        usage.modelCalls++;
        usage.inputTokens += input;
        usage.cachedTokens += read;
        usage.outputTokens += n(u.outputTokens);
        usage.contextTokens = input;
        const model = r.data?.message?.source?.model;
        if (typeof model === "string") usage.model = model;
      } else if (this.runtime === "cursor" || this.runtime === "devin") {
        // A Cursor turn's counts as the station's driver kept them (agents/cursor-bridge.mjs): the whole run's, not each
        // call's, so they say no context. Devin's driver keeps its turns' the same way (agents/devin.ts), with the context
        // the turn ended with and the model's window where Devin said them.
        const u = r?.type === "usage" ? r.usage : undefined;
        if (u === undefined || u === null) continue;
        const read = n(u.cacheReadTokens);
        // Devin's line says how many calls the turn made.
        usage.modelCalls += Math.max(1, n(r.calls));
        usage.inputTokens += n(u.inputTokens) + read + n(u.cacheWriteTokens);
        usage.cachedTokens += read;
        usage.outputTokens += n(u.outputTokens);
        if (typeof r.model === "string") usage.model = r.model;
        if (n(r.context) > 0) usage.contextTokens = n(r.context);
        if (n(r.window) > 0) usage.contextWindow = n(r.window);
      } else if (this.runtime === "grok") {
        // Grok Build's transcript says no counts (the station keeps them apart: agents/grok.ts), only the model.
        if (r?.type === "assistant" && typeof r.model_id === "string" && usage.model === null) usage.model = r.model_id;
      } else {
        const p = r?.payload ?? null;
        if (r?.type === "turn_context" && typeof p?.model === "string") usage.model = p.model;
        const info = r?.type === "event_msg" && p?.type === "token_count" ? p?.info : undefined;
        const last = info?.last_token_usage;
        if (last === undefined || last === null) continue;
        const total = info?.total_token_usage?.total_tokens;
        if (typeof total === "number") {
          if (this.totals.has(total)) continue;
          this.totals.add(total);
        }
        const input = n(last.input_tokens);
        const cached = Math.min(n(last.cached_input_tokens), input);
        const output = n(last.output_tokens);
        usage.modelCalls++;
        usage.inputTokens += input;
        usage.cachedTokens += cached;
        usage.outputTokens += output;
        usage.contextTokens = input;
        if (n(info?.model_context_window) > 0) usage.contextWindow = n(info.model_context_window);
      }
    }
  }
}

/// A session's transcripts read as one: those of the runtime sessions it ran in before (done, read whole) and then the
/// one it runs in now, their entries one after another, so its history goes on across a new runtime session.
export class ChainTail {
  readonly runtime: RuntimeKind;
  private tails: TranscriptTail[];
  private readonly shape: ((e: TimelineEntry) => TimelineEntry) | null;
  /// Whether what is read is kept (TranscriptTail.keeps).
  readonly keeps: boolean;

  constructor(runtime: RuntimeKind, paths: string[], shape: ((e: TimelineEntry) => TimelineEntry) | null = null, keeps = true) {
    this.runtime = runtime;
    this.shape = shape;
    this.keeps = keeps;
    this.tails = paths.map((path) => new TranscriptTail(runtime, path, shape, keeps));
  }

  /// A chain that goes on from where another's reading stood (`snapshot`), keeping none of what it read.
  static from(runtime: RuntimeKind, states: TailState[]): ChainTail {
    const chain = new ChainTail(runtime, [], null, false);
    chain.tails = states.map((state) => TranscriptTail.from(runtime, state));
    return chain;
  }

  /// Where each of its transcripts' reading stands.
  snapshot(): TailState[] {
    return this.tails.map((t) => t.snapshot());
  }

  /// The paths of its transcripts, the first first.
  get paths(): string[] {
    return this.tails.map((t) => t.path);
  }

  /// How many entries it has read.
  get length(): number {
    let n = 0;
    for (const t of this.tails) n += t.length;
    return n;
  }

  /// The transcript written to now.
  get path(): string {
    return this.tails.at(-1)!.path;
  }

  get entries(): TimelineEntry[] {
    return this.tails.length === 1 ? this.tails[0]!.entries : this.tails.flatMap((t) => t.entries);
  }

  get usage(): TranscriptUsage {
    const usage = noUsage();
    for (const t of this.tails) {
      usage.modelCalls += t.usage.modelCalls;
      usage.inputTokens += t.usage.inputTokens;
      usage.cachedTokens += t.usage.cachedTokens;
      usage.outputTokens += t.usage.outputTokens;
      usage.model = t.usage.model ?? usage.model;
      // The context is the transcript's written to last that has called the model.
      if (t.usage.modelCalls > 0) [usage.contextTokens, usage.contextWindow] = [t.usage.contextTokens, t.usage.contextWindow];
    }
    return usage;
  }

  /// Goes on with the transcripts given (those it has, then new ones): the new ones are read after what it has.
  extend(paths: string[]) {
    if (paths.length < this.tails.length || this.tails.some((t, i) => t.path !== paths[i])) {
      this.tails = paths.map((path) => new TranscriptTail(this.runtime, path, this.shape, this.keeps));
      return;
    }
    for (const path of paths.slice(this.tails.length)) this.tails.push(new TranscriptTail(this.runtime, path, this.shape, this.keeps));
  }

  /// New entries since the last read, with the index of the first (all from the first that changed when an earlier
  /// transcript gained some, or was written anew).
  read(): [number, TimelineEntry[]] {
    let offset = 0;
    let from: number | null = null;
    const told: TimelineEntry[] = [];
    for (let i = 0; i < this.tails.length; i++) {
      // One that keeps nothing, after one that changed: what it read is to be told again, numbered on from there, so it
      // is read again from its start (an earlier transcript that grew is rare: its runtime session is over).
      if (from !== null && !this.keeps && this.tails[i]!.length > 0) this.tails[i] = new TranscriptTail(this.runtime, this.tails[i]!.path, this.shape, false);
      const tail = this.tails[i]!;
      const had = tail.length;
      const [start, entries] = tail.read();
      if (from === null && (entries.length > 0 || start < had)) from = offset + start;
      if (from !== null) for (const e of entries) told.push(e);
      offset += tail.length;
    }
    if (from === null) return [offset, []];
    return [from, this.keeps ? this.entries.slice(from) : told];
  }
}

/// A transcript's line as its record (`undefined`: empty, or not JSON). A line's \r before its \n goes.
export function recordOf(line: string): Json | undefined {
  const text = line.endsWith("\r") ? line.slice(0, -1) : line;
  if (text === "") return undefined;
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

/// Where each line of `bytes` up to `cut` ends (just past its \n).
function linesOf(bytes: Buffer, cut: number): number[] {
  const out: number[] = [];
  for (let at = bytes.indexOf(0x0a); at >= 0 && at < cut; at = bytes.indexOf(0x0a, at + 1)) out.push(at + 1);
  return out;
}
