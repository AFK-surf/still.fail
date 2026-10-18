// An image's type and size from its first bytes (PNG, JPEG, GIF, WebP; SVG by its text), without decoding it.

export type Sniffed = { type: string; w?: number; h?: number };

const isSvg = (b: Uint8Array) => {
  const head = Buffer.from(b.subarray(0, 512)).toString("utf8").trimStart().toLowerCase();
  return head.startsWith("<svg") || ((head.startsWith("<?xml") || head.startsWith("<!doctype")) && head.includes("<svg"));
};

/// The type by the bytes (else `fallback`, as the book named it), and the width and height when the header gives them.
export function sniff(b: Uint8Array, fallback: string): Sniffed {
  const buf = Buffer.from(b.buffer, b.byteOffset, b.byteLength);
  const has = (n: number) => buf.length >= n;
  if (has(24) && buf.readUInt32BE(0) === 0x89504e47 && buf.toString("latin1", 12, 16) === "IHDR") {
    return { type: "image/png", w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
  }
  if (has(10) && buf.toString("latin1", 0, 4) === "GIF8") return { type: "image/gif", w: buf.readUInt16LE(6), h: buf.readUInt16LE(8) };
  if (has(30) && buf.toString("latin1", 0, 4) === "RIFF" && buf.toString("latin1", 8, 12) === "WEBP") {
    const chunk = buf.toString("latin1", 12, 16);
    if (chunk === "VP8 ") return { type: "image/webp", w: buf.readUInt16LE(26) & 0x3fff, h: buf.readUInt16LE(28) & 0x3fff };
    if (chunk === "VP8L") {
      const bits = buf.readUInt32LE(21);
      return { type: "image/webp", w: (bits & 0x3fff) + 1, h: ((bits >>> 14) & 0x3fff) + 1 };
    }
    if (chunk === "VP8X") return { type: "image/webp", w: 1 + buf.readUIntLE(24, 3), h: 1 + buf.readUIntLE(27, 3) };
    return { type: "image/webp" };
  }
  if (has(4) && buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i + 9 <= buf.length) {
      if (buf[i] !== 0xff) {
        i++;
        continue;
      }
      const m = buf[i + 1];
      if (m === 0xff) {
        i++;
        continue;
      }
      if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) {
        i += 2;
        continue;
      }
      if (m === 0xd9 || m === 0xda) break;
      /// A start of frame (not DHT, JPG, DAC): height, then width.
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return { type: "image/jpeg", h: buf.readUInt16BE(i + 5), w: buf.readUInt16BE(i + 7) };
      i += 2 + buf.readUInt16BE(i + 2);
    }
    return { type: "image/jpeg" };
  }
  if (isSvg(b)) return { type: "image/svg+xml" };
  return { type: fallback || "application/octet-stream" };
}
