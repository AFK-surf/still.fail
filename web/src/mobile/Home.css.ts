import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { spinKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { STILL, stillLoop } from "@stillfail/ui/styles/still.ts";

export const mDot = style({
  width: "7px", height: "7px", borderRadius: "50%", background: "var(--m-accent)", flex: "none",
});
// Home is navigation, not document text: iOS can expand a hold on an unselectable row to its selectable ancestor.
export const mHome = style({ position: "absolute", inset: "0", userSelect: "none", WebkitUserSelect: "none", WebkitTouchCallout: "none" });
globalStyle(`${mHome} input, ${mHome} textarea`, { userSelect: "text", WebkitUserSelect: "text", WebkitTouchCallout: "default" });
export const mHomePanes = style({ position: "absolute", inset: "0", overflow: "hidden" });
export const mHomeSlide = style({
  position: "absolute", inset: "0", transition: "transform 240ms var(--m-standard)",
  selectors: {
    "&:nth-child(2)": { transform: "translateX(100%)" },
    "&:nth-child(3)": { transform: "translateX(200%)" },
    [`${mHomePanes}[data-filter=mine] &:nth-child(1)`]: { transform: "translateX(-100%)" },
    [`${mHomePanes}[data-filter=mine] &:nth-child(2)`]: { transform: "none" },
    [`${mHomePanes}[data-filter=mine] &:nth-child(3)`]: { transform: "translateX(100%)" },
    [`${mHomePanes}[data-filter=watching] &:nth-child(1)`]: { transform: "translateX(-200%)" },
    [`${mHomePanes}[data-filter=watching] &:nth-child(2)`]: { transform: "translateX(-100%)" },
    [`${mHomePanes}[data-filter=watching] &:nth-child(3)`]: { transform: "none" },
  },
});
export const mHomePane = style({
  position: "absolute", inset: "0", display: "flex", flexDirection: "column", overflowY: "auto", overscrollBehavior: "contain",
  overflowAnchor: "none", vars: { "--list-gap": "0px" },
  padding: "calc(var(--m-top) + 58px) 0 calc(var(--m-foot) + 126px)",
});
export const mHomeItem = style({ flex: "none", display: "flow-root" });
/**
 * A list pulled down from its top (./pull.ts): a frosted disc in the middle of the gap the list leaves under the bar,
 * its arrow turning as it opens, in the accent once letting go reloads, spinning as it does.
 */
export const mPull = style({
  vars: { "--pull": "0", "--gap": "0px" },
  position: "absolute", top: "calc(var(--m-top) + 58px)", left: "50%", zIndex: "2", display: "grid", placeItems: "center",
  width: "36px", height: "36px", translate: "-50% 0", borderRadius: "50%", color: "var(--m-subtle)", pointerEvents: "none",
  opacity: "var(--pull)", transform: "translateY(calc(var(--gap) / 2 - 18px)) scale(calc(.6 + var(--pull) * .4))",
  transition: "opacity 200ms var(--m-ease), transform 200ms var(--m-ease), color 120ms",
  selectors: {
    // With the finger, not behind it.
    "&[data-pulling]": { transition: "color 120ms" },
    "&[data-ready]": { color: "var(--m-accent)" },
  },
});
globalStyle(`${mPull} > svg`, { transform: "rotate(calc(var(--pull) * 270deg))" });
globalStyle(`${mPull}[data-reloading] > svg`, { animation: `${spinKeyframes} 700ms linear infinite` });
// With motion reduced, slower, as a spinner (@stillfail/ui spinner.css.ts).
globalStyle(`${STILL} ${mPull}[data-reloading] > svg`, stillLoop("turn"));
export const mHomeBar = style({
  position: "absolute", top: "0", left: "0", right: "0", zIndex: "3", display: "flex", alignItems: "center",
  gap: "10px", padding: "calc(var(--m-top) + 8px) 16px 8px",
});
export const mHomeMe = style({
  display: "grid", flex: "none", padding: "0", border: "0", borderRadius: "50%", background: "none", cursor: "pointer",
});
export const mHomeWorkspace = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "6px", padding: "0", border: "0",
  borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none", textAlign: "left",
  cursor: "pointer",
});

export const mNewChat = style({
  display: "grid", placeItems: "center", flex: "none", width: "56px", height: "56px", padding: "0", border: "0",
  borderRadius: "50%", background: "var(--m-accent)", color: "#fff !important", cursor: "pointer", boxShadow: "0 2px 6px rgb(0 0 0 / .16)",
});
export const mEmpty = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: "8px", padding: "20px 30px",
  textAlign: "center",
});
/** A row: two lines, always the same height. */
export const mChatRow = style({
  position: "relative", display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "100%",
  height: "66px", padding: "0 16px 0 22px", border: "0", background: "transparent", color: "var(--m-ink)",
  textAlign: "left", cursor: "pointer", WebkitUserSelect: "none", userSelect: "none", WebkitTouchCallout: "none",
  vars: { "--mark-around": "var(--m-bg)" },
  selectors: {
    "&[data-held]": { background: "color-mix(in srgb, var(--m-ink) 5%, transparent)" },
  },
  "@media": {
    "(pointer: coarse)": {
      selectors: {
        "&:active": { background: "color-mix(in srgb, var(--m-ink) 5%, transparent)" },
      },
    },
    "(hover: hover) and (pointer: fine)": {
      selectors: {
        "&:hover": { background: "color-mix(in srgb, var(--m-ink) 4%, transparent)" },
      },
    },
  },
});
export const mChatText = style({
  display: "flex", flexDirection: "column", justifyContent: "center", flex: "1", minWidth: "0",
  // All its pieces of work done or dropped (the core's `settled`): the row stays, faded.
  selectors: { [`${mChatRow}[data-settled] &`]: { opacity: ".45" } },
});
/** Who is in a chat, at the second line's end: its time there instead while the row is held. */
export const mRowAside = style({
  selectors: { [`${mChatRow}[data-offline] &`]: { opacity: ".45" }, [`${mChatRow}[data-held] &`]: { display: "none" } },
  "@media": { "(hover: hover) and (pointer: fine)": { selectors: { [`${mChatRow}:hover &`]: { display: "none" } } } },
});
export const mChatLine1 = style({ display: "flex", alignItems: "center", gap: "8px", height: "22px" });
export const mMarkSlot = style({ display: "flex", flex: "none", width: 10, justifyContent: "center" });
export const mChatTitle = style({
  flex: "1", minWidth: "0", fontSize: vars.textUi, lineHeight: "22px", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
  selectors: {
    "&[data-unread]": { fontWeight: "500" },
    // Its station offline: greyed, and marked where a Slack chat's mark goes.
    [`${mChatRow}[data-offline] &`]: { opacity: ".45" },
  },
});
/** The icon of the station a chat runs on, after its title. */
export const mChatStation = style({ flex: "none", display: "grid", color: "var(--m-muted)" });
export const mChatMark = style({
  display: "grid", placeItems: "center", width: "14px", flex: "none",
  selectors: {
    [`${mChatRow}[data-offline] &`]: { color: "var(--m-subtle)" },
  },
});
/** The Slack mark's tip wrapper: a box of the mark's size, not a text line it sits on the baseline of. */
globalStyle(`${mChatMark} > span`, { display: "grid" });
export const mChatLine2 = style({ display: "flex", alignItems: "center", gap: "8px", height: "20px" });
export const mChatLast = style({ flex: "1", minWidth: "0", display: "flex" });
export const mChatTime = style({
  display: "none", fontSize: vars.textCaption, color: "var(--m-subtle)", whiteSpace: "nowrap",
  selectors: {
    "&[data-shown]": { display: "inline" },
  },
  "@media": {
    "(hover: hover) and (pointer: fine)": {
      selectors: {
        [`${mChatRow}:hover &`]: { display: "inline" },
      },
    },
  },
});
export const mLast = style({
  display: "inline-flex", alignItems: "center", gap: "5px", minWidth: "0",
  selectors: {
    [`${mChatRow}[data-offline] &`]: { opacity: ".45" },
  },
});
export const mLastText = style({
  minWidth: "0", fontSize: vars.textMeta, lineHeight: "20px", color: "var(--m-muted)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
  // Its turn (something waits on the viewer, ../ChatMark.tsx WaitingText): in ink.
  // A message that did not go (its row's `unsent`): in red.
  selectors: { "&[data-turn]": { color: "var(--m-ink)" }, "&[data-alert]": { color: "var(--m-red)" } },
});
globalStyle(`${mHomeWorkspace} svg`, { flex: "none", color: "var(--m-muted)" });
globalStyle(`${mEmpty} p`, { fontSize: vars.textMeta, color: "var(--m-muted)" });

/** The latest chats (Home.tsx Recent): a head, a few rows, the way to them all. */
export const mRecentHead = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", flex: "none", padding: "12px 12px 6px 18px",
  fontSize: vars.textBody,
});
export const mRecentRows = style({ flex: "1", minHeight: "0", overflowY: "auto", padding: "0 6px 6px" });
export const mRecentAll = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", flex: "none", width: "100%", boxSizing: "border-box",
  padding: "12px 16px 12px 18px", border: "0", borderTop: "0.5px solid var(--m-line)", background: "none",
  color: "var(--m-accent-ink) !important", fontSize: `${vars.textUi} !important`, cursor: "pointer",
});
globalStyle(`${mRecentRows} ${mChatRow}`, { height: "60px", padding: "0 12px 0 14px", borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape });
globalStyle(`${mRecentRows} ${mChatRow}[data-open]`, { background: "var(--m-accent-bg)" });
globalStyle(`${mRecentRows} ${mChatRow}[data-open] ${mChatTitle}`, { color: "var(--m-accent-ink)", fontWeight: "600" });
globalStyle(`${mNewChat}[data-small]`, { width: "32px", height: "32px" });

/**
 * A row with 归档 at its start (the core's `archivable`, Home.tsx SwipeArchive): a frame that stays put, reading the swipe;
 * in it the row and its 归档 sliding together, and what they uncover on the right.
 */
export const mChatRowWrap = style({
  position: "relative", overflowX: "clip", touchAction: "pan-y",
  selectors: { "&[data-leaving]": { overflow: "hidden", pointerEvents: "none" } },
});
export const mSwipeSlide = style({ position: "relative" });
globalStyle(`${mChatRow}[data-archivable]`, { paddingLeft: "72px" });
// Archive is wider than 归档.
globalStyle(`:root[lang="en"] ${mChatRow}[data-archivable]`, { paddingLeft: "96px" });
/** 归档 in words: a small chip, centred on the row's height, at its start. */
export const mRowArchive = style({
  position: "absolute", top: "0", bottom: "0", left: "14px", margin: "auto 0", height: "28px", padding: "0 12px",
  border: "0", borderRadius: "14px", background: "var(--m-chip)", cursor: "pointer", WebkitTapHighlightColor: "transparent",
  selectors: { "&:disabled": { opacity: ".4" }, "&:active:not(:disabled)": { filter: "brightness(.94)" } },
});
// The phone's buttons take their page's font (root.css.ts): its size and colour, as strong as that.
globalStyle(`${mChatRowWrap} button${mRowArchive}`, { color: "var(--m-ink)", fontSize: vars.textMeta, lineHeight: "28px", fontWeight: "500" });
/** What a row swiped left uncovers, as far as it has gone (slid in from the right, Home.tsx): 归档, in ink. */
export const mSwipeUnder = style({
  position: "absolute", top: "0", bottom: "0", left: "0", right: "0", transform: "translateX(100%)", display: "flex", alignItems: "center",
  overflow: "hidden", background: "var(--m-ink)", color: "var(--m-bg)", fontSize: vars.textBody, fontWeight: "600",
  whiteSpace: "nowrap",
});
globalStyle(`${mSwipeUnder} span`, { paddingLeft: "24px" });

// The search (Home.tsx SearchPage): a field at the top of each list, there once it is scrolled to its top; tapped, the
// list goes up and away, the bars with it, and the field comes up to the top, the chats and messages it finds under it.
export const mSearchField = style({
  display: "flex", alignItems: "center", gap: "8px", boxSizing: "border-box", width: "calc(100% - 32px)", height: "38px",
  margin: "0 16px 6px", padding: "0 12px", border: "0", borderRadius: "19px", cursor: "text",
  background: "color-mix(in srgb, var(--m-ink) 6%, transparent)", color: "var(--m-muted)", fontSize: vars.textBody,
});
globalStyle(`${mSearchField} svg`, { flex: "none" });
// Away while the search is open (`data-away`); as it closes they come back in the same 240 ms as its field goes back,
// so the field lands where the list's is, together.
globalStyle(`${mHome}[data-away] ${mHomePanes}`, { transform: "translateY(-56px)", opacity: "0", pointerEvents: "none" });
globalStyle(`${mHomePanes}`, { transition: "transform 240ms var(--m-standard), opacity 200ms var(--m-standard)" });
globalStyle(`${mHome}[data-away] ${mHomePanes}`, { transition: "transform 280ms var(--m-ease), opacity 200ms var(--m-standard)" });
globalStyle(`${mHome}[data-away] ${mHomeBar}`, { opacity: "0", pointerEvents: "none" });
globalStyle(`${mHomeBar}`, { transition: "opacity 200ms var(--m-standard)" });
export const mSearchPage = style({ position: "absolute", inset: "0", zIndex: "4", display: "flex", flexDirection: "column" });
export const mSearchBar = style({
  flex: "none", display: "flex", alignItems: "center", gap: "12px", padding: "calc(var(--m-top) + 8px) 16px 8px",
});
export const mSearchInput = style({
  flex: "1", minWidth: "0", boxSizing: "border-box", display: "flex", alignItems: "center", gap: "8px", height: "38px", padding: "0 12px",
  borderRadius: "19px", background: "color-mix(in srgb, var(--m-ink) 6%, transparent)", color: "var(--m-muted)",
});
globalStyle(`${mSearchInput} svg`, { flex: "none" });
globalStyle(`${mSearchInput} input`, {
  flex: "1", minWidth: "0", height: "100%", padding: "0", border: "0", outline: "none", background: "none",
  color: "var(--m-ink)", font: "inherit", fontSize: vars.textInput, WebkitAppearance: "none", appearance: "none",
});
globalStyle(`${mSearchInput} input::-webkit-search-cancel-button`, { display: "none" });
export const mSearchCancel = style({
  flex: "none", padding: "0", border: "0", background: "none", color: "var(--m-accent)", fontSize: vars.textTitle, cursor: "pointer",
});
export const mSearchResults = style({
  flex: "1", minHeight: "0", overflowY: "auto", overscrollBehavior: "contain", paddingBottom: "calc(var(--m-foot) + 20px)",
  animation: "none", transition: "opacity 200ms var(--m-standard)",
  selectors: { [`${mSearchPage}[data-leaving] &`]: { opacity: "0" } },
});
globalStyle(`${mSearchPage}[data-leaving] ${mSearchCancel}`, { opacity: "0", transition: "opacity 150ms" });
/** A found message's first line: what it says with the words, the row's width (not bold but the words). */
export const mFoundChat = style({
  flex: "1", minWidth: "0", fontSize: vars.textBody, lineHeight: "22px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mFoundMeta = style({ flex: "none", fontSize: vars.textCaption, color: "var(--m-muted)", whiteSpace: "nowrap" });
/** A found line's second: the chat it is in, cut where it meets who said it and when. */
export const mFoundUnder = style({
  flex: "1", minWidth: "0", fontSize: vars.textMeta, lineHeight: "20px", color: "var(--m-muted)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** 查看更多 under a kind found, and 全部结果 over one kind alone: a quiet row, as a list's own link. */
export const mFoundMore = style({
  display: "flex", alignItems: "center", gap: "4px", width: "100%", height: "44px", padding: "0 22px", border: "0",
  background: "transparent", color: "var(--m-accent)", fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
});
/** What the list says under it: stations not answered yet, offline, too old to search. */
export const mFoundNote = style({ margin: 0, padding: "12px 22px", fontSize: vars.textCaption, color: "var(--m-muted)" });
/** The words found, in a found message's line: in ink, bold (the rest of the line muted). */
export const mFoundHit = style({ background: "none", color: "var(--m-ink)", fontWeight: "600" });
// Over the page's own buttons' ink.
globalStyle(`${mSearchBar} button${mSearchCancel}`, { color: "var(--m-accent)" });
// One field at a time: the list's is the search's while it is open (it flies from and back to the list's place).
globalStyle(`${mHome}[data-searching] ${mSearchField}`, { visibility: "hidden" });
