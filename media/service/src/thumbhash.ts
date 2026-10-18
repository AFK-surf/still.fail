// A ThumbHash (evanw/thumbhash's encoder, as the station's thumbs.rs makes them: base64) of an image at most 100×100,
// for the thumbnails the station's /thumb does not make (HEIC, GIF, a video's poster): macOS's sips makes a small BMP of
// them, read here.

/// An uncompressed BMP's pixels (24 or 32 bits, either row order) as RGBA; null for any other.
export function readBmp(b: Buffer): { w: number; h: number; rgba: Uint8Array } | null {
  if (b.length < 54 || b.toString("latin1", 0, 2) !== "BM") return null;
  const data = b.readUInt32LE(10);
  const w = b.readInt32LE(18);
  const rawH = b.readInt32LE(22);
  const bits = b.readUInt16LE(28);
  const compression = b.readUInt32LE(30);
  const h = Math.abs(rawH);
  if (w <= 0 || h === 0 || w > 4096 || h > 4096 || (bits !== 24 && bits !== 32) || (compression !== 0 && compression !== 3)) return null;
  const stride = Math.ceil((w * bits) / 32) * 4;
  if (data + stride * h > b.length) return null;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const row = data + stride * (rawH > 0 ? h - 1 - y : y);
    for (let x = 0; x < w; x++) {
      const at = row + x * (bits / 8);
      const o = (y * w + x) * 4;
      rgba[o] = b[at + 2]!;
      rgba[o + 1] = b[at + 1]!;
      rgba[o + 2] = b[at]!;
      rgba[o + 3] = bits === 32 && compression === 3 ? b[at + 3]! : 255;
    }
  }
  return { w, h, rgba };
}

/// The ThumbHash of `w`×`h` RGBA pixels (each at most 100), base64.
export function thumbHash(w: number, h: number, rgba: Uint8Array): string {
  if (w > 100 || h > 100) throw new Error(`${w}x${h} doesn't fit in 100x100`);
  const { PI, round, max, cos, abs } = Math;
  let avgR = 0;
  let avgG = 0;
  let avgB = 0;
  let avgA = 0;
  for (let i = 0, j = 0; i < w * h; i++, j += 4) {
    const alpha = rgba[j + 3]! / 255;
    avgR += (alpha / 255) * rgba[j]!;
    avgG += (alpha / 255) * rgba[j + 1]!;
    avgB += (alpha / 255) * rgba[j + 2]!;
    avgA += alpha;
  }
  if (avgA) {
    avgR /= avgA;
    avgG /= avgA;
    avgB /= avgA;
  }
  const hasAlpha = avgA < w * h;
  const lLimit = hasAlpha ? 5 : 7;
  const lx = max(1, round((lLimit * w) / max(w, h)));
  const ly = max(1, round((lLimit * h) / max(w, h)));
  const l: number[] = [];
  const p: number[] = [];
  const q: number[] = [];
  const a: number[] = [];
  for (let i = 0, j = 0; i < w * h; i++, j += 4) {
    const alpha = rgba[j + 3]! / 255;
    const r = avgR * (1 - alpha) + (alpha / 255) * rgba[j]!;
    const g = avgG * (1 - alpha) + (alpha / 255) * rgba[j + 1]!;
    const b = avgB * (1 - alpha) + (alpha / 255) * rgba[j + 2]!;
    l[i] = (r + g + b) / 3;
    p[i] = (r + g) / 2 - b;
    q[i] = r - g;
    a[i] = alpha;
  }
  const encode = (channel: number[], nx: number, ny: number): [number, number[], number] => {
    let dc = 0;
    const ac: number[] = [];
    let scale = 0;
    const fx: number[] = [];
    for (let cy = 0; cy < ny; cy++) {
      for (let cx = 0; cx * ny < nx * (ny - cy); cx++) {
        let f = 0;
        for (let x = 0; x < w; x++) fx[x] = cos((PI / w) * cx * (x + 0.5));
        for (let y = 0; y < h; y++) {
          const fy = cos((PI / h) * cy * (y + 0.5));
          for (let x = 0; x < w; x++) f += channel[x + y * w]! * fx[x]! * fy;
        }
        f /= w * h;
        if (cx || cy) {
          ac.push(f);
          scale = max(scale, abs(f));
        } else dc = f;
      }
    }
    if (scale) for (let i = 0; i < ac.length; i++) ac[i] = 0.5 + (0.5 / scale) * ac[i]!;
    return [dc, ac, scale];
  };
  const [lDc, lAc, lScale] = encode(l, max(3, lx), max(3, ly));
  const [pDc, pAc, pScale] = encode(p, 3, 3);
  const [qDc, qAc, qScale] = encode(q, 3, 3);
  const [aDc, aAc, aScale] = hasAlpha ? encode(a, 5, 5) : [0, [], 0];
  const landscape = w > h;
  const header24 = round(63 * lDc) | (round(31.5 + 31.5 * pDc) << 6) | (round(31.5 + 31.5 * qDc) << 12) | (round(31 * lScale) << 18) | ((hasAlpha ? 1 : 0) << 23);
  const header16 = (landscape ? ly : lx) | (round(63 * pScale) << 3) | (round(63 * qScale) << 9) | ((landscape ? 1 : 0) << 15);
  const hash = [header24 & 255, (header24 >> 8) & 255, header24 >> 16, header16 & 255, header16 >> 8];
  const acStart = hasAlpha ? 6 : 5;
  let acIndex = 0;
  if (hasAlpha) hash.push(round(15 * aDc) | (round(15 * aScale) << 4));
  for (const ac of hasAlpha ? [lAc, pAc, qAc, aAc] : [lAc, pAc, qAc]) {
    for (const f of ac) {
      const i = acStart + (acIndex >> 1);
      hash[i] = (hash[i] ?? 0) | (round(15 * f) << ((acIndex++ & 1) << 2));
    }
  }
  return Buffer.from(hash).toString("base64");
}
