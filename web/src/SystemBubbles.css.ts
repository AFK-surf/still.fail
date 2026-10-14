// The app's own bubbles (SystemBubbles.tsx): at the page's bottom left, beside the rail (none on a narrow screen: the
// window's edge), the newest lowest, each rising in.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { panel } from "./styles/glass.ts";
import { toastInKeyframes } from "./styles/keyframes.css.ts";

export const stack = style({
  position: "fixed", zIndex: 150, left: "calc(env(safe-area-inset-left, 0px) + 12px)", bottom: "calc(env(safe-area-inset-bottom, 0px) + 12px)",
  display: "flex", flexDirection: "column", alignItems: "flex-start", gap: 8, maxWidth: "min(420px, calc(100vw - 24px))",
  pointerEvents: "none",
  "@media": { "(min-width: 701px)": { selectors: { ":root:has([data-rail]) &": { left: 68 } } } },
});
export const bubble = style({
  ...panel, display: "flex", alignItems: "center", gap: 10, maxWidth: "100%", padding: "6px 6px 6px 14px",
  // Its corner its pills' (14) and its padding (6): concentric, a capsule's ends.
  borderRadius: 20, boxShadow: `0 8px 24px ${vars.shadow}`,
  color: vars.text, fontSize: vars.textUi, lineHeight: "20px", pointerEvents: "auto",
  animation: `${toastInKeyframes} 220ms ${vars.easeOut}`,
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
});
export const icon = style({ display: "grid", placeItems: "center", flex: "none", color: vars.accent });
export const text = style({ display: "flex", flexDirection: "column", minWidth: 0, padding: "4px 0" });
export const line = style({ color: vars.muted, fontSize: vars.textMeta, lineHeight: "18px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** Its one thing to do: a small filled pill, as the page's primary buttons are. */
export const action = style({
  flex: "none", height: 28, padding: "0 12px", border: 0, borderRadius: 999, background: vars.primary, color: vars.onPrimary,
  font: "inherit", fontWeight: 500, lineHeight: "28px", textDecoration: "none", whiteSpace: "nowrap", cursor: "pointer",
  selectors: { "&:hover": { background: vars.primaryHover } },
});
export const close = style({
  display: "grid", placeItems: "center", flex: "none", width: 28, height: 28, padding: 0, border: 0, borderRadius: "50%",
  background: "none", color: vars.muted, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
