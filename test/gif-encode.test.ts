import assert from "node:assert/strict";
import { test } from "node:test";
import { gifOf, type GifFrame } from "../web/src/gifEncode.ts";

/** A GIF read back as its frames composed (disposal 1 and 2), each as RGBA, with its delay in ms and the loop count. */
function framesOf(gif: Uint8Array): { side: number; loops: number | null; frames: { pixels: Uint8ClampedArray; delay: number }[] } {
  assert.equal(String.fromCharCode(...gif.subarray(0, 6)), "GIF89a");
  const side = gif[6]! | (gif[7]! << 8);
  assert.equal(gif[10]! & 0x80, 0x80, "a global colour table");
  const size = 2 << (gif[10]! & 7);
  const table = gif.subarray(13, 13 + size * 3);
  let at = 13 + size * 3;
  const canvas = new Uint8ClampedArray(side * side * 4);
  const frames: { pixels: Uint8ClampedArray; delay: number }[] = [];
  let loops: number | null = null, delay = 0, clear = -1, disposal = 0;
  const blocks = () => { const parts: number[] = []; while (gif[at]) { const n = gif[at++]!; parts.push(...gif.subarray(at, at + n)); at += n; } at++; return Uint8Array.from(parts); };
  for (;;) {
    const kind = gif[at++];
    if (kind === 0x3b) break;
    if (kind === 0x21) {
      const label = gif[at++];
      const data = blocks();
      if (label === 0xf9) { disposal = (data[0]! >> 2) & 7; delay = (data[1]! | (data[2]! << 8)) * 10; clear = data[0]! & 1 ? data[3]! : -1; }
      if (label === 0xff && String.fromCharCode(...data.subarray(0, 11)) === "NETSCAPE2.0") loops = data[12]! | (data[13]! << 8);
      continue;
    }
    assert.equal(kind, 0x2c, `a block at ${at - 1}`);
    const [x, y, w, h] = [0, 2, 4, 6].map((o) => gif[at + o]! | (gif[at + o + 1]! << 8));
    at += 9;
    const min = gif[at++]!;
    const indexes = unlzw(blocks(), min, w! * h!);
    for (let i = 0; i < indexes.length; i++) {
      const v = indexes[i]!;
      if (v === clear) continue;
      const p = ((y! + ((i / w!) | 0)) * side + x! + (i % w!)) * 4;
      canvas.set([table[v * 3]!, table[v * 3 + 1]!, table[v * 3 + 2]!, 255], p);
    }
    frames.push({ pixels: canvas.slice(), delay });
    if (disposal === 2) canvas.fill(0);
  }
  return { side, loops, frames };
}

function unlzw(data: Uint8Array, min: number, count: number): number[] {
  const out: number[] = [];
  const clearCode = 1 << min, end = clearCode + 1;
  let size = min + 1, dict: number[][] = [], prev: number[] | null = null, acc = 0, bits = 0, at = 0;
  const reset = () => { dict = Array.from({ length: end + 1 }, (_, i) => [i]); size = min + 1; prev = null; };
  reset();
  for (;;) {
    while (bits < size) { acc |= (data[at++] ?? 0) << bits; bits += 8; }
    const code = acc & ((1 << size) - 1);
    acc >>>= size; bits -= size;
    if (code === clearCode) { reset(); continue; }
    if (code === end) break;
    const entry: number[] = code < dict.length ? dict[code]! : [...prev!, prev![0]!];
    out.push(...entry);
    if (prev) dict.push([...prev, entry[0]!]);
    prev = entry;
    if (dict.length === 1 << size && size < 12) size++;
  }
  assert.equal(out.length, count, "as many pixels as the frame has");
  return out;
}

const SIDE = 16;
/** A frame of one colour, with a square of another at (x, y). */
function frame(bg: [number, number, number], dot: [number, number, number], x: number, y: number, delay = 100): GifFrame {
  const pixels = new Uint8ClampedArray(SIDE * SIDE * 4);
  for (let i = 0; i < SIDE * SIDE; i++) {
    const inDot = i % SIDE >= x && i % SIDE < x + 4 && ((i / SIDE) | 0) >= y && ((i / SIDE) | 0) < y + 4;
    pixels.set([...(inDot ? dot : bg), 255], i * 4);
  }
  return { pixels, delay };
}

test("an animation's frames come back as drawn, looping, each for its own time", () => {
  const frames = [frame([255, 0, 0], [0, 0, 255], 0, 0, 80), frame([255, 0, 0], [0, 0, 255], 6, 3, 120), frame([255, 0, 0], [0, 255, 0], 12, 12, 200)];
  const back = framesOf(gifOf(frames, SIDE));
  assert.equal(back.side, SIDE);
  assert.equal(back.loops, 0, "loops for ever");
  assert.deepEqual(back.frames.map((f) => f.delay), [80, 120, 200]);
  back.frames.forEach((f, i) => assert.deepEqual(f.pixels, frames[i]!.pixels, `frame ${i}`));
});

test("a frame the same as the one before is joined to it, its time added", () => {
  const a = frame([10, 20, 30], [200, 200, 200], 2, 2), b = frame([10, 20, 30], [200, 200, 200], 8, 8);
  const back = framesOf(gifOf([a, { ...a }, b], SIDE));
  assert.deepEqual(back.frames.map((f) => f.delay), [200, 100]);
});

test("clear pixels stay clear, even where an earlier frame had colour", () => {
  const a = frame([0, 0, 0], [255, 255, 0], 0, 0);
  const b = frame([0, 0, 0], [255, 255, 0], 8, 8);
  for (const f of [a, b]) for (let p = 3; p < f.pixels.length; p += 4) if (f.pixels[p - 3] === 0) f.pixels[p] = 0;
  const back = framesOf(gifOf([a, b], SIDE));
  back.frames.forEach((f, i) => {
    for (let p = 0; p < f.pixels.length; p += 4) {
      const want = [a, b][i]!.pixels;
      assert.equal(f.pixels[p + 3], want[p + 3], `frame ${i} pixel ${p / 4}'s alpha`);
    }
  });
});

test("a long animation outgrows LZW's table and still comes back whole", () => {
  const frames: GifFrame[] = [];
  for (let n = 0; n < 4; n++) {
    const pixels = new Uint8ClampedArray(96 * 96 * 4);
    for (let i = 0; i < 96 * 96; i++) pixels.set([(i * 7 + n * 31) & 255, (i * 13) & 255, ((i >> 4) * 5 + n) & 255, 255], i * 4);
    frames.push({ pixels, delay: 50 });
  }
  const back = framesOf(gifOf(frames, 96));
  assert.equal(back.frames.length, 4);
  // More than 255 colours: each pixel is the palette's nearest, within 5 bits a channel of the 255 it has.
  for (const [i, f] of back.frames.entries()) {
    let far = 0;
    for (let p = 0; p < f.pixels.length; p += 4) if (Math.abs(f.pixels[p]! - frames[i]!.pixels[p]!) > 64) far++;
    assert.ok(far < f.pixels.length / 4 / 2, `frame ${i}: ${far} pixels far off`);
  }
});

test("a frame given no time is shown for a tenth of a second, as browsers show such a GIF", () => {
  const back = framesOf(gifOf([frame([0, 0, 0], [9, 9, 9], 0, 0, 0), frame([0, 0, 0], [9, 9, 9], 4, 4, 0)], SIDE));
  assert.deepEqual(back.frames.map((f) => f.delay), [100, 100]);
});
