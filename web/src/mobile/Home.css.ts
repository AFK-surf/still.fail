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
    [`${mHomePanes}[data-mine] &:nth-child(1)`]: { transform: "translateX(-100%)" },
    [`${mHomePanes}[data-mine] &:nth-child(2)`]: { transform: "none" },
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
  flex: "none", padding: "0", border: "0", borderRadius: "50%", background: "none", cursor: "pointer",
});
export const mHomeWorkspace = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "6px", padding: "0", border: "0",
  borderRadius: "8px", background: "none", textAlign: "left", cursor: "pointer",
});
export const mHomeToolbar = style({
  position: "absolute", left: "0", right: "0", bottom: "0", zIndex: "3",
  padding: "10px 16px calc(10px + var(--m-foot))",
});
export const mHomeCapsule = style({
  display: "flex", alignItems: "center", gap: "6px", padding: "6px", borderRadius: "999px",
});
export const mNewChat = style({
  display: "grid", placeItems: "center", flex: "none", width: "44px", height: "44px", padding: "0", border: "0",
  borderRadius: "50%", background: "var(--m-accent)", color: "#fff !important", cursor: "pointer",
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
});
/** A chat's picture: its agent's mark, or two of its agents' overlapping, its state at the corner. */
export const mRowPicture = style({
  position: "relative", flex: "none", width: "40px", height: "40px",
  vars: { "--mark-around": "var(--m-bg)" },
  selectors: {
    [`${mChatRow}[data-offline] &`]: { opacity: ".45" },
  },
});
export const mRowAgent = style({
  position: "absolute", display: "grid", placeItems: "center",
  selectors: {
    [`${mRowPicture}[data-count="1"] &`]: { inset: "0" },
    [`${mRowPicture}[data-count="2"] &`]: { width: "21px", height: "21px" },
    [`${mRowPicture}[data-count="2"] &:first-child`]: { left: "0", top: "0" },
    [`${mRowPicture}[data-count="2"] &:last-child`]: { right: "0", bottom: "0" },
  },
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
});
globalStyle(`${mHomeWorkspace} svg`, { flex: "none", color: "var(--m-muted)" });
globalStyle(`${mEmpty} p`, { fontSize: "14px", color: "var(--m-muted)" });
