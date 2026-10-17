// What waits looks the same everywhere (waiting.tsx; Android ui/Waiting.kt draws the same): placeholders shaped as
// what will come, breathing, in red what could not be read, a bar for what has a size.
import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { appearKeyframes } from "./styles/keyframes.css.ts";
import { pictureGlass } from "./styles/glass.ts";
import { centred } from "./styles/align.ts";

/** Words about a wait come only when it takes a while: what is there in a moment (from the device) shows none. */
export const LATER_MS = 400;
const later = `${appearKeyframes} 0s linear ${LATER_MS}ms both`;

// 1 → 0.5 and back in 1.4s; still for reduced motion (and faded, still, when what is waited on failed). A light
// sweeping over them was tried and judged busier (2026-10-17).
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
export const shapes = style({
  animation: `${breathe} 1.4s ease-in-out infinite`,
  selectors: { "&[data-still]": { animation: "none", opacity: 0.6 } },
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
});
const bar = { display: "block", background: vars.neutralBg, borderRadius: "999px" } as const;
export const row = style({
  display: "flex", alignItems: "center", gap: "12px", height: "66px", padding: "0 16px 0 22px", boxSizing: "border-box",
  selectors: { "&[data-dense]": { height: "40px", padding: "0 10px" } },
});
export const rowLines = style({ flex: "1", display: "grid", gap: "10px", justifyItems: "start", selectors: { [`${row}[data-dense] &`]: { gap: "7px" } } });
export const rowTitle = style({ ...bar, height: "13px", maxWidth: "100%", selectors: { [`${row}[data-dense] &`]: { height: "10px" } } });
export const rowLine = style({ ...bar, height: "10px", maxWidth: "100%", selectors: { [`${row}[data-dense] &`]: { height: "8px" } } });
export const rowPicture = style({ ...bar, width: "22px", height: "22px", borderRadius: "50%", flex: "none", selectors: { [`${row}[data-dense] &`]: { width: "16px", height: "16px" } } });
export const messages = style({ display: "grid", gap: "14px", paddingTop: "8px" });
export const message = style({ display: "flex", gap: "10px", padding: "0 16px", selectors: { "&[data-mine]": { justifyContent: "flex-end" } } });
export const bubble = style({ ...bar, borderRadius: "18px", maxWidth: "70%" }); // own corner: a message bubble's
export const face = style({ ...bar, width: "28px", height: "28px", borderRadius: "50%", flex: "none" });
export const cards = style({ display: "grid", gap: "16px" });
export const card = style({ ...bar, borderRadius: vars.rCard, cornerShape: vars.cornerShape });

export const track = style({
  position: "relative", display: "block", flex: "none", height: "3px", borderRadius: "999px", overflow: "hidden",
  background: `color-mix(in srgb, ${vars.accent} 18%, transparent)`,
});
const sweep = keyframes({ from: { transform: "translateX(-100%)" }, to: { transform: "translateX(250%)" } });
export const progress = style({
  position: "absolute", inset: "0 auto 0 0", borderRadius: "inherit", background: vars.accent, transition: `width 200ms ${vars.easeOut}`,
  selectors: { "&[data-unknown]": { width: "40%", animation: `${sweep} 1.4s ease-in-out infinite` } },
  "@media": { "(prefers-reduced-motion: reduce)": { selectors: { "&[data-unknown]": { animation: "none", width: "100%", opacity: 0.35 } } } },
});
