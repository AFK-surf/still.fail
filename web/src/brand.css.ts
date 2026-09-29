import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { buddyHopKeyframes, fadeKeyframes } from "./styles/keyframes.css.ts";
import { list, pageNarrow } from "./styles/pages.css.ts";
import { dialogError, dialogLead, dialogTitle, tooltip } from "./ui.css.ts";
import { newChat } from "./NewChat.css.ts";

export const brandLockup = style({ display: "block" });
export const illus = style({
  display: "block", maxWidth: "100%", height: "auto",
  selectors: {
    [`${newChat} &`]: { marginBottom: "4px" },
  },
  "@media": {
    "(max-height: 640px)": {
      selectors: {
        [`${newChat} &`]: { display: "none" },
      },
    },
  },
});
export const sidebarBuddy = style({
  selectors: {
    "[data-sidebar=\"closed\"] &": { left: "14px" },
    "[data-desktop] &": { top: "8px" },
    "[data-desktop][data-sidebar=\"closed\"] &": { left: "84px" },
  },
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
/** 更新 beside the buddy (the desktop app): left of it on the open sidebar's edge, right of it at rest by the window's buttons. */
export const sidebarUpdate = style({
  position: "fixed", zIndex: "40", top: "18px", left: "calc(var(--sidebar-w, 240px) - 36px)",
  transform: "translateX(-100%)", height: "22px", padding: "0 9px", border: "0", borderRadius: "999px",
  font: "inherit", fontSize: vars.textXs, fontWeight: "500", whiteSpace: "nowrap", background: vars.accentBg,
  color: vars.accentText, cursor: "pointer", WebkitAppRegion: "no-drag",
  selectors: {
    "&:hover:not(:disabled)": { filter: "brightness(.96)" },
    "&:disabled": { cursor: "progress" },
    "[data-sidebar=\"closed\"] &": { left: "50px", transform: "none" },
    "[data-desktop] &": { top: "11px" },
    "[data-desktop][data-sidebar=\"closed\"] &": { left: "120px" },
  },
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
export const brandWordmark = style({
  display: "block",
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
export const brandPhone = style({
  display: "none",
  "@media": {
    "(max-width: 700px)": {
      display: "contents",
    },
  },
});
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
globalStyle(dialogLead, { textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere" });
/** Here rather than with its class: it comes after .illus, and wins over it. */
globalStyle(`${pageNarrow} > *`, { maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
/** Lists stand on spacing, not frames or rules: their rows' text lines up with the page's, a row's ground shows on hover. */
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
globalStyle(list, { listStyle: "none", margin: "0 -12px", padding: "0", display: "grid", gap: "2px" });
/** Why a dialog's action did not work, just above its buttons. */
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
globalStyle(dialogError, { margin: "12px 0 0", fontSize: vars.textSm, color: vars.red, textWrap: "pretty" });
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
globalStyle(tooltip, {
  zIndex: "70", padding: "5px 10px", borderRadius: `calc(8px * ${vars.cornerScale})`, background: vars.primary,
  color: vars.onPrimary, fontSize: vars.textXs, lineHeight: "1.4", boxShadow: `0 4px 12px ${vars.shadow}`,
  animation: `${fadeKeyframes} 120ms ${vars.easeOut}`, cornerShape: vars.cornerShape, width: "max-content",
  maxWidth: "min(300px, calc(100vw - 16px))", textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere",
});
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
globalStyle(dialogTitle, {
  display: "flex", alignItems: "baseline", gap: "10px", margin: "0", fontSize: "20px", fontWeight: "650",
});
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
globalStyle(dialogLead, { margin: "6px 32px 0", fontSize: vars.textSm, color: vars.muted });
globalStyle(`${sidebarBuddy}[data-pose="hop"] img`, { animation: `${buddyHopKeyframes} 380ms ${vars.easeOut}` });
globalStyle(`${sidebarBuddy}[data-pose="hop"] img`, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
