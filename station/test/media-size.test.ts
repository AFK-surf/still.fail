import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { shownSize } from "../src/sessions/image-size.ts";
import { shownSize as coreShown } from "../../client/core-ts/src/imageSize.ts";
import { exif, film, jpeg } from "../../client/core-ts/test/media-bytes.ts";

// A picture's or a film's size as the station reads it from the file, and as the core reads it from the same bytes
// going up: the same, so a message holds the box it was sent in.
test("pictures and films are measured as shown, as the core measures them", async () => {
  const dir = mkdtempSync(join(tmpdir(), "media-size-"));
  const files: [string, Uint8Array, [number, number] | null][] = [
    ["screenshot.jpg", jpeg(1140, 2616), [1140, 2616]],
    ["photo.jpg", jpeg(4032, 3024, exif(6, true)), [3024, 4032]],
    ["photo-mm.jpg", jpeg(4032, 3024, exif(8, false)), [3024, 4032]],
    ["photo-thumb.jpg", jpeg(4032, 3024, exif(6, true, 70_000)), [3024, 4032]],
    ["recording.mp4", film(1140, 2616, { at: "end" }), [1140, 2616]],
    ["sideways.mp4", film(1920, 1080, { turn: 90 }), [1080, 1920]],
    ["sideways-v1.mov", film(1920, 1080, { turn: 270, version: 1 }), [1080, 1920]],
    ["with-sound.mp4", film(640, 360, { sound: true, large: true }), [640, 360]],
    ["sound.m4a", film(0, 0), null],
    ["notes.txt", new TextEncoder().encode("plain text"), null],
  ];
  for (const [name, bytes, want] of files) {
    const path = join(dir, name);
    writeFileSync(path, bytes);
    assert.deepEqual(shownSize(path), want, name);
    const core = await coreShown(async (start, end) => bytes.slice(start, end), bytes.length);
    assert.deepEqual(core && [core.width, core.height], want, `${name} (the core's)`);
  }
});
