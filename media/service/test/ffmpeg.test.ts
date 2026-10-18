// Where the service finds ffmpeg and ffprobe (src/ffmpeg.ts): MEDIA_FFMPEG/MEDIA_FFPROBE, else its package's bin/
// (MODULE_BIN_DIR, as the station starts a package), else PATH.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { tools } from "../src/ffmpeg.ts";

test("ffmpeg and ffprobe: as set, else the package's bin/, else PATH", (t) => {
  const bin = join(mkdtempSync(join(tmpdir(), "media-ff-")), "bin");
  t.after(() => rmSync(join(bin, ".."), { recursive: true, force: true }));
  mkdirSync(bin);
  assert.deepEqual(tools({}), { ffmpeg: "ffmpeg", ffprobe: "ffprobe" });
  assert.deepEqual(tools({ MODULE_BIN_DIR: bin }), { ffmpeg: "ffmpeg", ffprobe: "ffprobe" }, "not there: PATH's");
  writeFileSync(join(bin, "ffmpeg"), "");
  writeFileSync(join(bin, "ffprobe"), "");
  assert.deepEqual(tools({ MODULE_BIN_DIR: bin }), { ffmpeg: join(bin, "ffmpeg"), ffprobe: join(bin, "ffprobe") });
  assert.deepEqual(tools({ MODULE_BIN_DIR: bin, MEDIA_FFMPEG: "/opt/ff/ffmpeg" }), { ffmpeg: "/opt/ff/ffmpeg", ffprobe: join(bin, "ffprobe") });
});
