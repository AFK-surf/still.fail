// Applying a delta (scripts/delta.ts makes them, and says the format at its head): what turns the files a device
// already has into a release's package, here and in the release scripts alike (scripts/delta.ts takes these, so there
// is one applier in TypeScript; the apps carry their own in C and Java). The station applies one to its installed
// release to make the next release's raw archive (release.ts), in a process apart: the old blob is tens of MB.
import { createHash } from "node:crypto";
import { closeSync, lstatSync, openSync, readFileSync, rmSync, writeSync } from "node:fs";
import { join } from "node:path";
import { deflateRawSync, inflateRawSync } from "node:zlib";

export type Range = { at: number; len: number };
export type Header = {
  files: string[]; inflate: Range[]; oldSize: number; oldSha256: string; deflate: Range[]; madeSize: number;
  /** Where the chunks begin (parsed headers only). */
  payload?: number;
};
export type Sink = (bytes: Uint8Array) => void;

export const MAGIC = Buffer.from("SFDELTA1");
export const CHUNK = 1 << 20;
const TWO32 = 4294967296;
const sha256 = (b: Uint8Array) => createHash("sha256").update(b).digest("hex");
export const nodeDeflate = (raw: Uint8Array) => deflateRawSync(raw, { level: 6 });

// --- the header ---

/** Refuses a path that could reach outside the folder it is read in. */
export function checkPath(path: string) {
  const bad = path === "" || path.startsWith("/") || /^[A-Za-z]:/.test(path) || path.includes("\\") || path.includes("\0") ||
    path.split("/").some((part) => part === "" || part === "..");
  if (bad) throw new Error(`the delta names a path an applier refuses: ${JSON.stringify(path)}`);
}

const utf8 = new TextDecoder("utf-8", { fatal: true });

/** The header of a delta, refused when it is not one an applier takes. */
export function parseHeader(d: Buffer): Header {
  if (d.length < 8 || !d.subarray(0, 8).equals(MAGIC)) throw new Error("not a delta (bad magic)");
  let p = 8;
  const need = (n: number) => { if (p + n > d.length) throw new Error("the delta's header is cut short"); };
  const u32 = () => { need(4); p += 4; return d.readUInt32LE(p - 4); };
  const u64 = () => {
    need(8);
    const hi = d.readUInt32LE(p + 4);
    if (hi > 0x1fffff) throw new Error("the delta's header has a number too large");
    p += 8;
    return hi * TWO32 + d.readUInt32LE(p - 8);
  };
  const ranges = (what: string) => {
    const list: Range[] = [];
    for (let n = u32(), end = 0; n > 0; n--) {
      const r = { at: u64(), len: u64() };
      if (r.at < end) throw new Error(`the delta's ${what} ranges are not ascending`);
      end = r.at + r.len;
      list.push(r);
    }
    return list;
  };
  const files: string[] = [];
  for (let n = u32(); n > 0; n--) {
    need(2);
    const len = d.readUInt16LE(p);
    p += 2;
    need(len);
    let path: string;
    try { path = utf8.decode(d.subarray(p, p + len)); } catch { throw new Error("the delta names a path that is not UTF-8"); }
    checkPath(path);
    files.push(path);
    p += len;
  }
  const inflate = ranges("inflate");
  const oldSize = u64();
  need(32);
  const oldSha256 = d.toString("hex", p, p + 32);
  p += 32;
  const deflate = ranges("deflate");
  const madeSize = u64();
  if (files.length && inflate.length) throw new Error("the delta names both files and an apk's ranges");
  if (deflate.length && deflate.at(-1)!.at + deflate.at(-1)!.len > madeSize) throw new Error("the delta's deflate ranges go past made_size");
  return { files, inflate, oldSize, oldSha256, deflate, madeSize, payload: p };
}

// --- applying ---

function chunks(d: Buffer, start: number) {
  let at = start, buf = Buffer.alloc(0), pos = 0;
  const next = () => {
    if (at + 8 > d.length) throw new Error("the delta has no end chunk");
    const raw = d.readUInt32LE(at), packed = d.readUInt32LE(at + 4);
    at += 8;
    if (raw === 0) {
      if (packed !== 0 || at !== d.length) throw new Error("the delta goes on after its end chunk");
      return false;
    }
    if (raw > CHUNK) throw new Error(`a chunk of ${raw} bytes, more than ${CHUNK}`);
    if (at + packed > d.length) throw new Error("the delta has no end chunk (a chunk is cut short)");
    try { buf = inflateRawSync(d.subarray(at, at + packed), { maxOutputLength: raw }); } catch { throw new Error("a chunk does not inflate to its raw_len"); }
    if (buf.length !== raw) throw new Error("a chunk does not inflate to its raw_len");
    at += packed;
    pos = 0;
    return true;
  };
  return {
    /** How many of at most `max` bytes are at hand now (at least one), from `r.buf` at `r.pos`. */
    take(max: number) {
      while (pos === buf.length) if (!next()) throw new Error("the delta's stream ends early");
      return Math.min(max, buf.length - pos);
    },
    get buf() { return buf; },
    get pos() { return pos; },
    skip(n: number) { pos += n; },
    end() { if (pos !== buf.length || next()) throw new Error("the delta's stream goes on past made_size"); },
  };
}

/** bspatch: the made bytes, handed to `sink` in order (views it must copy to keep). */
export function patch(h: Header, old: Uint8Array, d: Buffer, sink: Sink): void {
  const r = chunks(d, h.payload ?? parseHeader(d).payload!), out = Buffer.allocUnsafe(CHUNK), ctrl = Buffer.alloc(24);
  const oldsize = old.length, made = h.madeSize;
  let fill = 0, o = 0, p = 0;
  const room = () => { if (fill === CHUNK) { sink(out); fill = 0; } return CHUNK - fill; };
  const i64 = (at: number) => {
    const hi = ctrl.readInt32LE(at + 4);
    if (hi > 0x1fffff || hi < -0x200000) throw new Error("a record's number is too large");
    return hi * TWO32 + ctrl.readUInt32LE(at);
  };
  while (o < made) {
    for (let got = 0; got < 24;) {
      const k = r.take(24 - got);
      r.buf.copy(ctrl, got, r.pos, r.pos + k);
      r.skip(k);
      got += k;
    }
    const x = i64(0), y = i64(8), z = i64(16);
    if (x < 0 || y < 0) throw new Error("a record with a negative length");
    if (x > made - o || y > made - o - x) throw new Error("a record goes past made_size");
    for (let left = x; left > 0;) {
      const k = r.take(Math.min(left, room())), b = r.buf, s = r.pos;
      if (p >= 0 && p + k <= oldsize) for (let i = 0; i < k; i++) out[fill + i] = b[s + i]! + old[p + i]!;
      else for (let i = 0; i < k; i++) out[fill + i] = b[s + i]! + (p + i >= 0 && p + i < oldsize ? old[p + i]! : 0);
      r.skip(k);
      fill += k;
      p += k;
      left -= k;
    }
    for (let left = y; left > 0;) {
      const k = r.take(Math.min(left, room()));
      r.buf.copy(out, fill, r.pos, r.pos + k);
      r.skip(k);
      fill += k;
      left -= k;
    }
    o += x + y;
    p += z;
  }
  r.end();
  if (fill) sink(out.subarray(0, fill));
}

/** A sink deflating `ranges` of what it is given (each held whole while it comes) before handing it on. */
function deflating(ranges: Range[], sink: Sink, deflate: (raw: Uint8Array) => Uint8Array) {
  let o = 0, k = 0, held = Buffer.alloc(0), fill = 0, holding = false;
  const write = (b: Uint8Array) => {
    for (let i = 0; i < b.length || (k < ranges.length && ranges[k]!.at === o && ranges[k]!.len === 0);) {
      const r = ranges[k];
      if (!r || o < r.at) {
        const n = r ? Math.min(b.length - i, r.at - o) : b.length - i;
        sink(b.subarray(i, i + n));
        i += n;
        o += n;
        continue;
      }
      if (!holding) { held = Buffer.allocUnsafe(r.len); fill = 0; holding = true; }
      const n = Math.min(b.length - i, r.len - fill);
      held.set(b.subarray(i, i + n), fill);
      fill += n;
      i += n;
      o += n;
      if (fill === r.len) { sink(deflate(held)); holding = false; k++; }
    }
  };
  return { write, end() { write(new Uint8Array(0)); if (k !== ranges.length || holding) throw new Error("the made bytes end inside a deflate range"); } };
}

/** The made package: bspatch, then the deflate ranges deflated. */
export function apply(h: Header, old: Uint8Array, d: Buffer, sink: Sink, deflate = nodeDeflate): void {
  if (h.deflate.length === 0) return patch(h, old, d, sink);
  const w = deflating(h.deflate, sink, deflate);
  patch(h, old, d, w.write);
  w.end();
}

/** The old blob a delta wants, checked against its size and sha256. */
export function readOld(h: Header, from: { dir: string } | { apk: string }): Buffer {
  let blob: Buffer;
  if ("dir" in from) {
    if (h.inflate.length || h.deflate.length) throw new Error("an apk's delta, given a folder");
    let total = 0;
    for (const f of h.files) {
      const st = lstatSync(join(from.dir, f), { throwIfNoEntry: false });
      if (!st?.isFile()) throw new Error(`the old file ${f} is not there`);
      total += st.size;
    }
    if (total !== h.oldSize) throw new Error(`the old files are ${total} bytes, the delta's old blob ${h.oldSize}`);
    blob = Buffer.concat(h.files.map((f) => readFileSync(join(from.dir, f))));
  } else {
    if (h.files.length) throw new Error("a folder's delta, given an apk");
    const apk = readFileSync(from.apk), parts: Buffer[] = [];
    let p = 0;
    for (const r of h.inflate) {
      if (r.at + r.len > apk.length) throw new Error("the delta's inflate ranges go past the old apk");
      parts.push(apk.subarray(p, r.at));
      try { parts.push(inflateRawSync(apk.subarray(r.at, r.at + r.len), { maxOutputLength: Math.max(1, h.oldSize) })); } catch {
        throw new Error(`the old apk's bytes at ${r.at} do not inflate`);
      }
      p = r.at + r.len;
    }
    parts.push(apk.subarray(p));
    blob = Buffer.concat(parts);
  }
  if (blob.length !== h.oldSize) throw new Error(`the old blob is ${blob.length} bytes, the delta's ${h.oldSize}`);
  if (sha256(blob) !== h.oldSha256) throw new Error("the old blob's sha256 is not the delta's");
  return blob;
}

/** Applies the delta file to what is installed, writing the made package to `out` as it comes; nothing is left on failure. */
export function applyFile(from: { dir: string } | { apk: string }, deltaPath: string, out: string, deflate = nodeDeflate): void {
  const d = readFileSync(deltaPath), h = parseHeader(d), old = readOld(h, from);
  const fd = openSync(out, "w");
  try {
    apply(h, old, d, (b) => { for (let w = 0; w < b.length;) w += writeSync(fd, b, w); }, deflate);
    closeSync(fd);
  } catch (e) {
    closeSync(fd);
    rmSync(out, { force: true });
    throw e;
  }
}
