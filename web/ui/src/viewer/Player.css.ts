import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { VIEWER_BAR } from "./ViewerBar.css.ts";
import { pictureGlass as glass } from "../styles/glass.ts";
import { vvBar } from "./media.css.ts";
import { STILL } from "../styles/still.ts";

/** The player fills its page (the phone's, or the desktop's main pane), in the theme's colours as the chat's video viewer. */
export const player = style({ position: "absolute", inset: "0", userSelect: "none", WebkitUserSelect: "none" });
// One cell the stage's size: the picture's own height must not grow it (a phone's tall recording, cut off in a wide window).
export const stage = style({ position: "absolute", inset: "0", display: "grid", gridTemplate: "minmax(0, 1fr) / minmax(0, 1fr)", placeItems: "center" });
export const media = style({
  display: "block", width: "100%", height: "100%", objectFit: "contain", background: "transparent",
  selectors: { "&[data-audio]": { position: "absolute", inset: "0", opacity: "0" } },
});

/** A song has no picture: its mark and its name. */
export const cover = style({
  display: "grid", justifyItems: "center", gap: "16px", padding: "0 32px", color: vars.muted, textAlign: "center",
});
globalStyle(`${cover} span`, { color: vars.text, fontSize: vars.textTitle, fontWeight: "600", overflowWrap: "anywhere" });

/** The way back and its name, floating at the top as a preview's bar does; it fades with the controls. */
export const head = style({
  ...glass,
  position: "absolute", zIndex: "3", top: "calc(var(--m-top, 0px) + max(12px, var(--safe-top)))", left: "50%", transform: "translateX(-50%)",
  display: "flex", alignItems: "center", gap: "8px", width: "max-content", maxWidth: "min(100% - 24px, 1080px)", height: "44px", boxSizing: "border-box",
  padding: "0 16px 0 6px", borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, color: vars.text,
  opacity: "0", pointerEvents: "none", transition: `opacity 320ms ${vars.easeOut}`,
  selectors: { "&[data-awake]": { opacity: "1", pointerEvents: "auto", transitionDuration: "120ms" }, [`${STILL} &`]: { transition: "none" } },
});
export const name = style({ display: "flex", alignItems: "baseline", gap: "10px", minWidth: "0" });
globalStyle(`${name} b`, { minWidth: "0", fontSize: vars.textBody, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${name} small`, { flex: "none", color: vars.muted, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums" });
/** Play, and the way back: in the text's colour, not the quieter one of the rest. */
export const bright = style({ color: `${vars.text} !important` });

export const note = style({ display: "grid", justifyItems: "center", gap: "14px", padding: "0 32px", color: vars.muted, fontSize: vars.textMeta, textAlign: "center" });
export const noteButton = style({
  display: "inline-flex", alignItems: "center", gap: "6px", height: "36px", padding: "0 16px", border: "0", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 12%, transparent)`, color: vars.text, fontSize: vars.textUi, cursor: "pointer",
});
/** What of it has come while it opens, under the words saying how much (waiting.tsx Progress). */
export const noteBar = style({ width: "220px", maxWidth: "100%" });
/** What of it has come: a lighter band under the played part. */
export const buffered = style({ position: "absolute", top: "0", bottom: "0", background: `color-mix(in srgb, ${vars.text} 22%, transparent)` });
/** A subtitle's lines over the picture: above the controls while they show, lower once they fade. */
export const cue = style({
  position: "absolute", zIndex: "2", left: "50%", transform: "translateX(-50%)", bottom: "calc(var(--m-foot, 0px) + 28px)",
  width: "min(100% - 32px, 900px)", textAlign: "center", pointerEvents: "none", transition: `bottom 240ms ${vars.easeOut}`,
  selectors: { "&[data-awake]": { bottom: "calc(var(--m-foot, 0px) + 112px)" }, [`${STILL} &`]: { transition: "none" } },
});
globalStyle(`${cue} span`, {
  display: "inline", padding: "2px 8px", borderRadius: "6px", background: "rgba(0, 0, 0, .6)", color: "#fff",
  fontSize: vars.textTitle, lineHeight: "1.6", whiteSpace: "pre-line", WebkitBoxDecorationBreak: "clone", boxDecorationBreak: "clone",
});
/** The time: in the controls' row, or over the timeline on a phone. */
export const timeTop = style({
  display: "none", padding: "6px 8px 0", fontFamily: vars.fontMono, fontSize: vars.textCaption, color: vars.muted, fontVariantNumeric: "tabular-nums",
  "@media": { "(max-width: 640px)": { display: "block" } },
});
globalStyle(`${timeTop} b`, { color: vars.text, fontWeight: "600" });
export const timeRow = style({ "@media": { "(max-width: 640px)": { visibility: "hidden" } } });

// ── with a mouse: a desktop's player ──
const BAR = VIEWER_BAR;
const LIST = 320;
const desk = `${player}:not([data-narrow]):not(:fullscreen)`;
// Its bar out of full screen is the one every file opened has (viewer/ViewerBar.tsx).
// Narrow or full screen, its floating bar, awake, takes the pointer over that row (FilePreview.css.ts).
globalStyle(`[data-desktop] ${head}[data-awake]`, { WebkitAppRegion: "no-drag" });
/** The picture under it, clear of the list docked at the right; the controls and a subtitle over the picture's middle. */
// The picture the whole window: the bar over it, gone with the controls as it plays on.
globalStyle(`${desk} ${stage}`, { top: "0" });
globalStyle(`${desk}[data-list] ${stage}`, { right: `${LIST}px` });
globalStyle(`${desk}[data-list] ${vvBar}, ${desk}[data-list] ${cue}`, { left: `calc((100% - ${LIST}px) / 2)`, width: `min(100% - ${LIST + 32}px, 1080px)` });

/** The folder's others, docked at the right under the toolbar. */
export const list = style({
  position: "absolute", zIndex: "3", top: `${BAR}px`, right: "0", bottom: "0", width: `${LIST}px`, display: "flex", flexDirection: "column",
  background: vars.canvas, boxShadow: `inset 1px 0 0 ${vars.line}`, color: vars.text,
});
export const listHead = style({ display: "flex", alignItems: "center", gap: "8px", padding: "12px 10px 6px 18px" });
globalStyle(`${listHead} b`, { fontSize: vars.textTitle, fontWeight: "600" });
globalStyle(`${listHead} small`, { flex: "1", color: vars.muted, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums" });
export const listRows = style({ flex: "1", minHeight: "0", overflowY: "auto", padding: "2px 8px 12px" });
export const listRow = style({
  display: "grid", gridTemplateColumns: "28px minmax(0, 1fr) auto", alignItems: "center", gap: "4px", width: "100%", minHeight: "40px",
  padding: "8px 10px", border: "0", borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none",
  color: vars.text, fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover }, "&[data-current]": { background: vars.selected, fontWeight: "500" } },
});
globalStyle(`${listRow} small`, { color: vars.muted, fontSize: vars.textCaption, fontVariantNumeric: "tabular-nums" });
globalStyle(`${listRow} span`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/** The sound: mute, and a short line to drag. */
export const volume = style({ display: "flex", alignItems: "center", gap: "2px", marginRight: "6px" });
export const volumeLine = style({ position: "relative", width: "72px", height: "22px", display: "grid", alignItems: "center", cursor: "pointer", touchAction: "none", outline: "none" });
export const volumeTrack = style({ position: "relative", display: "block", height: "4px", borderRadius: "2px", overflow: "hidden", background: `color-mix(in srgb, ${vars.text} 20%, transparent)` });
globalStyle(`${volumeTrack} > span`, { position: "absolute", inset: "0", transformOrigin: "left", background: vars.text });
export const volumeHead = style({
  position: "absolute", top: "50%", left: "0", width: "10px", height: "10px", borderRadius: "50%", background: vars.text,
  transform: "translate(-50%, -50%)", boxShadow: "0 1px 4px rgba(0, 0, 0, .35)",
});
/** The time where the pointer is along the timeline, over it. */
export const pointed = style({
  position: "absolute", bottom: "100%", transform: "translateX(-50%)", marginBottom: "4px", padding: "2px 6px", borderRadius: "6px",
  background: "rgba(0, 0, 0, .75)", color: "#fff", fontFamily: vars.fontMono, fontSize: vars.textCaption, fontVariantNumeric: "tabular-nums",
  pointerEvents: "none", whiteSpace: "nowrap",
});
