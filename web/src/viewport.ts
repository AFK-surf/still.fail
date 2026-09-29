// How big a web service's page is laid out in its preview (Preview.tsx): as big as the preview (none chosen), or a
// window of its own size, a phone's or a desktop's, drawn scaled down to fit. Kept per service, in this browser.
import { useSyncExternalStore } from "react";

/** A window `width` wide and `height` high (null: as high as the preview leaves it, at its scale). */
export interface Viewport { width: number; height: number | null }

export const PRESETS: { name: string; width: number; height: number }[] = [
  { name: "手机", width: 390, height: 844 },
  { name: "平板", width: 820, height: 1180 },
  { name: "笔记本", width: 1280, height: 800 },
  { name: "桌面", width: 1440, height: 900 },
];
export const LIMIT = { min: 240, max: 3840 };

/** A web service kept or shown: its station, then its job. */
export const previewKey = (station: string, service: string) => `${station}\n${service}`;

const STORE = "ember.previewViewport.";
const cache = new Map<string, Viewport | null>();
const listeners = new Set<() => void>();

const clamp = (n: number) => Math.round(Math.max(LIMIT.min, Math.min(LIMIT.max, n)));

/** What a preset is called when `v` is one (turned or not). */
export function presetOf(v: Viewport | null): string | null {
  if (!v || v.height === null) return null;
  const found = PRESETS.find((p) => (p.width === v.width && p.height === v.height) || (p.width === v.height && p.height === v.width));
  return found ? found.name : null;
}

export function viewportOf(key: string | undefined): Viewport | null {
  if (!key) return null;
  if (!cache.has(key)) {
    let read: Viewport | null = null;
    try {
      const v = JSON.parse(localStorage.getItem(STORE + key) ?? "null");
      if (v && typeof v.width === "number" && (v.height === null || typeof v.height === "number")) {
        read = { width: clamp(v.width), height: v.height === null ? null : clamp(v.height) };
      }
    } catch { /* as big as the preview */ }
    cache.set(key, read);
  }
  return cache.get(key)!;
}

export function setViewport(key: string, v: Viewport | null): void {
  const next = v && { width: clamp(v.width), height: v.height === null ? null : clamp(v.height) };
  cache.set(key, next);
  if (next) localStorage.setItem(STORE + key, JSON.stringify(next));
  else localStorage.removeItem(STORE + key);
  for (const listener of listeners) listener();
}

export function useViewport(key: string | undefined): Viewport | null {
  return useSyncExternalStore((listener) => { listeners.add(listener); return () => listeners.delete(listener); }, () => viewportOf(key));
}
