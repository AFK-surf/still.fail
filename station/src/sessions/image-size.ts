// A picture's or a film's size as it is shown, from the few bytes of it that say: the core's reading
// (client/core-ts/src/mediaFacts.ts), of a file here or bytes at hand. A film's length and how many frames its picture
// has are read from the same header (shownFacts), so a message carries them and a page shows them before it reads the
// film's head and its end.
import { closeSync, openSync, readSync as readFile } from "node:fs";
import { type Facts, facts, readSync } from "../../../client/core-ts/src/mediaFacts.ts";

export type { Facts };

/// The size the picture or film at `path` is shown at.
export function shownSize(path: string): [number, number] | null {
  const f = shownFacts(path);
  return f && [f.width, f.height];
}

/// What the picture or film at `path` says of itself.
export function shownFacts(path: string): Facts | null {
  try {
    const file = openSync(path, "r");
    try {
      return readSync(facts(), (at, n) => {
        const b = Buffer.alloc(n);
        return b.subarray(0, readFile(file, b, 0, n, at));
      });
    } finally {
      closeSync(file);
    }
  } catch {
    return null;
  }
}

/// The size a picture's or a film's bytes `b` (all of them, or as far as they go) say it is shown at.
export function sizeOf(b: Uint8Array): [number, number] | null {
  const f = readSync(facts(), (at, n) => b.subarray(at, at + n));
  return f && [f.width, f.height];
}
