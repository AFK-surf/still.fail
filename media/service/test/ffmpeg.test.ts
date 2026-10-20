// Where the service finds ffmpeg and ffprobe (src/ffmpeg.ts): MEDIA_FFMPEG/MEDIA_FFPROBE, else its package's bin/
// (MODULE_BIN_DIR, as the station starts a package), else PATH; null when none is there to run.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { tools } from "../src/ffmpeg.ts";

test("ffmpeg and ffprobe: as set, else the package's bin/, else PATH", (t) => {
  const root = mkdtempSync(join(tmpdir(), "media-ff-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, "bin");
  const path = join(root, "path");
  mkdirSync(bin);
  mkdirSync(path);
  const put = (dir: string, name: string) => writeFileSync(join(dir, name), "#!/bin/sh\n", { mode: 0o755 });
  assert.deepEqual(tools({ PATH: path }), { ffmpeg: null, ffprobe: null });
  put(path, "ffmpeg");
  put(path, "ffprobe");
  assert.deepEqual(tools({ PATH: path, MODULE_BIN_DIR: bin }), { ffmpeg: join(path, "ffmpeg"), ffprobe: join(path, "ffprobe") }, "not in bin/: PATH's");
  put(bin, "ffmpeg");
  put(bin, "ffprobe");
  assert.deepEqual(tools({ PATH: path, MODULE_BIN_DIR: bin }), { ffmpeg: join(bin, "ffmpeg"), ffprobe: join(bin, "ffprobe") });
  const own = join(root, "own-ffmpeg");
  put(root, "own-ffmpeg");
  assert.deepEqual(tools({ PATH: path, MODULE_BIN_DIR: bin, MEDIA_FFMPEG: own }), { ffmpeg: own, ffprobe: join(bin, "ffprobe") });
  assert.equal(tools({ MEDIA_FFMPEG: join(root, "none") }).ffmpeg, null, "a variable naming nothing: none");
});
