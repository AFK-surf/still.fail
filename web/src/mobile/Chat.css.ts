import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { jobDot } from "../Jobs.css.ts";
import { mChat, mListTop, mMessages } from "./styles/chat.css.ts";
import { outsetTop } from "@stillfail/ui/styles/align.ts";
import { STILL, stillAtOnce } from "@stillfail/ui/styles/still.ts";

export const mCenter = style({
  flex: "1", display: "grid", placeItems: "center", padding: "32px", textAlign: "center", fontSize: vars.textUi,
});
/** The chat's own sheet: its name, two lines at most, with the way to change it at its end. */
export const mInfoHead = style({ display: "flex", alignItems: "flex-start", gap: "12px", paddingTop: "4px" });
globalStyle(`${mInfoHead} > b`, {
  flex: "1", minWidth: "0", fontSize: vars.textTitle, lineHeight: vars.leadingTitle, fontWeight: "600", overflowWrap: "anywhere",
  display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical", overflow: "hidden",
});
export const mInfoEdit = style({
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", ...outsetTop(4), padding: "0", border: "0",
  borderRadius: "50%", background: "color-mix(in srgb, var(--m-ink) 5%, transparent)", cursor: "pointer",
});
/** Who started it, how many take part, when it was last written in: a quiet line under its name. */
export const mInfoFacts = style({
  display: "flex", alignItems: "center", gap: "8px", minWidth: "0", padding: "6px 0 16px", fontSize: vars.textMeta, color: "var(--m-muted)",
});
globalStyle(`${mInfoFacts} > span:last-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const mInfoAgent = style({ display: "flex", flexDirection: "column", minWidth: "0" });
/** Where the agent stands and for how long, under its name. */
export const mInfoStatus = style({});
/** The row's name, whole on its line; where the chat is shared after it, at its end, cut short rather than wrapped. */
export const mShareLabel = style({ flex: "none", whiteSpace: "nowrap" });
export const mShareText = style({
  flex: "1 1 0", width: "0", textAlign: "right", fontSize: vars.textMeta, color: "var(--m-muted)",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** One of a chat's public links in its sheet: when and by whom, cut short; 复制 and 撤销 at its end. */
export const mPublished = style({ minHeight: "41px", paddingTop: "6px", paddingBottom: "6px" });
export const mPublishedText = style({ fontSize: vars.textMeta, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** The sheet that publishes it: its lead, the preview (its attachments ticked in their messages), the button, one under another. */
export const mPublishBody = style({ display: "flex", flexDirection: "column", gap: "12px", padding: "4px 20px 30px" });
// Each as tall as it is: the sheet scrolls, nothing in it is squeezed.
globalStyle(`${mPublishBody} > *`, { flexShrink: "0" });
/** In its sheet, under the workspaces: whether their agents may send (faint while none is ticked). */
export const mShareWrite = style({ padding: "12px 20px 16px" });
globalStyle(`${mShareWrite} > button`, { width: "100%" });
globalStyle(`${mShareWrite} > button:disabled`, { opacity: "0.5", cursor: "default" });
export const mChatBar = style({
  position: "absolute", top: "0", left: "0", right: "0", zIndex: "3", display: "flex", alignItems: "center",
  padding: "calc(var(--m-top) + 5px) 16px 5px 4px",
});
/** A chat's page before its chat is there: what it waits on under its bar (which floats over the page), where its
 *  messages start. */
export const mChatWaiting = style({ paddingTop: mListTop });
export const mChatBack = style({
  display: "grid", placeItems: "center", flex: "none", width: "40px", height: "40px", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-accent) !important", cursor: "pointer",
});
export const mChatBarTitle = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "8px", paddingRight: "8px",
});
/** The station it runs on, after the title: a quiet tag, cut short. */
export const mBarStation = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: "4px", maxWidth: "104px", padding: "1px 8px",
  border: `1px solid ${vars.line}`, borderRadius: "999px", background: "none", color: vars.muted,
  fontSize: vars.textMeta, lineHeight: vars.leadingMeta, cursor: "pointer",
});
globalStyle(`${mBarStation} > span:last-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** Its card in a sheet: the card's own lines, as wide as the sheet's rows. */
export const mStationSheet = style({ padding: "4px 20px 24px" });
export const mBarAgent = style({ flex: "none", display: "grid", padding: "0", border: "0", background: "none", cursor: "pointer" });
/** The first agent's tile with the station it runs on (../ui.tsx AgentMark), one control: the maker's square, then the station's part. */
export const mBarJoinedAgent = style({ display: "grid", placeItems: "center", width: "var(--mark)", height: "var(--mark)" });
export const mBarJoinedStation = style({
  display: "inline-flex", alignItems: "center", height: "var(--mark)", maxWidth: "96px", overflow: "hidden", textOverflow: "ellipsis",
  selectors: { "&[data-name]": { display: "block", lineHeight: "var(--mark)" } },
});
/**
 * A message's words are picked by the page where a finger holds them (pick.tsx): the system's own menu never comes, and
 * for a finger the browser's own selection is off (on a phone it fights the list's scrolling and brings its own menus).
 */
globalStyle(`${mMessages} [data-author]`, {
  WebkitTouchCallout: "none",
  "@media": { "(hover: none)": { userSelect: "none", WebkitUserSelect: "none" } },
});
export const mJump = style({
  position: "absolute", right: "18px", bottom: "calc(var(--m-composer-room) + var(--asks-height, 0px) + 2px)", zIndex: "2", display: "grid",
  placeItems: "center", width: "36px", height: "36px", padding: "0", borderRadius: "50%",
  color: "var(--m-ink) !important", opacity: "0", transform: "translateY(18px) scale(.6)", pointerEvents: "none",
  // Gone, not drawn at all once faded (its frosted glass would still be worked out over the list at every frame).
  visibility: "hidden",
  transition: "opacity 150ms, transform 180ms var(--m-standard), visibility 0s 180ms", cursor: "pointer",
  selectors: {
    "&[data-shown]": {
      opacity: "1", transform: "none", pointerEvents: "auto", visibility: "visible",
      transition: "opacity 180ms, transform 220ms var(--m-standard), visibility 0s",
    },
    // With how many new messages wait at the end: a pill, growing leftwards from where it sits.
    "&[data-count]": { width: "auto", display: "flex", alignItems: "center", gap: "4px", padding: "0 14px 0 10px", borderRadius: "18px", whiteSpace: "nowrap" },
    // Its hiding waits for its shrinking, 1ms then.
    [`${STILL} &`]: stillAtOnce,
  },
});
/** The way to what waits to be decided (Chat.tsx): as mJump, over it when both show. */
export const mJumpAsk = style({
  selectors: { "&[data-above]": { bottom: "calc(var(--m-composer-room) + var(--asks-height, 0px) + 46px)" } },
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
  border: "0", background: "transparent", color: "var(--m-ink)", font: "inherit", fontFamily: vars.fontText, fontVariantNumeric: "normal", fontSize: vars.textInput, lineHeight: "21px",
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
export const mJob = style({
  selectors: {
    "&[data-off]": { opacity: ".55" },
  },
});
export const mJobText = style({ display: "flex", flexDirection: "column", gap: "1px", minWidth: "0" });
export const mJobHead = style({ display: "flex", alignItems: "flex-start", gap: "12px", padding: "4px 22px 14px" });
export const mJobBody = style({});
export const mJobNotices = style({ display: "grid", gap: "12px", fontSize: vars.textUi, overflowY: "auto" });
export const mJobOutput = style({
  overscrollBehaviorY: "none",
  margin: "0", padding: "12px 14px", maxHeight: "50vh", overflow: "auto", borderRadius: `calc(16px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape,
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
  display: "flex", flexDirection: "column", gap: "4px", padding: "12px 2px", fontSize: vars.textMeta, color: "var(--m-muted)",
});
export const mJobsAll = style({
  display: "flex", flexDirection: "column", alignItems: "flex-start", gap: "2px", marginTop: "14px",
  padding: "6px 2px", border: "0", background: "none", color: "var(--m-accent)", font: "inherit", fontSize: vars.textUi,
  textAlign: "left", cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});
/** Its words with a spinner before them while it is under way. */
export const mJobsAllLine = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
// Not the small note under it (./Connects.css.ts): the button's own words.
globalStyle(`${mJobsAll} ${mJobsAllLine}`, { fontSize: "inherit", color: "inherit" });
// The dot on the name's 21px line, half a pixel up for CJK ink (rounded to a whole pixel).
globalStyle(`${mJob} > ${jobDot}`, { marginTop: "6px" });
globalStyle(`${mJobHead} span > span`, {
  fontSize: vars.textCaption, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
globalStyle(`${mJobHead} > ${jobDot}`, { marginTop: "7px" });
globalStyle(`${mJobNotices} p`, { margin: "0", display: "grid", gridTemplateColumns: "3.4em 1fr", gap: "10px" });
globalStyle(`${mJobNotices} time`, { color: "var(--m-subtle)", fontVariantNumeric: "tabular-nums" });
// The phone's buttons take the page's font (root.css.ts), stronger than a class alone: the count's size is set as strongly.
globalStyle(`${mChat} button${mJump}[data-count]`, { fontSize: vars.textUi });

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

/** The chat's find bar in the page's bar (../ChatFind.tsx): all its width, what it says of how much was looked in on a line under it. */
globalStyle(`${mChatBar} > [data-chat-find]`, { flex: "1", flexWrap: "wrap", padding: "4px 0 4px 12px" });
globalStyle(`${mChatBar} > [data-chat-find] > div`, { flex: "1", width: "auto", height: "36px" });
globalStyle(`${mChatBar} > [data-chat-find] > p`, { order: "2", flex: "none", width: "100%", padding: "0 4px" });
// (At least 16px: a phone's browser zooms the page in on a smaller field.)
globalStyle(`${mChatBar} > [data-chat-find] input`, { fontSize: vars.textTitle });
