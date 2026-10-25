import assert from "node:assert/strict";
import { test } from "node:test";
import { headerSize, shownSize } from "../src/imageSize.ts";
import { exif, film, jpeg } from "./media-bytes.ts";

const bytes = (...parts: (string | number[])[]) => new Uint8Array(parts.flatMap((p) => typeof p === "string" ? [...p].map((c) => c.charCodeAt(0)) : p));
const be32 = (n: number) => [n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
const le16 = (n: number) => [n & 255, n >>> 8];

/// The size `b` is shown at, read as a phone's core reads a picked file: a part at a time, counting the parts.
async function shown(b: Uint8Array) {
  let reads = 0;
  const size = await shownSize(async (start, end) => { reads++; return b.slice(start, end); }, b.length);
  return { size, reads };
}

test("an_image_size_is_read_from_its_header", () => {
  assert.deepEqual(headerSize(bytes([0x89], "PNG\r\n\x1a\n", be32(13), "IHDR", be32(2880), be32(1800))), { width: 2880, height: 1800 });
  assert.deepEqual(headerSize(bytes("GIF89a", le16(320), le16(200))), { width: 320, height: 200 });
  // WebP: lossy, lossless and extended.
  assert.deepEqual(headerSize(bytes("RIFF", [0, 0, 0, 0], "WEBPVP8 ", [0, 0, 0, 0], [0, 0, 0], [0x9d, 0x01, 0x2a], le16(640), le16(480))), { width: 640, height: 480 });
  const bits = (100 - 1) | ((50 - 1) << 14);
  assert.deepEqual(headerSize(bytes("RIFF", [0, 0, 0, 0], "WEBPVP8L", [0, 0, 0, 0], [0x2f], [bits & 255, (bits >>> 8) & 255, (bits >>> 16) & 255, bits >>> 24], [0, 0, 0, 0, 0])), { width: 100, height: 50 });
  assert.deepEqual(headerSize(bytes("RIFF", [0, 0, 0, 0], "WEBPVP8X", [0, 0, 0, 0], [0, 0, 0, 0], [999 & 255, 999 >> 8, 0], [499 & 255, 499 >> 8, 0])), { width: 1000, height: 500 });
  // Cut short, or no size: nothing.
  assert.equal(headerSize(bytes([0x89], "PNG\r\n\x1a\n", be32(13), "IHDR")), null);
  assert.equal(headerSize(bytes("GIF89a", le16(0), le16(200))), null);
});

test("a_jpeg_is_shown_at_its_frame_size_turned_as_its_exif_says", async () => {
  // A phone's screenshot, upright: its frame as it is.
  assert.deepEqual((await shown(jpeg(1140, 2616))).size, { width: 1140, height: 2616 });
  // A phone's photo kept on its side (orientation 6, 8: a quarter turn; 3: a half), in either byte order.
  assert.deepEqual((await shown(jpeg(4032, 3024, exif(6, true)))).size, { width: 3024, height: 4032 });
  assert.deepEqual((await shown(jpeg(4032, 3024, exif(8, false)))).size, { width: 3024, height: 4032 });
  assert.deepEqual((await shown(jpeg(4032, 3024, exif(3, true)))).size, { width: 4032, height: 3024 });
  // Its EXIF note with a thumbnail in it, the frame past the first part read: read on to it.
  assert.deepEqual((await shown(jpeg(4032, 3024, exif(6, true, 70_000)))).size, { width: 3024, height: 4032 });
  // No frame before its data: nothing.
  assert.equal((await shown(bytes([0xff, 0xd8, 0xff, 0xe0, 0, 16], "JFIF\0", [1, 1, 0, 0, 1, 0, 1, 0, 0], [0xff, 0xda, 0, 2]))).size, null);
});

test("a_film_is_shown_at_its_picture_track_size_turned_as_its_matrix_says", async () => {
  // A phone's screen recording: its data first, its header at its end, read from there.
  const recording = await shown(film(1140, 2616, { at: "end" }));
  assert.deepEqual(recording.size, { width: 1140, height: 2616 });
  assert.ok(recording.reads <= 3, `${recording.reads} reads`);
  // Recorded on its side, turned a quarter (and three quarters) by its matrix.
  assert.deepEqual((await shown(film(1920, 1080, { turn: 90 }))).size, { width: 1080, height: 1920 });
  assert.deepEqual((await shown(film(1920, 1080, { turn: 270, version: 1 }))).size, { width: 1080, height: 1920 });
  // Its sound track first (0 by 0), then the picture's; a 64-bit data box.
  assert.deepEqual((await shown(film(640, 360, { sound: true, large: true }))).size, { width: 640, height: 360 });
  // Sound alone: nothing.
  assert.equal((await shown(film(0, 0))).size, null);
});
