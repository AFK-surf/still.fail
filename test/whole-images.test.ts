import assert from "node:assert/strict";
import { test } from "node:test";
import { standIn, wholeImage } from "../web/src/wholeImages.ts";

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

test("a picture that stands in for nothing is the image itself", async () => {
  assert.equal(await wholeImage("blob:app://stillfail/not-a-thumbnail"), null);
});

test("a thumbnail gives the image it stands in for; a PNG as it is", async () => {
  let asked = 0;
  const done = standIn("blob:app://stillfail/thumb-1", async () => { asked++; return new Blob([PNG], { type: "image/png" }); });
  assert.deepEqual(await wholeImage("blob:app://stillfail/thumb-1"), PNG);
  assert.equal(asked, 1);
  // Gone with its picture: it stands in for nothing then.
  done();
  assert.equal(await wholeImage("blob:app://stillfail/thumb-1"), null);
});

test("an image of another kind is drawn again as a PNG, whatever its name said", async (t) => {
  const { drawn } = drawing(t);
  const jpeg = new Blob([JPEG], { type: "image/png" });
  standIn("blob:app://stillfail/thumb-2", async () => jpeg);
  assert.deepEqual(await wholeImage("blob:app://stillfail/thumb-2"), PNG);
  // Drawn whole: the canvas as big as the image.
  assert.deepEqual(drawn, [{ image: jpeg, width: 1600, height: 1000 }]);
});

test("an image that could not be had is not passed off as one", async () => {
  standIn("blob:app://stillfail/thumb-3", () => Promise.reject(new Error("station offline")));
  await assert.rejects(wholeImage("blob:app://stillfail/thumb-3"), /station offline/);
});

test("a picture shown again keeps standing in when the one before it is let go", async () => {
  const first = standIn("blob:app://stillfail/thumb-4", async () => new Blob([PNG]));
  const again = new Uint8Array([...PNG, 9]);
  standIn("blob:app://stillfail/thumb-4", async () => new Blob([again]));
  first();
  assert.deepEqual(await wholeImage("blob:app://stillfail/thumb-4"), again);
});
