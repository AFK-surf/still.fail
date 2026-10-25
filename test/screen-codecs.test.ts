import assert from "node:assert/strict";
import { test } from "node:test";
import { avcCodec, hvcCodec } from "../web/src/screen/frames.ts";

test("an avcC's codec string: its profile, compatibility and level", () => {
  assert.equal(avcCodec(new Uint8Array([1, 0x42, 0xe0, 0x1f, 0xff])), "avc1.42E01F");
  assert.equal(avcCodec(undefined), "avc1.42E01F");
});

test("an hvcC's codec string: profile, reversed compatibility flags, tier and level, constraints without trailing zeros", () => {
  // Main (1), compatible with Main and Main 10 (bits 1 and 2: 0x60000000), Main tier, level 5.1 (153), progressive
  // source and frame-only constraints (0xB0): as VideoToolbox makes it.
  const main = new Uint8Array([1, 0x01, 0x60, 0, 0, 0, 0xb0, 0, 0, 0, 0, 0, 153, 0xf0]);
  assert.equal(hvcCodec(main), "hvc1.1.6.L153.B0");
  // High tier, Main 10 (2), compatible with Main 10 only (0x20000000), level 4 (120), two constraint bytes.
  const high = new Uint8Array([1, 0x22, 0x20, 0, 0, 0, 0x90, 0x08, 0, 0, 0, 0, 120, 0xf0]);
  assert.equal(hvcCodec(high), "hvc1.2.4.H120.90.8");
  assert.equal(hvcCodec(undefined), "hvc1.1.6.L153.B0");
});
