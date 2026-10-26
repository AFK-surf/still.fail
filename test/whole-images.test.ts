import assert from "node:assert/strict";
import { test } from "node:test";
import { asPng } from "../web/src/wholeImages.ts";

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 4, 5, 6]);

/** createImageBitmap and OffscreenCanvas as the page has them (Node has neither): what was drawn, and the PNG made of it. */
function drawing(t: { after(fn: () => void): void }): { drawn: unknown[] } {
  const drawn: unknown[] = [];
  const page = globalThis as Record<string, unknown>;
  page.createImageBitmap = async (image: Blob) => ({ image, width: 1600, height: 1000, close() {} });
  page.OffscreenCanvas = class {
    width: number;
    height: number;
    constructor(width: number, height: number) { this.width = width; this.height = height; }
    getContext() { return { drawImage: (bitmap: { image: Blob }) => drawn.push({ image: bitmap.image, width: this.width, height: this.height }) }; }
    convertToBlob(options: { type: string }) { return Promise.resolve(new Blob([PNG], { type: options.type })); }
  };
  t.after(() => { delete page.createImageBitmap; delete page.OffscreenCanvas; });
  return { drawn };
}

const bytes = async (blob: Blob) => new Uint8Array(await blob.arrayBuffer());

test("a PNG is copied as it is", async (t) => {
  const { drawn } = drawing(t);
  assert.deepEqual(await bytes(await asPng(new Blob([PNG]))), PNG);
  assert.deepEqual(drawn, []);
});

test("an image of another kind is drawn again as a PNG, whatever its name said", async (t) => {
  const { drawn } = drawing(t);
  const jpeg = new Blob([JPEG], { type: "image/png" });
  assert.deepEqual(await bytes(await asPng(jpeg)), PNG);
  // Drawn whole: the canvas as big as the image.
  assert.deepEqual(drawn, [{ image: jpeg, width: 1600, height: 1000 }]);
});
