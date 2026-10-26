// Pictures and films as phones make them, only as far as their sizes go: a JPEG's notes and frame header, an MP4's
// boxes (station/test/media-size.test.ts measures the same with the station's reader).

const u16 = (n: number, le = false) => le ? [n & 255, n >>> 8] : [n >>> 8, n & 255];
const u32 = (n: number, le = false) => le ? [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, n >>> 24] : [n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
const ascii = (s: string) => [...s].map((c) => c.charCodeAt(0));

/// An APP1 EXIF note saying `orientation` (little-endian: `le`), a thumbnail of `thumb` bytes after it.
export function exif(orientation: number, le: boolean, thumb = 0): number[] {
  const tiff = [...ascii(le ? "II" : "MM"), ...u16(42, le), ...u32(8, le),
    // IFD0: an image width entry, then the orientation's (SHORT, one), no next
    ...u16(2, le), ...u16(0x0100, le), ...u16(3, le), ...u32(1, le), ...u16(4032, le), 0, 0,
    ...u16(0x0112, le), ...u16(3, le), ...u32(1, le), ...u16(orientation, le), 0, 0, ...u32(0, le)];
  const body = [...ascii("Exif\0\0"), ...tiff, ...new Array<number>(thumb).fill(0)];
  // (a note is at most 65533 bytes: a thumbnail larger than one is split into two notes, the second not EXIF)
  const notes: number[] = [];
  for (let at = 0; at < body.length; at += 65533) {
    const part = body.slice(at, at + 65533);
    notes.push(0xff, 0xe1, ...u16(part.length + 2), ...part);
  }
  return notes;
}

/// A JPEG `width` by `height` as kept, its `notes` before its frame.
export function jpeg(width: number, height: number, notes: number[] = []): Uint8Array {
  const jfif = [0xff, 0xe0, ...u16(16), ...ascii("JFIF\0"), 1, 1, 0, 0, 1, 0, 1, 0, 0];
  const dqt = [0xff, 0xdb, ...u16(67), 0, ...new Array<number>(64).fill(1)];
  const sof = [0xff, 0xc0, ...u16(17), 8, ...u16(height), ...u16(width), 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1];
  return new Uint8Array([0xff, 0xd8, ...jfif, ...notes, ...dqt, ...sof, 0xff, 0xda, ...u16(12), 3, 1, 0, 2, 0x11, 3, 0x11, 0, 63, 0, 0xff, 0xd9]);
}

const box = (type: string, ...content: number[][]) => {
  const body = content.flat();
  return [...u32(body.length + 8), ...ascii(type), ...body];
};

/// A track header (`version` 0 or 1) `width` by `height`, turned `turn` degrees by its matrix.
function tkhd(width: number, height: number, turn: number, version: number): number[] {
  const one = 0x10000, minus = 0xffff0000;
  const [a, b, c, d]: [number, number, number, number] = turn === 90 ? [0, one, minus, 0] : turn === 270 ? [0, minus, one, 0] : turn === 180 ? [minus, 0, 0, minus] : [one, 0, 0, one];
  const times = version === 1 ? new Array<number>(8 + 8 + 4 + 4 + 8).fill(0) : new Array<number>(20).fill(0);
  return box("tkhd", [version, 0, 0, 3], times, new Array<number>(16).fill(0),
    [...u32(a), ...u32(b), ...u32(0), ...u32(c), ...u32(d), ...u32(0), ...u32(0), ...u32(0), ...u32(0x40000000)],
    u32(width * 65536), u32(height * 65536));
}

/// A media or a movie header (mdhd, mvhd: `version` 0 or 1) saying `ms` at `scale` a second, `rest` bytes after it.
function timed(type: string, version: number, ms: number, scale: number, rest: number): number[] {
  const length = Math.round(ms * scale / 1000);
  const times = version === 1 ? [...u32(0), ...u32(0), ...u32(0), ...u32(0), ...u32(scale), ...u32(Math.floor(length / 2 ** 32)), ...u32(length >>> 0)] : [...u32(0), ...u32(0), ...u32(scale), ...u32(length)];
  return box(type, [version, 0, 0, 0], times, new Array<number>(rest).fill(0));
}

/// An MP4 film whose picture is `width` by `height` (none: 0 by 0, a sound track's), its header first or at its
/// `end` (as a phone's recorder writes it), turned `turn` degrees; a sound track before the picture's; its data box's
/// size said in 64 bits (`large`); `ms` long as its picture track's media header says (at QuickTime's 600 a second;
/// the film's own header says it instead with `movie`), `frames` the count of its picture's sample sizes.
export function film(width: number, height: number, o: { at?: "start" | "end"; turn?: number; version?: number; sound?: boolean; large?: boolean; ms?: number; movie?: boolean; frames?: number } = {}): Uint8Array {
  const ftyp = box("ftyp", ascii("isom"), u32(512), ascii("isomiso2mp41"));
  const version = o.version ?? 0;
  const mdhd = o.ms !== undefined && !o.movie ? [timed("mdhd", version, o.ms, 600, 4)] : [];
  // every sample the same size (100), so none is listed
  const minf = o.frames !== undefined ? [box("minf", box("stbl", box("stsz", [0, 0, 0, 0], u32(100), u32(o.frames))))] : [];
  const picture = box("trak", tkhd(width, height, o.turn ?? 0, version), box("mdia", ...mdhd, ...minf));
  const tracks = [...(o.sound ? [box("trak", tkhd(0, 0, 0, 0), box("mdia", []))] : []), picture];
  const mvhd = o.ms !== undefined && o.movie ? timed("mvhd", 0, o.ms, 1000, 80) : box("mvhd", new Array<number>(100).fill(0));
  const moov = box("moov", mvhd, ...tracks);
  const data = new Array<number>(200_000).fill(7);
  const mdat = o.large ? [...u32(1), ...ascii("mdat"), ...u32(0), ...u32(data.length + 16), ...data] : box("mdat", data);
  return new Uint8Array(o.at === "end" ? [...ftyp, ...mdat, ...moov] : [...ftyp, ...moov, ...mdat]);
}
