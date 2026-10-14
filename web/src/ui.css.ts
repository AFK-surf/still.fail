import { globalStyle, style } from "@vanilla-extract/css";
import { busyRing } from "./styles/busyRing.ts";
import { vars } from "./styles/tokens.css.ts";
import { panel } from "./styles/glass.ts";
import { appearKeyframes, dialogInKeyframes, fadeKeyframes, pulseKeyframes, spinKeyframes } from "./styles/keyframes.css.ts";
import { gate, muted } from "./styles/shell.css.ts";
import { pageBar } from "./styles/sidebar.css.ts";
import { markdown } from "./styles/conversation.css.ts";
import { card, listRow } from "./styles/pages.css.ts";

export const firstOneTitle = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "12px 0 0", fontSize: vars.textTitle,
  fontWeight: "600",
});
export const firstOneLead = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "0", maxWidth: "34em",
  color: vars.muted, fontSize: vars.textUi, lineHeight: "1.6",
});
export const dialogLead = style({});
export const kindIcon = style({
  display: "inline-grid", placeItems: "center", width: "20px", height: "20px", flex: "none", color: vars.muted,
});
export const kindMark = style({ color: vars.text });
/** Centred on the line: aligned by baseline, the letter inside a small avatar would pull it down. */
/**
 * An agent: its model's maker on a tile; where it stands is a mark at the corner in the chat list's colours
 * (ChatMark.css.ts): a turning yellow ring at work, red when it wants someone (blocked, failed); no halo, the tile is
 * small. A gap of the ground (`--ring`) round it.
 */
export const agentMark = style({
  position: "relative", display: "inline-grid", placeItems: "center", flex: "none", width: "var(--mark)",
  height: "var(--mark)", borderRadius: `calc(var(--mark) * .3 * ${vars.cornerScale})`, background: vars.neutralBg,
  cornerShape: vars.cornerShape,
  vars: { "--ring": vars.canvas },
  selectors: {
    "&[data-badge]::after": {
      content: "\"\"", position: "absolute", right: "-3px", bottom: "-3px", width: "12px", height: "12px",
      boxSizing: "border-box", borderRadius: "50%", border: "2px solid var(--ring)", background: "var(--ring)",
    },
    "&[data-badge=\"block\"]::after, &[data-badge=\"failed\"]::after": { background: "#e5484d" },
    // At work: a turning ring with a gap, over the ground's disc.
    "&[data-badge=\"run\"]::before": {
      content: "\"\"", position: "absolute", right: "-1px", bottom: "-1px", width: "8px", height: "8px", zIndex: 1,
      background: `${busyRing(8)} center / 100% no-repeat`, animation: `${spinKeyframes} 1.2s linear infinite`,
    },
  },
  "@media": { "(prefers-reduced-motion: reduce)": { selectors: { "&[data-badge=\"run\"]::before": { animation: "none" } } } },
});
/**
 * With the station it runs on: one tile, as tall, the maker's part square, the station's (its icon or its name) after it,
 * centred in its own part; a badge sits further out on the corner, so it covers none of the station's.
 */
export const agentMarkJoined = style({
  display: "inline-flex", width: "auto", gap: "0", color: vars.muted, fontSize: vars.textMeta, lineHeight: "1", whiteSpace: "nowrap",
  selectors: {
    "&[data-badge]::after": { right: "-7px" },
    "&[data-badge=\"run\"]::before": { right: "-5px" },
  },
});
// Hover tints meet at straight edges inside the tile; only its two outside ends are rounded.
const joinedCorner = `calc(var(--mark) * .3 * ${vars.cornerScale})`;
globalStyle(`${agentMarkJoined} > *`, { borderRadius: "0", cornerShape: vars.cornerShape });
globalStyle(`${agentMarkJoined} > :first-child`, { borderStartStartRadius: joinedCorner, borderEndStartRadius: joinedCorner });
globalStyle(`${agentMarkJoined} > :last-child`, { borderStartEndRadius: joinedCorner, borderEndEndRadius: joinedCorner });
globalStyle(`${agentMarkJoined} > :last-child`, { paddingInline: "calc(var(--mark) * .19 + 1px)" });
export const empty = style({
  flex: "1", display: "grid", placeContent: "center", justifyItems: "center", gap: "6px", padding: "40px",
  textAlign: "center", color: vars.muted,
});
/** Section titles and their actions share a centre line. */
export const sectionHead = style({
  display: "flex", justifyContent: "space-between", gap: "12px", marginBottom: "10px", alignItems: "center",
});
export const sectionSub = style({ margin: "3px 0 0", fontSize: vars.textMeta, color: vars.muted, maxWidth: "52em" });
export const sectionActions = style({ display: "flex", gap: "8px" });
export const field = style({ display: "grid", gap: "6px" });
export const fieldTop = style({ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: "8px" });
export const fieldLabel = style({ fontSize: vars.textUi, fontWeight: "500" });
export const fieldHint = style({ fontSize: vars.textMeta, color: vars.muted });
export const dialogError = style({});
/** A pill, as a one-line field is (controls.css.ts input). */
export const select = style({
  width: "100%", minHeight: "36px", padding: "7px 16px", border: `1px solid ${vars.lineStrong}`,
  borderRadius: "999px", background: vars.canvas, fontSize: vars.textInput,
  transition: `border-color ${vars.dur} ${vars.easeOut}`, cornerShape: "round", display: "flex",
  alignItems: "center", justifyContent: "space-between", gap: "8px", textAlign: "left", cursor: "pointer",
  selectors: {
    "&:hover": { borderColor: vars.fieldHover },
    "&:focus": { outline: "none", borderColor: vars.fieldHover },
    "&[data-placeholder]": { color: vars.subtle },
    "&:disabled": { opacity: ".55", cursor: "default" },
  },
});
/** The track tints whatever it sits on; the chosen option's ground is a thumb that slides. */
/** As tall as its options wherever it sits (a stretching row would make the track taller than them and the thumb with it). */
// Equal columns, as wide as the widest option: the thumb is one column wide, so options as wide as their own text
// (flex) put it off them wherever a font sets one label wider than its share, as Windows' do.
export const segmented = style({
  position: "relative", isolation: "isolate", display: "grid", gridAutoFlow: "column", gridAutoColumns: "minmax(0, 1fr)",
  alignItems: "center", alignSelf: "center",
  height: "max-content", padding: "var(--pad)", gap: "var(--gap)", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`,
  vars: { "--pad": "3px", "--gap": "2px" },
});
export const segmentedThumb = style({
  position: "absolute", zIndex: "-1", top: "var(--pad)", bottom: "var(--pad)", left: "var(--pad)",
  width: "calc((100% - 2 * var(--pad) - (var(--n) - 1) * var(--gap)) / var(--n))", borderRadius: "999px",
  background: vars.canvas, boxShadow: `0 0 2px ${vars.shadow}, 0 0 0 .5px ${vars.line}`,
  transform: "translateX(calc(var(--i) * (100% + var(--gap))))", transition: `transform 240ms ${vars.easeOut}`,
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      transition: "none",
    },
  },
});
export const segmentedOption = style({
  display: "grid", placeItems: "center",
  height: "30px", padding: "0 12px", border: "0", borderRadius: "999px", background: "transparent", color: vars.muted,
  whiteSpace: "nowrap",
  fontSize: vars.textUi, cursor: "pointer", transition: `color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover:not([data-state=\"on\"])": { color: vars.text },
    "&[data-state=\"on\"]": { color: vars.text, fontWeight: "500" },
  },
});
/** The label, and under it the same in the chosen weight, unseen: an option is as wide unchosen as chosen, so the
 * columns (as wide as the widest) do not change width when the choice does. */
export const segmentedLabel = style({ gridArea: "1 / 1" });
export const segmentedSizer = style({ gridArea: "1 / 1", fontWeight: "500", visibility: "hidden" });
export const switch_ = style({
  position: "relative", flex: "none", width: "36px", height: "22px", padding: "0", border: "0", borderRadius: "999px",
  background: vars.lineStrong, cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-state=\"checked\"]": { background: vars.accent },
    "&:disabled": { opacity: ".5", cursor: "default" },
  },
});
export const switchThumb = style({
  display: "block", width: "18px", height: "18px", borderRadius: "50%", background: "#fff",
  boxShadow: "0 1px 2px oklch(0% 0 0 / .2)", transform: "translateX(2px)",
  transition: `transform ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-state=\"checked\"]": { transform: "translateX(16px)" },
  },
});
/** A switch in a line of small text (Versions.tsx): the same, smaller. */
export const switchSmall = style({ width: "26px", height: "16px", alignSelf: "center" });
export const switchThumbSmall = style({
  width: "12px", height: "12px",
  selectors: { "&[data-state=\"checked\"]": { transform: "translateX(12px)" } },
});
export const switchRow = style({ display: "flex", alignItems: "center", gap: "16px" });
export const switchRowText = style({ flex: "1", display: "grid", gap: "2px", fontSize: vars.textUi, cursor: "pointer" });
export const choices = style({ display: "grid", gap: "8px" });
export const choice = style({
  border: `1px solid ${vars.lineStrong}`, borderRadius: `calc(16px * ${vars.cornerScale})`, background: vars.canvas,
  transition: `border-color ${vars.dur} ${vars.easeOut}, box-shadow ${vars.dur} ${vars.easeOut}`,
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover:not([data-disabled])": { borderColor: vars.fieldHover },
    "&[data-checked]": { borderColor: vars.text, boxShadow: `0 0 0 1px ${vars.text}` },
    "&[data-disabled]": { opacity: ".55" },
  },
});
export const choiceHit = style({
  display: "flex", alignItems: "center", gap: "12px", width: "100%", padding: "12px 14px", border: "0",
  borderRadius: `calc(16px * ${vars.cornerScale})`, background: "none", textAlign: "left", cursor: "pointer",
  cornerShape: vars.cornerShape,
  selectors: {
    "&:disabled": { cursor: "default" },
  },
});
export const choiceText = style({ flex: "1", display: "grid", gap: "2px", fontSize: vars.textUi });
export const choiceExtra = style({ margin: "0 14px", padding: "12px 0 14px", borderTop: `1px solid ${vars.line}` });
export const radio = style({
  display: "grid", placeItems: "center", flex: "none", width: "18px", height: "18px", borderRadius: "50%",
  border: `1.5px solid ${vars.lineStrong}`,
  selectors: {
    [`${choice}[data-checked] &`]: { borderColor: vars.text },
  },
});
export const radioDot = style({ width: "8px", height: "8px", borderRadius: "50%", background: vars.text });
export const selectIcon = style({ color: vars.muted, display: "grid" });
export const selectContent = style({
  minWidth: "var(--radix-select-trigger-width)", maxHeight: "min(360px, var(--radix-select-content-available-height))",
});
export const selectViewport = style({ padding: "0" });
export const selectItem = style({ position: "relative", paddingRight: "32px" });
export const selectHint = style({ marginLeft: "auto", fontSize: vars.textMeta, color: vars.muted });
export const selectCheck = style({ position: "absolute", right: "10px", display: "grid", color: vars.text });
export const pill = style({
  display: "inline-flex", alignItems: "center", height: "22px", padding: "0 9px", borderRadius: "999px",
  fontSize: vars.textMeta, fontWeight: "500", whiteSpace: "nowrap", background: vars.neutralBg, color: vars.muted,
  selectors: {
    "&[data-tone=\"green\"]": { background: vars.greenBg, color: vars.green },
    "&[data-tone=\"blue\"]": { background: vars.blueBg, color: vars.blue },
    "&[data-tone=\"amber\"]": { background: vars.amberBg, color: vars.amber },
    "&[data-tone=\"red\"]": { background: vars.redBg, color: vars.red },
    "&[data-tone=\"accent\"]": { background: vars.accentBg, color: vars.accentText },
  },
});
export const statusDot = style({
  width: "7px", height: "7px", borderRadius: "50%", flex: "none", background: "transparent",
  boxShadow: `inset 0 0 0 1.5px ${vars.muted}`,
  selectors: {
    "&[data-state=\"online\"]": { background: vars.online, boxShadow: "none" },
    "&[data-state=\"busy\"]": { background: vars.amber, boxShadow: "none" },
    "&[data-state=\"error\"]": { background: vars.red, boxShadow: "none" },
  },
});
export const avatar = style({
  display: "inline-grid", placeItems: "center", flex: "none", color: "#fff", fontWeight: "600", lineHeight: "1",
  cornerShape: vars.cornerShape,
});
export const tooltip = style({});
/** A tip's keys, after what it says: quieter. */
export const tipKeys = style({ marginLeft: "8px", opacity: ".6" });
export const command = style({
  display: "flex", alignItems: "center", gap: "8px", padding: "6px 6px 6px 14px", borderRadius: vars.rField,
  background: vars.paper, cornerShape: vars.cornerShape,
});
export const overlay = style({
  position: "fixed", inset: "0", zIndex: "40", background: vars.overlay,
  animation: `${fadeKeyframes} 180ms ${vars.easeOut}`,
});
/**
 * A dialog's corners and what sits at them are one curve (concentric): its padding (DIALOG_PAD) plus a button's half
 * height (18) is its radius, so a pill button in a corner, the close button, and a card inside (radius DIALOG_INNER) all
 * follow its edge at the same distance.
 */
const DIALOG_PAD = 24;
export const DIALOG_INNER = `calc(18px * ${vars.cornerScale})`;
export const dialog = style({
  position: "fixed", left: "50%", top: "50%", zIndex: "50", transform: "translate(-50%, -50%)", display: "flex",
  flexDirection: "column", width: "min(520px, calc(100vw - 32px))", maxHeight: "calc(100dvh - 48px)",
  borderRadius: `calc(${DIALOG_PAD + 18}px * ${vars.cornerScale})`, ...panel, color: vars.text, boxShadow: `0 24px 64px ${vars.shadow}`,
  animation: `${dialogInKeyframes} 200ms ${vars.easeOut}`, cornerShape: vars.cornerShape,
  selectors: {
    "&:focus": { outline: "none" },
  },
});
export const dialogWide = style({ width: "min(640px, calc(100vw - 32px))" });
export const dialogAlert = style({ width: "min(420px, calc(100vw - 32px))", padding: `${DIALOG_PAD + 4}px ${DIALOG_PAD}px ${DIALOG_PAD}px`, gap: "8px" });
/** Its title, and the close button in the corner: round (half width 16), its centre the corner's radius from the edges. */
export const dialogHead = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", padding: `${DIALOG_PAD - 2}px ${DIALOG_PAD + 2}px 0 ${DIALOG_PAD}px`,
});
export const dialogTitle = style({});
export const dialogBody = style({
  // One column no wider than the dialog: a long unbroken line (an install command) scrolls in itself instead of widening it.
  display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "16px", padding: `18px ${DIALOG_PAD}px 0`, overflowY: "auto", minHeight: "0",
  selectors: { "&:last-child": { paddingBottom: `${DIALOG_PAD}px` } },
});
/** Its buttons, the last in the corner; anything before them that is not a button (a note) takes the room on their left. */
export const dialogFoot = style({
  display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "8px", padding: `${DIALOG_PAD}px`,
  selectors: {
    [`${dialogAlert} &`]: { padding: "16px 0 0" },
  },
});
export const srOnly = style({
  position: "absolute", width: "1px", height: "1px", overflow: "hidden", clip: "rect(0 0 0 0)", whiteSpace: "nowrap",
});
export const mobileBack = style({
  display: "none", alignItems: "center", gap: "2px", color: vars.muted, fontSize: vars.textUi, lineHeight: "20px",
  "@media": {
    "(max-width: 700px)": {
      display: "inline-flex", marginBottom: "12px",
      selectors: {
        [`${pageBar} &`]: { margin: "0" },
      },
    },
  },
});
/** A detail page's way back, on every screen, above its header. */
export const pageBackRow = style({ display: "flex", alignItems: "center", height: "24px", marginBottom: "14px" });
export const pageBack = style({
  display: "inline-flex", alignItems: "center", gap: "2px", marginLeft: "-4px", color: vars.muted,
  fontSize: vars.textUi, lineHeight: "20px", textDecoration: "none",
  selectors: {
    "&:hover": { color: vars.text },
  },
});
/** Loading says so only when it takes a while: a page that is there in a moment (from the device) shows nothing before it. */
export const loading = style({
  display: "flex", alignItems: "center", gap: "10px", color: vars.muted, fontSize: vars.textUi,
  animation: `${appearKeyframes} 0s linear 400ms both`,
  selectors: {
    [`${gate} &`]: { justifyContent: "center" },
  },
});
export const loadingFill = style({ flex: "1", minHeight: "100%", justifyContent: "center" });
export const splashLabel = style({
  margin: "0", maxWidth: "32em", fontSize: vars.textUi, color: vars.muted,
  animation: `${appearKeyframes} 0s linear 1s both`,
  selectors: {
    "&[data-now]": { animation: "none" },
  },
});
/** Offered once a splash has stood too long: loading the page again, as an app on the home screen has no reload of its own. */
export const splashReload = style({
  display: "inline-flex", alignItems: "center", gap: "6px", height: "32px", padding: "0 14px", border: "0", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`, color: vars.text, font: "inherit", fontSize: vars.textUi, cursor: "pointer",
  animation: `${appearKeyframes} 200ms ease-out both`,
});
export const skeletonRow = style({
  display: "grid", gap: "6px", padding: "9px 10px", animation: `${appearKeyframes} 0s linear 400ms both`,
});
export const runtimeLogo = style({ flex: "none", display: "block" });
export const resizeHandle = style({
  outline: "none", WebkitAppRegion: "no-drag",
  selectors: {
    "&[data-edge=\"right\"]": { right: "-4px" },
    "&[data-edge=\"left\"]": { left: "-4px" },
    // As Cue's: a hairline on the column's edge, short of its ends and fading toward them, only on the edge in hand.
    "&::after": {
      content: "\"\"", position: "absolute", top: "8px", bottom: "8px", left: "3px", width: "1px", borderRadius: "999px",
      background: `linear-gradient(to bottom, transparent 10%, ${vars.fieldHover} 50%, transparent 90%)`,
      opacity: 0, transition: `opacity 140ms ${vars.easeOut}`,
    },
    "&:hover::after, &:focus-visible::after, &[data-active]::after": { opacity: 1 },
    // The bar at its middle, on the line (Rail.css.ts edge, the sidebar's, is the same).
    "&::before": {
      // Odd widths on whole pixels: the bar's middle is the line's (the line left 3, 1 wide; the bar left 1, 5 wide).
      content: "\"\"", position: "absolute", top: "50%", left: "1px", width: "5px", height: "24px", borderRadius: "999px",
      background: vars.lineStrong, opacity: 0, transform: "translateY(-50%)", zIndex: 1,
      transition: `height 180ms cubic-bezier(.16, 1, .3, 1), opacity 180ms cubic-bezier(.16, 1, .3, 1), background-color 150ms ${vars.easeOut}`,
    },
    "&:hover::before, &:focus-visible::before, &[data-active]::before": { height: "48px", opacity: 1 },
    "&:active::before, &[data-active]::before": { background: vars.fieldHover },
  },
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
// The pointer over the column: its edge's bar is there to find.
globalStyle(`:hover > ${resizeHandle}::before`, { opacity: 1 });
/** A handle's tip, following the pointer along it (ui.tsx ResizeHandle): beside it, its middle level with the pointer. */
export const edgeTip = style({
  position: "fixed", top: 0, left: 0, zIndex: 70, pointerEvents: "none", willChange: "transform",
  selectors: { "&[data-edge=\"left\"]": { translate: "-100% 0" } },
});
globalStyle(`${edgeTip} > *`, { transform: "translateY(-50%)" });
export const modelLogo = style({
  flex: "none", display: "inline-block", verticalAlign: "-2px",
  selectors: {
    ":root[data-theme=\"dark\"] &[data-mono]": { filter: "invert(1)" },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        ":root:not([data-theme=\"light\"]) &[data-mono]": { filter: "invert(1)" },
      },
    },
  },
});
export const timeToggle = style({
  cursor: "pointer",
  selectors: {
    "&:hover": { textDecoration: "underline dotted", textUnderlineOffset: "2px" },
  },
});
export const firstOne = style({});
export const firstOneAction = style({
  width: "100%", minWidth: "0", marginTop: "12px", display: "flex", gap: "8px", alignItems: "center",
  justifyContent: "center", flexWrap: "wrap",
});
export const about = style({
  selectors: {
    "&:hover": { color: vars.text },
    "&:focus-visible": { color: vars.text },
  },
});
export const aboutText = style({ display: "block", lineHeight: "1.5" });
globalStyle(`${empty} h2`, { margin: "10px 0 0", fontSize: vars.textTitle, color: vars.text });
globalStyle(`${empty} p`, { margin: "0", maxWidth: "34em", fontSize: vars.textUi });
globalStyle(`${sectionHead} h2`, { margin: "0", fontSize: vars.textBody, lineHeight: "22px", fontWeight: "600" });
globalStyle(`${switchRowText} ${muted}`, { fontSize: vars.textMeta });
globalStyle(`${choiceText} strong`, { fontWeight: "600" });
globalStyle(`${choiceText} ${muted}`, { fontSize: vars.textMeta, lineHeight: "1.5" });
globalStyle(`${select} > span:first-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${command} code`, { flex: "1", fontSize: vars.textMeta, overflowX: "auto", whiteSpace: "nowrap" });
globalStyle(`${dialogAlert} ${dialogLead}`, { margin: "0" });
globalStyle(`${dialogHead} > button`, { borderRadius: "999px", cornerShape: "round" });
/** A list's rows in a dialog reach 12 past its words (pages.css.ts listRow): their hover follows the dialog's curve too. */
globalStyle(`${dialogBody} ${listRow}`, { borderRadius: `calc(${DIALOG_PAD + 18 - 12}px * ${vars.cornerScale})` });
/** Cards, choices and command lines in a dialog sit at its padding: their corners are the dialog's, less it. */
globalStyle(`${dialogBody} :is(${card}, ${choice}, ${command})`, { borderRadius: DIALOG_INNER });
/** Here rather than with its class: it comes after .empty p, and wins over it. */
globalStyle(`${markdown} p`, { margin: "0 0 8px" });
/** Here rather than with its class: it comes after .empty h2, and wins over it. */
globalStyle(`${markdown} h2`, { fontSize: vars.textBody, margin: "14px 0 6px" });
/** Here rather than with its class: it comes after .command code, and wins over it. */
globalStyle(`${markdown} code`, {
  fontSize: vars.textMeta, padding: "1px 5px", borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.neutralBg,
  cornerShape: vars.cornerShape,
});
globalStyle(`${dialog} ${command} code`, { minWidth: "0" });
globalStyle(`${skeletonRow} span`, {
  display: "block", height: "10px", borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.hover,
  animation: `${pulseKeyframes} 1.4s ease-in-out infinite`, cornerShape: vars.cornerShape,
});
globalStyle(`${skeletonRow} span`, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});

/** Inline completion mark, aligned with the state explanation's text. */
export const doneMark = style({ display: "inline-flex", width: 14, height: 14, verticalAlign: "-2px", alignItems: "center", justifyContent: "center" });

// ── a popped-up panel's parts (ui.tsx Panel*): inside styles/controls.css.ts popover, its rows concentric with it ──

export const panelHead = style({ display: "grid", gap: 2, padding: "2px 4px 4px" });
export const panelTitle = style({ fontSize: vars.textUi, fontWeight: 600 });
export const panelNote = style({ margin: 0, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted });
export const panelGroup = style({ display: "grid", gap: 2 });
export const panelLabel = style({ padding: "6px 4px 2px", fontSize: vars.textMeta, color: vars.muted });
export const panelRow = style({
  display: "flex", alignItems: "center", gap: 10, minHeight: 34, padding: "0 8px", border: 0, borderRadius: "var(--panel-in)",
  cornerShape: vars.cornerShape, background: "none", color: vars.text, fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover } },
});
export const panelRowIcon = style({ display: "grid", placeItems: "center", width: 20, color: vars.muted, flex: "none" });
export const panelRowLabel = style({ flex: 1, minWidth: 0 });
export const panelRowEnd = style({ display: "flex", color: vars.subtle, flex: "none" });
export const panelFoot = style({ display: "flex", justifyContent: "flex-end", gap: 6, paddingTop: 4 });
