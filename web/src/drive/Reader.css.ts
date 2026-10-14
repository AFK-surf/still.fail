import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { panel as panelGround } from "../styles/glass.ts";

/**
 * The papers, of still.fail's own grounds: the phone's warm page and its night (mobile/styles/root.css.ts), the desktop's
 * white canvas. Each sets the reader's ink, the bars' raised ground and the accent on it.
 */
const light = { "--r-ink": "#24272B", "--r-muted": "#7A7D83", "--r-line": "#E7E3DC", "--r-accent": "#E5704A" };
/** The papers, of still.fail's grounds: white the phone's warm page, 护眼 its green as a tint of it, 浅灰 its ink as one,
 *  night its dark page; the bars on each the raised ground over it. */
export const PAPER_BG = {
  white: "#F5F3EF",
  green: "color-mix(in srgb, #2F8F5B 13%, #F5F3EF)",
  grey: "color-mix(in srgb, #24272B 8%, #FBFAF7)",
  night: "#1B1C1F",
} as const;
const PAPER = {
  white: { ...light, "--r-bg": PAPER_BG.white, "--r-raised": "#FFFFFF" },
  green: { ...light, "--r-ink": "#24302A", "--r-bg": PAPER_BG.green, "--r-raised": "color-mix(in srgb, #2F8F5B 6%, #FFFFFF)", "--r-accent": "#2F8F5B" },
  grey: { ...light, "--r-bg": PAPER_BG.grey, "--r-raised": "#FFFFFF" },
  night: { "--r-bg": PAPER_BG.night, "--r-ink": "color-mix(in srgb, #ECECED 88%, #1B1C1F)", "--r-muted": "#9A9DA3", "--r-raised": "#2A2C31", "--r-line": "#34353A", "--r-accent": "#EF7A55" },
};

export const reader = style({
  position: "absolute", inset: "0", overflow: "hidden", background: "var(--r-bg)", color: "var(--r-ink)",
  selectors: {
    '&[data-paper="white"]': { vars: PAPER.white, colorScheme: "light" },
    '&[data-paper="green"]': { vars: PAPER.green, colorScheme: "light" },
    '&[data-paper="grey"]': { vars: PAPER.grey, colorScheme: "light" },
    '&[data-paper="night"]': { vars: PAPER.night, colorScheme: "dark" },
  },
});

export const scroller = style({
  position: "absolute", inset: "0", overflowY: "auto", overscrollBehavior: "contain", WebkitOverflowScrolling: "touch",
  padding: "calc(var(--m-top, 0px) + 28px) 0 calc(var(--m-foot, 0px) + 72px)",
  selectors: {
    // Beside the panel, the text keeps clear of it.
    "&[data-panel]": { paddingRight: "360px" },
  },
});

/** One column, as wide as a line reads well, in the reader's own size and lines. */
export const column = style({
  boxSizing: "border-box", maxWidth: "calc(34em + 2 * var(--r-margin))", margin: "0 auto", padding: "0 var(--r-margin)",
  fontSize: "var(--r-size)", lineHeight: "var(--r-line)", overflowWrap: "anywhere", textWrap: "wrap",
});

/** Lines laid out only as they come near the screen; their height kept once drawn. */
export const piece = style({ contentVisibility: "auto", containIntrinsicSize: "auto 1600px" });
globalStyle(`${piece} p`, { margin: "0" });
globalStyle(`${reader}[data-indent] ${piece} p`, { textIndent: "2em" });
globalStyle(`${piece} p[data-heading]`, { textIndent: "0", fontWeight: "600", fontSize: "calc(var(--r-size) * 1.2)", margin: "1.2em 0 0.6em" });
export const blank = style({ height: "0.6em" });

export const markdown = style({ fontSize: "var(--r-size)", lineHeight: "var(--r-line)", vars: { [vars.textBody]: "var(--r-size)" } });
globalStyle(`${markdown} h1`, { fontSize: "calc(var(--r-size) * 1.5)", lineHeight: "1.3", margin: "1em 0 0.5em" });
globalStyle(`${markdown} h2`, { fontSize: "calc(var(--r-size) * 1.3)", lineHeight: "1.35", margin: "1em 0 0.5em" });
globalStyle(`${markdown} h3`, { fontSize: "calc(var(--r-size) * 1.12)", margin: "1em 0 0.4em" });
globalStyle(`${markdown} p`, { margin: "0 0 0.8em" });

export const note = style({
  display: "grid", justifyItems: "center", gap: "12px", padding: "30vh 24px 0", color: "var(--r-muted)", fontSize: vars.textMeta,
  fontFamily: vars.fontBody, textAlign: "center",
});
export const loadTrack = style({
  position: "relative", display: "block", width: "180px", height: "2px", borderRadius: "1px", overflow: "hidden",
  background: "color-mix(in srgb, var(--r-ink) 14%, transparent)",
});
globalStyle(`${loadTrack} > span`, { position: "absolute", inset: "0", background: "var(--r-accent)", transformOrigin: "left", transition: "transform 160ms linear" });
export const cut = style({ margin: "2em 0 0", color: "var(--r-muted)", fontSize: vars.textMeta, fontFamily: vars.fontBody, textIndent: "0" });

/** With the bars away, how far through it is: a hairline along the bottom, in the accent. */
export const hairline = style({
  position: "absolute", left: "0", right: "0", bottom: "0", height: "2px", pointerEvents: "none",
  background: "color-mix(in srgb, var(--r-ink) 8%, transparent)", transition: `opacity 200ms ${vars.easeOut}`,
  selectors: { [`${reader}[data-bars] &`]: { opacity: "0" } },
});
globalStyle(`${hairline} > span`, { position: "absolute", inset: "0", background: "color-mix(in srgb, var(--r-accent) 70%, transparent)", transformOrigin: "left" });

/** What floats over the page: its raised ground frosted, as the composer and a preview's bars. */
const glassy = {
  background: "color-mix(in srgb, var(--r-raised) 72%, transparent)", WebkitBackdropFilter: "blur(20px) saturate(1.4)",
  backdropFilter: "blur(20px) saturate(1.4)", color: "var(--r-ink)", fontFamily: vars.fontBody,
  borderRadius: `calc(16px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
} as const;
const fades = {
  opacity: "0", pointerEvents: "none", transition: `opacity 240ms ${vars.easeOut}, translate 240ms ${vars.easeOut}`,
  selectors: { "&[data-shown]": { opacity: "1", pointerEvents: "auto", translate: "0 0", transitionDuration: "140ms" } },
  "@media": { "(prefers-reduced-motion: reduce)": { transition: "none" } },
} as const;

export const top = style({
  ...glassy, ...fades, translate: "0 -6px",
  position: "absolute", zIndex: "3", top: "calc(var(--m-top, 0px) + 8px)", left: "50%", transform: "translateX(-50%)",
  width: "min(100% - 24px, 720px)", boxSizing: "border-box", height: "48px", display: "grid", gridTemplateColumns: "minmax(64px, auto) minmax(0, 1fr) minmax(64px, auto)",
  alignItems: "center", padding: "0 6px",
});
export const back = style({
  display: "flex", alignItems: "center", gap: "2px", height: "36px", padding: "0 10px 0 4px", border: "0", background: "none",
  color: "var(--r-ink)", fontSize: vars.textUi, cursor: "pointer", borderRadius: `calc(12px * ${vars.cornerScale})`, maxWidth: "180px",
  selectors: { "&:hover": { background: "color-mix(in srgb, var(--r-ink) 7%, transparent)" } },
});
globalStyle(`${back} span`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${reader}[data-narrow] ${back} span`, { display: "none" });
export const backSpace = style({});
export const title = style({ display: "flex", flexDirection: "column", alignItems: "center", minWidth: "0", lineHeight: "1.25" });
globalStyle(`${title} b`, { maxWidth: "100%", fontSize: vars.textUi, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${title} small`, { maxWidth: "100%", fontSize: vars.textCaption, color: "var(--r-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

export const bottom = style({
  ...glassy, ...fades, translate: "0 6px",
  position: "absolute", zIndex: "3", bottom: "calc(var(--m-foot, 0px) + 12px)", left: "50%", transform: "translateX(-50%)",
  width: "min(100% - 24px, 560px)", boxSizing: "border-box", display: "grid", gap: "8px", padding: "12px 14px 8px",
});
export const chapterRow = style({ display: "grid", gridTemplateColumns: "auto minmax(0, 1fr) auto", alignItems: "center", gap: "10px" });
export const chapterName = style({ minWidth: "0", textAlign: "center", fontSize: vars.textMeta, color: "var(--r-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const chip = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "2px", minWidth: "30px", height: "30px", padding: "0 10px",
  border: "0", borderRadius: `calc(10px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "color-mix(in srgb, var(--r-ink, currentColor) 7%, transparent)", color: "inherit", fontSize: vars.textMeta, cursor: "pointer",
  selectors: {
    "&:disabled": { opacity: ".35", cursor: "default" },
  },
  "@media": { "(hover: hover)": { selectors: { "&:hover:not(:disabled)": { background: "color-mix(in srgb, var(--r-ink, currentColor) 12%, transparent)" } } } },
});

export const trackRow = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr) 40px", alignItems: "center", gap: "10px" });
export const percent = style({ textAlign: "right", fontSize: vars.textMeta, fontWeight: "600", fontVariantNumeric: "tabular-nums" });
/** A hairline to drag or tap along, its knob where the page is. */
export const track = style({ position: "relative", height: "28px", cursor: "pointer", touchAction: "none", margin: "0 7px" });
export const trackLine = style({
  position: "absolute", left: "0", right: "0", top: "13px", height: "2px", borderRadius: "1px", overflow: "hidden",
  background: "color-mix(in srgb, var(--r-ink) 16%, transparent)",
});
globalStyle(`${trackLine} > span`, { position: "absolute", inset: "0", background: "var(--r-accent)", transformOrigin: "left" });
export const knobRail = style({ position: "absolute", inset: "0", pointerEvents: "none" });
export const knob = style({
  position: "absolute", top: "7px", left: "-7px", width: "14px", height: "14px", borderRadius: "50%", boxSizing: "border-box",
  background: "var(--r-accent)", boxShadow: "0 0 0 3px color-mix(in srgb, var(--r-raised) 90%, transparent)",
  transition: `scale 120ms ${vars.easeOut}`,
  selectors: { "&[data-held]": { scale: "1.2" } },
});

export const tools = style({ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "4px" });
export const tool = style({
  display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "3px", height: "50px",
  border: "0", borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none", color: "var(--r-ink)",
  fontSize: vars.textCaption, cursor: "pointer",
  selectors: { "&[data-on]": { background: "color-mix(in srgb, var(--r-ink) 7%, transparent)" } },
  // A finger leaves no hover behind it.
  "@media": { "(hover: hover)": { selectors: { "&:hover": { background: "color-mix(in srgb, var(--r-ink) 7%, transparent)" } } } },
});

/** What was found, and the steps through it: a capsule under the top bar. */
export const findStrip = style({
  ...glassy,
  position: "absolute", zIndex: "3", left: "50%", transform: "translateX(-50%)", top: "calc(var(--m-top, 0px) + 8px)",
  display: "flex", alignItems: "center", gap: "4px", maxWidth: "calc(100% - 24px)", height: "40px", boxSizing: "border-box", padding: "0 5px 0 14px",
  transition: `top 200ms ${vars.easeOut}`,
  selectors: { "&[data-bars]": { top: "calc(var(--m-top, 0px) + 64px)" } },
});
export const findWords = style({ minWidth: "0", marginRight: "6px", fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums" });

/** Beside the text, with a mouse: the contents, the find or the layout, on what every panel stands on. */
export const panel = style({
  ...panelGround,
  position: "absolute", zIndex: "4", top: "16px", right: "16px", bottom: "16px", width: "328px", display: "flex", flexDirection: "column",
  borderRadius: vars.rMenu, cornerShape: vars.cornerShape, boxShadow: `0 8px 28px ${vars.shadow}`, color: vars.text, fontFamily: vars.fontBody,
  overflow: "hidden",
});
export const panelHead = style({ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "12px 12px 6px 18px" });
globalStyle(`${panelHead} b`, { fontSize: vars.textTitle, fontWeight: "600" });
export const panelList = style({ flex: "1", minHeight: "0", overflowY: "auto", padding: "2px 8px 12px" });
export const panelRow = style({
  display: "block", width: "100%", boxSizing: "border-box", padding: "10px 12px", border: "0", background: "none", color: "inherit",
  textAlign: "left", fontSize: vars.textUi, borderRadius: vars.rOption, cornerShape: vars.cornerShape, cursor: "pointer",
  selectors: {
    "&:hover": { background: "color-mix(in srgb, currentColor 6%, transparent)" },
    "&[data-current]": { color: `var(--m-accent-ink, ${vars.accentText})`, fontWeight: "500" },
  },
});
export const panelNote = style({ margin: "0", padding: "6px 20px 10px", color: `var(--m-muted, ${vars.muted})`, fontSize: vars.textMeta });
export const findPanel = style({ flex: "1", minHeight: "0", display: "flex", flexDirection: "column" });
export const findInput = style({
  boxSizing: "border-box", margin: "6px 16px 8px", height: "38px", padding: "0 16px", borderRadius: "999px",
  border: `1px solid color-mix(in srgb, currentColor 18%, transparent)`, background: "transparent", color: "inherit",
  font: "inherit", fontSize: vars.textInput, outline: "none",
  selectors: { "&:focus": { borderColor: "color-mix(in srgb, currentColor 40%, transparent)" } },
});
export const snippet = style({ display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical", overflow: "hidden", lineHeight: "1.5" });
globalStyle(`${snippet} b`, { fontWeight: "600", color: `var(--m-accent-ink, ${vars.accentText})` });

export const layout = style({ display: "block", padding: "4px 20px 24px" });
export const layoutRow = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "16px", minHeight: "48px", fontSize: vars.textUi });
export const stepper = style({ display: "flex", alignItems: "center", gap: "6px" });
globalStyle(`${stepper} button`, {
  display: "grid", placeItems: "center", width: "34px", height: "34px", padding: "0", border: "0", borderRadius: "50%",
  background: "color-mix(in srgb, currentColor 7%, transparent)", color: "inherit", cursor: "pointer",
});
globalStyle(`${stepper} button:disabled`, { opacity: ".35", cursor: "default" });
globalStyle(`${stepper} b`, { minWidth: "40px", textAlign: "center", fontWeight: "600", fontVariantNumeric: "tabular-nums" });
export const papers = style({ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: "8px" });
export const paperSwatch = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: "4px", padding: "0", border: "0", background: "none", color: "inherit",
  cursor: "pointer",
});
globalStyle(`${paperSwatch} > span`, {
  display: "grid", placeItems: "center", width: "100%", height: "44px", borderRadius: `calc(12px * ${vars.cornerScale})`,
  boxShadow: "inset 0 0 0 1px color-mix(in srgb, currentColor 14%, transparent)", fontFamily: "serif", fontSize: vars.textTitle,
});
globalStyle(`${paperSwatch}[data-on] > span`, { boxShadow: `inset 0 0 0 2px var(--m-accent, ${vars.accent})` });
globalStyle(`${paperSwatch} small`, { fontSize: vars.textCaption, color: `var(--m-muted, ${vars.muted})` });
globalStyle(`${paperSwatch}[data-paper="white"] > span`, { background: PAPER_BG.white, color: "#24272B" });
globalStyle(`${paperSwatch}[data-paper="green"] > span`, { background: PAPER_BG.green, color: "#24302A" });
globalStyle(`${paperSwatch}[data-paper="grey"] > span`, { background: PAPER_BG.grey, color: "#24272B" });
globalStyle(`${paperSwatch}[data-paper="night"] > span`, { background: PAPER_BG.night, color: "#ECECED" });

/** The panel open beside the text: the bars over the text, not under the panel. */
globalStyle(`${reader}:has(> ${panel}) ${top}, ${reader}:has(> ${panel}) ${bottom}, ${reader}:has(> ${panel}) ${findStrip}`, {
  left: "calc((100% - 360px) / 2)", maxWidth: "calc(100% - 384px)",
});
/** What was found, in the paper's ink (the app's own may be the other way round, white on a white page). */
globalStyle(`${column} ::highlight(find-hit), ${column} ::highlight(find-current)`, { color: "var(--r-ink)" });

/** The top bar's end: finding in the text. */
export const topEnd = style({ display: "flex", justifyContent: "flex-end" });
export const topButton = style({
  display: "grid", placeItems: "center", width: "36px", height: "36px", padding: "0", border: "0", borderRadius: `calc(12px * ${vars.cornerScale})`,
  background: "none", color: "var(--r-ink)", cursor: "pointer",
  selectors: { "&[data-on]": { background: "color-mix(in srgb, var(--r-ink) 7%, transparent)" } },
  "@media": { "(hover: hover)": { selectors: { "&:hover": { background: "color-mix(in srgb, var(--r-ink) 7%, transparent)" } } } },
});
/** Beside a panel's title: how many chapters, how far read. */
export const headNote = style({ marginLeft: "auto", marginRight: "8px", fontSize: vars.textMeta, color: `var(--m-muted, ${vars.muted})`, fontWeight: "400" });
export const findRow = style({ display: "flex", alignItems: "center", gap: "10px", color: `var(--m-muted, ${vars.muted})` });
/** A chapter: its number, its title, a check on the one being read. */
export const chapterLine = style({ display: "grid", gridTemplateColumns: "28px minmax(0, 1fr) auto", alignItems: "center", gap: "4px" });
globalStyle(`${chapterLine} small`, { color: `var(--m-muted, ${vars.muted})`, fontSize: vars.textCaption, fontVariantNumeric: "tabular-nums" });
globalStyle(`${chapterLine} span`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

export const layoutScroll = style({ overflowY: "auto", minHeight: "0", flex: "1" });
export const layoutBlock = style({ display: "grid", gap: "8px", minWidth: "0" });
export const layoutLabel = style({ fontSize: vars.textMeta, color: `var(--m-muted, ${vars.muted})` });
export const layoutPair = style({ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "14px" });
globalStyle(`${layout} > * + *`, { marginTop: "10px" });
export const sizeRow = style({
  display: "grid", gridTemplateColumns: "auto 1fr auto", alignItems: "center", height: "40px", padding: "0 4px",
  borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "color-mix(in srgb, currentColor 6%, transparent)",
});
globalStyle(`${sizeRow} b`, { textAlign: "center", fontWeight: "600", fontVariantNumeric: "tabular-nums" });
export const sizeKey = style({
  height: "32px", minWidth: "44px", padding: "0 10px", border: "0", borderRadius: `calc(10px * ${vars.cornerScale})`, background: "none", color: "inherit",
  fontSize: vars.textUi, fontWeight: "600", cursor: "pointer",
  selectors: { "&:disabled": { opacity: ".35", cursor: "default" }, "&:hover:not(:disabled)": { background: "color-mix(in srgb, currentColor 8%, transparent)" } },
});
/** A setting along a hairline with a knob (line height, margin): its name, the line, its value. */
export const sliderRow = style({ display: "grid", gridTemplateColumns: "48px minmax(0, 1fr) 48px", alignItems: "center", gap: "10px" });
export const slider = style({ position: "relative", height: "28px", cursor: "pointer", touchAction: "none", margin: "0 8px", outline: "none" });
export const sliderLine = style({
  position: "absolute", left: "0", right: "0", top: "13px", height: "2px", borderRadius: "1px", overflow: "hidden",
  background: "color-mix(in srgb, currentColor 16%, transparent)",
});
globalStyle(`${sliderLine} > span`, { position: "absolute", inset: "0", background: `var(--m-accent, ${vars.accent})`, transformOrigin: "left" });
export const sliderKnob = style({
  position: "absolute", top: "6px", left: "-8px", width: "16px", height: "16px", borderRadius: "50%", boxSizing: "border-box",
  background: `var(--m-accent, ${vars.accent})`, boxShadow: `0 0 0 3px var(--m-surface, ${vars.canvas})`, transition: `scale 120ms ${vars.easeOut}`,
  selectors: { "&[data-held]": { scale: "1.2" } },
});
export const sliderValue = style({ textAlign: "right", fontSize: vars.textMeta, fontWeight: "600", fontVariantNumeric: "tabular-nums" });

// ── with a mouse: a desktop's reader ──
const desk = `${reader}:not([data-narrow])`;
const BAR = 52;
const PANEL = 320;
/** The toolbar across the top, on the paper itself, a line under it: the way back, the name in the middle, the tools. */
globalStyle(`${desk} ${top}`, {
  top: "0", left: "0", right: "0", transform: "none", translate: "0 0", width: "auto", maxWidth: "none", height: `${BAR}px`, padding: "0 12px",
  gridTemplateColumns: "minmax(0, 1fr) minmax(0, auto) minmax(0, 1fr)", gap: "16px", borderRadius: "0",
  background: "var(--r-bg)", WebkitBackdropFilter: "none", backdropFilter: "none", boxShadow: "inset 0 -1px 0 var(--r-line)",
});
globalStyle(`${desk} ${back}`, { justifySelf: "start" });
globalStyle(`${desk} ${topEnd}`, { gap: "2px" });
globalStyle(`${desk} ${topButton}`, { width: "34px", height: "34px", borderRadius: `calc(10px * ${vars.cornerScale})`, color: "var(--r-muted)" });
globalStyle(`${desk} ${topButton}:hover, ${desk} ${topButton}[data-on]`, { color: "var(--r-ink)" });
/** The text under it, and clear of the panel docked at the right. */
globalStyle(`${desk} ${scroller}`, { top: `${BAR}px`, paddingTop: "40px", outline: "none" });
globalStyle(`${desk} ${scroller}[data-panel]`, { paddingRight: `${PANEL}px` });
/** How far through it is: the hairline along the bottom, always. */
globalStyle(`${desk} ${hairline}`, { opacity: "1" });
/** The panel docked at the right, under the toolbar, on the paper with a line before it. */
globalStyle(`${desk} ${panel}`, {
  top: `${BAR}px`, right: "0", bottom: "0", width: `${PANEL}px`, borderRadius: "0", boxShadow: "inset 1px 0 0 var(--r-line)",
  background: "var(--r-bg)", color: "var(--r-ink)", border: "0",
});
/** What was found, under the toolbar, over the text's middle. */
globalStyle(`${desk} ${findStrip}`, { top: `${BAR + 10}px` });
globalStyle(`${desk}:has(> ${panel}) ${top}`, { left: "0", maxWidth: "none" });
globalStyle(`${desk}:has(> ${panel}) ${findStrip}`, { left: `calc((100% - ${PANEL}px) / 2)` });
/** In the panel beside the text, the face and the indent each on a row of their own: side by side, 首行缩进 had no room. */
globalStyle(`${desk} ${layoutPair}`, { gridTemplateColumns: "minmax(0, 1fr)" });
/** The panel's close: square, as the toolbar's buttons. */
globalStyle(`${panelHead} ${chip}`, { width: "30px", minWidth: "0", padding: "0" });

// ── Markdown as a page, not a chat's message: everything in the reader's size and on its paper ──
const md = `${reader} ${markdown}`;
/** Room after each block of the page; none inside a code block's or a table's own frame (it would show as a gap in it). */
globalStyle(`${md} > *`, { marginBottom: "1em" });
globalStyle(`${md} > * pre, ${md} > * table, ${md} blockquote > *`, { margin: "0" });
globalStyle(`${md} li + li`, { marginTop: "0.3em" });
globalStyle(`${md} ul, ${md} ol`, { paddingLeft: "1.4em" });
/** Inline code a step under the text, on a tint of the paper's ink (not the chat's colour). */
globalStyle(`${md} :not(pre) > code`, {
  fontSize: "0.86em", padding: "0.12em 0.36em", borderRadius: `calc(6px * ${vars.cornerScale})`,
  background: "color-mix(in srgb, var(--r-ink) 7%, transparent)", color: "inherit",
});
globalStyle(`${md} pre`, {
  padding: "0.9em 1.1em", fontSize: "0.8em", lineHeight: "1.6", borderRadius: `calc(14px * ${vars.cornerScale})`,
  background: "color-mix(in srgb, var(--r-ink) 5%, transparent)",
});
globalStyle(`${md} table`, { fontSize: "0.86em" });
globalStyle(`${md} th, ${md} td`, { padding: "0.5em 0.9em", borderBottom: "1px solid var(--r-line)" });
globalStyle(`${md} th`, { fontSize: "inherit", color: "var(--r-muted)", background: "color-mix(in srgb, var(--r-ink) 4%, transparent)" });
globalStyle(`${md} blockquote`, { padding: "0.1em 0 0.1em 1em", borderLeft: "3px solid color-mix(in srgb, var(--r-ink) 22%, transparent)", color: "var(--r-muted)" });
globalStyle(`${md} hr`, { border: "0", borderTop: "1px solid var(--r-line)", margin: "1.6em 0" });
