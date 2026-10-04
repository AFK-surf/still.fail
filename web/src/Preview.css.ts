import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { glass } from "./styles/glass.ts";
import { enterUpKeyframes, jobBreatheKeyframes, popKeyframes } from "./styles/keyframes.css.ts";
import { iconBtn } from "./styles/pages.css.ts";
import { msg } from "./styles/conversation.css.ts";
import { enrollWait } from "./cloud/settings.css.ts";
import { sidePanel } from "./pages/ChatPage.css.ts";
import { composerQuote, msgUnsent } from "./Chat.css.ts";
import { hPhaseText } from "./History.css.ts";

/** A web service on the station's machine, in the side panel: where it is, then the page. */
export const preview = style({ flex: "1", minHeight: "0", display: "flex", flexDirection: "column" });
export const previewBar = style({ display: "flex", alignItems: "center", gap: "2px", padding: "6px 8px" });
/** Where it is: one soft capsule, its name then the path to type in. */
export const previewAddress = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "6px", height: "30px", margin: "0 4px",
  padding: "0 12px", borderRadius: "999px", background: vars.neutralBg, color: vars.muted, cursor: "text",
  transition: `background ${vars.dur} ${vars.easeOut}, box-shadow ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:focus-within": { background: vars.canvas, boxShadow: `0 0 0 1.5px ${vars.fieldFocus}` },
  },
});
export const previewHost = style({ fontSize: vars.textSm, fontWeight: "500", color: vars.text, whiteSpace: "nowrap" });
export const previewPage = style({
  position: "fixed", inset: "0", display: "flex", flexDirection: "column", background: vars.canvas,
});
export const previewMissing = style({ alignItems: "center", justifyContent: "center", color: vars.muted });
/** A service starting again: said over its page, which loads anew once it is up. */
export const previewRestart = style({
  position: "absolute", left: "50%", bottom: "18px", transform: "translateX(-50%)", display: "flex",
  alignItems: "center", gap: "12px", padding: "10px 18px 10px 16px", borderRadius: "999px", ...glass,
  boxShadow: `0 8px 24px ${vars.shadow}`, fontSize: vars.textSm, lineHeight: "1.35", whiteSpace: "nowrap",
  animation: `${popKeyframes} 140ms ${vars.easeOut}`,
});
export const previewRestartDot = style({
  width: "8px", height: "8px", borderRadius: "50%", background: vars.amber,
  animation: `${jobBreatheKeyframes} 1.4s ease-in-out infinite`,
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important",
    },
  },
});
export const previewPath = style({
  flex: "1", minWidth: "0", padding: "0", border: "0", background: "none", color: vars.muted, font: "inherit",
  fontSize: vars.textSm,
  selectors: {
    "&:focus": { outline: "none", color: vars.text },
  },
});
export const previewFrame = style({ display: "block", width: "100%", height: "100%", border: "0", background: "#fff" });
globalStyle(`${previewBar} ${iconBtn}`, { width: "28px", height: "28px" });
globalStyle(`${previewBar} ${iconBtn}:disabled`, { opacity: "0.35", cursor: "default", background: "none" });
globalStyle(`${previewAddress} svg`, { flex: "none" });
globalStyle(`${previewRestart} > span:last-child`, { display: "flex", flexDirection: "column" });
globalStyle(`${previewRestart} > span:last-child span`, { fontSize: vars.textXs, color: vars.muted });
/** A message that did not go: faded, with a short note (why is in its tip) and what to do about it, under it. */
/** Here rather than with its class: it comes after .preview-bar .icon-btn:disabled, and wins over it. */
globalStyle(`${msg}[data-unsent] > :not(${msgUnsent})`, { opacity: "0.55" });
/** Here rather than with its class: it comes after .preview-restart-dot, and wins over it. */
globalStyle("[data-enter]", { animation: `${enterUpKeyframes} 220ms ${vars.easeOut} both` });
/** Here rather than with its class: it comes after .preview-restart, and wins over it. */
globalStyle(`[data-enter], ${hPhaseText}, ${composerQuote}, ${sidePanel}`, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
/** Here rather than with its class: it comes after .preview-restart > span:last-child, and wins over it. */
globalStyle(`${enrollWait} > span:last-child`, { display: "grid", gap: "2px", fontSize: vars.textSm });

export const loadRing = style({ color: vars.muted, flex: "none", selectors: { '&[data-failed]': { color: vars.red } } });
export const loadDetails = style({
  zIndex: 1000, width: "min(420px, calc(100vw - 24px))", padding: "14px", borderRadius: vars.rCard,
  ...glass, color: vars.text,
  boxShadow: `0 2px 8px ${vars.shadow}`, fontSize: vars.textSm,
});
export const loadHeading = style({ fontWeight: "500", marginBottom: "4px" });
export const loadHint = style({ color: vars.muted, fontSize: vars.textXs });
export const loadList = style({ maxHeight: "min(320px, 55vh)", overflowY: "auto", marginTop: "10px" });
export const loadRow = style({
  display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto auto", gap: "4px 12px", padding: "5px 0", fontVariantNumeric: "tabular-nums", color: vars.muted,
  selectors: { '&[data-failed]': { color: vars.red } },
});
export const loadPath = style({ overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis", textAlign: "left" });
export const loadError = style({ gridColumn: "1 / -1", overflowWrap: "anywhere", fontSize: vars.textXs });
