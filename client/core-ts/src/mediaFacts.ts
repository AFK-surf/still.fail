// A picture's or a film's size as it is shown, read from the few bytes of it that say rather than by decoding it all,
// one reader for the station (station/src/sessions/image-size.ts, from a file or bytes at hand) and the core
// (imageSize.ts, from a file read a part at a time, as a phone's core reads): PNG, GIF and WebP say it in their first
// bytes; a JPEG in its frame's header, turned as the EXIF note before it says (a phone's photo is kept on its side,
// shown upright); an MP4 or QuickTime film in its picture track's header, turned as its matrix says (a phone's
// recording, the same), with the film's length and how many frames its picture has. Nothing is decoded; unknown files
// give null.
//
// The reading asks for its bytes as it goes (a generator yielding what it wants), so the same steps run on a file
// read at once (readSync) or one whose parts come later (readAsync).

/// What a picture or a film says of itself: the size it is shown at; a film's length (ms) and how many frames its
/// picture has, where its header says them.
export type Facts = { width: number; height: number; duration?: number; frames?: number };

/// Bytes wanted: [at, at + n); `rest`, what there is from `at` on, up to a chunk, however little.
type Want = { at: number; n: number; rest: boolean };
type Reading<T> = Generator<Want, T, Uint8Array | null>;

/// How much is read at once: a JPEG's notes before its frame, a film's box headers, mostly in the first of these.
const CHUNK = 64 * 1024;

/// A JPEG's markers, a film's boxes, at most this many looked through before giving up on one that never says.
const STEPS = 256;

function* get(at: number, n: number): Reading<Uint8Array | null> {
  if (at < 0 || n < 0) return null;
  return yield { at, n, rest: false };
}

function* rest(at: number): Reading<Uint8Array> {
  if (at < 0) return new Uint8Array(0);
  return (yield { at, n: CHUNK, rest: true }) ?? new Uint8Array(0);
}

/// What a picture's or a film's bytes say of it.
export function* facts(): Reading<Facts | null> {
  const head = (yield* get(0, 32)) ?? (yield* rest(0));
  if (head.length >= 8 && ascii(head, 4, "ftyp")) return yield* filmFacts();
  if (head.length >= 4 && head[0] === 0xff && head[1] === 0xd8) return yield* jpegSize();
  return headerSize(head);
}

/// A file read a chunk at a time, the last chunk kept (a header's next few bytes are most often in it): `read` gives
/// up to `n` bytes from `at`, fewer at its end.
export function readSync<T>(reading: Reading<T>, read: (at: number, n: number) => Uint8Array): T {
  const kept = chunks();
  let step = reading.next();
  while (!step.done) {
    const w = step.value;
    step = reading.next(kept.held(w) ?? kept.took(w, read(w.at, Math.max(w.n, CHUNK))));
  }
  return step.value;
}

/// The same, of a file of `size` bytes whose parts come later: `read` gives bytes [start, end).
export async function readAsync<T>(reading: Reading<T>, read: (start: number, end: number) => Promise<Uint8Array>, size: number): Promise<T> {
  const kept = chunks();
  let step = reading.next();
  while (!step.done) {
    const w = step.value;
    // (past its end: nothing to read)
    const beyond = w.rest ? w.at >= size : w.at + w.n > size;
    const got = beyond ? (w.rest ? new Uint8Array(0) : null) : (kept.held(w) ?? kept.took(w, await read(w.at, Math.min(size, w.at + Math.max(w.n, CHUNK)))));
    step = reading.next(got);
  }
  return step.value;
}

/// The last chunk read: what of it answers a want (`held`), and a chunk just read for one (`took`: kept, unless it
/// was read for `rest`).
function chunks() {
  let at = 0;
  let bytes = new Uint8Array(0);
  return {
    held(w: Want): Uint8Array | undefined {
      if (w.rest || w.at < at || w.at + w.n > at + bytes.length) return undefined;
      return bytes.subarray(w.at - at, w.at - at + w.n);
    },
    took(w: Want, read: Uint8Array): Uint8Array | null {
      if (w.rest) return read;
      bytes = read;
      at = w.at;
      return bytes.length < w.n ? null : bytes.subarray(0, w.n);
    },
  };
}

/// A PNG's, GIF's or WebP's size, from its first bytes; null for any other kind or a header not understood.
export function headerSize(b: Uint8Array): Facts | null {
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
function* jpegSize(): Reading<Facts | null> {
  let at = 2;
  let turned = false;
  for (let step = 0; step < STEPS; step++) {
    const m = yield* get(at, 4);
    if (!m || m[0] !== 0xff) return null;
    const kind = m[1]!;
    // fill, and the markers that stand alone
    if (kind === 0xff) {
      at += 1;
      continue;
    }
    if (kind === 0x01 || (kind >= 0xd0 && kind <= 0xd8)) {
      at += 2;
      continue;
    }
    // the image's data begun, or ended, with no frame said: none to be had
    if (kind === 0xd9 || kind === 0xda) return null;
    const len = (m[2]! << 8) | m[3]!;
    if (len < 2) return null;
    if (kind === 0xe1) {
      const note = yield* get(at + 4, len - 2);
      if (note) turned = exifTurned(note) ?? turned;
    } else if (kind >= 0xc0 && kind <= 0xcf && kind !== 0xc4 && kind !== 0xc8 && kind !== 0xcc) {
      // a start of frame (not DHT C4, JPG C8, DAC CC): its precision, then its height and width
      const f = yield* get(at + 4, 5);
      if (!f) return null;
      const height = (f[1]! << 8) | f[2]!;
      const width = (f[3]! << 8) | f[4]!;
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
  const u16 = (i: number) => (i + 2 <= t.length ? v.getUint16(i, le) : -1);
  const u32 = (i: number) => (i + 4 <= t.length ? v.getUint32(i, le) : -1);
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
function* filmFacts(): Reading<Facts | null> {
  const moov = yield* child(0, Number.MAX_SAFE_INTEGER, "moov");
  if (!moov) return null;
  let at = moov.start;
  for (let step = 0; step < STEPS && at < moov.end; step++) {
    const b = yield* boxAt(at, moov.end);
    if (!b) return null;
    if (b.type === "trak") {
      const tkhd = yield* child(b.start, b.end, "tkhd");
      const size = tkhd ? yield* trackSize(tkhd) : null;
      if (size) return { ...size, ...(yield* filmTime(moov, b)) };
    }
    at = b.end;
  }
  return null;
}

/// A picture track's length in ms (its media header's, else the film's own: mvhd) and how many frames it has (its
/// sample sizes' count: stsz, or stz2); none said of a film written in fragments (nothing in its header yet).
function* filmTime(moov: Box, trak: Box): Reading<{ duration?: number; frames?: number }> {
  const out: { duration?: number; frames?: number } = {};
  const mdia = yield* child(trak.start, trak.end, "mdia");
  const mdhd = mdia && (yield* child(mdia.start, mdia.end, "mdhd"));
  const mvhd = yield* child(moov.start, moov.end, "mvhd");
  const ms = (mdhd && (yield* timeOf(mdhd))) ?? (mvhd && (yield* timeOf(mvhd)));
  if (ms) out.duration = ms;
  const minf = mdia && (yield* child(mdia.start, mdia.end, "minf"));
  const stbl = minf && (yield* child(minf.start, minf.end, "stbl"));
  if (stbl) {
    const sizes = (yield* child(stbl.start, stbl.end, "stsz")) ?? (yield* child(stbl.start, stbl.end, "stz2"));
    // after its version and flags, a size for every sample (stsz) or a field's size (stz2), then their count
    const count = sizes && (yield* get(sizes.start + 8, 4));
    const frames = count ? new DataView(count.buffer, count.byteOffset, 4).getUint32(0) : 0;
    if (frames > 0) out.frames = frames;
  }
  return out;
}

/// What a media or a movie header (mdhd, mvhd: the same up to there) says its length is, in ms; null for none (0, or
/// all ones: not known).
function* timeOf(header: Box): Reading<number | null> {
  const version = yield* get(header.start, 1);
  if (!version) return null;
  // after its version and flags, its two times (64-bit ones in version 1), its scale, then its length
  const wide = version[0] === 1;
  const b = yield* get(header.start + (wide ? 20 : 12), wide ? 12 : 8);
  if (!b) return null;
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const scale = v.getUint32(0);
  const length = wide ? v.getUint32(4) * 2 ** 32 + v.getUint32(8) : v.getUint32(4);
  const unknown = wide ? v.getUint32(4) === 0xffffffff && v.getUint32(8) === 0xffffffff : length === 0xffffffff;
  if (scale === 0 || length === 0 || unknown) return null;
  const ms = Math.round((length * 1000) / scale);
  return ms > 0 && Number.isSafeInteger(ms) ? ms : null;
}

/// A track header's picture size (16.16 each), turned as its matrix says; null for a track with no picture.
function* trackSize(tkhd: Box): Reading<Facts | null> {
  const version = yield* get(tkhd.start, 1);
  if (!version) return null;
  // after its version and flags, its times, id and duration (64-bit ones in version 1), 16 more, then the matrix
  const matrix = tkhd.start + (version[0] === 1 ? 52 : 40);
  const b = yield* get(matrix, 44);
  if (!b || matrix + 44 > tkhd.end) return null;
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const width = Math.round(v.getUint32(36) / 65536);
  const height = Math.round(v.getUint32(40) / 65536);
  // [a b u; c d v; x y w]: a quarter turn has a and d nothing
  const turned = v.getInt32(0) === 0 && v.getInt32(16) === 0 && v.getInt32(4) !== 0;
  return turned ? ok(height, width) : ok(width, height);
}

/// A box: its type, where what it holds starts and where it ends.
type Box = { type: string; start: number; end: number };

/// The box at `at`, within `end` (as far as the file goes); null for one that does not fit.
function* boxAt(at: number, end: number): Reading<Box | null> {
  const h = (yield* get(at, 16)) ?? (yield* rest(at));
  if (h.length < 8) return null;
  const v = new DataView(h.buffer, h.byteOffset, h.byteLength);
  const type = String.fromCharCode(h[4]!, h[5]!, h[6]!, h[7]!);
  let size = v.getUint32(0);
  let start = at + 8;
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
function* child(start: number, end: number, type: string): Reading<Box | null> {
  let at = start;
  for (let step = 0; step < STEPS && at < end; step++) {
    const b = yield* boxAt(at, end);
    if (!b) return null;
    if (b.type === type) return b;
    at = b.end;
  }
  return null;
}

function ascii(b: Uint8Array, at: number, s: string): boolean {
  return b.length >= at + s.length && [...s].every((c, i) => b[at + i] === c.charCodeAt(0));
}

function ok(width: number, height: number): Facts | null {
  return width > 0 && height > 0 ? { width, height } : null;
}
