import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { activityInKeyframes, emitOutKeyframes, enterUpKeyframes, jobBreatheKeyframes, jobLiveKeyframes, msgFlashKeyframes, msgWaitingInKeyframes } from "./styles/keyframes.css.ts";
import { msg } from "./styles/conversation.css.ts";
import { segmented, segmentedOption } from "./ui.css.ts";
import { detailsList } from "./pages/ChatPage.css.ts";
import { agentActivity, composerThumb, msgFlash, msgWaitingLate } from "./Chat.css.ts";
import { tokenGuide } from "./pages/SlackApp.css.ts";

export const jobDot = style({
  position: "relative", flex: "none", width: "8px", height: "8px", borderRadius: "50%", background: vars.lineStrong,
  selectors: {
    "&[data-tone=\"up\"]": { background: vars.online },
    "&[data-tone=\"live\"]": { background: vars.online },
    "&[data-tone=\"restart\"]": { background: vars.amber, animation: `${jobBreatheKeyframes} 1.4s ease-in-out infinite` },
    "&[data-tone=\"fail\"]": { background: vars.red },
    // Alive: breathing slowly (not a spinner: a watcher is not about to finish).
    "&[data-tone=\"live\"]::after": {
      content: "\"\"", position: "absolute", inset: "-4px", borderRadius: "50%", background: vars.online,
      animation: `${jobLiveKeyframes} 2.4s ease-in-out infinite`,
    },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important",
      selectors: {
        "&::after": { animation: "none !important" },
      },
    },
  },
});
export const jobRow = style({
  display: "flex", alignItems: "flex-start", gap: "12px", flexShrink: "0", width: "100%", padding: "6px 8px 6px 12px",
  border: "0", borderRadius: vars.rOption, background: "none", color: vars.text, font: "inherit", textAlign: "left",
  cursor: "pointer", cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-selected]": { background: vars.selected },
    "&[data-static]": { cursor: "default" },
    "&[data-off]": { opacity: ".55" },
  },
});
export const jobFold = style({});
export const jobText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", gap: "1px" });
export const jobName = style({
  fontSize: vars.textSm, fontWeight: "500", lineHeight: "1.55", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
export const jobMeta = style({
  fontSize: vars.textXs, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  fontVariantNumeric: "tabular-nums",
});
export const jobWord = style({
  fontStyle: "normal",
  selectors: {
    "&[data-tone=\"up\"]": { color: vars.green },
    "&[data-tone=\"live\"]": { color: vars.green },
    "&[data-tone=\"restart\"]": { color: vars.amber },
    "&[data-tone=\"fail\"]": { color: vars.red },
  },
});
export const jobSaid = style({ color: vars.text });
export const jobEnd = style({
  display: "grid", placeItems: "center", flex: "none", alignSelf: "center", width: "24px", color: vars.subtle,
  transition: `color ${vars.dur} ${vars.easeOut}, transform ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${jobRow}:hover &`]: { color: vars.text },
  },
});
export const jobNotices = style({
  listStyle: "none", margin: "0", padding: "0", display: "grid", gap: "6px", fontSize: vars.textXs,
  selectors: {
    "&[data-clock]": { gap: "12px", fontSize: vars.textSm },
  },
});
export const jobNoticesNone = style({ margin: "0", fontSize: vars.textXs, color: vars.muted });
export const jobLast = style({
  display: "flex", flexDirection: "column", gap: "2px", marginTop: "10px", fontSize: "11px", color: vars.subtle,
  minWidth: "0",
});
export const jobActions = style({ display: "flex", gap: "2px", margin: "6px 0 0 -8px" });
export const jobAction = style({
  display: "inline-flex", alignItems: "center", gap: "5px", height: "26px", padding: "0 8px", border: "0",
  borderRadius: `calc(8px * ${vars.cornerScale})`, background: "none", color: vars.muted, font: "inherit",
  fontSize: vars.textXs, cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.selected, color: vars.text },
  },
});
export const jobsHead = style({
  display: "flex", alignItems: "baseline", gap: "6px", padding: "8px 12px 4px", fontSize: vars.textXs,
  fontWeight: "500", color: vars.muted,
});
export const jobFoldBody = style({
  margin: "0 0 4px", padding: "4px 8px 8px 32px", background: vars.hover,
  borderRadius: `0 0 ${vars.rOption} ${vars.rOption}`, cornerShape: vars.cornerShape,
});
export const jobsAll = style({
  display: "flex", alignItems: "center", gap: "10px", width: "100%", height: "38px", marginTop: "6px",
  padding: "0 12px 0 32px", border: "0", borderRadius: vars.rOption, background: "none", color: vars.muted,
  font: "inherit", fontSize: vars.textSm, cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
export const jobsQuiet = style({ margin: "8px 12px 0 32px", fontSize: vars.textSm, color: vars.muted });
export const jobsEmpty = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: "4px", padding: "26px 20px",
  textAlign: "center", color: vars.muted, fontSize: vars.textXs,
});
/** The 任务 tab: everything listed, a job picked shows what it said or its output. */
export const jobsTab = style({ flex: "1", minHeight: "0", display: "flex", flexDirection: "column" });
export const jobsTabList = style({
  flex: "none", maxHeight: "45%", overflowY: "auto", padding: "4px 8px 8px", display: "flex", flexDirection: "column",
});
export const jobDetail = style({
  flex: "1", minHeight: "0", display: "flex", flexDirection: "column", margin: "0 8px 8px", padding: "10px 6px 0 14px",
  borderRadius: vars.rField, background: vars.paper, cornerShape: vars.cornerShape,
});
export const jobDetailHead = style({
  display: "flex", alignItems: "center", gap: "8px", minWidth: "0", fontSize: vars.textSm,
});
export const jobDetailState = style({ fontSize: vars.textXs, color: vars.muted, whiteSpace: "nowrap" });
export const jobDetailGrow = style({ flex: "1" });
export const jobDetailStop = style({ width: "28px", height: "28px" });
export const jobDetailCommand = style({
  margin: "4px 0 6px", font: `11.5px/1.5 ${vars.fontMono}`, color: vars.subtle, whiteSpace: "nowrap",
  overflow: "hidden", textOverflow: "ellipsis",
});
export const jobDetailNotices = style({ flex: "1", minHeight: "0", overflowY: "auto", padding: "8px 10px 0 0" });
export const jobOutput = style({
  flex: "1", minHeight: "0", margin: "4px 0 8px", paddingRight: "8px", overflow: "auto",
  font: `11.5px/1.6 ${vars.fontMono}`, color: vars.text, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
globalStyle(`${jobFold}[data-open] > ${jobRow}`, { background: vars.hover });
/** Here rather than with its class: it comes after .job-fold[data-open] > .job-row, and wins over it. */
globalStyle(`${jobRow}[data-static]:hover`, { background: "none" });
/** The dot sits on the name's line: centred on its line box (13px × 1.55), half a pixel up for CJK ink. */
globalStyle(`${jobRow} > ${jobDot}`, { marginTop: `calc((${vars.textSm} * 1.55 - 8px) / 2 - .5px)` });
globalStyle(`${jobNotices} li`, { display: "grid", gridTemplateColumns: "5.6em 1fr", gap: "8px" });
globalStyle(`${jobNotices} time`, { color: vars.subtle, whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums" });
globalStyle(`${jobNotices}[data-clock] li`, { gridTemplateColumns: "3.4em 1fr" });
globalStyle(`${jobNotices}[data-clock] time`, { fontSize: vars.textSm });
globalStyle(`${jobNoticesNone} code`, { font: `11.5px ${vars.fontMono}` });
globalStyle(`${jobLast} code`, {
  font: `11.5px/1.5 ${vars.fontMono}`, color: vars.muted, whiteSpace: "nowrap", overflow: "hidden",
  textOverflow: "ellipsis",
});
globalStyle(`${jobsHead} span`, { fontWeight: "400", color: vars.subtle });
globalStyle(`${jobFold}[data-open] > ${jobRow}`, { borderEndStartRadius: "0", borderEndEndRadius: "0" });
globalStyle(`${jobsAll} span`, { marginLeft: "auto", fontSize: vars.textXs, color: vars.subtle });
globalStyle(`${jobsEmpty} b`, { color: vars.text, fontSize: vars.textSm, fontWeight: "500" });
globalStyle(`${jobsTabList} section + section`, { marginTop: "6px" });
globalStyle(`${jobDetailHead} b`, { fontWeight: "600", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${jobDetailHead} ${segmented}`, {
  width: "120px", flex: "none",
  vars: { "--pad": "2px" },
});
globalStyle(`${jobDetailHead} ${segmentedOption}`, { height: "24px", fontSize: vars.textXs });
globalStyle(`${jobDetail} > ${jobLast}`, { margin: "8px 0 12px" });
/** Here rather than with its class: it comes after .job-notices li, and wins over it. */
globalStyle(`${detailsList} li`, { display: "grid", gap: "2px" });
/**
 * Activity: one line, the agent's avatar (ringed while it works) and what it does now. What it does crossfades; the
 * turn over, the line fades and folds away.
 */
/** Here rather than with its class: it comes after [data-enter], and wins over it. */
globalStyle(agentActivity, {
  display: "grid", gridTemplateRows: "1fr", gridTemplateColumns: "minmax(0, 1fr)",
  animation: `${activityInKeyframes} 220ms ${vars.easeOut} both`,
  transition: `grid-template-rows 220ms ${vars.easeOut}, opacity 220ms ${vars.easeOut}`,
});
/** Here rather than with its class: it comes after .job-dot[data-tone="restart"], and wins over it. */
globalStyle(`${msg}[data-emitting] > *`, {
  transformOrigin: "12px 12px", willChange: "transform, clip-path",
  animation: `${emitOutKeyframes} 380ms ${vars.easeOut} both`,
});
/** Here rather than with its class: it comes after .agent-activity, and wins over it. */
globalStyle(`${agentActivity}, ${msg}[data-emitting] > *`, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
/** Here rather than with its class: it comes after .agent-activity, and wins over it. */
globalStyle(agentActivity, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      transition: "none",
    },
  },
});
/** Here rather than with its class: it comes after [data-enter], and wins over it. */
globalStyle(msgFlash, {
  animation: `${msgFlashKeyframes} 1400ms ${vars.easeOut}`, borderRadius: `calc(12px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape,
});
/** Here rather than with its class: it comes after .msg-flash, and wins over it. */
globalStyle(msgFlash, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none", outline: `2px solid ${vars.accent}`,
    },
  },
});
/** Here rather than with its class: it comes after [data-enter], and wins over it. */
globalStyle(composerThumb, {
  position: "relative", display: "block", width: "64px", height: "64px",
  borderRadius: `calc(10px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, overflow: "hidden",
  background: vars.neutralBg, animation: `${enterUpKeyframes} 180ms ${vars.easeOut} both`,
});
/** Here rather than with its class: it comes after .job-notices li, and wins over it. */
globalStyle(`${tokenGuide} li`, {
  counterIncrement: "guide", display: "grid", gap: "4px", paddingLeft: "36px", position: "relative",
  fontSize: vars.textSm,
});
/** A message its agents have not taken yet says so only after a second (most are taken before). */
/** Here rather than with its class: it comes after [data-enter], and wins over it. */
globalStyle(msgWaitingLate, { animation: `${msgWaitingInKeyframes} 0s linear 1s both` });
