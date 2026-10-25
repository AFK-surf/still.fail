// A station's replies taken apart in the engine the apps run (Hermes, no JIT), as the core takes them apart
// (station/requests.ts `plain`: fzstd's Decompress, a piece at a time as they come off the link): JSON as a station
// sends it (PACKED: agents' replies as a thread's entries, zstd at a reply's level and at a background batch's, given
// as base64 by whoever bundles it), timed. Bundled as the core is and run by Hermes's own command, and by V8 beside it:
// apps/mbui/scripts/core.sh zstd-read.
import { Decompress } from "fzstd";

declare const PACKED: { level: number; plain: number; b64: string }[];
declare const print: (line: string) => void;

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Base64's bytes (no engine here has a decoder of its own to count on).
function bytes(b64: string): Uint8Array {
  const out = new Uint8Array(Math.floor((b64.length * 3) / 4));
  let n = 0;
  let acc = 0;
  let bits = 0;
  for (let i = 0; i < b64.length; i++) {
    const v = ALPHABET.indexOf(b64[i]!);
    if (v < 0) continue;
    acc = ((acc << 6) | v) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[n++] = (acc >> bits) & 0xff;
    }
  }
  return out.subarray(0, n);
}

/// `packed` taken apart again and again for `ms`, `piece` bytes at a time: plain bytes made a second.
function rate(packed: Uint8Array, plain: number, piece: number, ms: number): number {
  const once = () => {
    const d = new Decompress(() => {});
    for (let at = 0; at < packed.length; at += piece) d.push(packed.subarray(at, Math.min(packed.length, at + piece)), at + piece >= packed.length);
  };
  once();
  const t0 = Date.now();
  let rounds = 0;
  while (Date.now() - t0 < ms) {
    once();
    rounds++;
  }
  return Math.round((plain * rounds) / ((Date.now() - t0) / 1000));
}

for (const p of PACKED) {
  const b = bytes(p.b64);
  print(JSON.stringify({ level: p.level, plain: p.plain, packed: b.length, plainBytesPerS: rate(b, p.plain, 16 * 1024, 3000) }));
}
