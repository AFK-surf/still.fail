import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { fadeKeyframes, searchStrokeKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { glass } from "@stillfail/ui/styles/glass.ts";

/** The chat's find bar (ChatFind.tsx): in the page's bar, in place of its buttons while it is open, so it covers
 *  nothing of the chat. Where a page has no such place, over the top right of the list. */
export const bar = style({
  display: "flex", alignItems: "center", gap: "8px", minWidth: "0",
  animation: `${fadeKeyframes} 120ms ${vars.easeOut}`,
  selectors: {
    "&[data-over]": { position: "absolute", top: "12px", right: "24px", zIndex: "6", maxWidth: "calc(100% - 48px)" },
  },
});
export const field = style({
  display: "flex", alignItems: "center", gap: "2px", width: "320px", maxWidth: "100%", minWidth: "0", height: "32px", padding: "0 2px 0 6px",
  borderRadius: "10px", border: `1px solid ${vars.line}`, background: vars.raised,
  selectors: { [`${bar}[data-over] &`]: { ...glass, boxShadow: `0 2px 8px ${vars.shadow}` } },
});
globalStyle("[data-find-slot]:has([data-chat-find]) > :not([data-chat-find])", { display: "none" });
export const input = style({
  flex: "1", minWidth: "0", height: "28px", padding: "0 4px", border: "0", outline: "none", background: "transparent",
  color: vars.text, fontSize: vars.textBody, fontFamily: "inherit",
  selectors: { "&::placeholder": { color: vars.muted } },
});
/** Which of how many: as wide as its figures, so the buttons after it do not shift as it counts. */
export const count = style({ flex: "none", padding: "0 6px", color: vars.muted, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
export const button = style({
  flex: "none", display: "grid", placeItems: "center", width: "26px", height: "26px", padding: "0", border: "0", borderRadius: "7px",
  background: "transparent", color: vars.text, cursor: "pointer",
  selectors: {
    "&:hover:not(:disabled)": { background: vars.hover },
    "&:disabled": { color: vars.muted, opacity: ".5", cursor: "default" },
  },
});
/** Not all the chat was looked in: said before the field. */
export const note = style({ margin: "0", minWidth: "0", color: vars.muted, fontSize: vars.textMeta, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });

/** What was found, marked in the messages drawn as the words a search opened a message for are (global.css.ts
 *  `search-hit` and its hand-drawn strokes): bold by a CSS custom highlight, a stroke under each. The one the reader is
 *  at has its stroke heavier and drawn in; the others' are lighter. */
globalStyle("::highlight(find-hit)", { color: vars.text, textShadow: "0.35px 0 0 currentColor, -0.35px 0 0 currentColor" });
globalStyle("::highlight(find-current)", { color: vars.text, textShadow: "0.5px 0 0 currentColor, -0.5px 0 0 currentColor" });
globalStyle("[data-search-marks][data-find] path", { animation: "none", strokeDashoffset: "0", strokeWidth: "2.5", opacity: ".45" });
globalStyle("[data-search-marks][data-find] svg[data-current] path", { strokeWidth: "4.5", opacity: "1" });
globalStyle("[data-search-marks][data-find] svg[data-current][data-fresh] path", {
  strokeDashoffset: "1", animation: `${searchStrokeKeyframes} 320ms ease-in-out forwards`, animationDelay: "0ms !important",
});
