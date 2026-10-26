// What waits looks the same everywhere (waiting.tsx; mbui's waiting.mbt draws the same): what will come in its bones,
// breathing, in red what could not be read, a bar for what has a size.
import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { appearKeyframes } from "./styles/keyframes.css.ts";
import { pictureGlass } from "./styles/glass.ts";
import { centred } from "./styles/align.ts";
import { STILL, stillLoop } from "./styles/still.ts";

/** Words about a wait come only when it takes a while: what is there in a moment (from the device) shows none. */
export const LATER_MS = 400;
const later = `${appearKeyframes} 0s linear ${LATER_MS}ms both`;

// 1 → 0.5 and back in 1.4s; still for reduced motion (and still, whole, when what is waited on failed: the red words
// over them say so; faded to 0.6 they were drawn too faint to be seen, docs/ui-panels.md 对比度). A light sweeping over
// them was tried and judged busier (2026-10-17).
const breathe = keyframes({ "0%, 100%": { opacity: 1 }, "50%": { opacity: 0.5 } });

export const wait = style({ position: "relative", display: "flex", flexDirection: "column", minHeight: 0 });
export const fill = style({ flex: "1", minHeight: "100%" });
export const pills = style({ display: "grid", justifyItems: "center", gap: "8px", padding: "14px 20px 4px" });
export const pill = style({
  display: "inline-flex", alignItems: "center", gap: "8px", maxWidth: "100%", boxSizing: "border-box",
  padding: "6px 12px", borderRadius: "999px", background: vars.neutralBg, color: vars.muted,
  fontSize: vars.textMeta, lineHeight: "18px", textAlign: "center", animation: later,
  selectors: { "&[data-error]": { color: vars.red, animation: "none" } },
});
/** Over a picture: frosted, in the middle of what holds it, the pointer going through to it. */
export const pillOver = style({
  ...pictureGlass, position: "absolute", zIndex: "2", ...centred, color: vars.text, whiteSpace: "nowrap", pointerEvents: "none",
});
export const line = style({
  display: "flex", alignItems: "center", gap: "8px", color: vars.muted, fontSize: vars.textMeta, lineHeight: "18px",
  animation: later, selectors: { "&[data-error]": { color: vars.red, animation: "none" } },
});
// Shown only once it has waited (waiting.tsx LaterLine): there at once.
export const lineNow = style({ animation: "none" });
// A page's bones (waiting.tsx Bones, ./bones.ts): what is drawn of made-up data keeps its grounds and edges and none of
// its ink (words, icons, pictures); a ground that says something by its colour, and what is drawn whole, nothing of
// their own; over it the bones, breathing together.
export const bones = style({
  position: "relative", animation: `${breathe} 1.4s ease-in-out infinite`,
  selectors: { "&[data-still]": { animation: "none" }, [`${STILL} &`]: stillLoop() },
});
export const bonesFill = style({ flex: "1", display: "flex", flexDirection: "column", minHeight: 0 });
export const boneBody = style({ selectors: { [`${bonesFill} > &`]: { flex: "1", display: "flex", flexDirection: "column", minHeight: 0 } } });
globalStyle(`${boneBody}, ${boneBody} *`, { color: "transparent !important", textShadow: "none !important", caretColor: "transparent" });
globalStyle(`${boneBody} ::placeholder`, { color: "transparent !important" });
// (unseen, not gone: measured as they are, ./bones.ts)
globalStyle(`${boneBody} :is(img, svg, video, canvas, picture)`, { filter: "opacity(0) !important" });
globalStyle(`${boneBody} [data-bone-ground]`, { background: "transparent !important" });
globalStyle(`${boneBody} [data-bone-whole]`, { background: "transparent !important", borderColor: "transparent !important", boxShadow: "none !important" });
globalStyle(`${boneBody} [data-bone-whole] > *`, { visibility: "hidden" });
export const boneMarks = style({ position: "absolute", inset: 0, pointerEvents: "none" });
// (in the line's grey, as what is drawn with nothing in it: docs/ui-panels.md 对比度)
export const bone = style({ position: "absolute", background: vars.line });

export const track = style({
  position: "relative", display: "block", flex: "none", height: "3px", borderRadius: "999px", overflow: "hidden",
  // (what is empty of it in the line's grey, as what is drawn with nothing in it: seen on any ground, docs/ui-panels.md
  // 对比度; the accent at 18% was 1.2 to 1 on white)
  background: vars.line,
});
const sweep = keyframes({ from: { transform: "translateX(-100%)" }, to: { transform: "translateX(250%)" } });
export const progress = style({
  position: "absolute", inset: "0 auto 0 0", borderRadius: "inherit", background: vars.accent, transition: `width 200ms ${vars.easeOut}`,
  selectors: { "&[data-unknown]": { width: "40%", animation: `${sweep} 1.4s ease-in-out infinite` }, [`${STILL} &[data-unknown]`]: stillLoop({ width: "100%", opacity: 0.35 }) },
});
