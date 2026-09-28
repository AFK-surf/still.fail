import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeInKeyframes } from "./styles/keyframes.css.ts";
import { msg, pageBarTitle } from "./styles/conversation.css.ts";
import { sessionPage } from "./styles/session.css.ts";
import { mineFilterBtn, mineFilterWide } from "./components.css.ts";
import { textToggle } from "./styles/controls.css.ts";
import { chooserMenu } from "./styles/chat.css.ts";
import { accountMenu } from "./cloud/workspace.css.ts";
import { detailRow, details, sessionDetails, sideContent } from "./pages/ChatPage.css.ts";

export const history = style({
  minWidth: "0", minHeight: "0", display: "flex", flexDirection: "column", borderLeft: `1px solid ${vars.line}`,
  background: vars.canvas,
  selectors: {
    [`${sideContent} &`]: { borderLeft: "0", flex: "1" },
  },
});
export const historyHead = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "8px", height: "44px",
  padding: "0 8px 0 16px", borderBottom: `1px solid ${vars.line}`,
});
export const historyIdentity = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", fontSize: vars.textSm, color: vars.muted,
  whiteSpace: "nowrap", overflow: "hidden",
});
export const historyTools = style({ display: "flex", alignItems: "center", gap: "2px", flex: "none" });
export const usage = style({
  display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(96px, 1fr))", gap: "10px 16px", margin: "0",
  padding: "12px 16px", borderBottom: `1px solid ${vars.line}`, background: vars.list,
});
export const historyBody = style({
  flex: "1", minHeight: "0", overflowY: "auto", padding: "12px 16px 40px", display: "grid",
  gridTemplateColumns: "minmax(0, 1fr)", gap: "14px", alignContent: "start", overflowAnchor: "none",
});
export const hPost = style({ minWidth: "0" });
export const hSteps = style({
  minWidth: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "2px", margin: "4px 0 0 6px",
  paddingLeft: "10px", borderLeft: `1px solid ${vars.line}`,
});
export const historyEdge = style({ margin: "4px 0", textAlign: "center", fontSize: vars.textXs, color: vars.muted });
export const hReceived = style({ display: "grid", gap: "6px" });
/** What does not fit goes to the next line, and a long place is cut short, rather than squeezing the words. */
export const hLabel = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "4px 6px", minWidth: "0", fontSize: vars.textXs,
  color: vars.muted,
});
/** A Slack user's name: a button that says whether it is the viewer. */
export const hPerson = style({
  font: "inherit", color: "inherit", background: "none", border: "0", padding: "0", cursor: "pointer",
  selectors: {
    "&:hover": { textDecoration: "underline" },
  },
});
export const hPlace = style({
  selectors: {
    "a&": { cursor: "pointer" },
    "button&": { cursor: "pointer" },
    "a&:hover": { background: vars.hover, textDecoration: "underline" },
    "button&:hover": { background: vars.hover, textDecoration: "underline" },
  },
});
export const hQuote = style({
  margin: "0", paddingLeft: "12px", borderLeft: `2px solid ${vars.lineStrong}`, fontSize: vars.textSm,
  whiteSpace: "pre-wrap", overflowWrap: "anywhere",
  selectors: {
    "&[data-clamped=\"true\"]": {
      display: "-webkit-box", WebkitLineClamp: "4", WebkitBoxOrient: "vertical", overflow: "hidden",
    },
    [`${hPost}[data-failed="true"] &`]: { borderLeftColor: vars.red },
  },
});
/** A sent message's words are Markdown: the bar of a received one, without its plain-text wrapping. */
export const hQuoteMd = style({ whiteSpace: "normal" });
export const hMark = style({
  display: "flex", alignItems: "center", gap: "10px", fontSize: vars.textXs, color: vars.muted,
  selectors: {
    "&::before": { content: "\"\"", flex: "1", height: "1px", background: vars.line },
    "&::after": { content: "\"\"", flex: "1", height: "1px", background: vars.line },
  },
});
export const hText = style({ color: vars.text });
export const hSub = style({ paddingLeft: "14px", borderLeft: `2px dashed ${vars.lineStrong}` });
export const hGroup = style({ borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape });
export const hGroupHead = style({
  display: "flex", alignItems: "center", gap: "6px", width: "100%", padding: "6px 8px", margin: "0 -8px", border: "0",
  borderRadius: `calc(10px * ${vars.cornerScale})`, background: "none", color: vars.muted, fontSize: vars.textXs,
  textAlign: "left", cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
export const hStep = style({});
export const hStepName = style({
  fontWeight: "600", flex: "none", whiteSpace: "nowrap",
  selectors: {
    [`${hStep}[data-failed="true"] &`]: { color: vars.red },
  },
});
export const hStepHint = style({
  flex: "1", minWidth: "0", color: vars.muted, fontFamily: vars.fontMono, overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
export const hStepMeta = style({
  flex: "none", color: vars.subtle, fontVariantNumeric: "tabular-nums",
  selectors: {
    [`${hStep}[data-failed="true"] &`]: { color: vars.red },
  },
});
export const hStepBody = style({
  padding: "4px 6px 8px", fontSize: vars.textXs, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
export const hThinking = style({
  padding: "2px 0 6px 6px", fontSize: vars.textXs, color: vars.muted, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
export const historyDetails = style({ borderBottom: `1px solid ${vars.line}`, background: vars.list });
export const flip = style({
  selectors: {
    [`${textToggle} &`]: { transform: "rotate(180deg)" },
  },
});
export const hPlaceName = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
export const hLiveThinking = style({
  display: "grid", gap: "4px", fontSize: vars.textXs, color: vars.muted, whiteSpace: "nowrap", overflow: "hidden",
  textOverflow: "ellipsis",
});
/** Long history text folds to five lines. */
export const fold = style({ display: "grid", gap: "2px", minWidth: "0" });
export const foldBody = style({
  selectors: {
    "&[data-folded]": {
      maxHeight: "calc(5lh + 2px)", overflow: "hidden",
      WebkitMaskImage: "linear-gradient(to bottom, #000 60%, transparent)",
      maskImage: "linear-gradient(to bottom, #000 60%, transparent)",
    },
    "&[data-anim]": { transition: `max-height 240ms ${vars.easeOut}` },
    "&[data-anim]:not([data-folded])": { maxHeight: "4000px" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      selectors: {
        "&[data-anim]": { transition: "none" },
      },
    },
  },
});
export const foldToggle = style({ justifySelf: "start" });
/** A message the agent sent: no frame of its own (its code blocks keep theirs), a rule in the accent down the side. */
export const hPhase = style({
  display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textXs, color: vars.muted, minHeight: "20px",
  selectors: {
    "&[data-phase=\"responding\"]": { color: vars.text },
  },
});
export const hPhaseTime = style({ fontVariantNumeric: "tabular-nums", color: vars.subtle });
/** An entry an activity row opened the history at: shown for a moment, then back to the page. */
export const hItem = style({
  display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "14px", minWidth: "0",
  borderRadius: `calc(8px * ${vars.cornerScale})`, transition: `background-color 900ms ${vars.easeOut}`,
  cornerShape: vars.cornerShape,
  selectors: {
    "&[data-focus]": { background: `color-mix(in oklch, ${vars.accent} 10%, transparent)`, transition: "none" },
  },
});
export const hPhaseText = style({ animation: `${fadeInKeyframes} 180ms ${vars.easeOut}` });
export const hStepSaid = style({
  minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: vars.text,
});
globalStyle(`${usage} dt`, { fontSize: vars.textXs, color: vars.muted });
globalStyle(`${usage} dd`, {
  margin: "2px 0 0", fontSize: vars.textSm, fontWeight: "600", fontVariantNumeric: "tabular-nums",
});
globalStyle(`${historyBody} > *`, { minWidth: "0" });
globalStyle(`${hLabel} strong`, { color: vars.text, fontWeight: "600" });
globalStyle(`${hReceived} ${textToggle}`, { justifySelf: "start", paddingLeft: "0" });
globalStyle(`${hPost} ${hLabel} svg`, { color: vars.accent });
/** One line each: what does not fit ends in an ellipsis (the whole of it is the row's tooltip). */
globalStyle(`${hGroupHead} > span:first-of-type`, {
  flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
globalStyle(`${hStep} summary`, {
  display: "flex", alignItems: "baseline", gap: "8px", padding: "5px 6px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, listStyle: "none", cursor: "pointer", fontSize: vars.textXs,
  cornerShape: vars.cornerShape,
});
globalStyle(`${hStep} summary::-webkit-details-marker`, { display: "none" });
globalStyle(`${hStep} summary:hover`, { background: vars.hover });
/** Here rather than with its class: it comes after .h-group-head > span:first-of-type, and wins over it. */
globalStyle(`${sessionPage} ${pageBarTitle} > :not(h1)`, { flex: "none" });
/** Here rather than with its class: it comes after .history-body > *, and wins over it. */
globalStyle(accountMenu, { minWidth: "260px" });
/** Here rather than with its class: it comes after .history-body > *, and wins over it. */
globalStyle(mineFilterBtn, {
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "6px", flex: "none", height: "32px",
  minWidth: "32px", padding: "0 8px", border: "0", borderRadius: `calc(8px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape, background: "none", color: vars.muted, font: "inherit", fontSize: vars.textSm,
  cursor: "pointer",
});
/** Here rather than with its class: it comes after .mine-filter-btn, and wins over it. */
globalStyle(mineFilterWide, { border: `1px solid ${vars.line}`, marginBottom: "12px" });
/** Here rather than with its class: it comes after .usage dd, and wins over it. */
globalStyle(`${detailRow} dd`, { margin: "0", minWidth: "0" });
globalStyle(`${historyDetails} ${sessionDetails}`, { padding: "12px 16px", maxHeight: "50vh" });
globalStyle(`${historyDetails} + ${usage}`, { background: vars.list });
/** Details pack tight: two columns of short facts, small type. */
globalStyle(`${historyDetails} ${sessionDetails}`, { gap: "10px", padding: "10px 14px" });
globalStyle(`${historyDetails} ${details}`, { gridTemplateColumns: "repeat(auto-fill, minmax(180px, 1fr))", gap: "4px 16px" });
globalStyle(`${historyDetails} ${detailRow}`, {
  gridTemplateColumns: "4.5em minmax(0, 1fr)", gap: "8px", fontSize: vars.textXs, minHeight: "22px",
});
globalStyle(`${historyDetails} ${detailRow} dd`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${hPlace} > svg`, { flex: "none" });
globalStyle(`${historyDetails} ${details}`, { gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" });
/** Here rather than with its class: it comes after .history-details .detail-row, and wins over it. */
globalStyle(`${msg}[data-held] > *`, { minHeight: "0", overflow: "hidden", visibility: "hidden" });
/** Here rather than with its class: it comes after .history-body > *, and wins over it. */
globalStyle(chooserMenu, { maxHeight: "360px", overflowY: "auto", minWidth: "220px" });
