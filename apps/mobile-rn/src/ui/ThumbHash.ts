// An image's ThumbHash as the station keeps it with the message (base64, made as it keeps the image, the Rust
// station's thumbs.rs): a blurred likeness of it, shown until the image itself loads (web/src/thumbhash.ts). The
// decoder is thumbhash's own (Evan Wallace, MIT), as the web uses it. The likeness is handed to an Image as a PNG
// data URL (an ImageBitmap in the Android app), written here uncompressed: it is 32px across.

/** The likeness as an Image takes it: its source, and its pixel size. */
export interface ThumbImage { uri: string; width: number; height: number }

interface Read { image: ThumbImage; ratio: number }

const NONE = Symbol("none");
/** What was drawn, by hash (an LruCache of 200 in the Android app): a Map kept in the order last used. */
const drawn = new Map<string, Read | typeof NONE>();

function remember(hash: string, got: Read | typeof NONE) {
  drawn.delete(hash);
  drawn.set(hash, got);
  while (drawn.size > 200) drawn.delete(drawn.keys().next().value!);
}

function bytesOf(base64: string): Uint8Array {
  const bin = globalThis.atob(base64.replace(/\s+/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function read(hash: string | null | undefined): Read | null {
  if (!hash) return null;
  const known = drawn.get(hash);
  if (known !== undefined) {
    remember(hash, known);
    return known === NONE ? null : known;
  }
  let got: Read | null;
  try {
    const bytes = bytesOf(hash);
    const [w, h, rgba] = toRgba(bytes);
    got = { image: { uri: png(w, h, rgba), width: w, height: h }, ratio: ratioOf(bytes) };
  } catch {
    got = null;
  }
  remember(hash, got ?? NONE);
  return got;
}

export const ThumbHash = {
  /** The likeness, about 32px across (the box it fills blurs it further), or null for none. */
  image(hash: string | null | undefined): ThumbImage | null {
    return read(hash)?.image ?? null;
  },

  /** The image's width over its height, near enough to size a box by. */
  ratio(hash: string | null | undefined): number | null {
    return read(hash)?.ratio ?? null;
  },
};

function ratioOf(hash: Uint8Array): number {
  const header = hash[3]!;
  const hasAlpha = (hash[2]! & 0x80) !== 0;
  const isLandscape = (hash[4]! & 0x80) !== 0;
  const lx = isLandscape ? (hasAlpha ? 5 : 7) : header & 7;
  const ly = isLandscape ? header & 7 : hasAlpha ? 5 : 7;
  return lx / ly;
}

function toRgba(hash: Uint8Array): [number, number, Uint8Array] {
  if (hash.length < 6) throw new Error("short thumbhash");
  const at = (i: number) => {
    const b = hash[i];
    if (b === undefined) throw new Error("short thumbhash");
    return b;
  };
  const header24 = at(0) | (at(1) << 8) | (at(2) << 16);
  const header16 = at(3) | (at(4) << 8);
  const lDc = (header24 & 63) / 63.0;
  const pDc = ((header24 >> 6) & 63) / 31.5 - 1;
  const qDc = ((header24 >> 12) & 63) / 31.5 - 1;
  const lScale = ((header24 >> 18) & 31) / 31.0;
  const hasAlpha = header24 >> 23 !== 0;
  const pScale = ((header16 >> 3) & 63) / 63.0;
  const qScale = ((header16 >> 9) & 63) / 63.0;
  const isLandscape = header16 >> 15 !== 0;
  const lx = Math.max(3, isLandscape ? (hasAlpha ? 5 : 7) : header16 & 7);
  const ly = Math.max(3, isLandscape ? header16 & 7 : hasAlpha ? 5 : 7);
  const aDc = hasAlpha ? (at(5) & 15) / 15.0 : 1.0;
  const aScale = (at(5) >> 4) / 15.0;

  // The varying factors (saturation boosted by 1.25x to make up for quantization).
  const acStart = hasAlpha ? 6 : 5;
  let acIndex = 0;
  const channel = (nx: number, ny: number, scale: number): number[] => {
    const ac: number[] = [];
    for (let cy = 0; cy < ny; cy++) {
      for (let cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
        ac.push((((at(acStart + (acIndex >> 1)) >> ((acIndex & 1) << 2)) & 15) / 7.5 - 1) * scale);
        acIndex++;
      }
    }
    return ac;
  };
  const lAc = channel(lx, ly, lScale);
  const pAc = channel(3, 3, pScale * 1.25);
  const qAc = channel(3, 3, qScale * 1.25);
  const aAc = hasAlpha ? channel(5, 5, aScale) : null;

  const ratio = ratioOf(hash);
  const w = Math.round(ratio > 1 ? 32 : 32 * ratio);
  const h = Math.round(ratio > 1 ? 32 / ratio : 32);
  const rgba = new Uint8Array(w * h * 4);
  const fx = new Array<number>(7).fill(0);
  const fy = new Array<number>(7).fill(0);
  let i = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let l = lDc;
      let p = pDc;
      let q = qDc;
      let a = aDc;
      for (let cx = 0, n = Math.max(lx, hasAlpha ? 5 : 3); cx < n; cx++) fx[cx] = Math.cos((Math.PI / w) * (x + 0.5) * cx);
      for (let cy = 0, n = Math.max(ly, hasAlpha ? 5 : 3); cy < n; cy++) fy[cy] = Math.cos((Math.PI / h) * (y + 0.5) * cy);
      let j = 0;
      for (let cy = 0; cy < ly; cy++) {
        const fy2 = fy[cy]! * 2;
        for (let cx = cy > 0 ? 0 : 1; cx * ly < lx * (ly - cy); cx++, j++) l += lAc[j]! * fx[cx]! * fy2;
      }
      j = 0;
      for (let cy = 0; cy < 3; cy++) {
        const fy2 = fy[cy]! * 2;
        for (let cx = cy > 0 ? 0 : 1; cx < 3 - cy; cx++, j++) {
          const f = fx[cx]! * fy2;
          p += pAc[j]! * f;
          q += qAc[j]! * f;
        }
      }
      if (aAc !== null) {
        j = 0;
        for (let cy = 0; cy < 5; cy++) {
          const fy2 = fy[cy]! * 2;
          for (let cx = cy > 0 ? 0 : 1; cx < 5 - cy; cx++, j++) a += aAc[j]! * fx[cx]! * fy2;
        }
      }
      const b = l - (2.0 / 3) * p;
      const r = (3 * l - b + q) / 2;
      const g = r - q;
      rgba[i] = Math.max(0, 255 * Math.min(1, r));
      rgba[i + 1] = Math.max(0, 255 * Math.min(1, g));
      rgba[i + 2] = Math.max(0, 255 * Math.min(1, b));
      rgba[i + 3] = Math.max(0, 255 * Math.min(1, a));
      i += 4;
    }
  }
  return [w, h, rgba];
}

// ── a PNG, stored (no compression): what an Image takes for pixels ─────

const CRC = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(bytes: Uint8Array, from: number, to: number): number {
  let c = 0xffffffff;
  for (let i = from; i < to; i++) c = CRC[(c ^ bytes[i]!) & 0xff]! ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function png(w: number, h: number, rgba: Uint8Array): string {
  // The rows, each after its filter byte (none).
  const raw = new Uint8Array(h * (w * 4 + 1));
  for (let y = 0; y < h; y++) raw.set(rgba.subarray(y * w * 4, (y + 1) * w * 4), y * (w * 4 + 1) + 1);
  // zlib: its header, the rows in stored blocks of at most 65535 bytes, their Adler-32.
  const blocks = Math.max(1, Math.ceil(raw.length / 65535));
  const zlib = new Uint8Array(2 + raw.length + blocks * 5 + 4);
  zlib[0] = 0x78;
  zlib[1] = 0x01;
  let z = 2;
  for (let b = 0; b < blocks; b++) {
    const part = raw.subarray(b * 65535, Math.min(raw.length, (b + 1) * 65535));
    zlib[z++] = b === blocks - 1 ? 1 : 0;
    zlib[z++] = part.length & 0xff;
    zlib[z++] = part.length >> 8;
    zlib[z++] = ~part.length & 0xff;
    zlib[z++] = (~part.length >> 8) & 0xff;
    zlib.set(part, z);
    z += part.length;
  }
  let s1 = 1;
  let s2 = 0;
  for (let i = 0; i < raw.length; i++) {
    s1 = (s1 + raw[i]!) % 65521;
    s2 = (s2 + s1) % 65521;
  }
  const adler = ((s2 << 16) | s1) >>> 0;
  zlib[z++] = adler >>> 24;
  zlib[z++] = (adler >>> 16) & 0xff;
  zlib[z++] = (adler >>> 8) & 0xff;
  zlib[z++] = adler & 0xff;

  const chunks: Uint8Array[] = [];
  const chunk = (type: string, data: Uint8Array) => {
    const c = new Uint8Array(12 + data.length);
    const v = new DataView(c.buffer);
    v.setUint32(0, data.length);
    for (let i = 0; i < 4; i++) c[4 + i] = type.charCodeAt(i);
    c.set(data, 8);
    v.setUint32(8 + data.length, crc32(c, 4, 8 + data.length));
    chunks.push(c);
  };
  const ihdr = new Uint8Array(13);
  const hv = new DataView(ihdr.buffer);
  hv.setUint32(0, w);
  hv.setUint32(4, h);
  ihdr[8] = 8; // bits per channel
  ihdr[9] = 6; // RGBA
  chunk("IHDR", ihdr);
  chunk("IDAT", zlib);
  chunk("IEND", new Uint8Array(0));

  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  let bin = String.fromCharCode(...signature);
  for (const c of chunks) for (let i = 0; i < c.length; i += 4096) bin += String.fromCharCode(...c.subarray(i, i + 4096));
  return `data:image/png;base64,${globalThis.btoa(bin)}`;
}
