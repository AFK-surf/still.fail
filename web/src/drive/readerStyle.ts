// How the reader lays text out on this device: the core's `prefs.reader` (client/core-ts/src/prefs.ts readerOf keeps
// each setting within its bounds), read through the page's prefs (../prefs.ts: shown at once, before the core answers),
// changed one setting at a time (`prefs.set {reader: {size: 19}}`).
import type { ReaderPaper, ReaderPrefs } from "../core/shapes.ts";
import { prefs, setPrefs, usePrefs, type PrefsPatch } from "../prefs.ts";

export type { ReaderPaper as Paper };
export type ReaderStyle = ReaderPrefs;

export const SIZES = { min: 12, max: 32 } as const;
export const LINES = { min: 1.2, max: 2.4 } as const;
export const MARGINS = { min: 8, max: 44 } as const;

export function useReaderStyle(): ReaderPrefs {
  return usePrefs((p) => p.reader);
}

/** One setting (or a few) changed; the rest as they are. */
export function setReaderStyle(change: Partial<ReaderPrefs>): void {
  setPrefs({ reader: change } as PrefsPatch);
}

/** The prefs now (outside a render). */
export const readerNow = () => prefs().reader;
