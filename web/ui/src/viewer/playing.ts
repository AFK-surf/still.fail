// What the player (Player.tsx) works out without the page: its times said, its speeds, the folder's others it plays
// through.
import type { ViewerEntry } from "./file.ts";
import { compareNatural } from "./names.ts";

/** The speeds it plays at: slow ones to look closely, fast ones to get through. */
export const SPEEDS = [0.1, 0.25, 0.5, 1, 1.25, 1.5, 2] as const;

/** Seconds as h:mm:ss or m:ss. */
export function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}` : `${m}:${String(r).padStart(2, "0")}`;
}

/** Seconds to the millisecond: h:mm:ss.mmm or m:ss.mmm (a frame's time). */
export function clockMs(seconds: number): string {
  const ms = Math.max(0, Math.round((Number.isFinite(seconds) ? seconds : 0) * 1000));
  const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60;
  const tail = `${String(r).padStart(2, "0")}.${String(ms % 1000).padStart(3, "0")}`;
  return h ? `${h}:${String(m).padStart(2, "0")}:${tail}` : `${m}:${tail}`;
}

/** A speed as it is said: 1×, 0.25×. */
export function speedLabel(speed: number): string {
  return `${speed}×`;
}

/** The folder's others of `kind`, in their names' order: what it plays through. */
export function playlist(siblings: readonly ViewerEntry[], kind: string): ViewerEntry[] {
  return siblings.filter((e) => !e.dir && e.kind === kind).sort((a, b) => compareNatural(a.name, b.name));
}

/** Where a finger along the picture has taken it: from `from`, `dx` of a `width` wide being as much as `span` seconds
 *  (all of it, a short one), within `duration`. */
export function draggedTo(from: number, dx: number, width: number, duration: number, span: number): number {
  const across = Math.min(duration, span);
  return Math.max(0, Math.min(duration, from + (dx / Math.max(1, width)) * across));
}
