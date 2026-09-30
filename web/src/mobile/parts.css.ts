import { globalStyle, style } from "@vanilla-extract/css";
import { m } from "./styles/root.css.ts";
import { mForm } from "./styles/sheets.css.ts";
import { mMessages } from "./styles/chat.css.ts";
import { mRunLabel } from "./styles/history.css.ts";
import { mReaderBar, mSheetHead } from "./app.css.ts";
import { mAttach, mChatBar, mChatBarTitle, mInfoAgent, mJobHead } from "./Chat.css.ts";
import { mSteps } from "./styles/settings.css.ts";
import { mHomeBar, mHomeWorkspace } from "./Home.css.ts";

export const mMaker = style({
  display: "block", flex: "none",
  selectors: {
    [`:root[data-theme="dark"] ${m} &[data-mono]`]: { filter: "invert(1)" },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        [`:root:not([data-theme="light"]) ${m} &[data-mono]`]: { filter: "invert(1)" },
      },
    },
  },
});
export const mModelMark = style({ position: "relative", display: "inline-block", flex: "none" });
export const mModelTile = style({
  display: "grid", placeItems: "center", width: "100%", height: "100%", boxSizing: "border-box",
  background: "var(--m-surface)", border: "1px solid var(--m-line)",
});
export const mBadge = style({ display: "block" });
export const mAvatar = style({
  display: "inline-grid", placeItems: "center", flex: "none", borderRadius: "50%", overflow: "hidden", color: "#fff",
  fontWeight: "600", lineHeight: "1",
});
/** Laid out as a box wherever it is put (its look is the wide screen's spinner). */
export const mSpinner = style({ display: "inline-block", flex: "none", boxSizing: "border-box" });
/** A segmented choice: a track that tints what it sits on, and a thumb that slides to the chosen option. */
export const mSeg = style({
  position: "relative", boxSizing: "border-box", overflow: "hidden",
  selectors: {
    "&[data-track]": { background: "color-mix(in srgb, var(--m-ink) 6%, transparent)" },
  },
});
export const mSegRow = style({ position: "relative", display: "flex", height: "100%" });
export const mSegOption = style({
  border: "0", background: "none", padding: "0 10px", fontSize: "13px !important", color: "var(--m-muted) !important",
  whiteSpace: "nowrap", cursor: "pointer", position: "relative",
  selectors: {
    [`${mSeg}[data-fill] &`]: { flex: "1", padding: "0 12px", fontSize: "14px !important" },
    "&[data-on]": { color: "var(--m-ink) !important" },
    [`${mSeg}:not([data-track]) &[data-on]`]: { fontWeight: "600" },
  },
});
export const mSegThumb = style({
  position: "absolute", top: "0", bottom: "0", left: "0",
  background: "color-mix(in srgb, var(--m-ink) 8%, transparent)",
  selectors: {
    [`${mSeg}[data-track] &`]: { background: "var(--m-thumb)", boxShadow: "inset 0 0 0 0.5px var(--m-line)" },
    [`:root[data-theme="dark"] ${m} ${mSeg}:not([data-track]) &`]: { background: "color-mix(in srgb, var(--m-ink) 13%, transparent)" },
    "&[data-moved]": {
      transition: "transform 240ms cubic-bezier(0, 0, .2, 1), width 240ms cubic-bezier(0, 0, .2, 1)",
    },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        [`:root:not([data-theme="light"]) ${m} ${mSeg}:not([data-track]) &`]: { background: "color-mix(in srgb, var(--m-ink) 13%, transparent)" },
      },
    },
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mNavBack = style({
  display: "inline-flex", alignItems: "center", gap: "0", padding: "4px 6px 4px 0", border: "0", background: "none",
  borderRadius: "8px", color: "var(--m-accent) !important", fontSize: "17px !important", lineHeight: "24px",
  cursor: "pointer",
});
export const mNavbar = style({
  display: "grid", gridTemplateColumns: "84px minmax(0, 1fr) 84px", alignItems: "start", flex: "none",
  padding: "calc(var(--m-top) + 6px) 16px 10px 10px", background: "var(--m-bg)",
});
/** The buttons and the title's first line share one 32px line, the title set 1px higher in it so it stands on the back word's baseline (17px to its 16px); a title's second line (sub) hangs below it. */
export const mNavbarBack = style({ gridColumn: "1", justifySelf: "start", display: "flex", alignItems: "center", height: "32px", whiteSpace: "nowrap" });
export const mNavbarTitle = style({
  gridColumn: "2", display: "flex", flexDirection: "column", alignItems: "center", minWidth: "0", textAlign: "center",
});
export const mNavbarSub = style({ display: "flex", alignItems: "center", gap: "5px", maxWidth: "100%", marginTop: "-4px" });
export const mNavbarTrailing = style({ gridColumn: "3", justifySelf: "end", display: "flex", alignItems: "center", height: "32px" });
export const mTopBack = style({ padding: "calc(var(--m-top) + 6px) 0 4px 10px" });
/** A top bar with a button at its end as well (a page's ＋). */
export const mTopBackRow = style({ display: "flex", alignItems: "center", justifyContent: "space-between", paddingRight: "10px" });
export const mLargeTitle = style({ padding: "0 16px 6px" });
export const mSection = style({ display: "flex", alignItems: "flex-end", padding: "14px 20px 6px" });
export const mListCard = style({
  margin: "0 12px 10px", borderRadius: "16px", background: "var(--m-surface)", overflow: "hidden",
  selectors: {
    [`${mSteps} &`]: { margin: "0" },
  },
});
export const mListRow = style({
  display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "100%", minHeight: "46px",
  padding: "12px 16px", border: "0", background: "none", color: "var(--m-ink)", textAlign: "left",
  selectors: {
    "button&": { cursor: "pointer" },
  },
});
export const mPickRow = style({
  display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "calc(100% - 24px)",
  minHeight: "46px", margin: "0 12px", padding: "12px 8px", border: "0", background: "none", color: "var(--m-ink)", textAlign: "left",
  cursor: "pointer",
  selectors: {
    "&:disabled": { color: "var(--m-subtle)" },
    "&[data-accent]": { color: "var(--m-accent) !important" },
    [`${mForm} &`]: { width: "100%", margin: "0" },
  },
});
export const mPickText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column" });
/** A row with notes at its end: its lines and the notes in two columns, each note on the baseline of its line. */
export const mPickGrid = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto", columnGap: "12px", alignItems: "baseline" });
export const mPickAside = style({ textAlign: "right" });
export const mInfoList = style({
  borderRadius: "14px", background: "color-mix(in srgb, var(--m-ink) 5%, transparent)", overflow: "hidden",
  // Two lists one after the other, with no group label between them, are still two cards.
  selectors: { "& + &": { marginTop: "10px" } },
});
export const mButton = style({
  display: "inline-flex", alignItems: "center", gap: "8px", flex: "none", height: "38px", padding: "0 16px",
  border: "0", borderRadius: "19px", background: "var(--m-chip)", color: "var(--m-ink) !important",
  fontSize: "14px !important", fontWeight: "600", whiteSpace: "nowrap", cursor: "pointer",
  selectors: {
    "&[data-primary]": { background: "var(--m-ink)", color: "var(--m-bg) !important" },
    [`&[data-primary]:disabled:not(:has(${mSpinner}))`]: { background: "var(--m-line)" },
    [`${mSteps} > &`]: { alignSelf: "flex-end" },
  },
});
export const mLoading = style({
  flex: "1", display: "grid", placeItems: "center", padding: "32px", fontSize: "14px", color: "var(--m-muted)",
  textAlign: "center",
});
globalStyle(`${mAvatar} img`, { width: "100%", height: "100%", objectFit: "cover" });
globalStyle(`${mNavbarTitle} b`, {
  maxWidth: "100%", fontSize: "16px", fontWeight: "600", lineHeight: "30px", marginBottom: "2px", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
globalStyle(`${mLargeTitle} span`, { fontSize: "13px", color: "var(--m-muted)" });
globalStyle(`${mLargeTitle} h1`, {
  margin: "0", fontSize: "32px", fontWeight: "700", letterSpacing: "-0.6px", lineHeight: "1.25",
});
globalStyle(`${mSection} b`, { fontSize: "15px", fontWeight: "600" });
globalStyle(`${mSection} span`, { marginLeft: "auto", fontSize: "13px", color: "var(--m-muted)" });
globalStyle(`${mPickText} > span`, { fontSize: "15px" });
globalStyle(`${mPickText} small`, { fontSize: "12px", color: "var(--m-muted)" });
/** Here rather than with its class: it comes after .m-navbar-title b, and wins over it. */
globalStyle(`${mInfoAgent} b`, {
  fontSize: "15px", fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-large-title span, and wins over it. */
globalStyle(`${mInfoAgent} span`, {
  display: "flex", alignItems: "center", gap: "4px", fontSize: "12px", color: "var(--m-muted)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-ring-disc b, and wins over it. */
globalStyle(`${mHomeWorkspace} b`, {
  minWidth: "0", fontSize: "24px", lineHeight: "34px", fontWeight: "700", letterSpacing: "-0.4px", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-ring-disc b, and wins over it. */
globalStyle(`${mSheetHead} b`, { flex: "1", fontSize: "17px", fontWeight: "700" });
/** Here rather than with its class: it comes after .m-section b, and wins over it. */
globalStyle(`${mChatBarTitle} b`, {
  flex: "0 1 auto", minWidth: "0", fontSize: "16px", fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-loading, and wins over it. */
globalStyle(`${mMessages} > *`, { flex: "none" });
/** Here rather than with its class: it comes after .m-pick-text > span, and wins over it. */
globalStyle(`${mAttach} span`, { fontSize: "13px" });
globalStyle(`:root[data-desktop] :is(${mHomeBar}, ${mChatBar}, ${mNavbar}, ${mTopBack}, ${mReaderBar})`, { WebkitAppRegion: "drag" });
globalStyle(`:root[data-desktop] :is(${mHomeBar}, ${mChatBar}, ${mNavbar}, ${mTopBack}, ${mReaderBar}) :is(button, a)`, { WebkitAppRegion: "no-drag" });
globalStyle(`${mListRow} ${mRunLabel}`, { width: "32px", flex: "none", fontSize: "13px", color: "var(--m-muted)" });
/** Here rather than with its class: it comes after .m-quote-source > span, and wins over it. */
globalStyle(`${mJobHead} span`, { display: "flex", flexDirection: "column", minWidth: "0" });
