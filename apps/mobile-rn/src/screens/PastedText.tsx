// A long paste goes with the message as a text file, not into the composer (web/src/pastedText.ts): the field stays
// quick, and the agent reads it whole from the file.
import { Picked } from "./Composer";

/** Pasted at once, this many characters or more go as a file. */
export const PASTE_THRESHOLD = 5_000;
/** A file of pasted text this long at most can be put back into the composer. */
export const PASTE_RESTORE_LIMIT = 25_000;

/** Text pasted as a file: its first line (of its first 200 characters), how long, and itself. */
export class PastedText {
  readonly preview: string;
  constructor(readonly text: string) {
    this.preview = text.slice(0, 200).trim().split(/\r?\n/)[0] ?? "";
  }
  get characters(): number { return this.text.length; }
  /** It can be put back into the composer (not too long for it). */
  get restorable(): boolean { return this.text.length <= PASTE_RESTORE_LIMIT; }
}

/** A random UUID, as java.util.UUID.randomUUID() writes one. */
function uuid(): string {
  const b = new Uint8Array(16);
  const c = (globalThis as { crypto?: { getRandomValues?: (a: Uint8Array) => Uint8Array } }).crypto;
  if (c?.getRandomValues) c.getRandomValues(b);
  else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
  b[6] = (b[6]! & 0x0f) | 0x40;
  b[8] = (b[8]! & 0x3f) | 0x80;
  const h = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** The text in UTF-8. */
export function utf8(text: string): Uint8Array {
  return new TextEncoder().encode(text);
}

/** The file it goes as: `pasted-text-<uuid>.txt`, in UTF-8, as the web names it. */
export function pastedPicked(pasted: PastedText): Picked {
  return new Picked(`pasted-text-${uuid()}.txt`, utf8(pasted.text), null, null, null);
}
