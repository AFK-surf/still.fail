// A picture's or a film's size as it is shown, from the few bytes of it that say (the Rust station's image_size.rs, and
// the core's client/core-ts/src/imageSize.ts, read the same way and tested on the same files): PNG, GIF and WebP from
// their first bytes; a JPEG from its frame's header, turned as the EXIF note before it says (a phone's photo is kept on
// its side, shown upright); an MP4 or QuickTime film from its picture track's header, turned as its matrix says (a
// phone's recording, the same). Nothing is decoded; unknown files give null. A film's length and how many frames its
// picture has are read from the same header (shownFacts), so a message carries them and a page shows them before it
// reads the film's head and its end.
import { closeSync, openSync, readSync } from "node:fs";

/// How much is read at once; a JPEG's markers and a film's boxes looked through at most so many.
const CHUNK = 64 * 1024;
const STEPS = 256;

/// What a picture or a film says of itself, as a message keeps it: the size it is shown at; a film's length (ms) and
/// how many frames its picture has, where its header says them.
export type Facts = { width: number; height: number; duration?: number; frames?: number };

/// The size the picture or film at `path` is shown at.
export function shownSize(path: string): [number, number] | null {
  const facts = shownFacts(path);
  return facts && [facts.width, facts.height];
}

/// What the picture or film at `path` says of itself.
export function shownFacts(path: string): Facts | null {
  try {
    const file = openSync(path, "r");
    try {
      return factsIn(new Parts((at, n) => {
        const b = Buffer.alloc(n);
        return b.subarray(0, readSync(file, b, 0, n, at));
      }));
    } finally {
      closeSync(file);
    }
  } catch {
    return null;
  }
}

/// The size a picture's or a film's bytes `b` (all of them, or as far as they go) say it is shown at.
export function sizeOf(b: Uint8Array): [number, number] | null {
  const facts = factsIn(new Parts((at, n) => b.subarray(at, at + n)));
  return facts && [facts.width, facts.height];
}

function factsIn(p: Parts): Facts | null {
  const head = p.get(0, 32) ?? p.rest(0);
  if (head.length >= 8 && ascii(head, 4, "ftyp")) return filmFacts(p);
  const size = head.length >= 4 && head[0] === 0xff && head[1] === 0xd8 ? jpegSize(p) : headerSize(head);
  return size && { width: size[0], height: size[1] };
}

function headerSize(b: Uint8Array): [number, number] | null {
  const be32 = (i: number) => ((b[i]! << 24) | (b[i + 1]! << 16) | (b[i + 2]! << 8) | b[i + 3]!) >>> 0;
  const le32 = (i: number) => (b[i]! | (b[i + 1]! << 8) | (b[i + 2]! << 16) | (b[i + 3]! << 24)) >>> 0;
  const le16 = (i: number) => b[i]! | (b[i + 1]! << 8);
  const le24 = (i: number) => b[i]! | (b[i + 1]! << 8) | (b[i + 2]! << 16);
  if (b.length >= 24 && be32(0) === 0x89504e47 && ascii(b, 12, "IHDR")) return ok(be32(16), be32(20));
  if (b.length >= 10 && ascii(b, 0, "GIF")) return ok(le16(6), le16(8));
  if (b.length >= 30 && ascii(b, 0, "RIFF") && ascii(b, 8, "WEBP")) {
    if (ascii(b, 12, "VP8 ")) return ok(le16(26) & 0x3fff, le16(28) & 0x3fff);
    if (ascii(b, 12, "VP8L")) {
      const v = le32(21);
      return ok((v & 0x3fff) + 1, ((v >>> 14) & 0x3fff) + 1);
    }
    if (ascii(b, 12, "VP8X")) return ok(1 + le24(24), 1 + le24(27));
  }
  return null;
}

/// A JPEG's frame size (its start of frame's), its sides swapped where its EXIF orientation turns it a quarter (5–8).
function jpegSize(p: Parts): [number, number] | null {
  let at = 2;
  let turned = false;
  for (let step = 0; step < STEPS; step++) {
    const m = p.get(at, 4);
    if (!m || m[0] !== 0xff) return null;
    const kind = m[1]!;
    // fill, and the markers that stand alone
    if (kind === 0xff) { at += 1; continue; }
    if (kind === 0x01 || (kind >= 0xd0 && kind <= 0xd8)) { at += 2; continue; }
    // the image's data begun, or ended, with no frame said: none to be had
    if (kind === 0xd9 || kind === 0xda) return null;
    const len = (m[2]! << 8) | m[3]!;
    if (len < 2) return null;
    if (kind === 0xe1) {
      const note = p.get(at + 4, len - 2);
      if (note) turned = exifTurned(note) ?? turned;
    } else if (kind >= 0xc0 && kind <= 0xcf && kind !== 0xc4 && kind !== 0xc8 && kind !== 0xcc) {
      // a start of frame (not DHT C4, JPG C8, DAC CC): its precision, then its height and width
      const f = p.get(at + 4, 5);
      if (!f) return null;
      const height = (f[1]! << 8) | f[2]!, width = (f[3]! << 8) | f[4]!;
      return turned ? ok(height, width) : ok(width, height);
    }
    at += 2 + len;
  }
  return null;
}

/// Whether an APP1 note (`Exif\0\0`, then a TIFF) says the picture is shown turned a quarter (orientation 5–8); null
/// for a note that is not EXIF or says no orientation.
function exifTurned(b: Uint8Array): boolean | null {
  if (b.length < 14 || !ascii(b, 0, "Exif\0\0")) return null;
  const t = b.subarray(6);
  const le = ascii(t, 0, "II");
  if (!le && !ascii(t, 0, "MM")) return null;
  const v = new DataView(t.buffer, t.byteOffset, t.byteLength);
  const u16 = (i: number) => i + 2 <= t.length ? v.getUint16(i, le) : -1;
  const u32 = (i: number) => i + 4 <= t.length ? v.getUint32(i, le) : -1;
  if (u16(2) !== 42) return null;
  const ifd = u32(4);
  const count = u16(ifd);
  if (ifd < 0 || count < 0) return null;
  for (let i = 0; i < count; i++) {
    const e = ifd + 2 + i * 12;
    if (u16(e) === 0x0112) {
      const o = u16(e + 8);
      return o < 0 ? null : o >= 5 && o <= 8;
    }
  }
  return null;
}

/// An MP4's or QuickTime film's facts: its first track with a picture's size (an audio track's tkhd says 0 by 0), its
/// sides swapped where its matrix turns it a quarter; that track's length and how many frames it has (filmTime).
function filmFacts(p: Parts): Facts | null {
  const moov = child(p, 0, Number.MAX_SAFE_INTEGER, "moov");
  if (!moov) return null;
  let at = moov.start;
  for (let step = 0; step < STEPS && at < moov.end; step++) {
    const b = boxAt(p, at, moov.end);
    if (!b) return null;
    if (b.type === "trak") {
      const tkhd = child(p, b.start, b.end, "tkhd");
      const size = tkhd ? trackSize(p, tkhd) : null;
      if (size) return { width: size[0], height: size[1], ...filmTime(p, moov, b) };
    }
    at = b.end;
  }
  return null;
}

/// A picture track's length in ms (its media header's, else the film's own: mvhd) and how many frames it has (its
/// sample sizes' count: stsz, or stz2); none said of a film written in fragments (nothing in its header yet).
function filmTime(p: Parts, moov: Box, trak: Box): { duration?: number; frames?: number } {
  const out: { duration?: number; frames?: number } = {};
  const mdia = child(p, trak.start, trak.end, "mdia");
  const mdhd = mdia && child(p, mdia.start, mdia.end, "mdhd");
  const mvhd = child(p, moov.start, moov.end, "mvhd");
  const ms = (mdhd && timeOf(p, mdhd)) ?? (mvhd && timeOf(p, mvhd));
  if (ms) out.duration = ms;
  const stbl = mdia && ["minf", "stbl"].reduce<Box | null>((b, type) => b && child(p, b.start, b.end, type), mdia);
  if (stbl) {
    const sizes = child(p, stbl.start, stbl.end, "stsz") ?? child(p, stbl.start, stbl.end, "stz2");
    // after its version and flags, a size for every sample (stsz) or a field's size (stz2), then their count
    const count = sizes && p.get(sizes.start + 8, 4);
    const frames = count ? new DataView(count.buffer, count.byteOffset, 4).getUint32(0) : 0;
    if (frames > 0) out.frames = frames;
  }
  return out;
}

/// What a media or a movie header (mdhd, mvhd: the same up to there) says its length is, in ms; null for none (0, or
/// all ones: not known).
function timeOf(p: Parts, header: Box): number | null {
  const version = p.get(header.start, 1);
  if (!version) return null;
  // after its version and flags, its two times (64-bit ones in version 1), its scale, then its length
  const wide = version[0] === 1;
  const b = p.get(header.start + (wide ? 20 : 12), wide ? 12 : 8);
  if (!b) return null;
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const scale = v.getUint32(0);
  const length = wide ? v.getUint32(4) * 2 ** 32 + v.getUint32(8) : v.getUint32(4);
  const unknown = wide ? v.getUint32(4) === 0xffffffff && v.getUint32(8) === 0xffffffff : length === 0xffffffff;
  if (scale === 0 || length === 0 || unknown) return null;
  const ms = Math.round(length * 1000 / scale);
  return ms > 0 && Number.isSafeInteger(ms) ? ms : null;
}

/// A track header's picture size (16.16 each), turned as its matrix says; null for a track with no picture.
function trackSize(p: Parts, tkhd: Box): [number, number] | null {
  const version = p.get(tkhd.start, 1);
  if (!version) return null;
  // after its version and flags, its times, id and duration (64-bit ones in version 1), 16 more, then the matrix
  const matrix = tkhd.start + (version[0] === 1 ? 52 : 40);
  const b = p.get(matrix, 44);
  if (!b || matrix + 44 > tkhd.end) return null;
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const width = Math.round(v.getUint32(36) / 65536), height = Math.round(v.getUint32(40) / 65536);
  // [a b u; c d v; x y w]: a quarter turn has a and d nothing
  const turned = v.getInt32(0) === 0 && v.getInt32(16) === 0 && v.getInt32(4) !== 0;
  return turned ? ok(height, width) : ok(width, height);
}

/// A box: its type, where what it holds starts and where it ends.
type Box = { type: string; start: number; end: number };

/// The box at `at`, within `end` (as far as the file goes); null for one that does not fit.
function boxAt(p: Parts, at: number, end: number): Box | null {
  const h = p.get(at, 16) ?? p.rest(at);
  if (h.length < 8) return null;
  const v = new DataView(h.buffer, h.byteOffset, h.byteLength);
  const type = String.fromCharCode(h[4]!, h[5]!, h[6]!, h[7]!);
  let size = v.getUint32(0), start = at + 8;
  // as large as its 64-bit size says; 0: to the end
  if (size === 1) {
    if (h.length < 16) return null;
    size = v.getUint32(8) * 2 ** 32 + v.getUint32(12);
    start = at + 16;
  } else if (size === 0) {
    size = end - at;
  }
  if (size < start - at || at + size > end) return null;
  return { type, start, end: at + size };
}

/// The first box of `type` among those from `start` to `end`.
function child(p: Parts, start: number, end: number, type: string): Box | null {
  let at = start;
  for (let step = 0; step < STEPS && at < end; step++) {
    const b = boxAt(p, at, end);
    if (!b) return null;
    if (b.type === type) return b;
    at = b.end;
  }
  return null;
}

/// A file read a chunk at a time (`read`: up to `n` bytes from `at`, fewer at its end), the last chunk kept.
class Parts {
  readonly read: (at: number, n: number) => Uint8Array;
  #at = 0;
  #bytes: Uint8Array = new Uint8Array(0);
  constructor(read: (at: number, n: number) => Uint8Array) {
    this.read = read;
  }

  /// Bytes [at, at + n), null where the file has fewer.
  get(at: number, n: number): Uint8Array | null {
    if (at < 0 || n < 0) return null;
    if (at < this.#at || at + n > this.#at + this.#bytes.length) {
      this.#bytes = this.read(at, Math.max(n, CHUNK));
      this.#at = at;
      if (this.#bytes.length < n) return null;
    }
    return this.#bytes.subarray(at - this.#at, at - this.#at + n);
  }

  /// What there is from `at` on, up to a chunk (fewer than asked of get, at the file's end).
  rest(at: number): Uint8Array {
    return at < 0 ? new Uint8Array(0) : this.read(at, CHUNK);
  }
}

function ascii(b: Uint8Array, at: number, s: string): boolean {
  return b.length >= at + s.length && [...s].every((c, i) => b[at + i] === c.charCodeAt(0));
}

function ok(w: number, h: number): [number, number] | null {
  return w > 0 && h > 0 ? [w, h] : null;
}
