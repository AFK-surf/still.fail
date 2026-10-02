import { globalStyle, style } from "@vanilla-extract/css";

export const mDot = style({
  width: "7px", height: "7px", borderRadius: "50%", background: "var(--m-accent)", flex: "none",
});
export const mHome = style({ position: "absolute", inset: "0" });
export const mHomePanes = style({ position: "absolute", inset: "0", overflow: "hidden" });
export const mHomePane = style({
  position: "absolute", inset: "0", overflowY: "auto", overscrollBehavior: "contain",
  padding: "calc(var(--m-top) + 58px) 0 calc(var(--m-foot) + 84px)", transition: "transform 240ms var(--m-standard)",
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
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mHomeBar = style({
  position: "absolute", top: "0", left: "0", right: "0", zIndex: "3", display: "flex", alignItems: "center",
  gap: "10px", padding: "calc(var(--m-top) + 8px) 16px 8px",
});
export const mHomeMe = style({
  display: "grid", flex: "none", padding: "0", border: "0", borderRadius: "50%", background: "none", cursor: "pointer",
});
export const mHomeWorkspace = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "6px", padding: "0", border: "0",
  borderRadius: "8px", background: "none", textAlign: "left", cursor: "pointer",
});
export const mHomeToolbar = style({
  position: "absolute", left: "0", right: "0", bottom: "0", zIndex: "3",
  display: "flex", justifyContent: "flex-end", padding: "10px 16px calc(10px + var(--m-foot))", pointerEvents: "none",
  "@media": {
    // Wider (app.tsx WIDE): at the screen's corner, not the column's.
    "(min-width: 680px)": { position: "fixed", left: "auto", right: "10px", padding: "0 0 calc(10px + var(--m-foot))" },
  },
});
/** 奏 N: a frosted capsule as tall as the new-chat one, left of it. */
export const mDecisions = style({
  display: "flex", alignItems: "center", gap: "6px", height: "56px", padding: "0 22px 0 10px", marginRight: "10px",
  borderRadius: "999px", color: "var(--m-ink)", cursor: "pointer", pointerEvents: "auto",
});
export const mHomeCapsule = style({
  display: "flex", alignItems: "center", gap: "6px", borderRadius: "999px", pointerEvents: "auto",
});
/** The list's filter in the head: the accent while it narrows the list (over root.css.ts's `button { color: inherit }`). */
export const mFilter = style({});
globalStyle(`${mHomeBar} button${mFilter}[data-on]`, { color: "var(--m-accent)" });
export const mNewChat = style({
  display: "grid", placeItems: "center", flex: "none", width: "56px", height: "56px", padding: "0", border: "0",
  borderRadius: "50%", background: "var(--m-accent)", color: "#fff !important", cursor: "pointer", boxShadow: "0 1px 3px rgb(0 0 0 / .04)",
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
export const mChatTitle = style({
  flex: "1", minWidth: "0", fontSize: "16px", lineHeight: "22px", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
  selectors: {
    "&[data-unread]": { fontWeight: "600" },
    // Its station offline: greyed, and marked where a Slack chat's mark goes.
    [`${mChatRow}[data-offline] &`]: { opacity: ".45" },
  },
});
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
  display: "none", fontSize: "12px", color: "var(--m-subtle)", whiteSpace: "nowrap",
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
  minWidth: "0", fontSize: "14px", lineHeight: "20px", color: "var(--m-muted)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
  // Its turn (something waits on the viewer, ../ChatMark.tsx WaitingText): in ink.
  selectors: { "&[data-turn]": { color: "var(--m-ink)" } },
});
globalStyle(`${mHomeWorkspace} svg`, { flex: "none", color: "var(--m-muted)" });
globalStyle(`${mEmpty} p`, { fontSize: "14px", color: "var(--m-muted)" });

/** The latest chats (Home.tsx Recent): a head, a few rows, the way to them all. */
export const mRecentHead = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", flex: "none", padding: "12px 12px 6px 18px",
  fontSize: "15px",
});
export const mRecentRows = style({ flex: "1", minHeight: "0", overflowY: "auto", padding: "0 6px 6px" });
export const mRecentAll = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", flex: "none", width: "100%", boxSizing: "border-box",
  padding: "12px 16px 12px 18px", border: "0", borderTop: "0.5px solid var(--m-line)", background: "none",
  color: "var(--m-accent-ink) !important", fontSize: "14px !important", cursor: "pointer",
});
globalStyle(`${mRecentRows} ${mChatRow}`, { height: "60px", padding: "0 12px 0 14px", borderRadius: "14px" });
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
globalStyle(`${mChatRowWrap} button${mRowArchive}`, { color: "var(--m-ink)", fontSize: "13px", lineHeight: "28px", fontWeight: "500" });
/** What a row swiped left uncovers, as wide as it has gone: 归档, in ink. */
export const mSwipeUnder = style({
  position: "absolute", top: "0", bottom: "0", right: "0", width: "0", display: "flex", alignItems: "center",
  overflow: "hidden", background: "var(--m-ink)", color: "var(--m-bg)", fontSize: "15px", fontWeight: "600",
  whiteSpace: "nowrap",
});
globalStyle(`${mSwipeUnder} span`, { paddingLeft: "24px" });
globalStyle(`${mDecisions} svg`, { flex: "none" });
