// What a device type's framebuffer mask says of its panel (screens/sim-mask.ts): paths as iPhone Duo's and iPhone 17 Pro's
// masks have them.
import assert from "node:assert/strict";
import { test } from "node:test";
import { deflateSync } from "node:zlib";
import { panelOf } from "../src/screens/sim-mask.ts";

const pdf = (box: string, path: string, deflate = true) =>
  Buffer.concat([
    Buffer.from(`%PDF-1.3\n<< /Length 1 ${deflate ? "/Filter /FlateDecode " : ""}>>\nstream\n`),
    deflate ? deflateSync(path) : Buffer.from(path),
    Buffer.from(`\nendstream\n<< /Type /Pages /MediaBox [${box}] >>\n`),
  ]);

const round = (w: number, h: number, [tl, tr, br, bl]: number[]) =>
  `${tl} ${h} m ${w - tr!} ${h} l ${w} ${h} ${w} ${h} ${w} ${h - tr!} c ${w} ${br} l ${w} 0 ${w} 0 ${w - br!} 0 c ${bl} 0 l 0 0 0 0 0 ${bl} c 0 ${h - tl!} l h W* n 0 0 ${w} ${h} re f`;

test("a panel's corners, each from its edge, as shares of its width", () => {
  const cover = panelOf(pdf("0 0 466 678", `q Q q ${round(466, 678, [10.25, 75.6, 75.6, 10.25])}`))!;
  assert.deepEqual([cover.width, cover.height], [466, 678]);
  assert.deepEqual(cover.corners, [0.022, 0.1622, 0.1622, 0.022]);
});

test("a clip round the page first is not the shape", () => {
  const clip = "q Q q -3940 3548 m 8304 3548 l 8304 -1476 l -3940 -1476 l h W* n ";
  assert.deepEqual(panelOf(pdf("0 0 2064 2752", clip + round(2064, 2752, [77, 77, 77, 77])))!.corners, [0.0373, 0.0373, 0.0373, 0.0373]);
  const page = "q Q q 0 2622 m 1206 2622 l 1206 0 l 0 0 l h W* n ";
  assert.deepEqual(panelOf(pdf("0 0 1206 2622", page + round(1206, 2622, [254, 254, 254, 254])))!.corners, [0.2106, 0.2106, 0.2106, 0.2106]);
});

test("not compressed is read too, and what is no mask says so", () => {
  assert.deepEqual(panelOf(pdf("0 0 100 200", round(100, 200, [10, 10, 10, 10]), false))!.corners, [0.1, 0.1, 0.1, 0.1]);
  assert.equal(panelOf(Buffer.from("not a pdf")), null);
  assert.equal(panelOf(pdf("0 0 100 200", "q Q")), null);
});
