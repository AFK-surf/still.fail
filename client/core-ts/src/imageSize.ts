/// An image's size as its header says it (PNG, GIF, WebP), read from its first bytes rather than by decoding it all:
/// a big screenshot takes a while to decode, and a message sent meanwhile would show it in a box of another shape.
/// Null for any other kind (a JPEG's orientation lies further in: decoded instead) or a header not understood.
export function headerSize(b: Uint8Array): { width: number; height: number } | null {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const ascii = (at: number, s: string) => b.length >= at + s.length && [...s].every((c, i) => b[at + i] === c.charCodeAt(0));
  const ok = (width: number, height: number) => width > 0 && height > 0 ? { width, height } : null;
  if (b.length >= 24 && b[0] === 0x89 && ascii(1, "PNG") && ascii(12, "IHDR")) return ok(v.getUint32(16), v.getUint32(20));
  if (b.length >= 10 && (ascii(0, "GIF87a") || ascii(0, "GIF89a"))) return ok(v.getUint16(6, true), v.getUint16(8, true));
  if (b.length >= 30 && ascii(0, "RIFF") && ascii(8, "WEBP")) {
    if (ascii(12, "VP8 ") && b[23] === 0x9d && b[24] === 0x01 && b[25] === 0x2a) return ok(v.getUint16(26, true) & 0x3fff, v.getUint16(28, true) & 0x3fff);
    if (ascii(12, "VP8L") && b[20] === 0x2f) {
      const bits = v.getUint32(21, true);
      return ok((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1);
    }
    if (ascii(12, "VP8X")) return ok((b[24]! | (b[25]! << 8) | (b[26]! << 16)) + 1, (b[27]! | (b[28]! << 8) | (b[29]! << 16)) + 1);
  }
  return null;
}
