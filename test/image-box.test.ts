import assert from "node:assert/strict";
import { test } from "node:test";
import { imageBox } from "../web/src/imageBox.ts";

const image = (width: number, height: number) => ({ name: "shot.png", path: "/shot.png", size: 1, width, height });

test("an image keeps its own proportions within 360×300", () => {
  assert.deepEqual(imageBox(image(1200, 800)), { width: 360, aspectRatio: "360 / 240" });
  assert.deepEqual(imageBox(image(100, 600)), { width: 50, aspectRatio: "50 / 300" });
});

test("an image thinner than 40px gets a 40px box and is letterboxed in it, not cropped", () => {
  assert.deepEqual(imageBox(image(701, 60)), { width: 360, aspectRatio: "360 / 40", letterbox: true });
  assert.deepEqual(imageBox(image(20, 600)), { width: 40, aspectRatio: "40 / 300", letterbox: true });
});
