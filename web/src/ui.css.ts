import { globalStyle, style } from "@vanilla-extract/css";
import { busyRing } from "./styles/busyRing.ts";
import { vars } from "./styles/tokens.css.ts";
import { appearKeyframes, dialogInKeyframes, fadeKeyframes, pulseKeyframes, spinKeyframes } from "./styles/keyframes.css.ts";
import { gate, muted } from "./styles/shell.css.ts";
import { pageBar } from "./styles/sidebar.css.ts";
import { markdown } from "./styles/conversation.css.ts";

export const firstOneTitle = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "12px 0 0", fontSize: vars.textMd,
  fontWeight: "600",
});
export const firstOneLead = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "0", maxWidth: "34em",
  color: vars.muted, fontSize: vars.textSm, lineHeight: "1.6",
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
export const empty = style({
  flex: "1", display: "grid", placeContent: "center", justifyItems: "center", gap: "6px", padding: "40px",
  textAlign: "center", color: vars.muted,
});
/** Section titles and their actions share a centre line. */
export const sectionHead = style({
  display: "flex", justifyContent: "space-between", gap: "12px", marginBottom: "10px", alignItems: "center",
});
export const sectionSub = style({ margin: "3px 0 0", fontSize: vars.textXs, color: vars.muted, maxWidth: "52em" });
export const sectionActions = style({ display: "flex", gap: "8px" });
export const field = style({ display: "grid", gap: "6px" });
export const fieldTop = style({ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: "8px" });
export const fieldLabel = style({ fontSize: vars.textSm, fontWeight: "500" });
export const fieldHint = style({ fontSize: vars.textXs, color: vars.muted });
export const dialogError = style({});
export const select = style({
  width: "100%", minHeight: "36px", padding: "7px 12px", border: `1px solid ${vars.lineStrong}`,
  borderRadius: vars.rField, background: vars.canvas, fontSize: vars.textSm,
  transition: `border-color ${vars.dur} ${vars.easeOut}`, cornerShape: vars.cornerShape, display: "flex",
  alignItems: "center", justifyContent: "space-between", gap: "8px", textAlign: "left", cursor: "pointer",
  selectors: {
    "&:hover": { borderColor: vars.fieldHover },
    "&:focus": { outline: "none", borderColor: vars.fieldFocus },
    "&[data-placeholder]": { color: vars.subtle },
    "&:disabled": { opacity: ".55", cursor: "default" },
  },
});
/** The track tints whatever it sits on; the chosen option's ground is a thumb that slides. */
/** As tall as its options wherever it sits (a stretching row would make the track taller than them and the thumb with it). */
export const segmented = style({
  position: "relative", isolation: "isolate", display: "flex", alignItems: "center", alignSelf: "center",
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
  flex: "1", height: "30px", border: "0", borderRadius: "999px", background: "transparent", color: vars.muted,
  fontSize: vars.textSm, cursor: "pointer", transition: `color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover:not([data-state=\"on\"])": { color: vars.text },
    "&[data-state=\"on\"]": { color: vars.text, fontWeight: "500" },
  },
});
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
export const switchRow = style({ display: "flex", alignItems: "center", gap: "16px" });
export const switchRowText = style({ flex: "1", display: "grid", gap: "2px", fontSize: vars.textSm, cursor: "pointer" });
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
export const choiceText = style({ flex: "1", display: "grid", gap: "2px", fontSize: vars.textSm });
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
export const selectHint = style({ marginLeft: "auto", fontSize: vars.textXs, color: vars.muted });
export const selectCheck = style({ position: "absolute", right: "10px", display: "grid", color: vars.text });
export const pill = style({
  display: "inline-flex", alignItems: "center", height: "22px", padding: "0 9px", borderRadius: "999px",
  fontSize: vars.textXs, fontWeight: "500", whiteSpace: "nowrap", background: vars.neutralBg, color: vars.muted,
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
  display: "inline-grid", placeItems: "center", flex: "none", color: "#fff", fontWeight: "650", lineHeight: "1",
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
export const dialog = style({
  position: "fixed", left: "50%", top: "50%", zIndex: "50", transform: "translate(-50%, -50%)", display: "flex",
  flexDirection: "column", width: "min(520px, calc(100vw - 32px))", maxHeight: "calc(100dvh - 48px)",
  borderRadius: vars.rDialog, background: vars.canvas, color: vars.text, boxShadow: `0 24px 64px ${vars.shadow}`,
  animation: `${dialogInKeyframes} 200ms ${vars.easeOut}`, cornerShape: vars.cornerShape,
  selectors: {
    "&:focus": { outline: "none" },
  },
});
export const dialogWide = style({ width: "min(640px, calc(100vw - 32px))" });
export const dialogAlert = style({ width: "min(420px, calc(100vw - 32px))", padding: "32px", gap: "10px" });
export const dialogHead = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", padding: "28px 24px 0 32px",
});
export const dialogTitle = style({});
export const dialogBody = style({
  display: "grid", gap: "18px", padding: "20px 32px 4px", overflowY: "auto", minHeight: "0",
});
export const dialogFoot = style({
  display: "flex", justifyContent: "flex-end", gap: "8px", padding: "20px 32px 32px",
  selectors: {
    [`${dialogAlert} &`]: { padding: "12px 0 0" },
  },
});
export const srOnly = style({
  position: "absolute", width: "1px", height: "1px", overflow: "hidden", clip: "rect(0 0 0 0)", whiteSpace: "nowrap",
});
export const mobileBack = style({
  display: "none", alignItems: "center", gap: "2px", color: vars.muted, fontSize: vars.textSm, lineHeight: "20px",
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
  fontSize: vars.textSm, lineHeight: "20px", textDecoration: "none",
  selectors: {
    "&:hover": { color: vars.text },
  },
});
/** Loading says so only when it takes a while: a page that is there in a moment (from the device) shows nothing before it. */
export const loading = style({
  display: "flex", alignItems: "center", gap: "10px", color: vars.muted, fontSize: vars.textSm,
  animation: `${appearKeyframes} 0s linear 400ms both`,
  selectors: {
    [`${gate} &`]: { justifyContent: "center" },
  },
});
export const loadingFill = style({ flex: "1", minHeight: "100%", justifyContent: "center" });
export const splashLabel = style({
  margin: "0", maxWidth: "32em", fontSize: vars.textSm, color: vars.muted,
  animation: `${appearKeyframes} 0s linear 1s both`,
  selectors: {
    "&[data-now]": { animation: "none" },
  },
});
export const skeletonRow = style({
  display: "grid", gap: "6px", padding: "9px 10px", animation: `${appearKeyframes} 0s linear 400ms both`,
});
export const runtimeLogo = style({ flex: "none", display: "block" });
export const resizeHandle = style({
  selectors: {
    "&[data-edge=\"right\"]": { right: "-4px" },
    "&[data-edge=\"left\"]": { left: "-4px" },
    "&::after": {
      content: "\"\"", position: "absolute", top: "0", bottom: "0", left: "3px", width: "1px",
      background: "transparent", transition: `background ${vars.dur} ${vars.easeOut}`,
    },
    "&:hover::after": { background: vars.fieldFocus },
    "body[data-resizing] &::after": { background: vars.fieldFocus },
  },
  "@media": {
    "(max-width: 700px)": {
      display: "none",
    },
  },
});
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
globalStyle(`${empty} h2`, { margin: "10px 0 0", fontSize: vars.textMd, color: vars.text });
globalStyle(`${empty} p`, { margin: "0", maxWidth: "34em", fontSize: vars.textSm });
globalStyle(`${sectionHead} h2`, { margin: "0", fontSize: vars.textBody, lineHeight: "22px", fontWeight: "600" });
globalStyle(`${switchRowText} ${muted}`, { fontSize: vars.textXs });
globalStyle(`${choiceText} strong`, { fontWeight: "600" });
globalStyle(`${choiceText} ${muted}`, { fontSize: vars.textXs, lineHeight: "1.5" });
globalStyle(`${select} > span:first-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${command} code`, { flex: "1", fontSize: vars.textXs, overflowX: "auto", whiteSpace: "nowrap" });
globalStyle(`${dialogAlert} ${dialogLead}`, { margin: "0" });
/** Here rather than with its class: it comes after .empty p, and wins over it. */
globalStyle(`${markdown} p`, { margin: "0 0 8px" });
/** Here rather than with its class: it comes after .empty h2, and wins over it. */
globalStyle(`${markdown} h2`, { fontSize: vars.textBody, margin: "14px 0 6px" });
/** Here rather than with its class: it comes after .command code, and wins over it. */
globalStyle(`${markdown} code`, {
  fontSize: "12px", padding: "1px 5px", borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.neutralBg,
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
