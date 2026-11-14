// A session's transcripts read as they grow (tail.ts `ChainTail`), each read done by a reader (the MoonBit program
// where it is there: read/pool.ts `tailRead`), not on the station's thread: the live view (sessions/live.ts) follows
// every session at work, and what its transcripts gain was parsed there before, line by line, as they were written.
// What it keeps is where each transcript's reading stands (`TailState`) and, where it keeps them (`keeps`), the entries.
import type { RuntimeKind } from "../agents/runtime.ts";
import type { TailState, TranscriptRef } from "./tail.ts";
import type { TimelineEntry } from "./transcript.ts";

/// A read of one transcript on from where its reading stood (none: from its start), as tail.ts `TranscriptTail.readSoon`
/// gives it, with where it stands after.
export type TailRead = (runtime: RuntimeKind, state: TailState | { path: string; runtime: RuntimeKind }) => Promise<{ start: number; entries: TimelineEntry[]; state: TailState }>;

type One = { runtime: RuntimeKind; path: string; state: TailState | null; entries: TimelineEntry[] };

const ref = (runtime: RuntimeKind, r: TranscriptRef) => (typeof r === "string" ? { path: r, runtime } : r);

/// How many bytes a base64 string holds.
const base64Bytes = (s: string) => (s.length === 0 ? 0 : Math.floor((s.length * 3) / 4) - (s.endsWith("==") ? 2 : s.endsWith("=") ? 1 : 0));

export class ReadTail {
  readonly runtime: RuntimeKind;
  readonly keeps: boolean;
  private tails: One[];
  private readonly reading: TailRead;

  constructor(runtime: RuntimeKind, paths: TranscriptRef[], reading: TailRead, keeps = true) {
    this.runtime = runtime;
    this.keeps = keeps;
    this.reading = reading;
    this.tails = paths.map((r) => ({ ...ref(runtime, r), state: null, entries: [] }));
  }

  /// One that goes on from where another's reading stood, keeping none of what it read.
  static from(runtime: RuntimeKind, states: TailState[], reading: TailRead): ReadTail {
    const chain = new ReadTail(runtime, [], reading, false);
    chain.tails = states.map((state) => ({ runtime: state.runtime ?? runtime, path: state.path, state, entries: [] }));
    return chain;
  }

  snapshot(): TailState[] {
    return this.tails.map((t) => t.state ?? { path: t.path, runtime: t.runtime, offset: 0, partial: "", count: 0, inner: [], packedStamp: null });
  }

  get paths(): string[] {
    return this.tails.map((t) => t.path);
  }

  private lengthOf(t: One): number {
    return this.keeps ? t.entries.length : (t.state?.count ?? 0);
  }

  get length(): number {
    let n = 0;
    for (const t of this.tails) n += this.lengthOf(t);
    return n;
  }

  get readBytes(): number {
    let n = 0;
    for (const t of this.tails) if (t.state) n += t.state.offset - base64Bytes(t.state.partial);
    return n;
  }

  get path(): string {
    return this.tails.at(-1)!.path;
  }

  get entries(): TimelineEntry[] {
    return this.tails.length === 1 ? this.tails[0]!.entries : this.tails.flatMap((t) => t.entries);
  }

  extend(paths: TranscriptRef[]): boolean {
    const refs = paths.map((r) => ref(this.runtime, r));
    if (refs.length < this.tails.length || this.tails.some((t, i) => t.path !== refs[i]!.path || t.runtime !== refs[i]!.runtime)) {
      this.tails = refs.map((r) => ({ ...r, state: null, entries: [] }));
      return true;
    }
    if (refs.length === this.tails.length) return false;
    for (const r of refs.slice(this.tails.length)) this.tails.push({ ...r, state: null, entries: [] });
    return true;
  }

  /// As tail.ts `ChainTail.readSoon`. Not to be asked again before it is done.
  async readSoon(): Promise<[number, TimelineEntry[]]> {
    let offset = 0;
    let from: number | null = null;
    const told: TimelineEntry[] = [];
    for (let i = 0; i < this.tails.length; i++) {
      const tail = this.tails[i]!;
      // (one that keeps nothing, after one that changed: read again from its start, numbered on from there)
      if (from !== null && !this.keeps && this.lengthOf(tail) > 0) {
        tail.state = null;
        tail.entries = [];
      }
      const had = this.lengthOf(tail);
      const read = await this.reading(tail.runtime, tail.state ?? { path: tail.path, runtime: tail.runtime });
      tail.state = read.state;
      if (this.keeps) {
        tail.entries.length = Math.min(tail.entries.length, read.start);
        for (const e of read.entries) tail.entries.push(e);
      }
      if (from === null && (read.entries.length > 0 || read.start < had)) from = offset + read.start;
      if (from !== null) for (const e of read.entries) told.push(e);
      offset += this.lengthOf(tail);
    }
    if (from === null) return [offset, []];
    return [from, this.keeps ? this.entries.slice(from) : told];
  }
}
