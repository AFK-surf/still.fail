// Reading a zip held in memory (an EPUB): its central directory, then an entry's bytes, stored or deflated. Zip64's
// sizes and offsets are read; encrypted entries and other methods are refused.
import { inflateRawSync } from "node:zlib";

export type ZipEntry = { name: string; method: number; flags: number; packed: number; size: number; at: number };

export class ZipError extends Error {}

/// The entries by name. Throws ZipError when `buf` is not a zip this can read.
export function readZip(buf: Buffer): Map<string, ZipEntry> {
  let end = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 0xffff); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) throw new ZipError("no end of central directory");
  let count = buf.readUInt16LE(end + 10);
  let start = buf.readUInt32LE(end + 16);
  if (start === 0xffffffff || count === 0xffff) {
    /// Zip64: the locator just before, naming the zip64 end record.
    const loc = end - 20;
    if (loc < 0 || buf.readUInt32LE(loc) !== 0x07064b50) throw new ZipError("no zip64 locator");
    const at = Number(buf.readBigUInt64LE(loc + 8));
    if (at + 56 > buf.length || buf.readUInt32LE(at) !== 0x06064b50) throw new ZipError("no zip64 end record");
    count = Number(buf.readBigUInt64LE(at + 32));
    start = Number(buf.readBigUInt64LE(at + 48));
  }
  const entries = new Map<string, ZipEntry>();
  let p = start;
  for (let n = 0; n < count; n++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) throw new ZipError("bad central directory");
    const flags = buf.readUInt16LE(p + 8);
    const method = buf.readUInt16LE(p + 10);
    let packed = buf.readUInt32LE(p + 20);
    let size = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    let at = buf.readUInt32LE(p + 42);
    const name = buf.subarray(p + 46, p + 46 + nameLen).toString("utf8");
    /// Zip64's extra field: the values that did not fit, in this order.
    let x = p + 46 + nameLen;
    const xEnd = x + extraLen;
    while (x + 4 <= xEnd) {
      const id = buf.readUInt16LE(x);
      const len = buf.readUInt16LE(x + 2);
      if (id === 0x0001) {
        let q = x + 4;
        const next = () => {
          const v = q + 8 <= x + 4 + len ? Number(buf.readBigUInt64LE(q)) : 0xffffffff;
          q += 8;
          return v;
        };
        if (size === 0xffffffff) size = next();
        if (packed === 0xffffffff) packed = next();
        if (at === 0xffffffff) at = next();
      }
      x += 4 + len;
    }
    if (!name.endsWith("/")) entries.set(name, { name, method, flags, packed, size, at });
    p = xEnd + commentLen;
  }
  return entries;
}

/// An entry's bytes.
export function unzip(buf: Buffer, e: ZipEntry): Buffer {
  if (e.flags & 1) throw new ZipError(`${e.name} is encrypted`);
  if (e.at + 30 > buf.length || buf.readUInt32LE(e.at) !== 0x04034b50) throw new ZipError(`bad local header for ${e.name}`);
  const data = e.at + 30 + buf.readUInt16LE(e.at + 26) + buf.readUInt16LE(e.at + 28);
  const packed = buf.subarray(data, data + e.packed);
  if (packed.length < e.packed) throw new ZipError(`${e.name} is cut short`);
  if (e.method === 0) return packed;
  if (e.method === 8) {
    try {
      return inflateRawSync(packed, { maxOutputLength: Math.max(e.size, 1) });
    } catch (err) {
      throw new ZipError(`${e.name}: ${(err as Error).message}`);
    }
  }
  throw new ZipError(`${e.name}: method ${e.method}`);
}
