/// A picture's or a film's size as it is shown, read from the few bytes of it that say rather than by decoding it all:
/// a big screenshot takes a while to decode (and Hermes, the phone's core, decodes nothing), and a message sent
/// meanwhile would show it in a box of another shape. The reading is mediaFacts.ts's, the station's too.
import { exifTurned, facts, headerSize as header, readAsync } from "./mediaFacts.ts";

export type Size = { width: number; height: number };

/// Bytes [start, end) of a file (fewer at its end).
export type Read = (start: number, end: number) => Promise<Uint8Array>;

/// The size `read` (a file of `size` bytes) is shown at; null for any other kind, or one whose bytes do not say.
export async function shownSize(read: Read, size: number): Promise<Size | null> {
  const f = await readAsync(facts(), read, size);
  return f && { width: f.width, height: f.height };
}

/// A PNG's, GIF's or WebP's size, from its first bytes; null for any other kind or a header not understood.
export function headerSize(b: Uint8Array): Size | null {
  return header(b);
}

export { exifTurned };
