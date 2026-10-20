// What photos and videos say of themselves (src/exif.ts, photometa.ts, thumbhash.ts): EXIF in a JPEG (either byte
// order), a HEIC's Exif item past the first megabyte and its turned ispe, an MP4's mvhd and turned tkhd with the moov
// at the end, PNG/GIF sizes, what is not a photo; a ThumbHash from a BMP.
process.env.TZ = "Asia/Shanghai";
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseTiff, timeOf } from "../src/exif.ts";
import { type Source, HEAD, kindOf, metaOf } from "../src/photometa.ts";
import { readBmp, thumbHash } from "../src/thumbhash.ts";
import { PHONE_EXIF, bmp, exifJpeg, gif, heic, mp4, png, tiff } from "./helpers.ts";

/// A file in memory as the indexer reads it, counting the reads past the head.
function source(b: Buffer) {
  const reads: [number, number][] = [];
  const src: Source = {
    size: b.length,
    head: b.subarray(0, HEAD),
    read: async (offset, length) => {
      reads.push([offset, length]);
      return b.subarray(offset, offset + length);
    },
  };
  return { src, reads };
}

const TOKYO = { taken: Date.UTC(2024, 4, 1, 1, 20, 30), camera: "Apple iPhone 15 Pro", lens: "iPhone 15 Pro back camera 6.86mm f/1.78", gps: { lat: 35.6582, lon: 139.741733 } };

test("kinds by name", () => {
  assert.deepEqual(["a.JPG", "b.jpeg", "c.png", "d.HEIC", "e.heif", "f.webp", "g.gif", "h.mp4", "i.MOV", "j.m4v", "k.txt", "l", "m.avi"].map(kindOf), [
    "photo", "photo", "photo", "photo", "photo", "photo", "photo", "video", "video", "video", null, null, null,
  ]);
});

test("EXIF time: with its offset, else the station's local time; sub-seconds", () => {
  assert.equal(timeOf("2024:05:01 10:20:30", "+09:00"), Date.UTC(2024, 4, 1, 1, 20, 30));
  assert.equal(timeOf("2024:05:01 10:20:30", "-05:30", "25"), Date.UTC(2024, 4, 1, 15, 50, 30, 250));
  assert.equal(timeOf("2024:05:01 10:20:30"), Date.UTC(2024, 4, 1, 2, 20, 30));
  assert.equal(timeOf("0000:00:00 00:00:00"), undefined);
  assert.equal(timeOf("    :  :     :  :  "), undefined);
});

test("a JPEG's EXIF, big- and little-endian: time, turn (width and height swapped), camera, lens, GPS", async () => {
  for (const le of [false, true]) {
    const meta = await metaOf(source(exifJpeg(4032, 3024, PHONE_EXIF(le))).src);
    assert.deepEqual(meta, { ...TOKYO, w: 3024, h: 4032 }, le ? "II" : "MM");
  }
  // Not turned, Make repeated in Model, south and west.
  const exif = tiff([[0x010f, 2, "Canon"], [0x0110, 2, "Canon EOS R5"], [0x0112, 3, [1]]], [[0x9003, 2, "2020:01:02 03:04:05"]], [[1, 2, "S"], [2, 5, [33, 1, 52, 1, 0, 1]], [3, 2, "W"], [4, 5, [70, 1, 30, 1, 0, 1]]]);
  assert.deepEqual(await metaOf(source(exifJpeg(600, 400, exif)).src), { taken: new Date(2020, 0, 2, 3, 4, 5).getTime(), camera: "Canon EOS R5", gps: { lat: -33.866667, lon: -70.5 }, w: 600, h: 400 });
  assert.deepEqual(parseTiff(Buffer.from("not a tiff")), {});
});

test("a HEIC: the Exif item read where iloc says (past the first megabyte), the size from ispe turned by irot", async () => {
  const file = heic(4032, 3024, PHONE_EXIF(), 1_200_000);
  const { src, reads } = source(file);
  assert.deepEqual(await metaOf(src), { ...TOKYO, w: 3024, h: 4032 });
  assert.equal(reads.length, 1, "the Exif item read on its own");
  // Not turned (irot 0): as coded, whatever the EXIF says.
  assert.deepEqual(await metaOf(source(heic(4032, 3024, PHONE_EXIF(), 0, 0)).src), { ...TOKYO, w: 4032, h: 3024 });
});

test("an MP4: mvhd's time and duration, the video track's size turned by its matrix; the moov after the media found", async () => {
  const made = Date.UTC(2022, 5, 15, 8, 0, 0);
  assert.deepEqual(await metaOf(source(mp4(made, 12.5, 1920, 1080)).src), { taken: made, duration: 12.5, w: 1080, h: 1920 });
  const { src, reads } = source(mp4(made, 3, 1280, 720, 1_500_000));
  assert.deepEqual(await metaOf(src), { taken: made, duration: 3, w: 720, h: 1280 });
  assert.ok(reads.length >= 2, "the box headers past the head, then the moov");
});

test("PNG, GIF sizes; what is no photo says nothing", async () => {
  assert.deepEqual(await metaOf(source(png(10, 20)).src), { w: 10, h: 20 });
  assert.deepEqual(await metaOf(source(gif(3, 5)).src), { w: 3, h: 5 });
  assert.deepEqual(await metaOf(source(Buffer.from("hello")).src), {});
  assert.deepEqual(await metaOf(source(Buffer.from([0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff])).src), {});
});

test("a ThumbHash from a BMP: white and black as their luminance, landscape said", () => {
  const white = readBmp(bmp(8, 4, [255, 255, 255]))!;
  assert.deepEqual([white.w, white.h, [...white.rgba.subarray(0, 4)]], [8, 4, [255, 255, 255, 255]]);
  const w = Buffer.from(thumbHash(white.w, white.h, white.rgba), "base64");
  assert.equal(w[0]! & 63, 63);
  assert.equal(w[4]! >> 7, 1, "landscape");
  const black = readBmp(bmp(4, 8, [0, 0, 0]))!;
  const b = Buffer.from(thumbHash(black.w, black.h, black.rgba), "base64");
  assert.equal(b[0]! & 63, 0);
  assert.equal(b[4]! >> 7, 0);
  assert.equal(readBmp(Buffer.from("BMnope")), null);
  assert.throws(() => thumbHash(101, 1, new Uint8Array(404)));
});
