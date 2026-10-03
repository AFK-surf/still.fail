import assert from "node:assert/strict";
import { test } from "node:test";
import { imageBox } from "../web/src/imageBox.ts";

const image = (width: number, height: number) => ({ name: "shot.png", path: "/shot.png", size: 1, width, height });

test("an image keeps its own proportions within 360×300, however flat", () => {
  assert.deepEqual(imageBox(image(1200, 800)), { width: 360, aspectRatio: "360 / 240" });
  assert.deepEqual(imageBox(image(100, 600)), { width: 50, aspectRatio: "50 / 300" });
  assert.deepEqual(imageBox(image(701, 60)), { width: 360, aspectRatio: "360 / 31" });
});

test("a tiny image is drawn up to 40px on its longer side, its proportions kept", () => {
  assert.deepEqual(imageBox(image(10, 10)), { width: 40, aspectRatio: "40 / 40" });
  assert.deepEqual(imageBox(image(30, 20)), { width: 40, aspectRatio: "40 / 27" });
});

test("a strip thinner than 16px gets a 16px box and is letterboxed in it, not cropped", () => {
  assert.deepEqual(imageBox(image(2000, 40)), { width: 360, aspectRatio: "360 / 16", letterbox: true });
  assert.deepEqual(imageBox(image(10, 600)), { width: 16, aspectRatio: "16 / 300", letterbox: true });
});
