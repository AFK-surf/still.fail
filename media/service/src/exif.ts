// EXIF (a TIFF structure, as a JPEG's APP1, a HEIF's Exif item or a WebP's EXIF chunk carry it): when a photo was
// taken (DateTimeOriginal and its OffsetTimeOriginal), how it is turned (Orientation), the camera, the lens, where.

export type Exif = {
  /// When it was taken, ms: in the offset it gives, else as the station's local time.
  taken?: number;
  /// 1..8; 5–8 are turned a quarter (width and height swap).
  orientation?: number;
  camera?: string;
  lens?: string;
  gps?: { lat: number; lon: number };
  /// The image's size as the EXIF says (PixelXDimension, PixelYDimension), stored orientation.
  w?: number;
  h?: number;
};

const SIZES: Record<number, number> = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8 };

type Entry = { type: number; count: number; at: number };

/// The TIFF in `b` (from its "II*\0" / "MM\0*" header); an empty result for what is not one. Never throws.
export function parseTiff(b: Buffer): Exif {
  try {
    return tiff(b);
  } catch {
    return {};
  }
}

function tiff(b: Buffer): Exif {
  if (b.length < 8) return {};
  const order = b.toString("latin1", 0, 2);
  if (order !== "II" && order !== "MM") return {};
  const le = order === "II";
  const u16 = (at: number) => (le ? b.readUInt16LE(at) : b.readUInt16BE(at));
  const u32 = (at: number) => (le ? b.readUInt32LE(at) : b.readUInt32BE(at));
  const i32 = (at: number) => (le ? b.readInt32LE(at) : b.readInt32BE(at));
  if (u16(2) !== 42) return {};

  /// An IFD's entries by tag (the first of each), where each value is.
  const ifd = (offset: number): Map<number, Entry> => {
    const out = new Map<number, Entry>();
    if (offset < 8 || offset + 2 > b.length) return out;
    const n = u16(offset);
    for (let i = 0; i < n && i < 1000; i++) {
      const e = offset + 2 + i * 12;
      if (e + 12 > b.length) break;
      const tag = u16(e);
      const type = u16(e + 2);
      const count = u32(e + 4);
      const size = (SIZES[type] ?? 0) * count;
      if (size === 0 || out.has(tag)) continue;
      const at = size <= 4 ? e + 8 : u32(e + 8);
      if (at + size > b.length) continue;
      out.set(tag, { type, count, at });
    }
    return out;
  };
  const text = (e: Entry | undefined) => {
    if (!e || (e.type !== 2 && e.type !== 7)) return undefined;
    const s = b.toString("latin1", e.at, e.at + e.count).replace(/\0[\s\S]*$/, "").trim();
    // UTF-8 when it is (the standard says ASCII; phones write UTF-8).
    const utf8 = Buffer.from(s, "latin1").toString("utf8");
    return (utf8.includes("�") ? s : utf8) || undefined;
  };
  const num = (e: Entry | undefined, i = 0): number | undefined => {
    if (!e || i >= e.count) return undefined;
    const at = e.at + i * (SIZES[e.type] ?? 0);
    switch (e.type) {
      case 1:
      case 7:
        return b[at];
      case 3:
        return u16(at);
      case 4:
        return u32(at);
      case 9:
        return i32(at);
      case 5: {
        const d = u32(at + 4);
        return d === 0 ? undefined : u32(at) / d;
      }
      case 10: {
        const d = i32(at + 4);
        return d === 0 ? undefined : i32(at) / d;
      }
    }
    return undefined;
  };

  const out: Exif = {};
  const ifd0 = ifd(u32(4));
  const orientation = num(ifd0.get(0x0112));
  if (orientation !== undefined && orientation >= 1 && orientation <= 8) out.orientation = orientation;
  const make = text(ifd0.get(0x010f));
  const model = text(ifd0.get(0x0110));
  const camera = make && model && !model.toLowerCase().startsWith(make.toLowerCase().split(" ")[0]!) ? `${make} ${model}` : (model ?? make);
  if (camera) out.camera = camera;

  const exifAt = num(ifd0.get(0x8769));
  if (exifAt !== undefined) {
    const ex = ifd(exifAt);
    const when = text(ex.get(0x9003)) ?? text(ex.get(0x9004));
    const offset = text(ex.get(0x9011)) ?? text(ex.get(0x9010));
    const sub = text(ex.get(0x9291));
    const taken = when ? timeOf(when, offset, sub) : undefined;
    if (taken !== undefined) out.taken = taken;
    const lens = text(ex.get(0xa434));
    if (lens) out.lens = lens;
    const w = num(ex.get(0xa002));
    const h = num(ex.get(0xa003));
    if (w && h) {
      out.w = w;
      out.h = h;
    }
  }

  const gpsAt = num(ifd0.get(0x8825));
  if (gpsAt !== undefined) {
    const g = ifd(gpsAt);
    const dms = (e: Entry | undefined) => {
      const d = num(e, 0);
      const m = num(e, 1) ?? 0;
      const s = num(e, 2) ?? 0;
      return d === undefined ? undefined : d + m / 60 + s / 3600;
    };
    const lat = dms(g.get(2));
    const lon = dms(g.get(4));
    if (lat !== undefined && lon !== undefined && (lat !== 0 || lon !== 0) && lat <= 90 && lon <= 180) {
      const sign = (e: Entry | undefined, neg: string) => (text(e)?.toUpperCase() === neg ? -1 : 1);
      out.gps = { lat: round(sign(g.get(1), "S") * lat), lon: round(sign(g.get(3), "W") * lon) };
    }
  }
  return out;
}

const round = (v: number) => Math.round(v * 1e6) / 1e6;

/// "YYYY:MM:DD HH:MM:SS" (EXIF's), with "+HH:MM" when it is given (else the station's local time), and the sub-seconds.
export function timeOf(when: string, offset?: string, sub?: string): number | undefined {
  const m = /^(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(when.trim());
  if (!m) return undefined;
  const [y, mo, d, h, mi, s] = m.slice(1).map(Number) as [number, number, number, number, number, number];
  if (y < 1900 || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) return undefined;
  const ms = sub && /^\d+$/.test(sub.trim()) ? Math.round(Number(`0.${sub.trim()}`) * 1000) : 0;
  const o = offset ? /^([+-])(\d{2}):?(\d{2})$/.exec(offset.trim()) : null;
  if (o) {
    const minutes = (o[1] === "-" ? -1 : 1) * (Number(o[2]) * 60 + Number(o[3]));
    return Date.UTC(y, mo - 1, d, h, mi, s, ms) - minutes * 60_000;
  }
  return new Date(y, mo - 1, d, h, mi, s, ms).getTime();
}
