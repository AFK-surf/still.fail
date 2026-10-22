// A small animated GIF writer, for a GIF put up as a station's or workspace's icon (stationPick.ts): its frames, already
// drawn square at the size it is shown, go out as one GIF89a that loops, in one palette of the 255 colours they use most
// (5 bits a channel), the 256th being clear. Where nothing is clear, a frame carries only what changed since the one
// before (the rest clear, the frame cut to the box that changed), which is most of what makes an animation small.

/** A frame as drawn: `side` × `side` RGBA pixels, shown for `delay` ms. */
export type GifFrame = { pixels: Uint8ClampedArray; delay: number };

const CLEAR = 255;

/** `frames` (each `side` px square) as one looping GIF. */
export function gifOf(frames: GifFrame[], side: number): Uint8Array {
  const palette = paletteOf(frames);
  const near = nearest(palette);
  // A clear pixel that later turns opaque, or the other way, cannot be drawn by leaving it as it was: then every frame
  // is whole, each put over nothing (disposal 2).
  const clear = frames.some((f) => f.pixels.some((v, i) => (i & 3) === 3 && v < 128));
  const out = new Bytes();
  out.text("GIF89a");
  out.u16(side); out.u16(side);
  out.byte(0xf7); out.byte(0); out.byte(0); // a global table of 256 colours
  for (let i = 0; i < 256; i++) { const c = palette[i] ?? 0; out.byte(c >> 16); out.byte((c >> 8) & 255); out.byte(c & 255); }
  out.bytes([0x21, 0xff, 11, ...[..."NETSCAPE2.0"].map((ch) => ch.charCodeAt(0)), 3, 1, 0, 0, 0]); // loop for ever
  let before: Uint8Array | null = null;
  for (const frame of merged(frames, side, near, clear)) {
    let [x0, y0, x1, y1] = [0, 0, side, side];
    let indexes = frame.indexes;
    if (before && !clear) {
      const changed = new Uint8Array(indexes.length).fill(CLEAR);
      [x0, y0, x1, y1] = [side, side, 0, 0];
      for (let i = 0; i < indexes.length; i++) {
        if (indexes[i] === before[i]) continue;
        changed[i] = indexes[i]!;
        const x = i % side, y = (i / side) | 0;
        x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x + 1); y1 = Math.max(y1, y + 1);
      }
      indexes = changed;
    }
    before = frame.indexes;
    const w = x1 - x0, h = y1 - y0;
    const cut = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) cut.set(indexes.subarray((y0 + y) * side + x0, (y0 + y) * side + x1), y * w);
    // In hundredths; under two is shown as ten by browsers, so it is written so (what it looked like before).
    const cs = frame.delay < 20 ? 10 : Math.round(frame.delay / 10);
    out.bytes([0x21, 0xf9, 4, ((clear ? 2 : 1) << 2) | 1, cs & 255, cs >> 8, CLEAR, 0]);
    out.byte(0x2c); out.u16(x0); out.u16(y0); out.u16(w); out.u16(h); out.byte(0);
    out.byte(8);
    const data = lzw(cut);
    for (let i = 0; i < data.length; i += 255) { const n = Math.min(255, data.length - i); out.byte(n); out.bytes(data.subarray(i, i + n)); }
    out.byte(0);
  }
  out.byte(0x3b);
  return out.done();
}

/** Each frame in the palette's indexes, a frame the same as the one before it joined to it (its time added). */
function merged(frames: GifFrame[], side: number, near: (r: number, g: number, b: number) => number, clear: boolean): { indexes: Uint8Array; delay: number }[] {
  const out: { indexes: Uint8Array; delay: number }[] = [];
  for (const f of frames) {
    const indexes = new Uint8Array(side * side);
    for (let i = 0, p = 0; i < indexes.length; i++, p += 4) {
      indexes[i] = clear && f.pixels[p + 3]! < 128 ? CLEAR : near(f.pixels[p]!, f.pixels[p + 1]!, f.pixels[p + 2]!);
    }
    const last = out[out.length - 1];
    if (last && last.indexes.every((v, i) => v === indexes[i])) last.delay += f.delay;
    else out.push({ indexes, delay: f.delay });
  }
  return out;
}

/** The 255 colours the frames use most, each the mean of the pixels at 5 bits a channel that make it, as 0xRRGGBB. */
function paletteOf(frames: GifFrame[]): number[] {
  const count = new Float64Array(32768), r = new Float64Array(32768), g = new Float64Array(32768), b = new Float64Array(32768);
  for (const f of frames) {
    const px = f.pixels;
    for (let p = 0; p < px.length; p += 4) {
      if (px[p + 3]! < 128) continue;
      const k = ((px[p]! >> 3) << 10) | ((px[p + 1]! >> 3) << 5) | (px[p + 2]! >> 3);
      count[k]!++; r[k]! += px[p]!; g[k]! += px[p + 1]!; b[k]! += px[p + 2]!;
    }
  }
  const used = [...count.keys()].filter((k) => count[k]! > 0).sort((a, z) => count[z]! - count[a]! || a - z).slice(0, 255);
  return used.map((k) => (Math.round(r[k]! / count[k]!) << 16) | (Math.round(g[k]! / count[k]!) << 8) | Math.round(b[k]! / count[k]!));
}

/** The palette's index nearest a colour, worked out once for each colour at 5 bits a channel. */
function nearest(palette: number[]): (r: number, g: number, b: number) => number {
  const known = new Int16Array(32768).fill(-1);
  return (r, g, b) => {
    const k = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    if (known[k]! >= 0) return known[k]!;
    const [cr, cg, cb] = [((k >> 10) << 3) | 4, (((k >> 5) & 31) << 3) | 4, ((k & 31) << 3) | 4];
    let best = 0, least = Infinity;
    palette.forEach((c, i) => {
      const d = ((c >> 16) - cr) ** 2 + (((c >> 8) & 255) - cg) ** 2 + ((c & 255) - cb) ** 2;
      if (d < least) { least = d; best = i; }
    });
    return (known[k] = best);
  };
}

/** GIF's LZW of 8-bit indexes: codes from 9 bits to 12, starting over (a clear code) when the table is full. */
function lzw(indexes: Uint8Array): Uint8Array {
  const out = new Bytes();
  let acc = 0, bits = 0, size = 9, next = 258;
  const put = (code: number) => {
    acc |= code << bits; bits += size;
    while (bits >= 8) { out.byte(acc & 255); acc >>>= 8; bits -= 8; }
  };
  let table = new Map<number, number>();
  put(256);
  let prefix = indexes[0] ?? 0;
  for (let i = 1; i < indexes.length; i++) {
    const k = indexes[i]!;
    const key = (prefix << 8) | k;
    const found = table.get(key);
    if (found !== undefined) { prefix = found; continue; }
    put(prefix);
    if (next === 4096) {
      put(256);
      table = new Map(); next = 258; size = 9;
    } else {
      table.set(key, next++);
      if (next > 1 << size && size < 12) size++;
    }
    prefix = k;
  }
  put(prefix);
  put(257);
  if (bits > 0) out.byte(acc & 255);
  return out.done();
}

/** Bytes written one after another. */
class Bytes {
  private buf = new Uint8Array(4096);
  private n = 0;
  byte(v: number) { if (this.n === this.buf.length) { const b = new Uint8Array(this.buf.length * 2); b.set(this.buf); this.buf = b; } this.buf[this.n++] = v; }
  bytes(vs: ArrayLike<number>) { for (let i = 0; i < vs.length; i++) this.byte(vs[i]!); }
  u16(v: number) { this.byte(v & 255); this.byte(v >> 8); }
  text(s: string) { for (const ch of s) this.byte(ch.charCodeAt(0)); }
  done(): Uint8Array { return this.buf.slice(0, this.n); }
}
