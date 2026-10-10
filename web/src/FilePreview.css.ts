import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeInKeyframes } from "./styles/keyframes.css.ts";
import { iconBtn } from "./styles/pages.css.ts";
import { spinner } from "./styles/waiting.css.ts";
import { segmented, segmentedOption } from "./ui.css.ts";
import { btn } from "./styles/controls.css.ts";
import { enrollWait } from "./cloud/settings.css.ts";
import { avatarTile, tokenGuide } from "./pages/SlackApp.css.ts";
import { codeBar, codeBlock, codeShiki } from "./Prose.css.ts";

/** Dark whatever the theme, as a viewer of pictures (images, video): the page's colours, redefined within it. */
export const dark = {
  [vars.canvas]: "#111113", [vars.text]: "#f4f4f5", [vars.muted]: "rgba(255, 255, 255, .6)",
  [vars.subtle]: "rgba(255, 255, 255, .35)", [vars.hover]: "rgba(255, 255, 255, .12)", [vars.selected]: "rgba(255, 255, 255, .16)",
  [vars.line]: "rgba(255, 255, 255, .1)", [vars.accent]: "#f4f4f5",
};
/** Frosted glass over a picture. */
export const glass = {
  background: "rgba(18, 18, 20, .62)", backdropFilter: "blur(24px) saturate(1.6)", WebkitBackdropFilter: "blur(24px) saturate(1.6)",
};
/** The same over a page of the theme's colours (a document). */
const pageGlass = {
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, backdropFilter: "blur(20px) saturate(1.4)",
  WebkitBackdropFilter: "blur(20px) saturate(1.4)",
};

/** A file over the whole window, its bars floating over it (as a video's player): they fade when the pointer rests. */
export const fp = style({
  position: "fixed", inset: "0", zIndex: "61", display: "grid", gridTemplateRows: "minmax(0, 1fr)",
  background: vars.canvas, color: vars.text, outline: "none", animation: `${fadeInKeyframes} 140ms ${vars.easeOut}`,
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
globalStyle(`${fp}[data-kind="image"]`, { vars: dark, background: "#000" });
// The page bars under it drag the desktop window whatever lies over them: without this, the top of its bar takes no pointer.
globalStyle(`[data-desktop] ${fp}`, { WebkitAppRegion: "no-drag" });
/** What floats: shown while the pointer moves, and whenever it or focus is on it (faded, it stays where it is to be clicked). */
const floating = {
  ...pageGlass,
  position: "absolute", zIndex: "3", left: "50%", transform: "translateX(-50%)", display: "flex", alignItems: "center",
  borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, color: vars.text,
  opacity: "0", transition: `opacity 320ms ${vars.easeOut}`,
} as const;
/** One bar at the top, as wide as what it holds: the file's name, its own tools (zoom, source or rendered), how far it has come, download and close. */
export const fpHead = style({
  ...floating,
  top: "max(16px, env(safe-area-inset-top))", width: "max-content", maxWidth: "min(100% - 32px, 1080px)", height: "44px", gap: "12px",
  padding: "0 6px 0 16px",
  "@media": {
    "(max-width: 640px)": { top: "max(8px, env(safe-area-inset-top))", maxWidth: "calc(100% - 16px)", gap: "4px", padding: "0 2px 0 12px" },
    "(prefers-reduced-motion: reduce)": { transition: "none" },
  },
});
globalStyle(`${fp}[data-kind="image"] ${fpHead}`, glass);
globalStyle(`${fp}[data-awake] ${fpHead}, ${fpHead}:hover, ${fpHead}:has(:focus-visible)`, {
  opacity: "1", transitionDuration: "120ms",
});
export const fpHeadProgress = style({
  display: "flex", alignItems: "center", gap: "10px", padding: "0 8px", color: vars.muted, fontSize: vars.textMeta,
  fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
});
globalStyle(`${fpHeadProgress} b`, { color: vars.text, fontWeight: "600" });
export const fpTitle = style({ flex: "0 1 auto", minWidth: "0", display: "flex", alignItems: "baseline", gap: "10px", marginRight: "auto", paddingRight: "12px" });
export const fpName = style({
  margin: "0", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  fontSize: vars.textBody, fontWeight: "600",
});
export const fpMeta = style({
  flex: "none", color: vars.muted, fontSize: vars.textMeta,
  "@media": {
    "(max-width: 640px)": {
      display: "none",
    },
  },
});
export const fpZoom = style({ display: "flex", alignItems: "center", gap: "2px" });
export const fpToolText = style({
  height: "32px", minWidth: "36px", padding: "0 8px", border: "0", borderRadius: `calc(12px * ${vars.cornerScale})`,
  background: "none", color: vars.muted, font: "inherit", fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums",
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
  minWidth: "0", minHeight: "0", overflow: "hidden", display: "grid", gridTemplate: "minmax(0, 1fr) / minmax(0, 1fr)",
  placeItems: "center",
  selectors: {

    [`${fp}[data-kind="pdf"] &`]: { background: `color-mix(in srgb, ${vars.text} 5%, ${vars.canvas})` },
  },
});
globalStyle(`${fpBody} > *`, { gridArea: "1 / 1" });
/** What is shown, in the body's place: moved sideways as one stepping through images slides it. */
export const fpSlide = style({
  position: "relative", minWidth: "0", minHeight: "0", width: "100%", height: "100%", display: "grid", gridTemplate: "minmax(0, 1fr) / minmax(0, 1fr)",
  placeItems: "center",
});
/** An image beside the one shown, a window's width (and a gap) to its side. */
export const fpPeek = style({ position: "absolute", inset: "0", pointerEvents: "none" });
/** Over the image's sides, in the middle: to the one before and after. */
export const fpStep = style({
  gridArea: "1 / 1", alignSelf: "center", zIndex: "1", display: "grid", placeItems: "center", width: "40px", height: "40px",
  margin: "0 16px", border: "0", borderRadius: "50%", padding: "0", cursor: "pointer",
  background: `color-mix(in srgb, ${vars.canvas} 80%, transparent)`, color: vars.text, backdropFilter: "blur(12px)",
  boxShadow: "0 1px 3px rgba(0, 0, 0, .10)", transition: `opacity ${vars.dur} ${vars.easeOut}, background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-side=before]": { justifySelf: "start" },
    "&[data-side=after]": { justifySelf: "end" },
    [`${fp}:not([data-awake]) &:not(:hover):not(:focus-visible)`]: { opacity: "0" },
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
export const fpProgress = style({
  display: "grid", gap: "8px", width: "220px", padding: "12px 14px", borderRadius: `calc(14px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape, background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`,
  WebkitBackdropFilter: "blur(20px)", backdropFilter: "blur(20px)", color: vars.muted, fontSize: vars.textUi,
  fontVariantNumeric: "tabular-nums", textAlign: "center", animation: `${fadeInKeyframes} 200ms ${vars.easeOut}`,
});
export const fpProgressText = style({});
globalStyle(`${fpProgressText} b`, { color: vars.text, fontWeight: "600" });
export const fpProgressTrack = style({
  position: "relative", flex: "none", height: "4px", borderRadius: "999px", overflow: "hidden",
  background: `color-mix(in srgb, ${vars.text} 12%, transparent)`,
});
const sweepKeyframes = keyframes({ from: { transform: "translateX(-100%)" }, to: { transform: "translateX(250%)" } });
export const fpProgressBar = style({
  position: "absolute", left: "0", top: "0", bottom: "0", width: "0", borderRadius: "999px", background: vars.accent,
  transition: `width 200ms ${vars.easeOut}`,
  selectors: {
    "&[data-unknown]": { width: "40%", animation: `${sweepKeyframes} 1.2s ease-in-out infinite` },
  },
});
export const fpAudio = style({ display: "grid", gap: "14px", justifyItems: "center", width: "min(100% - 48px, 480px)" });
export const fpAudioName = style({
  maxWidth: "100%", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textUi,
  color: vars.muted,
});
export const fpFrame = style({ width: "100%", height: "100%", border: "0", background: "#fff" });
export const fpPage = style({ width: "100%", height: "100%", overflow: "auto", overscrollBehavior: "contain" });
/** A page (HTML) starts below the head, as a document's text does: its own top is not under the bar. */
export const fpPageFrame = style({
  overflow: "hidden", display: "grid", paddingTop: "76px",
  "@media": { "(max-width: 640px)": { paddingTop: "60px" } },
});
export const fpMarkdown = style({
  maxWidth: "760px", margin: "0 auto", padding: "84px 32px 96px", fontSize: vars.textBody, lineHeight: "1.75",
  "@media": {
    "(max-width: 640px)": {
      padding: "64px 18px 64px",
    },
  },
});
export const fpCode = style({ padding: "64px 12px 48px", fontSize: vars.textMeta });
export const fpPdf = style({
  display: "grid", justifyItems: "center", alignContent: "start", gap: "20px", padding: "76px 28px 28px",
  selectors: {
    [`${fp}[data-kind="pdf"] &`]: { maxWidth: "1000px", margin: "0 auto" },
  },
  "@media": {
    "(max-width: 640px)": {
      padding: "60px 12px 12px", gap: "12px",
    },
  },
});
export const fpPdfPage = style({
  display: "block", maxWidth: "100%", background: "#fff",
  boxShadow: "0 1px 3px rgba(0, 0, 0, .08), 0 8px 28px rgba(0, 0, 0, .10)",
});
export const fpPlain = style({
  margin: "0", padding: "76px 32px 64px", fontSize: vars.textMeta, lineHeight: "1.65", whiteSpace: "pre-wrap",
  overflowWrap: "anywhere",
  "@media": {
    "(max-width: 640px)": {
      padding: "60px 16px 48px",
    },
  },
});
export const fpCut = style({
  position: "sticky", top: "0", zIndex: "2", padding: "8px 20px", background: vars.amberBg, color: vars.amber,
  fontSize: vars.textMeta,
});
export const fpTableWrap = style({ overflow: "visible", padding: "68px 0 48px" });
export const fpTable = style({
  borderCollapse: "collapse", minWidth: "100%", fontSize: vars.textUi, fontVariantNumeric: "tabular-nums",
});
export const fpRow = style({
  selectors: {
    [`${fpTable} &`]: { width: "1%", paddingLeft: "20px", color: vars.muted, textAlign: "right" },
  },
});
export const fpNote = style({
  display: "grid", justifyItems: "center", gap: "14px", color: vars.muted, fontSize: vars.textUi,
});
globalStyle(`${fpHeadProgress} ${fpProgressTrack}`, { width: "120px" });
globalStyle(`${fpHead} ${segmented}`, {
  width: "120px",
  vars: { "--pad": "2px" },
});
globalStyle(`${fpHead} ${segmentedOption}`, { height: "26px", padding: "0", fontSize: vars.textMeta });
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

/** Room for the widest it says ("15.0 MB / 15.0 MB"), so the bar does not grow as the numbers do. */
globalStyle(`${fpHeadProgress} ${fpProgressText}`, { minWidth: "172px", textAlign: "right" });
