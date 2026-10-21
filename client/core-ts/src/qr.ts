// A QR code of a text (a link to open on a phone), as rows of modules the views draw: byte mode, error correction
// level M, the smallest version it fits in, the mask with the lowest penalty (ISO/IEC 18004, after Project Nayuki's
// QR Code generator, MIT). No dependencies: it runs in the browser's worker and in Android's Hermes alike.

/// A text's UTF-8 bytes (here, not util.ts: the web's stories draw QR codes with this file alone).
function utf8(text: string): number[] {
  const out: number[] = [];
  for (const ch of text) {
    const c = ch.codePointAt(0)!;
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return out;
}

// By version (index 0 unused), level M.
const ECC_PER_BLOCK = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];
const BLOCKS = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49];
/// Level M's two format bits.
const LEVEL_M = 0;

const bit = (x: number, i: number) => ((x >>> i) & 1) !== 0;

function rawModules(ver: number): number {
  let result = (16 * ver + 128) * ver + 64;
  if (ver >= 2) {
    const align = Math.floor(ver / 7) + 2;
    result -= (25 * align - 10) * align - 55;
    if (ver >= 7) result -= 36;
  }
  return result;
}

const dataCodewords = (ver: number) => Math.floor(rawModules(ver) / 8) - ECC_PER_BLOCK[ver]! * BLOCKS[ver]!;

function multiply(x: number, y: number): number {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

function divisor(degree: number): number[] {
  const result = new Array<number>(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      result[j] = multiply(result[j]!, root);
      if (j + 1 < degree) result[j]! ^= result[j + 1]!;
    }
    root = multiply(root, 0x02);
  }
  return result;
}

function remainder(data: number[], div: number[]): number[] {
  const result = div.map(() => 0);
  for (const b of data) {
    const factor = b ^ result.shift()!;
    result.push(0);
    div.forEach((coef, i) => (result[i]! ^= multiply(coef, factor)));
  }
  return result;
}

function withEcc(data: number[], ver: number): number[] {
  const blocks = BLOCKS[ver]!;
  const eccLen = ECC_PER_BLOCK[ver]!;
  const raw = Math.floor(rawModules(ver) / 8);
  const shortBlocks = blocks - (raw % blocks);
  const shortLen = Math.floor(raw / blocks);
  const div = divisor(eccLen);
  const all: number[][] = [];
  for (let i = 0, k = 0; i < blocks; i++) {
    const dat = data.slice(k, k + shortLen - eccLen + (i < shortBlocks ? 0 : 1));
    k += dat.length;
    const ecc = remainder(dat, div);
    if (i < shortBlocks) dat.push(0);
    all.push(dat.concat(ecc));
  }
  const result: number[] = [];
  for (let i = 0; i < all[0]!.length; i++) {
    all.forEach((block, j) => {
      if (i !== shortLen - eccLen || j >= shortBlocks) result.push(block[i]!);
    });
  }
  return result;
}

function alignments(ver: number): number[] {
  if (ver === 1) return [];
  const n = Math.floor(ver / 7) + 2;
  const step = Math.floor((ver * 8 + n * 3 + 5) / (n * 4 - 4)) * 2;
  const result = [6];
  for (let pos = ver * 4 + 17 - 7; result.length < n; pos -= step) result.splice(1, 0, pos);
  return result;
}

class Grid {
  readonly ver: number;
  readonly size: number;
  readonly dark: boolean[][];
  readonly fixed: boolean[][];
  constructor(ver: number) {
    this.ver = ver;
    this.size = ver * 4 + 17;
    this.dark = Array.from({ length: this.size }, () => new Array<boolean>(this.size).fill(false));
    this.fixed = Array.from({ length: this.size }, () => new Array<boolean>(this.size).fill(false));
  }

  set(x: number, y: number, dark: boolean) {
    this.dark[y]![x] = dark;
    this.fixed[y]![x] = true;
  }

  patterns() {
    const s = this.size;
    for (let i = 0; i < s; i++) {
      this.set(6, i, i % 2 === 0);
      this.set(i, 6, i % 2 === 0);
    }
    for (const [x, y] of [[3, 3], [s - 4, 3], [3, s - 4]] as const) {
      for (let dy = -4; dy <= 4; dy++) {
        for (let dx = -4; dx <= 4; dx++) {
          const d = Math.max(Math.abs(dx), Math.abs(dy));
          const xx = x + dx;
          const yy = y + dy;
          if (xx >= 0 && xx < s && yy >= 0 && yy < s) this.set(xx, yy, d !== 2 && d !== 4);
        }
      }
    }
    const at = alignments(this.ver);
    const last = at.length - 1;
    at.forEach((ax, i) =>
      at.forEach((ay, j) => {
        if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) return;
        for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) this.set(ax + dx, ay + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }),
    );
    this.format(0);
    if (this.ver >= 7) {
      let rem = this.ver;
      for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
      const bits = (this.ver << 12) | rem;
      for (let i = 0; i < 18; i++) {
        const b = bit(bits, i);
        const a = s - 11 + (i % 3);
        const c = Math.floor(i / 3);
        this.set(a, c, b);
        this.set(c, a, b);
      }
    }
  }

  format(mask: number) {
    const data = (LEVEL_M << 3) | mask;
    let rem = data;
    for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    const bits = ((data << 10) | rem) ^ 0x5412;
    const s = this.size;
    for (let i = 0; i <= 5; i++) this.set(8, i, bit(bits, i));
    this.set(8, 7, bit(bits, 6));
    this.set(8, 8, bit(bits, 7));
    this.set(7, 8, bit(bits, 8));
    for (let i = 9; i < 15; i++) this.set(14 - i, 8, bit(bits, i));
    for (let i = 0; i < 8; i++) this.set(s - 1 - i, 8, bit(bits, i));
    for (let i = 8; i < 15; i++) this.set(8, s - 15 + i, bit(bits, i));
    this.set(8, s - 8, true);
  }

  codewords(data: number[]) {
    const s = this.size;
    let i = 0;
    for (let right = s - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < s; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const up = ((right + 1) & 2) === 0;
          const y = up ? s - 1 - vert : vert;
          if (!this.fixed[y]![x] && i < data.length * 8) {
            this.dark[y]![x] = bit(data[i >>> 3]!, 7 - (i & 7));
            i++;
          }
        }
      }
    }
  }

  mask(m: number) {
    for (let y = 0; y < this.size; y++) {
      for (let x = 0; x < this.size; x++) {
        const flip = [
          (x + y) % 2 === 0,
          y % 2 === 0,
          x % 3 === 0,
          (x + y) % 3 === 0,
          (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
          ((x * y) % 2) + ((x * y) % 3) === 0,
          (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
          (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
        ][m]!;
        if (!this.fixed[y]![x] && flip) this.dark[y]![x] = !this.dark[y]![x];
      }
    }
  }

  penalty(): number {
    const s = this.size;
    let result = 0;
    const count = (h: number[]) => {
      const n = h[1]!;
      const core = n > 0 && h[2] === n && h[3] === n * 3 && h[4] === n && h[5] === n;
      return (core && h[0]! >= n * 4 && h[6]! >= n ? 1 : 0) + (core && h[6]! >= n * 4 && h[0]! >= n ? 1 : 0);
    };
    const add = (len: number, h: number[]) => {
      if (h[0] === 0) len += s;
      h.pop();
      h.unshift(len);
    };
    const line = (at: (i: number) => boolean) => {
      let color = false;
      let run = 0;
      const h = [0, 0, 0, 0, 0, 0, 0];
      for (let i = 0; i < s; i++) {
        if (at(i) === color) {
          run++;
          if (run === 5) result += 3;
          else if (run > 5) result++;
        } else {
          add(run, h);
          if (!color) result += count(h) * 40;
          color = at(i);
          run = 1;
        }
      }
      if (color) {
        add(run, h);
        run = 0;
      }
      add(run + s, h);
      result += count(h) * 40;
    };
    for (let y = 0; y < s; y++) line((x) => this.dark[y]![x]!);
    for (let x = 0; x < s; x++) line((y) => this.dark[y]![x]!);
    for (let y = 0; y < s - 1; y++) {
      for (let x = 0; x < s - 1; x++) {
        const c = this.dark[y]![x];
        if (c === this.dark[y]![x + 1] && c === this.dark[y + 1]![x] && c === this.dark[y + 1]![x + 1]) result += 3;
      }
    }
    const dark = this.dark.reduce((n, row) => n + row.filter(Boolean).length, 0);
    const total = s * s;
    result += (Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1) * 10;
    return result;
  }
}

/// A text's QR code: its size in modules and its rows, each a string of `1` (dark) and `0`, without the quiet zone
/// (the views leave four modules' margin). Null for a text longer than a QR code holds.
export function qr(text: string): { size: number; rows: string[] } | null {
  const bytes = utf8(text);
  let ver = 1;
  for (; ver <= 40; ver++) {
    const used = 4 + (ver <= 9 ? 8 : 16) + bytes.length * 8;
    if (used <= dataCodewords(ver) * 8) break;
  }
  if (ver > 40) return null;
  const capacity = dataCodewords(ver) * 8;
  const bits: number[] = [];
  const append = (value: number, len: number) => {
    for (let i = len - 1; i >= 0; i--) bits.push((value >>> i) & 1);
  };
  append(0x4, 4);
  append(bytes.length, ver <= 9 ? 8 : 16);
  for (const b of bytes) append(b, 8);
  append(0, Math.min(4, capacity - bits.length));
  append(0, (8 - (bits.length % 8)) % 8);
  for (let pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11) append(pad, 8);
  const data: number[] = [];
  for (let i = 0; i < bits.length; i += 8) data.push(bits.slice(i, i + 8).reduce((v, b) => (v << 1) | b, 0));
  const grid = new Grid(ver);
  grid.patterns();
  grid.codewords(withEcc(data, ver));
  let best = 0;
  let lowest = Infinity;
  for (let m = 0; m < 8; m++) {
    grid.mask(m);
    grid.format(m);
    const p = grid.penalty();
    if (p < lowest) {
      best = m;
      lowest = p;
    }
    grid.mask(m);
  }
  grid.mask(best);
  grid.format(best);
  return { size: grid.size, rows: grid.dark.map((row) => row.map((d) => (d ? "1" : "0")).join("")) };
}
