// An image's pixel size from its first bytes: PNG, GIF, JPEG and WebP, the
// formats pages show inline. Nothing is decoded; unknown files give null.
import { closeSync, openSync, readSync } from "node:fs";

export function imageSize(path: string): { width: number; height: number } | null {
  const fd = openSync(path, "r");
  try {
    const head = Buffer.alloc(64 * 1024);
    const n = readSync(fd, head, 0, head.length, 0);
    return sizeOf(head.subarray(0, n));
  } finally {
    closeSync(fd);
  }
}

export function sizeOf(b: Buffer): { width: number; height: number } | null {
  const ok = (width: number, height: number) => (width > 0 && height > 0 ? { width, height } : null);
  if (b.length >= 24 && b.readUInt32BE(0) === 0x89504e47 && b.toString("ascii", 12, 16) === "IHDR") return ok(b.readUInt32BE(16), b.readUInt32BE(20));
  if (b.length >= 10 && b.toString("ascii", 0, 3) === "GIF") return ok(b.readUInt16LE(6), b.readUInt16LE(8));
  if (b.length >= 30 && b.toString("ascii", 0, 4) === "RIFF" && b.toString("ascii", 8, 12) === "WEBP") {
    const chunk = b.toString("ascii", 12, 16);
    if (chunk === "VP8 ") return ok(b.readUInt16LE(26) & 0x3fff, b.readUInt16LE(28) & 0x3fff);
    if (chunk === "VP8L") { const v = b.readUInt32LE(21); return ok((v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1); }
    if (chunk === "VP8X") return ok(1 + b.readUIntLE(24, 3), 1 + b.readUIntLE(27, 3));
    return null;
  }
  if (b.length >= 4 && b[0] === 0xff && b[1] === 0xd8) {
    // Walk the markers to the first start-of-frame, which carries the size.
    let i = 2;
    while (i + 9 < b.length) {
      if (b[i] !== 0xff) { i++; continue; }
      const marker = b[i + 1]!;
      if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { i += 2; continue; }
      const length = b.readUInt16BE(i + 2);
      if ((marker >= 0xc0 && marker <= 0xcf) && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) return ok(b.readUInt16BE(i + 7), b.readUInt16BE(i + 5));
      i += 2 + length;
    }
  }
  return null;
}
