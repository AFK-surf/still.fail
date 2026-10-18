// What a photo or video says of itself, from its first bytes (a megabyte at most, through the station's drive/read)
// without decoding it: when it was taken, its size as it is seen (turned as it says), how long a video runs, the
// camera, the lens, where. JPEG (EXIF in APP1, SOF), PNG, WebP, GIF, HEIF/HEIC (ISO BMFF: meta → iinf/iloc for the
// Exif item, ipco/ipma for ispe and irot), MP4/MOV (mvhd's time and duration, tkhd's size and turn). A video whose moov
// comes after its media data is read again where the moov is (its size from the box headers).
import { type Exif, parseTiff } from "./exif.ts";
import { sniff } from "./images.ts";

export type Kind = "photo" | "video";

const PHOTOS = new Set(["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"]);
const VIDEOS = new Set(["mp4", "mov", "m4v"]);

export const extOf = (name: string) => {
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
};

/// A file's kind by its name; null for what the library does not keep.
export function kindOf(name: string): Kind | null {
  const ext = extOf(name);
  if (PHOTOS.has(ext)) return "photo";
  if (VIDEOS.has(ext)) return "video";
  return null;
}

export type Meta = {
  taken?: number;
  w?: number;
  h?: number;
  /// Seconds.
  duration?: number;
  camera?: string;
  lens?: string;
  gps?: { lat: number; lon: number };
};

/// How the file is read: its size, its first bytes, and any part of it.
export type Source = { size: number; head: Buffer; read: (offset: number, length: number) => Promise<Buffer> };

/// The head read at first.
export const HEAD = 1024 * 1024;
/// The most of a moov (or a HEIF's Exif item) read past the head.
const MOST_BOX = 8 * 1024 * 1024;

const turned = (o: number | undefined) => o !== undefined && o >= 5 && o <= 8;

const fromExif = (x: Exif): Meta => ({
  ...(x.taken !== undefined ? { taken: x.taken } : {}),
  ...(x.camera ? { camera: x.camera } : {}),
  ...(x.lens ? { lens: x.lens } : {}),
  ...(x.gps ? { gps: x.gps } : {}),
});

/// The file's metadata (what it does not say is left out). Never throws for a file that is not what its name says.
export async function metaOf(src: Source): Promise<Meta> {
  try {
    const b = src.head;
    if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8) return jpegMeta(b);
    if (b.length >= 12 && b.toString("latin1", 4, 8) === "ftyp") {
      const brand = b.toString("latin1", 8, 12);
      if (/^(heic|heix|heim|heis|hevc|hevx|mif1|msf1|avif)$/.test(brand)) return await heifMeta(src);
      return await mp4Meta(src);
    }
    if (b.length >= 12 && b.toString("latin1", 0, 4) === "RIFF" && b.toString("latin1", 8, 12) === "WEBP") return webpMeta(b);
    const s = sniff(b, "");
    if (s.w && s.h) return { w: s.w, h: s.h };
    // A QuickTime file may start with a box other than ftyp (wide, mdat, moov).
    if (b.length >= 8 && /^(moov|mdat|wide|free|skip|pnot)$/.test(b.toString("latin1", 4, 8))) return await mp4Meta(src);
  } catch {}
  return {};
}

function jpegMeta(b: Buffer): Meta {
  let exif: Exif = {};
  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) {
      i++;
      continue;
    }
    const m = b[i + 1]!;
    if (m === 0xff) {
      i++;
      continue;
    }
    if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) {
      i += 2;
      continue;
    }
    if (m === 0xd9 || m === 0xda) break;
    const len = b.readUInt16BE(i + 2);
    if (m === 0xe1 && b.toString("latin1", i + 4, i + 10) === "Exif\0\0" && exif.taken === undefined && exif.orientation === undefined) {
      exif = parseTiff(b.subarray(i + 10, Math.min(b.length, i + 2 + len)));
    }
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc && i + 9 <= b.length) {
      const h = b.readUInt16BE(i + 5);
      const w = b.readUInt16BE(i + 7);
      return { ...fromExif(exif), ...(turned(exif.orientation) ? { w: h, h: w } : { w, h }) };
    }
    i += 2 + len;
  }
  return { ...fromExif(exif), ...sizeOf(exif.w, exif.h, exif.orientation) };
}

const sizeOf = (w: number | undefined, h: number | undefined, orientation: number | undefined) =>
  w && h ? (turned(orientation) ? { w: h, h: w } : { w, h }) : {};

function webpMeta(b: Buffer): Meta {
  const s = sniff(b, "");
  let exif: Exif = {};
  for (let at = 12; at + 8 <= b.length; ) {
    const id = b.toString("latin1", at, at + 4);
    const len = b.readUInt32LE(at + 4);
    if (id === "EXIF") {
      let tiff = b.subarray(at + 8, Math.min(b.length, at + 8 + len));
      if (tiff.toString("latin1", 0, 6) === "Exif\0\0") tiff = tiff.subarray(6);
      exif = parseTiff(tiff);
      break;
    }
    at += 8 + len + (len & 1);
  }
  return { ...fromExif(exif), ...sizeOf(s.w, s.h, exif.orientation) };
}

// ISO BMFF boxes.

type Box = { type: string; start: number; body: number; end: number };

/// The boxes in `b` from `from` to `to` (a box running past the end of `b` is given as far as its header says).
function boxes(b: Buffer, from: number, to: number): Box[] {
  const out: Box[] = [];
  let at = from;
  while (at + 8 <= to && at + 8 <= b.length) {
    let size = b.readUInt32BE(at);
    const type = b.toString("latin1", at + 4, at + 8);
    let body = at + 8;
    if (size === 1) {
      if (at + 16 > b.length) break;
      size = Number(b.readBigUInt64BE(at + 8));
      body = at + 16;
    } else if (size === 0) size = to - at;
    if (size < body - at) break;
    out.push({ type, start: at, body, end: at + size });
    at += size;
  }
  return out;
}

const child = (b: Buffer, parent: Box, type: string, skip = 0) => boxes(b, parent.body + skip, Math.min(parent.end, b.length)).find((c) => c.type === type);

/// A number of `size` bytes (0, 4 or 8) at `at`.
const uint = (b: Buffer, at: number, size: number) => (size === 0 ? 0 : size === 2 ? b.readUInt16BE(at) : size === 4 ? b.readUInt32BE(at) : size === 8 ? Number(b.readBigUInt64BE(at)) : 0);

async function heifMeta(src: Source): Promise<Meta> {
  const b = src.head;
  const meta = boxes(b, 0, b.length).find((x) => x.type === "meta");
  if (!meta) return {};
  // A full box: version and flags first.
  const inMeta = boxes(b, meta.body + 4, Math.min(meta.end, b.length));
  const find = (type: string) => inMeta.find((x) => x.type === type);

  const pitm = find("pitm");
  const primary = pitm ? (b[pitm.body] === 0 ? b.readUInt16BE(pitm.body + 4) : b.readUInt32BE(pitm.body + 4)) : undefined;

  // The items' types (iinf → infe).
  const types = new Map<number, string>();
  const iinf = find("iinf");
  if (iinf) {
    const v = b[iinf.body]!;
    for (const infe of boxes(b, iinf.body + 4 + (v === 0 ? 2 : 4), Math.min(iinf.end, b.length))) {
      if (infe.type !== "infe") continue;
      const iv = b[infe.body]!;
      if (iv < 2) continue;
      const id = iv === 2 ? b.readUInt16BE(infe.body + 4) : b.readUInt32BE(infe.body + 4);
      const typeAt = infe.body + 4 + (iv === 2 ? 2 : 4) + 2;
      types.set(id, b.toString("latin1", typeAt, typeAt + 4));
    }
  }

  // Where the items are (iloc).
  const where = new Map<number, { method: number; extents: { offset: number; length: number }[] }>();
  const iloc = find("iloc");
  if (iloc) {
    let at = iloc.body;
    const v = b[at]!;
    at += 4;
    const offsetSize = b[at]! >> 4;
    const lengthSize = b[at]! & 15;
    const baseSize = b[at + 1]! >> 4;
    const indexSize = v === 1 || v === 2 ? b[at + 1]! & 15 : 0;
    at += 2;
    const count = v < 2 ? b.readUInt16BE(at) : b.readUInt32BE(at);
    at += v < 2 ? 2 : 4;
    for (let i = 0; i < count && at < iloc.end; i++) {
      const id = v < 2 ? b.readUInt16BE(at) : b.readUInt32BE(at);
      at += v < 2 ? 2 : 4;
      let method = 0;
      if (v === 1 || v === 2) {
        method = b.readUInt16BE(at) & 15;
        at += 2;
      }
      at += 2; // data_reference_index
      const base = uint(b, at, baseSize);
      at += baseSize;
      const n = b.readUInt16BE(at);
      at += 2;
      const extents: { offset: number; length: number }[] = [];
      for (let e = 0; e < n; e++) {
        at += indexSize;
        const offset = uint(b, at, offsetSize);
        at += offsetSize;
        const length = uint(b, at, lengthSize);
        at += lengthSize;
        extents.push({ offset: base + offset, length });
      }
      where.set(id, { method, extents });
    }
  }

  // The Exif item's bytes, from the file (method 0) or the idat (method 1).
  let exif: Exif = {};
  const exifId = [...types].find(([, t]) => t === "Exif")?.[0];
  const loc = exifId !== undefined ? where.get(exifId) : undefined;
  if (loc && loc.extents.length > 0) {
    const parts: Buffer[] = [];
    const idat = find("idat");
    for (const e of loc.extents) {
      const length = e.length || 64 * 1024;
      if (length > MOST_BOX) break;
      if (loc.method === 1) {
        if (idat) parts.push(b.subarray(idat.body + e.offset, idat.body + e.offset + length));
      } else if (loc.method === 0) {
        parts.push(e.offset + length <= b.length ? b.subarray(e.offset, e.offset + length) : await src.read(e.offset, length));
      }
    }
    const item = Buffer.concat(parts);
    if (item.length > 4) {
      const skip = item.readUInt32BE(0);
      exif = parseTiff(item.subarray(4 + skip));
      // Some writers put the TIFF right after "Exif\0\0" without counting it.
      if (exif.taken === undefined && exif.orientation === undefined) {
        const tiffAt = item.indexOf("Exif\0\0", 0, "latin1");
        if (tiffAt >= 0) exif = parseTiff(item.subarray(tiffAt + 6));
      }
    }
  }

  // The primary image's size (ispe) and turn (irot), by ipco and ipma.
  let w: number | undefined;
  let h: number | undefined;
  let rot: number | undefined;
  const iprp = find("iprp");
  if (iprp) {
    const props = boxes(b, iprp.body, Math.min(iprp.end, b.length));
    const ipco = props.find((x) => x.type === "ipco");
    const ipma = props.find((x) => x.type === "ipma");
    const list = ipco ? boxes(b, ipco.body, Math.min(ipco.end, b.length)) : [];
    const ispe = (p: Box) => ({ w: b.readUInt32BE(p.body + 4), h: b.readUInt32BE(p.body + 8) });
    let assoc: number[] | undefined;
    if (ipma && primary !== undefined) {
      const v = b[ipma.body]!;
      const wide = (b.readUInt32BE(ipma.body) & 1) === 1;
      let at = ipma.body + 4;
      const count = b.readUInt32BE(at);
      at += 4;
      for (let i = 0; i < count && at < ipma.end; i++) {
        const id = v < 1 ? b.readUInt16BE(at) : b.readUInt32BE(at);
        at += v < 1 ? 2 : 4;
        const n = b[at]!;
        at += 1;
        const idx: number[] = [];
        for (let k = 0; k < n; k++) {
          idx.push(wide ? b.readUInt16BE(at) & 0x7fff : b[at]! & 0x7f);
          at += wide ? 2 : 1;
        }
        if (id === primary) assoc = idx;
      }
    }
    if (assoc) {
      for (const i of assoc) {
        const p = list[i - 1];
        if (p?.type === "ispe") ({ w, h } = ispe(p));
        if (p?.type === "irot") rot = b[p.body]! & 3;
      }
    }
    if (w === undefined) {
      // No association known: the largest ispe.
      for (const p of list.filter((x) => x.type === "ispe")) {
        const s = ispe(p);
        if (w === undefined || s.w * s.h > w * (h ?? 0)) ({ w, h } = s);
      }
    }
  }
  const size = w && h ? (rot !== undefined ? (rot % 2 === 1 ? { w: h, h: w } : { w, h }) : sizeOf(w, h, exif.orientation)) : sizeOf(exif.w, exif.h, exif.orientation);
  return { ...fromExif(exif), ...size };
}

/// Seconds from 1904 (QuickTime's epoch) to 1970.
const EPOCH_1904 = 2_082_844_800;

async function mp4Meta(src: Source): Promise<Meta> {
  let b = src.head;
  let moov = boxes(b, 0, b.length).find((x) => x.type === "moov");
  if (!moov || moov.end > b.length) {
    // Walk the top-level boxes by their headers to where the moov is, and read it whole.
    let at = 0;
    let found: { at: number; size: number } | null = moov ? { at: moov.start, size: moov.end - moov.start } : null;
    for (let i = 0; !found && at + 8 <= src.size && i < 64; i++) {
      const h = at + 16 <= b.length ? b.subarray(at, at + 16) : await src.read(at, 16);
      if (h.length < 8) break;
      let size = h.readUInt32BE(0);
      const type = h.toString("latin1", 4, 8);
      if (size === 1 && h.length >= 16) size = Number(h.readBigUInt64BE(8));
      else if (size === 0) size = src.size - at;
      if (size < 8) break;
      if (type === "moov") found = { at, size };
      at += size;
    }
    if (!found || found.size > MOST_BOX) return {};
    b = await src.read(found.at, found.size);
    moov = boxes(b, 0, b.length).find((x) => x.type === "moov");
    if (!moov) return {};
  }
  const out: Meta = {};
  const mvhd = child(b, moov, "mvhd");
  if (mvhd) {
    const v = b[mvhd.body]!;
    const created = v === 1 ? Number(b.readBigUInt64BE(mvhd.body + 4)) : b.readUInt32BE(mvhd.body + 4);
    const scale = v === 1 ? b.readUInt32BE(mvhd.body + 20) : b.readUInt32BE(mvhd.body + 12);
    const duration = v === 1 ? Number(b.readBigUInt64BE(mvhd.body + 24)) : b.readUInt32BE(mvhd.body + 16);
    // Zero, or before 1971: not set.
    if (created > EPOCH_1904 + 365 * 86400) out.taken = (created - EPOCH_1904) * 1000;
    if (scale > 0 && duration > 0 && duration !== 0xffffffff) out.duration = Math.round((duration / scale) * 1000) / 1000;
  }
  for (const trak of boxes(b, moov.body, Math.min(moov.end, b.length)).filter((x) => x.type === "trak")) {
    const tkhd = child(b, trak, "tkhd");
    if (!tkhd) continue;
    const v = b[tkhd.body]!;
    const matrix = tkhd.body + 4 + (v === 1 ? 32 : 20) + 16;
    const w = b.readUInt32BE(matrix + 36) / 65536;
    const h = b.readUInt32BE(matrix + 40) / 65536;
    if (!(w > 0 && h > 0)) continue;
    const a = b.readInt32BE(matrix);
    const bb = b.readInt32BE(matrix + 4);
    const quarter = a === 0 && Math.abs(bb) === 65536;
    out.w = Math.round(quarter ? h : w);
    out.h = Math.round(quarter ? w : h);
    break;
  }
  return out;
}
