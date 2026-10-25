// Where each entry of a transcript is (read/tail.ts `Mark`): what the pages of a history ask for (GET
// /sessions/:key/timeline), and where a session's live view goes on from (sessions/live.ts), read from a place near it,
// not from the transcript's start. A transcript is read once: as it is read, where its reading stands and a mark every
// MARK_EVERY entries (or MARK_BYTES) are kept, and kept on disk (`<data>/transcript-marks/`), so a reader that starts
// again (one goes after a minute idle, all of them at every start of the station) reads on from there, and a page of a
// long one (hundreds of MB) is the lines from the mark before it. How many entries a transcript has is what it was
// counted to have, the same across the station's starts.
//
// Kept as they were read by `READING` (read/transcript.ts): what a line gives changes with it, so marks of another are
// read anew.
import { createHash } from "node:crypto";
import { closeSync, mkdirSync, openSync, readFileSync, readSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { threadId } from "node:worker_threads";
import { zstdDecompressSync } from "node:zlib";
import type { RuntimeKind } from "../agents/runtime.ts";
import { type Mark, type TailState, TranscriptTail, recordOf } from "./tail.ts";
import { READING, type ReadState, type TimelineEntry, brief, storage, timelineOf, utf8 } from "./transcript.ts";

/// The transcripts whose reading is kept in memory, the most recently read last (a reader's heap is small: one's reading
/// keeps the ids of its responses, a MB for a long one).
const KEPT = 16;

/// What of the ids a reading counted usage by is kept on disk: those of the last responses, as a response's lines are
/// written one after another (read/tail.ts `seen`, `totals`).
const KEPT_IDS = 64;

/// A transcript's reading: where it stands (the entries before it counted, none kept) and its marks.
export type Marked = { reading: number; state: TailState; marks: Mark[] };

const kept = new Map<string, Marked>();

/// The transcript put away whose history is being read, decompressed (one is hundreds of MB): its pages are read one
/// after another. Let go once another history is read (`chainOf`), and with the reader.
let unpacked: { path: string; stamp: string | null; bytes: Buffer } | null = null;

/// Where the readings of transcripts are kept on disk.
export const marksDir = (dataDir: string) => join(dataDir, "transcript-marks");

/// Where a transcript's reading is kept on disk, in `dir`.
const fileOf = (dir: string, path: string) => join(dir, `${createHash("sha1").update(path).digest("hex")}.json`);

/// Lets go of what is kept on disk of transcripts' readings (their session deleted).
export function forgetMarks(dir: string, paths: string[]): void {
  for (const path of paths) rmSync(fileOf(dir, path), { force: true });
}

/// A transcript's reading, read on to where it is written now: from what is kept, else from disk, else from its start.
/// `dir`: where readings are kept on disk (null: nowhere, as in tests).
function markedOf(runtime: RuntimeKind, path: string, dir: string | null): Marked {
  let had = kept.get(path) ?? null;
  kept.delete(path);
  if (had === null && dir !== null) {
    try {
      const v = JSON.parse(readFileSync(fileOf(dir, path), "utf8")) as Marked;
      if (v.reading === READING && v.state.path === path) had = v;
    } catch {}
  }
  const tail = had === null ? new TranscriptTail(runtime, path, null, false, true) : TranscriptTail.from(runtime, had.state, had.marks);
  tail.read();
  const now: Marked = { reading: READING, state: tail.snapshot(), marks: tail.marks };
  kept.set(path, now);
  if (kept.size > KEPT) kept.delete(kept.keys().next().value!);
  // Written down when there is a mark more (or it was written anew, or put away or back): what a reader starting again
  // reads on from there is less than MARK_EVERY entries and MARK_BYTES.
  const changed = had === null || tail.anew || now.marks.length !== had.marks.length || now.state.packedStamp !== had.state.packedStamp;
  if (dir !== null && changed) {
    try {
      mkdirSync(dir, { recursive: true });
      const file = fileOf(dir, path);
      const state = { ...now.state, seen: now.state.seen.slice(-KEPT_IDS), totals: now.state.totals.slice(-KEPT_IDS) };
      // Its own: two readers may write the same one.
      const tmp = `${file}.${process.pid}.${threadId}.tmp`;
      writeFileSync(tmp, JSON.stringify({ ...now, state }));
      renameSync(tmp, file);
    } catch {}
  }
  return now;
}

/// A session's transcripts read as one (those of the runtime sessions it ran in before first): each one's reading, read
/// on to where it is written now.
export function chainOf(runtime: RuntimeKind, paths: string[], dir: string | null): Marked[] {
  if (unpacked !== null && !paths.includes(unpacked.path)) unpacked = null;
  return paths.map((path) => markedOf(runtime, path, dir));
}

/// How many entries a chain of transcripts has.
export const lengthOf = (chain: Marked[]): number => chain.reduce((n, m) => n + m.state.count, 0);

/// Where the reading of a chain of transcripts stands now (read/tail.ts `snapshot`): what the live view of a session
/// goes on from on the main thread, which then reads none of what came before (sessions/live.ts).
export function stateOf(runtime: RuntimeKind, paths: string[], dir: string | null): TailState[] {
  return chainOf(runtime, paths, dir).map((m) => m.state);
}

/// Entries `from ..< to` of a chain of transcripts as `chainOf` read it (fewer where it has fewer, or where one could not
/// be read: none after it, which would be given as others), whole or in brief (transcript.ts `brief`): each read from
/// the mark before it.
export function entriesOf(runtime: RuntimeKind, chain: Marked[], from: number, to: number, inBrief: boolean): TimelineEntry[] {
  const entries: TimelineEntry[] = [];
  let first = 0;
  for (const m of chain) {
    const [a, b] = [Math.max(from, first), Math.min(to, first + m.state.count)];
    if (a < b) {
      const read = readBetween(runtime, m, a - first, b - first);
      for (const e of read) entries.push(inBrief ? brief(e) : e);
      if (read.length < b - a) break;
    }
    first += m.state.count;
  }
  return entries;
}

/// Entries `from ..< to` of one transcript, read from the last mark at or before `from` up to where its reading stands.
function readBetween(runtime: RuntimeKind, m: Marked, from: number, to: number): TimelineEntry[] {
  let mark: Mark = { offset: 0, index: 0, inner: [] };
  for (const each of m.marks) {
    if (each.index > from) break;
    mark = each;
  }
  const path = m.state.path;
  // Up to the end of its last whole line read: what comes after is the next read's.
  const end = m.state.offset - Buffer.from(m.state.partial, "base64").length;
  const state: ReadState = { inner: new Map(mark.inner) };
  const out: TimelineEntry[] = [];
  let index = mark.index;
  /// A line read: whether more are wanted.
  const line = (bytes: Buffer): boolean => {
    const record = recordOf(utf8.decode(bytes));
    if (record === undefined) return true;
    const entries: TimelineEntry[] = [];
    timelineOf(runtime, record, state, entries);
    for (const e of entries) {
      if (index >= from && index < to) out.push(e);
      index++;
    }
    return index < to;
  };
  /// Lines from `data` on, while more are wanted: what is left of the last, not yet whole (null: no more wanted).
  const lines = (data: Buffer): Buffer | null => {
    let at = 0;
    for (let nl = data.indexOf(0x0a); nl >= 0; nl = data.indexOf(0x0a, at)) {
      if (!line(data.subarray(at, nl))) return null;
      at = nl + 1;
    }
    return data.subarray(at);
  };
  const disk = storage(path);
  if (disk !== path) {
    // Put away: decompressed once while its history is read.
    try {
      const stamp = m.state.packedStamp;
      if (unpacked?.path !== path || unpacked.stamp !== stamp) unpacked = { path, stamp, bytes: zstdDecompressSync(readFileSync(disk)) };
      lines(unpacked.bytes.subarray(mark.offset, end));
    } catch {}
    return out;
  }
  let file: number;
  try {
    file = openSync(path, "r");
  } catch {
    return out;
  }
  try {
    const piece = Buffer.alloc(Math.min(PIECE_READ, Math.max(0, end - mark.offset)));
    let carry: Buffer = Buffer.alloc(0);
    for (let at = mark.offset; at < end; ) {
      const n = readSync(file, piece, 0, Math.min(piece.length, end - at), at);
      if (n === 0) break;
      at += n;
      const left = lines(carry.length > 0 ? Buffer.concat([carry, piece.subarray(0, n)]) : piece.subarray(0, n));
      if (left === null) break;
      carry = Buffer.from(left);
    }
  } catch {
    // What could be read is given.
  } finally {
    closeSync(file);
  }
  return out;
}

/// How much is read at a time from a mark on: a page is a few hundred entries, most often well within it.
const PIECE_READ = 1 << 20;

/// Lets go of the readings kept in memory (for tests: a reader started again), and of those on disk in `dir`.
export function forgetKept(dir: string | null = null): void {
  kept.clear();
  unpacked = null;
  if (dir !== null) rmSync(dir, { recursive: true, force: true });
}
