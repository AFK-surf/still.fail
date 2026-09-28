import { globalStyle, style } from "@vanilla-extract/css";
import { msgAvatar } from "../styles/chat.css.ts";
import { activityAvatar, activityElapsed, activityLine } from "../Chat.css.ts";
import { jobDot } from "../Jobs.css.ts";
import { mMessages, mMine } from "./styles/chat.css.ts";

export const mCenter = style({
  flex: "1", display: "grid", placeItems: "center", padding: "32px", textAlign: "center", fontSize: "14px",
});
export const mInfoLabel = style({ width: "72px", flex: "none", color: "var(--m-muted)" });
export const mInfoAgent = style({ display: "flex", flexDirection: "column" });
export const mChatBar = style({
  position: "absolute", top: "0", left: "0", right: "0", zIndex: "3", display: "flex", alignItems: "center",
  padding: "calc(var(--m-top) + 6px) 16px 8px 4px",
});
export const mChatBack = style({
  display: "grid", placeItems: "center", flex: "none", width: "40px", height: "40px", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-accent) !important", cursor: "pointer",
});
export const mChatBarTitle = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "8px", paddingRight: "8px",
});
export const mBarAgent = style({ flex: "none", padding: "0", border: "0", background: "none", cursor: "pointer" });
export const mRow = style({
  selectors: {
    // A message is a block; waiting its turn or coming out of an avatar it folds as the desktop's does (Chat.css.ts).
    [`${mMessages} &`]: { fontSize: "15px", lineHeight: "1.4" },
    [`${mMessages} &:not([data-held]):not([data-emitting])`]: { display: "block" },
  },
});
export const mOlder = style({ display: "grid", placeItems: "center" });
export const mChatEmpty = style({ padding: "30px 24px", fontSize: "14px", color: "var(--m-muted)", textAlign: "center" });
export const mUnreadLine = style({ display: "flex", alignItems: "center", gap: "10px" });
export const mSaidBody = style({
  borderRadius: "12px", minWidth: "0", WebkitTouchCallout: "none",
  selectors: {
    "&[data-pressed]": { boxShadow: "inset 0 0 0 999px color-mix(in srgb, var(--m-accent) 12%, transparent)" },
  },
});
export const mUnsent = style({
  display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "4px", marginTop: "4px", fontSize: "12px",
});
export const mUnsentNote = style({
  marginRight: "6px", padding: "0", border: "0", background: "none", color: "var(--m-red)", font: "inherit",
});
export const mUnsentBtn = style({
  padding: "4px 8px", border: "0", borderRadius: "8px", background: "none", color: "var(--m-muted)", font: "inherit",
  selectors: {
    "&:active": { background: "var(--m-surface2)" },
  },
});
export const mSaid = style({ display: "flex", flexDirection: "column", gap: "4px", minWidth: "0" });
export const mSaidHead = style({ display: "flex", alignItems: "center", gap: "6px" });
export const mAgentHead = style({
  display: "inline-flex", alignItems: "center", gap: "6px", minWidth: "0", padding: "0", border: "0",
  borderRadius: "6px", background: "none", color: "var(--m-ink)",
  selectors: {
    "button&": { cursor: "pointer" },
  },
});
export const mMd14 = style({ fontSize: "14px", lineHeight: "21px" });
export const mSystem = style({
  display: "flex", gap: "8px", alignSelf: "center", maxWidth: "min(460px, 100%)", boxSizing: "border-box",
  padding: "9px 12px", borderRadius: "14px", background: "color-mix(in srgb, var(--m-warn) 12%, transparent)",
  border: "1px solid color-mix(in srgb, var(--m-warn) 25%, transparent)",
});
export const mQuote = style({ maxWidth: "280px", borderRadius: "12px", background: "var(--m-chip)", overflow: "hidden" });
export const mQuoteSource = style({
  display: "flex", gap: "6px", boxSizing: "border-box", width: "100%", padding: "6px 10px", border: "0",
  background: "color-mix(in srgb, var(--m-accent-bg) 60%, transparent)", color: "var(--m-muted) !important",
  fontSize: "12px !important", textAlign: "left",
});
export const mQuoteComment = style({ padding: "6px 10px", fontSize: "13px" });
export const mActivity = style({});
export const mJump = style({
  position: "absolute", right: "18px", bottom: "calc(var(--m-bottom) + 2px)", zIndex: "2", display: "grid",
  placeItems: "center", width: "36px", height: "36px", padding: "0", borderRadius: "50%",
  color: "var(--m-ink) !important", opacity: "0", transform: "translateY(18px) scale(.6)", pointerEvents: "none",
  transition: "opacity 150ms, transform 180ms var(--m-standard)", cursor: "pointer",
  selectors: {
    "&[data-shown]": {
      opacity: "1", transform: "none", pointerEvents: "auto",
      transition: "opacity 180ms, transform 220ms var(--m-standard)",
    },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mFiles = style({
  display: "flex", flexDirection: "column", alignItems: "flex-start", gap: "6px",
  selectors: {
    [`${mMine} &`]: { alignItems: "flex-end" },
  },
});
export const mImage = style({
  display: "block", padding: "0", border: "0", borderRadius: "14px", background: "var(--m-chip)", overflow: "hidden",
  cursor: "zoom-in",
});
export const mFile = style({
  display: "inline-flex", alignItems: "center", gap: "8px", boxSizing: "border-box", maxWidth: "260px",
  padding: "8px 10px", borderRadius: "12px", background: "var(--m-chip)", color: "var(--m-muted)",
  selectors: {
    "&[data-composer]": { borderRadius: "18px" },
  },
});
export const mFileText = style({ display: "flex", flexDirection: "column", minWidth: "0" });
export const mFileOpen = style({
  display: "inline-flex", maxWidth: "100%", padding: "0", border: "0", background: "none", font: "inherit",
  textAlign: "left", borderRadius: "12px",
});
export const mFileRemove = style({
  display: "grid", placeItems: "center", width: "20px", height: "20px", padding: "0", border: "0", background: "none",
  color: "var(--m-subtle) !important",
});
export const mComposerBar = style({ display: "flex", alignItems: "flex-end", gap: "2px" });
export const mPlus = style({
  display: "grid", placeItems: "center", flex: "none", width: "36px", height: "36px", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-ink) !important", cursor: "pointer",
  selectors: {
    "&:disabled": { opacity: ".35", cursor: "default" },
  },
});
export const mComposerField = style({
  flex: "1", minWidth: "0", minHeight: "36px", boxSizing: "border-box", margin: "0", padding: "7px 14px 7px 0",
  border: "0", background: "transparent", color: "var(--m-ink)", font: "inherit", fontSize: "16px", lineHeight: "21px",
  resize: "none", outline: "none",
  selectors: {
    "&::placeholder": { color: "var(--m-subtle)" },
  },
});
export const mSend = style({
  display: "grid", placeItems: "center", flex: "none", width: "36px", height: "36px", padding: "0", border: "0",
  borderRadius: "50%", background: "color-mix(in srgb, var(--text) 18%, var(--raised))", color: "var(--raised) !important",
  cursor: "pointer",
  selectors: {
    "&[data-ready]": { background: "var(--m-ink)", color: "var(--m-bg) !important" },
  },
});
export const mDraftQuote = style({ borderRadius: "18px", background: "var(--m-chip)", overflow: "hidden" });
export const mDraftQuoteSource = style({
  display: "flex", alignItems: "center", gap: "8px", padding: "6px 4px 6px 10px",
  background: "color-mix(in srgb, var(--m-accent-bg) 60%, transparent)", fontSize: "12px", color: "var(--m-muted)",
});
export const mDraftQuoteComment = style({
  boxSizing: "border-box", width: "100%", padding: "8px 10px", border: "0", background: "transparent",
  color: "var(--m-ink)", font: "inherit", fontSize: "16px", outline: "none",
  selectors: {
    "&::placeholder": { color: "var(--m-subtle)" },
  },
});
export const mDraftFiles = style({ display: "flex", gap: "6px", overflowX: "auto" });
export const mDraftThumb = style({
  position: "relative", flex: "none", width: "56px", height: "56px", borderRadius: "18px", background: "var(--m-chip)",
  overflow: "hidden",
});
export const mDraftThumbWait = style({
  position: "absolute", inset: "0", display: "grid", placeItems: "center", background: "rgba(0, 0, 0, .25)",
  color: "#fff", fontSize: "11px",
  selectors: {
    "&[data-error]": { background: "rgba(0, 0, 0, .5)" },
  },
});
export const mAttach = style({ display: "flex", gap: "10px", padding: "4px 18px 24px" });
/** A passage selected with a mouse: 引用 over it. */
export const mQuotePop = style({
  position: "fixed", zIndex: "45", display: "inline-flex", alignItems: "center", gap: "4px", padding: "5px 10px",
  border: "0", borderRadius: "999px", background: "var(--m-ink)", color: "var(--m-bg) !important",
  fontSize: "13px !important", transform: "translate(-50%, calc(-100% - 8px))", cursor: "pointer",
});
export const mJob = style({
  selectors: {
    "&[data-off]": { opacity: ".55" },
  },
});
export const mJobText = style({ display: "flex", flexDirection: "column", gap: "1px", minWidth: "0" });
export const mJobHead = style({ display: "flex", alignItems: "flex-start", gap: "12px", padding: "4px 22px 14px" });
export const mJobBody = style({});
export const mJobNotices = style({ display: "grid", gap: "12px", fontSize: "14px", overflowY: "auto" });
export const mJobOutput = style({
  margin: "0", padding: "12px 14px", maxHeight: "50vh", overflow: "auto", borderRadius: "16px",
  background: "color-mix(in srgb, var(--m-ink) 5%, transparent)",
  font: "11.5px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace", whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
export const mJobLast = style({
  display: "flex", flexDirection: "column", gap: "2px", fontSize: "11px", color: "var(--m-subtle)",
});
export const mJobStop = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "6px", height: "46px", border: "0",
  borderRadius: "999px", background: "color-mix(in srgb, var(--m-red) 12%, transparent)", color: "var(--m-red)",
  font: "inherit", fontSize: "15px", fontWeight: "500", cursor: "pointer",
});
export const mJobCommand = style({
  font: "11.5px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace", color: "var(--m-muted)", overflowWrap: "anywhere",
});
/** The chat bar's button for its services and jobs: a small dot on it when one died lately (red) or a service restarts (amber). */
export const mJobsTrigger = style({ position: "relative" });
export const mJobsAlarm = style({
  position: "absolute", top: "6px", right: "6px", width: "7px", height: "7px", borderRadius: "50%",
  boxShadow: "0 0 0 2px var(--m-bg)", pointerEvents: "none",
  selectors: {
    "&[data-alarm=\"fail\"]": { background: "var(--m-red)" },
    "&[data-alarm=\"restart\"]": { background: "var(--m-warn)" },
  },
});
export const mJobsEmpty = style({
  display: "flex", flexDirection: "column", gap: "4px", padding: "12px 2px", fontSize: "13px", color: "var(--m-muted)",
});
export const mJobsAll = style({
  display: "flex", flexDirection: "column", alignItems: "flex-start", gap: "2px", marginTop: "14px",
  padding: "6px 2px", border: "0", background: "none", color: "var(--m-accent)", font: "inherit", fontSize: "14px",
  textAlign: "left", cursor: "pointer",
});
globalStyle(`${mUnreadLine} i`, {
  flex: "1", height: "1px", background: "color-mix(in srgb, var(--m-blue) 50%, transparent)",
});
globalStyle(`${mAgentHead} ${msgAvatar}`, { display: "inline-flex", flex: "none" });
globalStyle(`${mSystem} > img`, { marginTop: "2px", flex: "none" });
/** The running turn: the agent's mark in a ring that turns, and what it does. */
globalStyle(`${mActivity} ${activityLine}`, { gap: "8px", fontSize: "13px !important", color: "var(--m-muted) !important" });
globalStyle(`${mActivity} ${activityAvatar}`, { width: "20px", height: "20px", margin: "3px" });
globalStyle(`${mActivity} ${activityElapsed}`, { fontSize: "11px", color: "var(--m-subtle)" });
globalStyle(`${mImage} img`, { width: "100%", height: "100%", objectFit: "cover", display: "block" });
globalStyle(`${mFileText} small[data-error]`, { color: "var(--m-red)" });
globalStyle(`${mDraftQuoteSource} button`, {
  display: "grid", placeItems: "center", flex: "none", width: "24px", height: "24px", padding: "0", border: "0",
  background: "none", color: "var(--m-subtle) !important",
});
globalStyle(`${mDraftThumb} img`, { width: "100%", height: "100%", objectFit: "cover" });
globalStyle(`${mDraftThumb} button`, {
  position: "absolute", top: "3px", right: "3px", display: "grid", placeItems: "center", width: "18px", height: "18px",
  padding: "0", border: "0", borderRadius: "50%", background: "rgba(0, 0, 0, .5)", color: "#fff !important",
});
globalStyle(`${mAttach} button`, {
  flex: "1", display: "flex", flexDirection: "column", alignItems: "center", gap: "6px", padding: "16px 0 12px",
  border: "0", borderRadius: "18px", background: "var(--m-chip)", cursor: "pointer",
});
globalStyle(`${mJob} > ${jobDot}`, { marginTop: "calc((15px * 1.45 - 8px) / 2 - .5px)" });
globalStyle(`${mJobHead} span > span`, {
  fontSize: "12.5px", color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
globalStyle(`${mJobHead} > ${jobDot}`, { marginTop: "calc((16px * 1.45 - 8px) / 2 - .5px)" });
globalStyle(`${mJobNotices} p`, { margin: "0", display: "grid", gridTemplateColumns: "3.4em 1fr", gap: "10px" });
globalStyle(`${mJobNotices} time`, { color: "var(--m-subtle)", fontVariantNumeric: "tabular-nums" });
/** Who said it, as the wide screen names them: in the accent's ink, cut short past its room. */
globalStyle(`${mAgentHead} b`, {
  minWidth: "0", fontWeight: "650", color: "var(--m-accent-ink)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
