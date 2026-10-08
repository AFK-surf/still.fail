import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { m } from "./styles/root.css.ts";
import { mGrow } from "./styles/parts.css.ts";
import { mNavButton } from "./styles/bars.css.ts";
import { mPill } from "./styles/history.css.ts";
import { mNewNone } from "./styles/new-chat.css.ts";
import { mStationOffline } from "./Stations.css.ts";
import { mMe } from "./Me.css.ts";
import { mBarAgent, mChatBack, mJob, mJobBody, mPlus, mSend } from "./Chat.css.ts";
import { mInfoRow } from "./styles/lists.css.ts";
import { mListRow, mPickRow } from "./parts.css.ts";

export const mWarn = style({ color: "var(--m-warn)" });
export const mHHead = style({ display: "flex", alignItems: "center", gap: "6px", padding: "4px 18px 0" });
export const mHAct = style({
  display: "grid", placeItems: "center", flex: "none", width: "28px", height: "28px", padding: "0", border: "0",
  borderRadius: "50%", background: "var(--m-chip)", cursor: "pointer",
  selectors: {
    "&:disabled": { color: "var(--m-subtle) !important" },
  },
});
export const mHSummary = style({
  display: "flex", alignItems: "center", gap: "10px", padding: "6px 18px 8px", fontSize: vars.textCaption,
});
export const mHBody = style({ position: "relative", flex: "1", minHeight: "0" });
export const mHSteps = style({
  position: "absolute", inset: "0", display: "flex", flexDirection: "column", gap: "10px", overflowY: "auto",
  overscrollBehavior: "contain", padding: "0 18px 24px",
});
export const mHEdge = style({ padding: "10px 0", fontSize: vars.textCaption, color: "var(--m-subtle)", textAlign: "center" });
export const mHItem = style({
  borderRadius: "8px", transition: "background 900ms",
  selectors: {
    "&[data-marked]": { background: "color-mix(in srgb, var(--m-accent) 10%, transparent)" },
  },
});
export const mHLive = style({
  fontSize: vars.textMeta, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mHReceived = style({ display: "flex", flexDirection: "column", gap: "10px" });
export const mHMessage = style({ display: "flex", flexDirection: "column", gap: "5px" });
export const mHLabel = style({
  display: "flex", alignItems: "center", flexWrap: "wrap", fontSize: vars.textMeta, color: "var(--m-muted)", minWidth: "0",
});
export const mHQuote = style({ paddingLeft: "10px", borderLeft: "2px solid var(--m-line)" });
export const mHBrief = style({
  display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical", overflow: "hidden",
  boxSizing: "border-box", width: "100%", padding: "0", border: "0", borderRadius: "6px", background: "none",
  color: "var(--m-ink) !important", fontSize: `${vars.textUi} !important`, lineHeight: "21px", textAlign: "left",
  cursor: "pointer",
});
export const mHSub = style({ paddingLeft: "12px" });
export const mHMark = style({ display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: "var(--m-muted)" });
export const mHPlace = style({
  display: "inline-flex", alignItems: "center", gap: "3px", maxWidth: "100%", minWidth: "0", padding: "0", border: "0",
  borderRadius: "4px", background: "none", verticalAlign: "middle",
  selectors: {
    "&[data-link]": { cursor: "pointer" },
  },
});
export const mHGroupHead = style({
  display: "flex", alignItems: "center", gap: "6px", boxSizing: "border-box", width: "100%", padding: "4px 0",
  border: "0", borderRadius: "6px", background: "none", color: "var(--m-subtle) !important", textAlign: "left",
  cursor: "pointer",
});
export const mHGroupBody = style({ display: "flex", flexDirection: "column", gap: "6px", padding: "4px 0 4px 19px" });
export const mHThought = style({ fontSize: vars.textMeta, lineHeight: "20px", color: "var(--m-muted)", whiteSpace: "pre-wrap" });
export const mHFold = style({ display: "flex", flexDirection: "column", gap: "4px" });
export const mHFoldHead = style({
  display: "flex", alignItems: "center", gap: "8px", boxSizing: "border-box", width: "100%", padding: "3px 0",
  border: "0", background: "none", textAlign: "left", cursor: "pointer",
});
export const mHFoldName = style({
  fontSize: vars.textMeta, color: "var(--m-ink)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: {
    "&[data-hint]": { fontWeight: "500", flex: "none", maxWidth: "50%" },
    "&:not([data-hint])": { flex: "1" },
    [`${mHFoldHead}[data-failed] &`]: { color: "var(--m-red)" },
  },
});
export const mHFoldHint = style({
  flex: "1", minWidth: "0", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: vars.textCaption,
  color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mHFoldMeta = style({
  flex: "none", fontSize: vars.textCaption, color: "var(--m-subtle)",
  selectors: {
    [`${mHFoldHead}[data-failed] &`]: { color: "var(--m-red)" },
  },
});
export const mHPhase = style({ display: "inline-flex", alignItems: "center", gap: "8px", fontSize: vars.textMeta });
export const mHDetails = style({
  position: "absolute", inset: "0", overflowY: "auto", overscrollBehavior: "contain", padding: "0 18px 30px",
});
export const mRunRow = style({
  display: "flex", alignItems: "center", gap: "6px", boxSizing: "border-box", width: "100%", marginTop: "6px",
  padding: "10px 12px", border: "1px solid var(--m-line)", borderRadius: "10px", background: "none", textAlign: "left",
  cursor: "pointer",
});
export const mHFacts = style({ display: "flex", flexDirection: "column", gap: "8px", padding: "12px 0 10px" });
export const mHDetail = style({ display: "flex", gap: "16px", fontSize: vars.textUi });
export const mHRings = style({ display: "flex", gap: "18px", padding: "10px 0" });
/** Changing how it runs. */
export const mRunSummary = style({
  display: "flex", flexDirection: "column", gap: "6px", marginTop: "8px", padding: "14px", borderRadius: "14px",
  background: "var(--m-chip)",
});
export const mRunLine = style({ display: "flex", alignItems: "center", gap: "8px" });
export const mRunWas = style({
  flex: "1", minWidth: "0", fontSize: vars.textUi, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: {
    "&[data-moved]": { flex: "0 1 auto", color: "var(--m-muted)" },
  },
});
export const mRunBecomes = style({
  flex: "1", minWidth: "0", fontSize: vars.textUi, fontWeight: "600", color: "var(--m-accent)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mSettingRow = style({
  display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "100%", minHeight: "46px",
  padding: "12px 14px", border: "0", borderRadius: "12px", background: "var(--m-chip)", textAlign: "left", cursor: "pointer",
});
export const mSettingText = style({ display: "flex", flexDirection: "column" });
export const mPickLine = style({
  display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "100%", minHeight: "44px",
  padding: "11px 4px",
  border: "0", borderRadius: "10px", background: "none", fontSize: `${vars.textBody} !important`, textAlign: "left",
  cursor: "pointer",
});
export const mPickCheck = style({
  display: "grid", placeItems: "center", width: "18px", flex: "none", color: "var(--m-accent)",
});
export const mFilter = style({ margin: "8px 0 4px" });
export const mAccountNote = style({ padding: "8px 0 4px" });
globalStyle(`${mHHead} > b`, {
  flex: "1", minWidth: "0", fontSize: vars.textTitle, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
globalStyle(`${mHSteps} > *`, { flex: "none" });
globalStyle(`${mHLabel} > svg`, { flex: "none", marginRight: "5px" });
globalStyle(`${mHLabel} b`, { color: "var(--m-ink)", fontWeight: "600" });
globalStyle(`${mHPlace} b`, {
  fontSize: vars.textMeta, fontWeight: "600", color: "var(--m-ink)", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
globalStyle(`${mHPlace}[data-link] b`, { color: "var(--m-accent-ink)" });
globalStyle(`${mHGroupHead} > span:not(${mPill})`, {
  flex: "0 1 auto", minWidth: "0", fontSize: vars.textMeta, color: "var(--m-muted)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
globalStyle(`${mHGroupHead} > span[data-open]`, {
  whiteSpace: "normal", display: "-webkit-box", WebkitLineClamp: "3", WebkitBoxOrient: "vertical",
});
globalStyle(`${mHGroupHead} > span[data-failed]`, { color: "var(--m-red)" });
globalStyle(`${mHPhase} i`, { width: "7px", height: "7px", borderRadius: "50%", background: "var(--m-accent)" });
globalStyle(`${mRunRow} b`, { flex: "none", fontSize: vars.textUi, fontWeight: "400", whiteSpace: "nowrap" });
globalStyle(`${mRunRow} span`, {
  flex: "1", minWidth: "0", fontSize: vars.textMeta, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
globalStyle(`${mRunRow} svg:last-child`, { flex: "none", color: "var(--m-muted)" });
globalStyle(`${mHDetail} > span:first-child`, { width: "64px", flex: "none", color: "var(--m-muted)" });
globalStyle(`${mRunLine} svg`, { flex: "none" });
globalStyle(`${mSettingRow} > svg:last-child`, { flex: "none", color: "var(--m-muted)" });
globalStyle(`${mPickLine} ${mGrow}`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** Here rather than with its class: it comes after .m-h-steps > *, and wins over it. */
globalStyle(mNewNone, {
  flex: "1", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "10px",
  padding: "30px", textAlign: "center",
});
/** Here rather than with its class: it comes after .m-h-head > b, and wins over it. */
globalStyle(`${mNewNone} b`, { fontSize: vars.textTitle, fontWeight: "600" });
/** Here rather than with its class: it comes after .m-run-row span, and wins over it. */
globalStyle(`${mStationOffline} span`, { fontSize: vars.textMeta, color: "var(--m-muted)" });
/** Here rather than with its class: it comes after .m-h-label b, and wins over it. */
globalStyle(`${mMe} b`, { display: "block", fontSize: vars.textTitle, fontWeight: "600" });
globalStyle(`${m} :is(${mNavButton}, ${mPlus}, ${mSend}, ${mChatBack}, ${mHAct}, ${mBarAgent})`, {
  "@media": {
    "(pointer: coarse)": {
      position: "relative",
    },
  },
});
globalStyle(`${m} :is(${mNavButton}, ${mPlus}, ${mSend}, ${mChatBack}, ${mHAct}, ${mBarAgent})::after`, {
  "@media": {
    "(pointer: coarse)": {
      content: "\"\"", position: "absolute", inset: "min(-6px, calc((100% - 44px) / 2))",
    },
  },
});
globalStyle(`${m} :is(${mNavButton}, ${mPlus}:not(:disabled), ${mChatBack}, ${mHAct}, ${mPickRow}, ${mListRow}, ${mInfoRow}, ${mSettingRow}, ${mPickLine}):hover`, {
  "@media": {
    "(hover: hover) and (pointer: fine)": {
      backgroundColor: "color-mix(in srgb, var(--m-ink) 5%, transparent)",
    },
  },
});
/** A chat's services and background jobs (../Jobs.tsx): the dot on the name's line, what it is up to under it. */
/** Here rather than with its class: it comes after .m-h-steps > *, and wins over it. */
globalStyle(mJob, { flex: "1", minWidth: "0", display: "flex", alignItems: "flex-start", gap: "12px" });
/** Here rather than with its class: it comes after .m-h-steps > *, and wins over it. */
globalStyle(mJobBody, { display: "flex", flexDirection: "column", gap: "14px", flex: "1", minHeight: "0" });
