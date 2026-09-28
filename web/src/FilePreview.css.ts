import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeInKeyframes } from "./styles/keyframes.css.ts";
import { iconBtn } from "./styles/pages.css.ts";
import { spinner } from "./styles/waiting.css.ts";
import { segmented, segmentedOption } from "./ui.css.ts";
import { btn } from "./styles/controls.css.ts";
import { enrollWait } from "./cloud/settings.css.ts";
import { avatarTile, tokenGuide } from "./pages/SlackApp.css.ts";
import { codeBar, codeBlock, codeShiki } from "./Prose.css.ts";

export const fp = style({
  position: "fixed", inset: "0", zIndex: "61", display: "grid", gridTemplateRows: "auto minmax(0, 1fr)",
  background: vars.canvas, color: vars.text, outline: "none", animation: `${fadeInKeyframes} 140ms ${vars.easeOut}`,
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
export const fpHead = style({
  display: "flex", alignItems: "center", gap: "4px", height: "52px", padding: "0 10px 0 20px",
  paddingTop: "env(safe-area-inset-top)", borderBottom: `1px solid ${vars.line}`,
  "@media": {
    "(max-width: 640px)": {
      height: "48px", padding: "0 4px 0 14px",
    },
  },
});
export const fpTitle = style({ flex: "1", minWidth: "0", display: "flex", alignItems: "baseline", gap: "10px" });
export const fpName = style({
  margin: "0", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  fontSize: vars.textBody, fontWeight: "600",
});
export const fpMeta = style({
  flex: "none", color: vars.muted, fontSize: vars.textXs,
  "@media": {
    "(max-width: 640px)": {
      display: "none",
    },
  },
});
export const fpTools = style({
  flex: "none", display: "flex", alignItems: "center", marginRight: "8px",
  selectors: {
    "&:empty": { display: "none" },
  },
  "@media": {
    "(max-width: 640px)": {
      marginRight: "0",
    },
  },
});
export const fpZoom = style({ display: "flex", alignItems: "center", gap: "2px" });
export const fpToolText = style({
  height: "32px", minWidth: "36px", padding: "0 8px", border: "0", borderRadius: `calc(12px * ${vars.cornerScale})`,
  background: "none", color: vars.muted, font: "inherit", fontSize: vars.textXs, fontVariantNumeric: "tabular-nums",
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
  "@media": {
    "(max-width: 640px)": {
      selectors: {
        [`${fpZoom} &:last-child`]: { display: "none" },
      },
    },
  },
});
export const fpPercent = style({ minWidth: "52px" });
export const fpBody = style({
  minWidth: "0", minHeight: "0", display: "grid", gridTemplate: "minmax(0, 1fr) / minmax(0, 1fr)",
  placeItems: "center",
  selectors: {
    [`${fp}[data-kind="image"] &`]: { background: `color-mix(in oklch, ${vars.text} 5%, ${vars.canvas})` },
    [`${fp}[data-kind="pdf"] &`]: { background: `color-mix(in oklch, ${vars.text} 5%, ${vars.canvas})` },
  },
});
globalStyle(`${fpBody} > *`, { gridArea: "1 / 1" });
/** Over the image's sides, in the middle: to the one before and after. */
export const fpStep = style({
  gridArea: "1 / 1", alignSelf: "center", zIndex: "1", display: "grid", placeItems: "center", width: "40px", height: "40px",
  margin: "0 16px", border: "0", borderRadius: "50%", padding: "0", cursor: "pointer",
  background: `color-mix(in srgb, ${vars.canvas} 80%, transparent)`, color: vars.text, backdropFilter: "blur(12px)",
  boxShadow: "0 1px 3px rgba(0, 0, 0, .10)", transition: `opacity ${vars.dur} ${vars.easeOut}, background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-side=before]": { justifySelf: "start" },
    "&[data-side=after]": { justifySelf: "end" },
    "&:hover:not(:disabled)": { background: vars.canvas },
    "&:disabled": { opacity: "0", pointerEvents: "none" },
  },
  "@media": {
    "(max-width: 640px)": { width: "36px", height: "36px", margin: "0 8px" },
  },
});
export const fpStage = style({
  position: "relative", width: "100%", height: "100%", overflow: "hidden", touchAction: "none", cursor: "zoom-in",
  userSelect: "none",
  selectors: {
    "&[data-zoomed]": { cursor: "zoom-out" },
    "&[data-pan]": { cursor: "grab" },
    "&[data-pan]:active": { cursor: "grabbing" },
  },
});
export const fpImage = style({
  position: "absolute", left: "50%", top: "50%", maxWidth: "none", transformOrigin: "center",
  boxShadow: "0 1px 3px rgba(0, 0, 0, .08), 0 8px 28px rgba(0, 0, 0, .10)", WebkitUserDrag: "none",
});
export const fpAudio = style({ display: "grid", gap: "14px", justifyItems: "center", width: "min(100% - 48px, 480px)" });
export const fpAudioName = style({
  maxWidth: "100%", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textSm,
  color: vars.muted,
});
export const fpFrame = style({ width: "100%", height: "100%", border: "0", background: "#fff" });
export const fpPage = style({ width: "100%", height: "100%", overflow: "auto", overscrollBehavior: "contain" });
export const fpPageFrame = style({ overflow: "hidden", display: "grid" });
export const fpMarkdown = style({
  maxWidth: "760px", margin: "0 auto", padding: "40px 32px 96px", fontSize: vars.textBody, lineHeight: "1.75",
  "@media": {
    "(max-width: 640px)": {
      padding: "24px 18px 64px",
    },
  },
});
export const fpCode = style({ padding: "8px 12px 48px", fontSize: "12.5px" });
export const fpPdf = style({
  display: "grid", justifyItems: "center", alignContent: "start", gap: "20px", padding: "28px",
  selectors: {
    [`${fp}[data-kind="pdf"] &`]: { maxWidth: "1000px", margin: "0 auto" },
  },
  "@media": {
    "(max-width: 640px)": {
      padding: "12px", gap: "12px",
    },
  },
});
export const fpPdfPage = style({
  display: "block", maxWidth: "100%", background: "#fff",
  boxShadow: "0 1px 3px rgba(0, 0, 0, .08), 0 8px 28px rgba(0, 0, 0, .10)",
});
export const fpPlain = style({
  margin: "0", padding: "24px 32px 64px", fontSize: "12.5px", lineHeight: "1.65", whiteSpace: "pre-wrap",
  overflowWrap: "anywhere",
  "@media": {
    "(max-width: 640px)": {
      padding: "16px 16px 48px",
    },
  },
});
export const fpCut = style({
  position: "sticky", top: "0", zIndex: "2", padding: "8px 20px", background: vars.amberBg, color: vars.amber,
  fontSize: vars.textXs,
});
export const fpTableWrap = style({ overflow: "visible", padding: "0 0 48px" });
export const fpTable = style({
  borderCollapse: "collapse", minWidth: "100%", fontSize: vars.textSm, fontVariantNumeric: "tabular-nums",
});
export const fpRow = style({
  selectors: {
    [`${fpTable} &`]: { width: "1%", paddingLeft: "20px", color: vars.muted, textAlign: "right" },
  },
});
export const fpNote = style({
  display: "grid", justifyItems: "center", gap: "14px", color: vars.muted, fontSize: vars.textSm,
});
globalStyle(`${fpTools} ${segmented}`, {
  width: "120px",
  vars: { "--pad": "2px" },
});
globalStyle(`${fpTools} ${segmentedOption}`, { height: "26px", fontSize: vars.textXs });
globalStyle(`${fpZoom} ${iconBtn}:disabled`, { opacity: ".35", cursor: "default", background: "none" });
globalStyle(`${fpAudio} audio`, { width: "100%" });
globalStyle(`${fpCode} ${codeBlock}`, { margin: "0", border: "0", borderRadius: "0", background: "none" });
globalStyle(`${fpCode} ${codeBar}`, { display: "none" });
globalStyle(`${fpCode} pre, ${fpCode} ${codeShiki} pre.shiki`, { padding: "16px 20px", overflow: "visible" });
globalStyle(`${fpTable} th, ${fpTable} td`, {
  padding: "8px 16px", textAlign: "left", whiteSpace: "nowrap", maxWidth: "420px", overflow: "hidden",
  textOverflow: "ellipsis",
});
globalStyle(`${fpTable} th`, {
  position: "sticky", top: "0", background: vars.canvas, fontWeight: "600", boxShadow: `inset 0 -1px 0 ${vars.line}`,
});
globalStyle(`${fpTable} tbody tr:hover`, { background: vars.hover });
globalStyle(`${fpTable} th:first-child`, { width: "1%", paddingLeft: "20px", color: vars.muted, textAlign: "right" });
globalStyle(`${fpTable} td:last-child, ${fpTable} th:last-child`, { width: "100%" });
globalStyle(`${fpNote} ${btn}`, { display: "inline-flex", alignItems: "center", gap: "6px" });
globalStyle(`${fpNote} ${spinner}`, { width: "16px", height: "16px" });
/** Here rather than with its class: it comes after .fp-table th:first-child, and wins over it. */
globalStyle(`${tokenGuide} li > ${btn}`, { marginTop: "6px" });
/** Here rather than with its class: it comes after .fp-table th:first-child, and wins over it. */
globalStyle(`${tokenGuide} li > ${btn}`, { width: "max-content" });
/** Here rather than with its class: it comes after .token-guide li > .btn, and wins over it. */
globalStyle(`${avatarTile} img[data-maker]`, { width: "55%", height: "55%", transform: "none" });
/** Here rather than with its class: it comes after .fp-note .spinner, and wins over it. */
globalStyle(`${enrollWait} ${spinner}`, { width: "18px", height: "18px", borderTopColor: vars.accent });
