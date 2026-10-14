import assert from "node:assert/strict";
import { test } from "node:test";
import { headerSize } from "../src/imageSize.ts";

const bytes = (...parts: (string | number[])[]) => new Uint8Array(parts.flatMap((p) => typeof p === "string" ? [...p].map((c) => c.charCodeAt(0)) : p));
const be32 = (n: number) => [n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
const le16 = (n: number) => [n & 255, n >>> 8];

test("an_image_size_is_read_from_its_header", () => {
  assert.deepEqual(headerSize(bytes([0x89], "PNG\r\n\x1a\n", be32(13), "IHDR", be32(2880), be32(1800))), { width: 2880, height: 1800 });
  assert.deepEqual(headerSize(bytes("GIF89a", le16(320), le16(200))), { width: 320, height: 200 });
  // WebP: lossy, lossless and extended.
  assert.deepEqual(headerSize(bytes("RIFF", [0, 0, 0, 0], "WEBPVP8 ", [0, 0, 0, 0], [0, 0, 0], [0x9d, 0x01, 0x2a], le16(640), le16(480))), { width: 640, height: 480 });
  const bits = (100 - 1) | ((50 - 1) << 14);
  assert.deepEqual(headerSize(bytes("RIFF", [0, 0, 0, 0], "WEBPVP8L", [0, 0, 0, 0], [0x2f], [bits & 255, (bits >>> 8) & 255, (bits >>> 16) & 255, bits >>> 24], [0, 0, 0, 0, 0])), { width: 100, height: 50 });
  assert.deepEqual(headerSize(bytes("RIFF", [0, 0, 0, 0], "WEBPVP8X", [0, 0, 0, 0], [0, 0, 0, 0], [999 & 255, 999 >> 8, 0], [499 & 255, 499 >> 8, 0])), { width: 1000, height: 500 });
  // Not one of these (a JPEG is decoded for its orientation), cut short, or no size: nothing.
  assert.equal(headerSize(bytes([0xff, 0xd8, 0xff, 0xe0], "JFIF")), null);
  assert.equal(headerSize(bytes([0x89], "PNG\r\n\x1a\n", be32(13), "IHDR")), null);
  assert.equal(headerSize(bytes("GIF89a", le16(0), le16(200))), null);
});
