// A transcript put away (sessions/archive.ts `packFile`) is in segments as zork keeps a session's events (HOOLC/zork
// docs/design/agent-runtime.md, SEGMENT-01): each about SEGMENT bytes of it, ending at the end of a line, compressed
// once; the last, what is read most, stored as it is. Here they are zstd frames of the one file the runtime's
// transcript is put away as (every reader finds it as `<file>.zst`), then a table of the frames' sizes (zstd's seekable
// format: a skippable frame, which zstd readers pass over). A page of a history, read from the mark before it,
// decompresses the segment or two it is in, and the latest pages none: not the whole transcript (one is 150 MB) each
// time. Read whole, it is read a segment at a time too: Node 24.15's zstd (Studio's) gives the first of several frames
// and stops. One put away before the table (2026-11) has none and is read whole, until it is put away again in segments
// (sessions/cold.ts `segmentHistories`).
import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { type FileHandle, open } from "node:fs/promises";
import { promisify } from "node:util";
import { zstdDecompress, zstdDecompressSync } from "node:zlib";

const unzstd = promisify(zstdDecompress);

/// How much of a transcript a frame holds.
export const SEGMENT = 16 << 20;

const FRAME_MAGIC = 0xfd2fb528;
const SKIPPABLE = 0x184d2a5e;
const SEEKABLE = 0x8f92eab1;
const FOOTER = 9;
/// The most a raw block holds (zstd's Block_Maximum_Size).
const BLOCK = 128 << 10;

/// A frame of a put-away transcript: where it is in the file (`at`, `packed` bytes) and what it holds of the transcript
/// (`size` bytes from `from`).
export type Frame = { at: number; packed: number; from: number; size: number };

/// A zstd frame holding `bytes` as they are (raw blocks): what is read most is not decompressed.
export function storedFrame(bytes: Buffer): Buffer {
  const blocks = Math.max(1, Math.ceil(bytes.length / BLOCK));
  const out = Buffer.alloc(4 + 1 + 8 + blocks * 3 + bytes.length);
  out.writeUInt32LE(FRAME_MAGIC, 0);
  // Its content size in 8 bytes, one segment (no window descriptor), no checksum, no dictionary.
  out[4] = 0xe0;
  out.writeBigUInt64LE(BigInt(bytes.length), 5);
  let at = 13;
  for (let i = 0; i < blocks; i++) {
    const piece = bytes.subarray(i * BLOCK, Math.min(bytes.length, (i + 1) * BLOCK));
    const head = (piece.length << 3) | (i === blocks - 1 ? 1 : 0);
    out[at] = head & 0xff;
    out[at + 1] = (head >> 8) & 0xff;
    out[at + 2] = (head >> 16) & 0xff;
    piece.copy(out, at + 3);
    at += 3 + piece.length;
  }
  return out;
}

/// The table that ends a put-away transcript: each frame's size in the file and of the transcript.
export function seekTable(frames: { packed: number; size: number }[]): Buffer {
  const out = Buffer.alloc(8 + frames.length * 8 + FOOTER);
  out.writeUInt32LE(SKIPPABLE, 0);
  out.writeUInt32LE(out.length - 8, 4);
  frames.forEach((f, i) => {
    out.writeUInt32LE(f.packed, 8 + i * 8);
    out.writeUInt32LE(f.size, 12 + i * 8);
  });
  const end = 8 + frames.length * 8;
  out.writeUInt32LE(frames.length, end);
  out.writeUInt32LE(SEEKABLE, end + 5);
  return out;
}

function bytesAt(file: number, at: number, n: number): Buffer {
  const out = Buffer.alloc(n);
  for (let got = 0; got < n; ) {
    const read = readSync(file, out, got, n - got, at + got);
    if (read === 0) throw new Error("a put-away transcript ended early");
    got += read;
  }
  return out;
}

/// How long the table at the end of a put-away transcript of `size` bytes is, from its last FOOTER bytes: null without
/// one.
function tableLength(size: number, footer: Buffer): { length: number; entry: number } | null {
  if (size < 8 + FOOTER || footer.readUInt32LE(5) !== SEEKABLE || (footer[4]! & 0x7f) !== 0) return null;
  const entry = footer[4]! & 0x80 ? 12 : 8;
  const length = 8 + footer.readUInt32LE(0) * entry + FOOTER;
  return length > size ? null : { length, entry };
}

/// The frames a table lists: null when they do not add up to the file.
function framesIn(size: number, table: Buffer, entry: number): Frame[] | null {
  if (table.readUInt32LE(0) !== SKIPPABLE || table.readUInt32LE(4) !== table.length - 8) return null;
  const n = (table.length - 8 - FOOTER) / entry;
  const frames: Frame[] = [];
  let at = 0;
  let from = 0;
  for (let i = 0; i < n; i++) {
    const packed = table.readUInt32LE(8 + i * entry);
    const each = table.readUInt32LE(12 + i * entry);
    frames.push({ at, packed, from, size: each });
    at += packed;
    from += each;
  }
  return at === size - table.length ? frames : null;
}

/// A put-away transcript's frames, from its table: null without one, or one that does not add up to the file.
export function framesOf(file: number): Frame[] | null {
  const size = fstatSync(file).size;
  if (size < 8 + FOOTER) return null;
  const table = tableLength(size, bytesAt(file, size - FOOTER, FOOTER));
  return table === null ? null : framesIn(size, bytesAt(file, size - table.length, table.length), table.entry);
}

/// `framesOf` off the thread that asks (the usage counter's, the station's own).
async function framesOfHandle(file: FileHandle): Promise<Frame[] | null> {
  const size = (await file.stat()).size;
  const at = async (from: number, n: number) => {
    const out = Buffer.alloc(n);
    const { bytesRead } = await file.read(out, 0, n, from);
    if (bytesRead < n) throw new Error("a put-away transcript ended early");
    return out;
  };
  if (size < 8 + FOOTER) return null;
  const table = tableLength(size, await at(size - FOOTER, FOOTER));
  return table === null ? null : framesIn(size, await at(size - table.length, table.length), table.entry);
}

/// How long a put-away transcript is as written, from its table, off the thread that asks: null without one.
export async function writtenLength(path: string): Promise<number | null> {
  const file = await open(path, "r");
  try {
    const frames = await framesOfHandle(file);
    return frames === null ? null : frames.reduce((n, f) => n + f.size, 0);
  } finally {
    await file.close();
  }
}

/// What a put-away transcript holds from `from` on (as written), a segment's worth at a time, decompressed off the
/// thread that asks; null when it has no table (it is to be read whole).
export async function segmentsFrom(path: string, from: number): Promise<AsyncGenerator<Buffer> | null> {
  const file = await open(path, "r");
  let frames: Frame[] | null;
  try {
    frames = await framesOfHandle(file);
  } catch (error) {
    await file.close();
    throw error;
  }
  if (frames === null) {
    await file.close();
    return null;
  }
  const these = frames.slice(first(frames, from));
  return (async function* () {
    try {
      for (const f of these) {
        if (f.from + f.size <= from) continue;
        const packed = Buffer.alloc(f.packed);
        const { bytesRead } = await file.read(packed, 0, f.packed, f.at);
        if (bytesRead < f.packed) throw new Error("a put-away transcript ended early");
        const bytes = await unzstd(packed);
        yield bytes.subarray(Math.max(0, from - f.from));
      }
    } finally {
      await file.close();
    }
  })();
}

/// The frame `from` is in, found by where each begins (zork's SessionQuery, by each segment's first event).
function first(frames: Frame[], from: number): number {
  let lo = 0;
  for (let hi = frames.length - 1; lo < hi; ) {
    const mid = (lo + hi + 1) >> 1;
    if (frames[mid]!.from <= from) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/// All of a put-away transcript, a segment at a time (one without a table decompressed whole).
export function unpackedWhole(path: string): Buffer {
  const file = openSync(path, "r");
  try {
    const frames = framesOf(file);
    if (frames === null) return zstdDecompressSync(bytesAt(file, 0, fstatSync(file).size));
    return Buffer.concat(frames.map((f) => zstdDecompressSync(bytesAt(file, f.at, f.packed))));
  } finally {
    closeSync(file);
  }
}

/// Whether a put-away transcript has its table (else it is read whole).
export function segmented(path: string): boolean {
  try {
    const file = openSync(path, "r");
    try {
      return framesOf(file) !== null;
    } finally {
      closeSync(file);
    }
  } catch {
    return false;
  }
}

/// How long a put-away transcript is as written, from its table: null without one.
export function writtenSize(path: string): number | null {
  const file = openSync(path, "r");
  try {
    const frames = framesOf(file);
    return frames === null ? null : frames.reduce((n, f) => n + f.size, 0);
  } finally {
    closeSync(file);
  }
}

/// What a put-away transcript holds from `from` up to `end` (as written), given to `take` a segment's worth at a time
/// while it wants more (it says false once it has what it wants). False when it has no table: it is to be read whole.
export function readSegments(path: string, from: number, end: number, take: (piece: Buffer) => boolean): boolean {
  const file = openSync(path, "r");
  try {
    const frames = framesOf(file);
    if (frames === null) return false;
    for (const f of frames.slice(first(frames, from))) {
      if (f.from + f.size <= from) continue;
      if (f.from >= end) break;
      const bytes = zstdDecompressSync(bytesAt(file, f.at, f.packed));
      if (!take(bytes.subarray(Math.max(0, from - f.from), Math.min(bytes.length, end - f.from)))) break;
    }
    return true;
  } finally {
    closeSync(file);
  }
}
