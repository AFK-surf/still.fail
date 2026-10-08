import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { jobDot } from "../Jobs.css.ts";
import { mChat, mMessages } from "./styles/chat.css.ts";

export const mCenter = style({
  flex: "1", display: "grid", placeItems: "center", padding: "32px", textAlign: "center", fontSize: vars.textControl,
});
export const mInfoLabel = style({ width: "72px", flex: "none", color: "var(--m-muted)" });
export const mInfoName = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", textAlign: "left" });
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
export const mBarAgent = style({ flex: "none", display: "grid", padding: "0", border: "0", background: "none", cursor: "pointer" });
/** A message held for its menu (a long press): its words marked while the menu is open; the system's own menu never comes. */
globalStyle(`${mMessages} [data-author]`, { WebkitTouchCallout: "none" });
globalStyle(`${mMessages} [data-pressed]`, {
  boxShadow: "inset 0 0 0 999px color-mix(in srgb, var(--m-accent) 12%, transparent)",
});
export const mJump = style({
  position: "absolute", right: "18px", bottom: "calc(var(--m-composer-room) + var(--asks-height, 0px) + 2px)", zIndex: "2", display: "grid",
  placeItems: "center", width: "36px", height: "36px", padding: "0", borderRadius: "50%",
  color: "var(--m-ink) !important", opacity: "0", transform: "translateY(18px) scale(.6)", pointerEvents: "none",
  transition: "opacity 150ms, transform 180ms var(--m-standard)", cursor: "pointer",
  selectors: {
    "&[data-shown]": {
      opacity: "1", transform: "none", pointerEvents: "auto",
      transition: "opacity 180ms, transform 220ms var(--m-standard)",
    },
    // With how many new messages wait at the end: a pill, growing leftwards from where it sits.
    "&[data-count]": { width: "auto", display: "flex", alignItems: "center", gap: "4px", padding: "0 14px 0 10px", borderRadius: "18px", whiteSpace: "nowrap" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mComposerBar = style({
  display: "flex", alignItems: "flex-end", gap: "2px",
  selectors: { "&[data-expanded]": { display: "grid", gridTemplateColumns: "36px 1fr 36px", rowGap: "4px" } },
});
export const mPlus = style({
  display: "grid", placeItems: "center", flex: "none", width: "36px", height: "36px", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-ink) !important", cursor: "pointer",
  selectors: {
    "&:disabled": { opacity: ".35", cursor: "default" },
    [`${mComposerBar}[data-expanded] &`]: { gridRow: "2", gridColumn: "1" },
  },
});
export const mComposerField = style({
  flex: "1", minWidth: "0", minHeight: "36px", boxSizing: "border-box", margin: "0", padding: "7px 14px 7px 0",
  border: "0", background: "transparent", color: "var(--m-ink)", font: "inherit", fontSize: vars.textInput, lineHeight: "21px",
  resize: "none", outline: "none", textWrap: "wrap",
  selectors: {
    "&::placeholder": { color: "var(--m-subtle)" },
    [`${mComposerBar}[data-expanded] &`]: { gridRow: "1", gridColumn: "1 / -1", width: "100%", paddingLeft: "14px" },
  },
});
export const mSend = style({
  display: "grid", placeItems: "center", flex: "none", width: "36px", height: "36px", padding: "0", border: "0",
  borderRadius: "50%", background: "color-mix(in srgb, var(--text) 18%, var(--raised))", color: "var(--raised) !important",
  cursor: "pointer",
  selectors: {
    "&[data-ready]": { background: "var(--m-ink)", color: "var(--m-bg) !important" },
    [`${mComposerBar}[data-expanded] &`]: { gridRow: "2", gridColumn: "3" },
  },
});
export const mAttach = style({ display: "flex", gap: "10px", padding: "4px 18px 24px" });
export const mJob = style({
  selectors: {
    "&[data-off]": { opacity: ".55" },
  },
});
export const mJobText = style({ display: "flex", flexDirection: "column", gap: "1px", minWidth: "0" });
export const mJobHead = style({ display: "flex", alignItems: "flex-start", gap: "12px", padding: "4px 22px 14px" });
export const mJobBody = style({});
export const mJobNotices = style({ display: "grid", gap: "12px", fontSize: vars.textControl, overflowY: "auto" });
export const mJobOutput = style({
  margin: "0", padding: "12px 14px", maxHeight: "50vh", overflow: "auto", borderRadius: "16px",
  background: "color-mix(in srgb, var(--m-ink) 5%, transparent)",
  font: `${vars.textCaption}/1.6 ui-monospace, SFMono-Regular, Menlo, monospace`, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
export const mJobLast = style({
  display: "flex", flexDirection: "column", gap: "2px", fontSize: vars.textCaption, color: "var(--m-subtle)",
});
export const mJobStop = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "6px", height: "46px", border: "0",
  borderRadius: "999px", background: "color-mix(in srgb, var(--m-red) 12%, transparent)", color: "var(--m-red)",
  font: "inherit", fontSize: vars.textBody, fontWeight: "500", cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});
export const mJobCommand = style({
  font: `${vars.textCaption}/1.5 ui-monospace, SFMono-Regular, Menlo, monospace`, color: "var(--m-muted)", overflowWrap: "anywhere",
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
  display: "flex", flexDirection: "column", gap: "4px", padding: "12px 2px", fontSize: vars.textSecondary, color: "var(--m-muted)",
});
export const mJobsAll = style({
  display: "flex", flexDirection: "column", alignItems: "flex-start", gap: "2px", marginTop: "14px",
  padding: "6px 2px", border: "0", background: "none", color: "var(--m-accent)", font: "inherit", fontSize: vars.textControl,
  textAlign: "left", cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});
/** Its words with a spinner before them while it is under way. */
export const mJobsAllLine = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
// Not the small note under it (./Connects.css.ts): the button's own words.
globalStyle(`${mJobsAll} ${mJobsAllLine}`, { fontSize: "inherit", color: "inherit" });
globalStyle(`${mAttach} button`, {
  flex: "1", display: "flex", flexDirection: "column", alignItems: "center", gap: "6px", padding: "16px 0 12px",
  border: "0", borderRadius: "18px", background: "var(--m-chip)", cursor: "pointer",
});
// The dot on the name's 21px line, half a pixel up for CJK ink (rounded to a whole pixel).
globalStyle(`${mJob} > ${jobDot}`, { marginTop: "6px" });
globalStyle(`${mJobHead} span > span`, {
  fontSize: vars.textLabel, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
globalStyle(`${mJobHead} > ${jobDot}`, { marginTop: "7px" });
globalStyle(`${mJobNotices} p`, { margin: "0", display: "grid", gridTemplateColumns: "3.4em 1fr", gap: "10px" });
globalStyle(`${mJobNotices} time`, { color: "var(--m-subtle)", fontVariantNumeric: "tabular-nums" });
// The phone's buttons take the page's font (root.css.ts), stronger than a class alone: the count's size is set as strongly.
globalStyle(`${mChat} button${mJump}[data-count]`, { fontSize: vars.textControl });

/**
 * What waits to be decided (../Asks.tsx), over the composer: its foot 10px over the capsule (8px of the composer's own
 * padding), as wide as it; in the phone's colours.
 */
export const mAsks = style({
  position: "absolute", left: "10px", right: "10px", bottom: "calc(var(--m-composer-room) + 2px)", zIndex: "4",
  vars: {
    "--ask-ink": "var(--m-ink)", "--ask-ground": "var(--m-bg)", "--ask-muted": "var(--m-muted)", "--ask-subtle": "var(--m-subtle)",
    "--ask-chip": "var(--m-chip)", "--ask-solid": "var(--m-surface)",
  },
});
