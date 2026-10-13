// How the reader lays text out on this device (its size, its lines, its face, the paper under it): one value, kept in
// the browser beside the page (a reading habit of this screen, not a setting of the account), read by the reader and
// by its 排版 panel alike.
import { useSyncExternalStore } from "react";

/** The papers: as the app looks (`auto`: the warm page in light, the night one in dark), or one of still.fail's grounds. */
export type Paper = "auto" | "paper" | "white" | "night";
export type Face = "serif" | "sans";

export interface ReaderStyle { size: number; line: number; face: Face; paper: Paper }

export const SIZES = { min: 14, max: 28 } as const;
export const LINES = { min: 1.4, max: 2.2 } as const;
const DEFAULT: ReaderStyle = { size: 18, line: 1.8, face: "serif", paper: "auto" };
const KEY = "stillfail.reader";

function read(): ReaderStyle {
  try {
    const kept = JSON.parse(localStorage.getItem(KEY) ?? "null") as Partial<ReaderStyle> | null;
    if (!kept || typeof kept !== "object") return DEFAULT;
    const size = typeof kept.size === "number" ? Math.min(SIZES.max, Math.max(SIZES.min, Math.round(kept.size))) : DEFAULT.size;
    const line = typeof kept.line === "number" ? Math.min(LINES.max, Math.max(LINES.min, Math.round(kept.line * 10) / 10)) : DEFAULT.line;
    const face = kept.face === "sans" ? "sans" : "serif";
    const paper = (["auto", "paper", "white", "night"] as const).find((p) => p === kept.paper) ?? DEFAULT.paper;
    return { size, line, face, paper };
  } catch {
    return DEFAULT;
  }
}

let current: ReaderStyle | null = null;
const heard = new Set<() => void>();

export function readerStyle(): ReaderStyle {
  return (current ??= typeof localStorage === "undefined" ? DEFAULT : read());
}

export function setReaderStyle(change: Partial<ReaderStyle>): void {
  current = { ...readerStyle(), ...change };
  try { localStorage.setItem(KEY, JSON.stringify(current)); } catch { /* kept for this page only */ }
  for (const h of heard) h();
}

export function useReaderStyle(): ReaderStyle {
  return useSyncExternalStore((h) => { heard.add(h); return () => { heard.delete(h); }; }, readerStyle, readerStyle);
}
