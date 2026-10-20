// The shared parts' own looks (parts.tsx): fields, choices, switches, dialogs, tips, the parts of a small panel, a
// list's first one, a column's edge. What the pages put around them is the app's (web/src/ui.css.ts after this one).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { panel } from "./styles/glass.ts";
import { dialogInKeyframes, fadeKeyframes } from "./styles/keyframes.css.ts";
import { iconBtn } from "./styles/page.css.ts";
import { PANEL_PILL, TEXT_IN } from "./styles/align.ts";

/** What a choice or a switch's row says under its title: quieter. */
export const note = style({ color: vars.muted });
export const firstOneTitle = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "12px 0 0", fontSize: vars.textTitle,
  fontWeight: "600",
});
export const firstOneLead = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "0", maxWidth: "34em",
  color: vars.muted, fontSize: vars.textUi, lineHeight: "1.6",
});
export const dialogLead = style({});
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
});
export const segmentedOption = style({
  display: "grid", placeItems: "center",
  height: "30px", padding: "0 12px", border: "0", borderRadius: "999px", background: "transparent", color: vars.muted,
  whiteSpace: "nowrap",
  fontSize: vars.textUi, cursor: "pointer", transition: `color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover:not([data-state=\"on\"]):not(:disabled)": { color: vars.text },
    "&[data-state=\"on\"]": { color: vars.text, fontWeight: "500" },
    // One that cannot be chosen: fainter, and no pointer or hover saying otherwise.
    "&:disabled": { cursor: "default" },
    "&:disabled:not([data-state=\"on\"])": { opacity: ".4" },
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
  // Its card's own corner, whatever the card is rounded to (a dialog's cards: DIALOG_INNER).
  borderRadius: "inherit", background: "none", textAlign: "left", cursor: "pointer",
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
/** Its copy button at its right end, 6 in: rounded as it less that (concentric). */
globalStyle(`${command} ${iconBtn}`, { borderRadius: `calc(${vars.rField} - 6px)`, cornerShape: vars.cornerShape });
export const overlay = style({
  position: "fixed", inset: "0", zIndex: "40", background: vars.overlay,
  animation: `${fadeKeyframes} 180ms ${vars.easeOut}`,
});
/**
 * A dialog's corners and what sits at them are one curve (concentric): its padding (DIALOG_PAD) plus a button's half
 * height (18) is its radius, so a pill button in a corner, the close button, and a card inside (radius DIALOG_INNER) all
 * follow its edge at the same distance.
 */
export const DIALOG_PAD = 24;
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
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", padding: `${DIALOG_PAD + 1}px ${DIALOG_PAD + 2}px 0 ${DIALOG_PAD}px`,
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
globalStyle(`${switchRowText} ${note}`, { fontSize: vars.textMeta });
globalStyle(`${choiceText} strong`, { fontWeight: "600" });
globalStyle(`${choiceText} ${note}`, { fontSize: vars.textMeta, lineHeight: "1.5" });
globalStyle(`${select} > span:first-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${command} code`, { flex: "1", fontSize: vars.textMeta, overflowX: "auto", whiteSpace: "nowrap" });
globalStyle(`${dialogAlert} ${dialogLead}`, { margin: "0" });
globalStyle(`${dialogHead} > button`, { borderRadius: "999px", cornerShape: "round" });
/** Cards, choices and command lines in a dialog sit at its padding: their corners are the dialog's, less it. */
globalStyle(`${dialogBody} :is(${choice}, ${command})`, { borderRadius: DIALOG_INNER });
globalStyle(`${dialogBody} ${command} ${iconBtn}`, { borderRadius: `calc(${DIALOG_INNER} - 6px)` });
globalStyle(`${dialog} ${command} code`, { minWidth: "0" });

// ── a popped-up panel's parts (parts.tsx Panel*): inside styles/controls.css.ts popover, its rows concentric with it ──

// Its words in by a row's padding (align.ts TEXT_IN), as the rows' icons and words are: one line from the panel's edge.
export const panelHead = style({ display: "grid", gap: 2, padding: `6px ${TEXT_IN}px 4px` });
export const panelTitle = style({ fontSize: vars.textUi, fontWeight: 600 });
export const panelNote = style({ margin: 0, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted });
export const panelGroup = style({ display: "grid", gap: 2 });
export const panelLabel = style({ padding: `6px ${TEXT_IN}px 2px`, fontSize: vars.textMeta, color: vars.muted });
export const panelRow = style({
  display: "flex", alignItems: "center", gap: 10, minHeight: 34, padding: `0 ${TEXT_IN}px`, border: 0, borderRadius: "var(--panel-in)",
  cornerShape: vars.cornerShape, background: "none", color: vars.text, fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
  selectors: { "&:is(button):hover": { background: vars.hover }, "&:not(button)": { cursor: "default" } },
});
export const panelRowIcon = style({ display: "grid", placeItems: "center", width: 20, color: vars.muted, flex: "none" });
// When the row is too narrow, what is at its end is cut short, not the words; with nothing at the end, the words are.
export const panelRowLabel = style({
  flex: "1 1 auto", minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: { "&:not(:last-child)": { flexShrink: 0 } },
});
export const panelRowEnd = style({ display: "flex", alignItems: "center", gap: 6, minWidth: 0, color: vars.subtle, flex: "0 1 auto" });
export const panelFoot = style({ display: "flex", justifyContent: "flex-end", gap: 6, paddingTop: 4 });
export const panelText = style({ paddingInline: TEXT_IN });

// ── a small panel's buttons (notices, popovers, cards): small pills, whatever the panel's corner (2026-10-15) ──
/**
 * Words to press in a small panel: a small pill, 24 high, in the meta size; a ground only while pointed at.
 * `data-tone`: accent (the one thing to do), quiet (a lesser one), filled (the accent's ground always, for one that
 * must be seen). In a corner it stands as far from both edges (align.ts).
 */
export const panelButton = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 4, height: PANEL_PILL, padding: "0 10px", border: 0,
  borderRadius: 999, background: "none", color: vars.text, font: "inherit",
  fontSize: vars.textMeta, fontWeight: 500, lineHeight: `${PANEL_PILL}px`, textDecoration: "none", whiteSpace: "nowrap", cursor: "pointer", flex: "none",
  selectors: {
    "&:hover:not(:disabled)": { background: vars.hover },
    '&[data-tone="accent"]': { color: vars.accentText },
    '&[data-tone="quiet"]': { color: vars.muted },
    '&[data-tone="quiet"]:hover:not(:disabled)': { color: vars.text },
    '&[data-tone="filled"]': { background: vars.accentBg, color: vars.accentText },
    '&[data-tone="filled"]:hover:not(:disabled)': { background: `color-mix(in srgb, ${vars.accent} 22%, transparent)` },
    "&:disabled": { opacity: .5, cursor: "default" },
  },
});
/** An icon to press in a small panel (close, stop, step): a 24 circle, as panelButton is a pill. */
export const panelIcon = style({
  display: "grid", placeItems: "center", width: PANEL_PILL, height: PANEL_PILL, padding: 0, border: 0, flex: "none",
  borderRadius: "50%", background: "none", color: vars.muted, cursor: "pointer",
  selectors: { "&:hover:not(:disabled)": { background: vars.hover, color: vars.text }, "&:disabled": { opacity: .35, cursor: "default" } },
});

globalStyle(tooltip, {
  zIndex: "70", padding: "5px 10px", borderRadius: `calc(8px * ${vars.cornerScale})`, background: vars.primary,
  color: vars.onPrimary, fontSize: vars.textMeta, lineHeight: "1.4", boxShadow: `0 4px 12px ${vars.shadow}`,
  animation: `${fadeKeyframes} 120ms ${vars.easeOut}`, cornerShape: vars.cornerShape, width: "max-content",
  maxWidth: "min(300px, calc(100vw - 16px))", textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere",
});
globalStyle(dialogTitle, {
  display: "flex", alignItems: "baseline", gap: "10px", margin: "0", fontSize: vars.textHeading, fontWeight: "600",
});
globalStyle(dialogLead, { textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere" });
globalStyle(dialogLead, { margin: "6px 24px 0", fontSize: vars.textUi, color: vars.muted });
/** Why a dialog's action did not work, just above its buttons. */
globalStyle(dialogError, { margin: "12px 0 0", fontSize: vars.textUi, color: vars.red });
/** Failed a moment ago (IconButton, DoingMark): a small red round "!" where the spinner was (as the phone's), why on hover. */
export const failedMark = style({
  display: "inline-grid", placeItems: "center", flex: "none", boxSizing: "border-box", borderRadius: "50%",
  background: vars.red, color: "#fff", fontWeight: "600", lineHeight: "1", cursor: "help",
});
