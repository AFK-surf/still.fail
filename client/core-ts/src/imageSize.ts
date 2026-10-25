/// A picture's or a film's size as it is shown, read from the few bytes of it that say rather than by decoding it all:
/// a big screenshot takes a while to decode (and Hermes, the phone's core, decodes nothing), and a message sent
/// meanwhile would show it in a box of another shape. PNG, GIF and WebP say it in their first bytes; a JPEG in its
/// frame's header, turned as the EXIF note before it says (a phone's photo is kept on its side, shown upright); an MP4
/// or QuickTime film in its picture track's header, turned as its matrix says (a phone's recording, the same).
/// The station reads them the same way (station/src/sessions/image-size.ts), tested on the same files.

export type Size = { width: number; height: number };

/// Bytes [start, end) of a file (fewer at its end).
export type Read = (start: number, end: number) => Promise<Uint8Array>;

/// How much is read at once: a JPEG's notes before its frame, a film's box headers, mostly in the first of these.
const CHUNK = 64 * 1024;

/// A JPEG's markers, a film's boxes, at most this many looked through before giving up on one that never says.
const STEPS = 256;

/// The size `read` (a file of `size` bytes) is shown at; null for any other kind, or one whose bytes do not say.
export async function shownSize(read: Read, size: number): Promise<Size | null> {
  const p = new Parts(read, size);
  const head = await p.get(0, Math.min(size, 32));
  if (!head) return null;
  if (head.length >= 4 && head[0] === 0xff && head[1] === 0xd8) return jpegSize(p);
  if (head.length >= 8 && ascii(head, 4, "ftyp")) return filmSize(p);
  return headerSize(head);
}

/// A PNG's, GIF's or WebP's size, from its first bytes; null for any other kind or a header not understood.
export function headerSize(b: Uint8Array): Size | null {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  if (b.length >= 24 && b[0] === 0x89 && ascii(b, 1, "PNG") && ascii(b, 12, "IHDR")) return ok(v.getUint32(16), v.getUint32(20));
  if (b.length >= 10 && (ascii(b, 0, "GIF87a") || ascii(b, 0, "GIF89a"))) return ok(v.getUint16(6, true), v.getUint16(8, true));
  if (b.length >= 30 && ascii(b, 0, "RIFF") && ascii(b, 8, "WEBP")) {
    if (ascii(b, 12, "VP8 ") && b[23] === 0x9d && b[24] === 0x01 && b[25] === 0x2a) return ok(v.getUint16(26, true) & 0x3fff, v.getUint16(28, true) & 0x3fff);
    if (ascii(b, 12, "VP8L") && b[20] === 0x2f) {
      const bits = v.getUint32(21, true);
      return ok((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1);
    }
    if (ascii(b, 12, "VP8X")) return ok((b[24]! | (b[25]! << 8) | (b[26]! << 16)) + 1, (b[27]! | (b[28]! << 8) | (b[29]! << 16)) + 1);
  }
  return null;
}

/// A JPEG's frame size (its start of frame's), its sides swapped where its EXIF orientation turns it a quarter (5–8).
async function jpegSize(p: Parts): Promise<Size | null> {
  let at = 2;
  let turned = false;
  for (let step = 0; step < STEPS; step++) {
    const m = await p.get(at, 4);
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
      const note = await p.get(at + 4, len - 2);
      if (note) turned = exifTurned(note) ?? turned;
    } else if (kind >= 0xc0 && kind <= 0xcf && kind !== 0xc4 && kind !== 0xc8 && kind !== 0xcc) {
      // a start of frame (not DHT C4, JPG C8, DAC CC): its precision, then its height and width
      const f = await p.get(at + 4, 5);
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
export function exifTurned(b: Uint8Array): boolean | null {
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

/// An MP4's or QuickTime film's size: its first track with a picture's (an audio track's tkhd says 0 by 0), its sides
/// swapped where its matrix turns it a quarter.
async function filmSize(p: Parts): Promise<Size | null> {
  const moov = await child(p, 0, p.size, "moov");
  if (!moov) return null;
  let at = moov.start;
  for (let step = 0; step < STEPS && at < moov.end; step++) {
    const b = await boxAt(p, at, moov.end);
    if (!b) return null;
    if (b.type === "trak") {
      const tkhd = await child(p, b.start, b.end, "tkhd");
      const size = tkhd ? await trackSize(p, tkhd) : null;
      if (size) return size;
    }
    at = b.end;
  }
  return null;
}

/// A track header's picture size (16.16 each), turned as its matrix says; null for a track with no picture.
async function trackSize(p: Parts, tkhd: Box): Promise<Size | null> {
  const version = await p.get(tkhd.start, 1);
  if (!version) return null;
  // after its version and flags, its times, id and duration (64-bit ones in version 1), 16 more, then the matrix
  const matrix = tkhd.start + (version[0] === 1 ? 52 : 40);
  const b = await p.get(matrix, 44);
  if (!b || matrix + 44 > tkhd.end) return null;
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const width = Math.round(v.getUint32(36) / 65536), height = Math.round(v.getUint32(40) / 65536);
  // [a b u; c d v; x y w]: a quarter turn has a and d nothing
  const turned = v.getInt32(0) === 0 && v.getInt32(16) === 0 && v.getInt32(4) !== 0;
  return turned ? ok(height, width) : ok(width, height);
}

/// A box: its type, where what it holds starts and where it ends.
type Box = { type: string; start: number; end: number };

/// The box at `at`, within `end`; null for one that does not fit.
async function boxAt(p: Parts, at: number, end: number): Promise<Box | null> {
  const h = await p.get(at, Math.min(16, end - at));
  if (!h || h.length < 8) return null;
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
async function child(p: Parts, start: number, end: number, type: string): Promise<Box | null> {
  let at = start;
  for (let step = 0; step < STEPS && at < end; step++) {
    const b = await boxAt(p, at, end);
    if (!b) return null;
    if (b.type === type) return b;
    at = b.end;
  }
  return null;
}

/// A file read a chunk at a time, the last chunk kept: a header's next few bytes are most often in it.
class Parts {
  readonly read: Read;
  readonly size: number;
  #at = 0;
  #bytes: Uint8Array = new Uint8Array(0);
  constructor(read: Read, size: number) {
    this.read = read;
    this.size = size;
  }

  /// Bytes [at, at + n), null where the file has fewer.
  async get(at: number, n: number): Promise<Uint8Array | null> {
    if (at < 0 || n < 0 || at + n > this.size) return null;
    if (at < this.#at || at + n > this.#at + this.#bytes.length) {
      this.#bytes = await this.read(at, Math.min(this.size, at + Math.max(n, CHUNK)));
      this.#at = at;
      if (this.#bytes.length < n) return null;
    }
    return this.#bytes.subarray(at - this.#at, at - this.#at + n);
  }
}

function ascii(b: Uint8Array, at: number, s: string): boolean {
  return b.length >= at + s.length && [...s].every((c, i) => b[at + i] === c.charCodeAt(0));
}

function ok(width: number, height: number): Size | null {
  return width > 0 && height > 0 ? { width, height } : null;
}
