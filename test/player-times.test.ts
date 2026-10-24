// What the player works out without a page (web/ui/src/viewer/playing.ts, frames.ts): its times said, the frame showing
// at a time, a file's rate, the folder's others it plays through, where a finger along the picture takes it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { clock, clockMs, draggedTo, playlist, speedLabel, SPEEDS } from "../web/ui/src/viewer/playing.ts";
import { frameAt, rateOf } from "../web/ui/src/viewer/frames.ts";
import type { ViewerEntry } from "../web/ui/src/viewer/file.ts";

const entry = (name: string, kind: string, dir = false): ViewerEntry => ({ name, size: 1, mtime: 0, type: "", kind, dir });

test("the time of how long in whole seconds; a frame's to the millisecond; an hour's with its hours", () => {
  assert.equal(clock(312.9), "5:12");
  assert.equal(clock(3725), "1:02:05");
  assert.equal(clock(Number.NaN), "0:00");
  assert.equal(clockMs(312.0004), "5:12.000");
  assert.equal(clockMs(0.0166667), "0:00.017");
  assert.equal(clockMs(3725.5), "1:02:05.500");
});

test("the frame showing at a time is the last to start by then, a frame's own start included", () => {
  const starts = [0, 0.1, 0.2, 0.3];
  assert.equal(frameAt(starts, 0), 0);
  assert.equal(frameAt(starts, 0.15), 1);
  assert.equal(frameAt(starts, 0.2), 2);
  assert.equal(frameAt(starts, 9), 3);
  assert.equal(frameAt(starts, -1), 0);
});

test("a steady file's rate; a screen recording's frames that come when something changes are said to vary", () => {
  const steady = rateOf([0, 1 / 30, 2 / 30, 3 / 30]);
  assert.ok(Math.abs(steady.fps - 30) < 1e-6 && steady.steady);
  const uneven = rateOf([0, 0.1, 0.2, 1.5, 1.6]);
  assert.equal(uneven.steady, false);
  assert.deepEqual(rateOf([0]), { fps: 0, steady: true });
});

test("its playlist is the folder's others of its kind, in their names' number order; no folders", () => {
  const folder = [entry("第10集.mp4", "video"), entry("片尾曲.m4a", "audio"), entry("第2集.mp4", "video"), entry("花絮", "video", true), entry("第01集.mp4", "video")];
  assert.deepEqual(playlist(folder, "video").map((e) => e.name), ["第01集.mp4", "第2集.mp4", "第10集.mp4"]);
  assert.deepEqual(playlist(folder, "audio").map((e) => e.name), ["片尾曲.m4a"]);
});

test("a finger across the whole picture moves through two minutes, or all of a shorter one, within its length", () => {
  assert.equal(draggedTo(60, 195, 390, 3600, 120), 120);
  assert.equal(draggedTo(5, 390, 390, 20, 120), 20);
  assert.equal(draggedTo(5, -390, 390, 20, 120), 0);
});

test("the speeds run from a tenth to twice, said as figures", () => {
  assert.equal(SPEEDS[0], 0.1);
  assert.equal(SPEEDS.at(-1), 2);
  assert.equal(speedLabel(0.25), "0.25×");
  assert.equal(speedLabel(1), "1×");
});
