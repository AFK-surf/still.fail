// The faces this device's pages are set in, as the core keeps them (prefs.ts `faces`, client/core-ts/src/fonts.ts):
// each place's family put on the root before the app's own (--font-body, --font-text, --font-mono), the stylesheet of a
// face still.fail keeps added once it is used (its slices are fetched as their characters show). The copy of the
// prefs the page starts from has them too: the first paint is in the faces chosen.
import { useEffect, useState } from "react";
import type { FontFace, FontsView } from "./core/shapes.ts";
import { onPrefs, prefs } from "./prefs.ts";

/** The app's own faces after a chosen one: what it has no character for is drawn as before. */
const BODY = "-apple-system, BlinkMacSystemFont, \"PingFang SC\", \"Hiragino Sans GB\", sans-serif";
const MONO = "ui-monospace, SFMono-Regular, Menlo, monospace";
const VARS = { ui: "--font-body", text: "--font-text", code: "--font-mono" } as const;

const linked = new Set<string>();

/** Its stylesheet in the page, once. */
export function loadFace(face: FontFace): void {
  if (!face.css || linked.has(face.css)) return;
  linked.add(face.css);
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = face.css;
  link.crossOrigin = "anonymous";
  document.head.append(link);
}

/** How a face is written in a style: its family, then the app's own for the place; none (the app's own): null. */
export function familyOf(face: FontFace, code: boolean): string | null {
  if (!face.family) return null;
  return `"${face.family.replace(/["\\]/g, "")}", ${code ? MONO : BODY}`;
}

function apply(faces: FontsView | undefined, textChosen: boolean): void {
  const root = document.documentElement.style;
  for (const place of ["ui", "text", "code"] as const) {
    const face = faces?.[place];
    const family = face ? familyOf(face, place === "code") : null;
    if (face) loadFace(face);
    // Text none chosen is as ui: the stylesheet's own --font-text follows --font-body.
    if (family === null || (place === "text" && !textChosen)) root.removeProperty(VARS[place]);
    else root.setProperty(VARS[place], family);
  }
}

/** The page is set in the faces kept on this device from now on; call once before the first render. */
export function followFonts(): void {
  let last: FontsView | undefined;
  const again = () => {
    const faces = prefs().faces;
    if (faces === last) return;
    last = faces;
    apply(faces, Boolean(prefs().fonts?.text));
  };
  again();
  onPrefs(again);
}

/** Families installed here, where the browser lets a page ask (Chromium's Local Font Access: the desktop app, Chrome,
 * Edge); asked only when its person asks, as the browser asks them first. */
export const canListLocal = typeof window !== "undefined" && "queryLocalFonts" in window;

let local: string[] | null = null;
const localWatchers = new Set<() => void>();

export async function listLocal(): Promise<void> {
  const query = (window as unknown as { queryLocalFonts(): Promise<{ family: string }[]> }).queryLocalFonts;
  const all = await query();
  local = [...new Set(all.map((f) => f.family))].sort((a, b) => a.localeCompare(b));
  for (const f of localWatchers) f();
}

/** The families installed here, once listed; null before. */
export function useLocalFonts(): string[] | null {
  const [, redraw] = useState(0);
  useEffect(() => {
    const f = () => redraw((n) => n + 1);
    localWatchers.add(f);
    return () => { localWatchers.delete(f); };
  }, []);
  return local;
}
