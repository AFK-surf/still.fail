import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { m } from "./styles/root.css.ts";
import { mForm } from "./styles/sheets.css.ts";
import { mMessages } from "./styles/chat.css.ts";
import { mRunLabel } from "./styles/history.css.ts";
import { mReaderBar, mSheetHead } from "./app.css.ts";
import { mChatBar, mChatBarTitle, mInfoAgent, mInfoStatus, mJobHead } from "./Chat.css.ts";
import { mSteps } from "./styles/settings.css.ts";
import { mHomeBar, mHomeWorkspace } from "./Home.css.ts";
import { outsetTop } from "@stillfail/ui/styles/align.ts";
import { spinner } from "@stillfail/ui/styles/spinner.css.ts";

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
  background: "var(--m-surface)", border: "1px solid var(--m-line)", cornerShape: vars.cornerShape,
});
export const mBadge = style({ display: "block" });
export const mAvatar = style({
  display: "inline-grid", placeItems: "center", flex: "none", borderRadius: "50%", overflow: "hidden", color: "#fff",
  fontWeight: "600", lineHeight: "1",
});
/** What was asked failed a moment ago (FailedMark): a small red round "!", tapped to say why. */
export const mFailed = style({
  display: "inline-grid", placeItems: "center", flex: "none", alignSelf: "center", boxSizing: "border-box", borderRadius: "50%",
  background: "var(--m-red)", color: "var(--m-on-red)", fontWeight: "600", lineHeight: "1", cursor: "pointer",
});
/** A segmented choice: a track that tints what it sits on, and a thumb that slides to the chosen option. */
export const mSeg = style({
  position: "relative", boxSizing: "border-box", overflow: "hidden",
  selectors: {
    "&[data-track]": { background: "color-mix(in srgb, var(--m-ink) 6%, transparent)" },
    // Not a capsule (parts.tsx Seg): the smooth corner, its thumb's too.
    "&[data-smooth]": { cornerShape: vars.cornerShape },
    // Filling, where its options' words need more than its width: they scroll sideways in it, whole (parts.tsx Seg
    // brings the chosen one into view).
    "&[data-fill]": { overflowX: "auto", overscrollBehaviorX: "contain", scrollbarWidth: "none" },
    "&[data-fill]::-webkit-scrollbar": { display: "none" },
  },
});
export const mSegRow = style({ position: "relative", display: "flex", height: "100%" });
export const mSegOption = style({
  border: "0", background: "none", padding: "0 10px", fontSize: `${vars.textMeta} !important`, color: "var(--m-muted) !important",
  whiteSpace: "nowrap", cursor: "pointer", position: "relative",
  selectors: {
    // Filling: an equal share each, never narrower than its words and 8 either side (a flex item's own minimum), so five
    // parts' English words fit a phone's 320 whole.
    [`${mSeg}[data-fill] &`]: { flex: "1", padding: "0 8px", fontSize: `${vars.textUi} !important` },
    "&[data-on]": { color: "var(--m-ink) !important" },
    [`${mSeg}:not([data-track]) &[data-on]`]: { fontWeight: "600" },
  },
});
export const mSegThumb = style({
  position: "absolute", top: "0", bottom: "0", left: "0",
  background: "color-mix(in srgb, var(--m-ink) 8%, transparent)",
  selectors: {
    [`${mSeg}[data-track] &`]: { background: "var(--m-thumb)", boxShadow: "inset 0 0 0 0.5px var(--m-line)" },
    [`${mSeg}[data-smooth] &`]: { cornerShape: vars.cornerShape },
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
  },
});
/** The chevron, then the word on the same line or not at all: a word that does not fit the room beside a bar's title
 * wraps to a second line, which the button's height leaves out (the chevron alone still says back, as on iOS). The gap
 * between the lines puts the second past the bottom padding, which the clip would show. */
export const mNavBack = style({
  display: "inline-flex", flexWrap: "wrap", alignItems: "center", alignContent: "flex-start", height: "32px", maxWidth: "100%", overflow: "hidden",
  gap: "8px 0", padding: "4px 6px 4px 0", border: "0", background: "none", boxSizing: "border-box",
  borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, // own corner: the app's back button's (nav_back_box)
  color: "var(--m-accent-ink) !important", fontSize: `${vars.textTitle} !important`, lineHeight: "24px",
  cursor: "pointer",
});
export const mNavBackWord = style({ whiteSpace: "nowrap" });
/** The title in the middle with 84px clear at each side at least; the back button and the action get what is left beside
 * it (less 8px), so a long back word never runs under the title. */
export const mNavbar = style({
  display: "grid", gridTemplateColumns: "minmax(84px, 1fr) minmax(0, max-content) minmax(84px, 1fr)", alignItems: "start", flex: "none",
  padding: "calc(var(--m-top) + 6px) 16px 10px 10px", background: "var(--m-bg)",
});
/** The buttons and the title's first line share one 32px line, the title set 1px higher in it so it stands on the back word's baseline (17px to its 16px); a title's second line (sub) hangs below it. */
export const mNavbarBack = style({ gridColumn: "1", justifySelf: "start", display: "flex", alignItems: "center", height: "32px", whiteSpace: "nowrap", minWidth: "0", maxWidth: "calc(100% - 8px)" });
export const mNavbarTitle = style({
  gridColumn: "2", display: "flex", flexDirection: "column", alignItems: "center", minWidth: "0", textAlign: "center",
});
export const mNavbarSub = style({ display: "flex", alignItems: "center", gap: "5px", maxWidth: "100%", ...outsetTop(4) });
export const mNavbarTrailing = style({ gridColumn: "3", justifySelf: "end", display: "flex", alignItems: "center", height: "32px", minWidth: "0", maxWidth: "calc(100% - 8px)" });
export const mTopBack = style({ padding: "calc(var(--m-top) + 6px) 0 4px 10px" });
/** A top bar with a button at its end as well (a page's ＋). */
export const mTopBackRow = style({ display: "flex", alignItems: "center", justifyContent: "space-between", paddingRight: "10px" });
export const mLargeTitle = style({ padding: "0 16px 6px" });
/**
 * A place's own page's head (parts.tsx PlaceHead), the bottom bar under it: Home's top bar (Home.css.ts mHomeBar), the
 * page's name where Home has the workspace's; what is under it scrolls under its glass.
 */
export const mPlaceHead = style({
  position: "sticky", top: "0", zIndex: 3, flex: "none", display: "flex", alignItems: "center", gap: "10px",
  padding: "calc(var(--m-top) + 8px) 16px 8px", marginBottom: "8px",
});
export const mPlaceTitle = style({
  flex: "1", minWidth: "0", margin: "0", fontSize: vars.textDisplay, lineHeight: "34px", fontWeight: "600", letterSpacing: "-0.4px",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** What a place is, under its empty list on its page: as inset as the rows' marks (SidebarList phone rows, 22). */
export const mPlaceNote = style({ margin: "0", padding: "8px 22px", fontSize: vars.textMeta, lineHeight: "20px", color: "var(--m-muted)" });
/** A list's filter in a head (FilterMenu): in the accent while it narrows the list, over root.css.ts's `button { color: inherit }`. */
export const mFilterMenu = style({});
globalStyle(`${m} button${mFilterMenu}[data-on]`, { color: "var(--m-accent)" });
export const mSection = style({ display: "flex", alignItems: "flex-end", padding: "14px 20px 6px" });
/** A section title's mark: centred on its line, 8 from its words. */
export const mSectionMark = style({ display: "flex", alignSelf: "center", marginRight: "8px" });
export const mListCard = style({
  margin: "0 12px 10px", borderRadius: `calc(16px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "var(--m-surface)", overflow: "hidden",
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
    // Under way, not out of reach: it keeps its ink.
    "&[data-busy]:disabled": { color: "var(--m-ink)", cursor: "default" },
    // Done (a station joined): its ink kept, what it says under it in green.
    "&[data-done]:disabled": { color: "var(--m-ink)", cursor: "default" },
    "&[data-accent]": { color: "var(--m-accent) !important" },
    [`${mForm} &`]: { width: "100%", margin: "0" },
  },
});
/** A done row's check, and what it says under its name. */
export const mPickDone = style({ color: "var(--m-green)", flex: "none" });
globalStyle(`${mPickRow}[data-done] small`, { color: "var(--m-green-ink)" });
export const mPickText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column" });
/** A row with notes at its end: its lines and the notes in two columns, each note on the baseline of its line. */
export const mPickGrid = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto", columnGap: "12px", alignItems: "baseline" });
export const mPickAside = style({ textAlign: "right" });
/** A label with a mark after it (PickRow `mark`). */
export const mPickLabel = style({ display: "flex", alignItems: "center", gap: "6px", minWidth: "0" });
export const mPickLabelText = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const mInfoList = style({
  borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "color-mix(in srgb, var(--m-ink) 5%, transparent)", overflow: "hidden",
  // Two lists one after the other, with no group label between them, are still two cards.
  selectors: { "& + &": { marginTop: "10px" } },
});
export const mButton = style({
  display: "inline-flex", alignItems: "center", gap: "8px", flex: "none", height: "38px", padding: "0 16px",
  border: "0", borderRadius: "19px", background: "var(--m-chip)", color: "var(--m-ink) !important",
  fontSize: `${vars.textUi} !important`, fontWeight: "600", whiteSpace: "nowrap", cursor: "pointer",
  selectors: {
    "&[data-primary]": { background: "var(--m-ink)", color: "var(--m-bg) !important" },
    // Not to be pressed yet: a quiet ground, its words grey (white on it is hardly read).
    [`&[data-primary]:disabled:not(:has(${spinner}))`]: { background: "var(--m-line)", color: "var(--m-muted) !important" },
    [`${mSteps} > &`]: { alignSelf: "flex-end" },
  },
});
/** What a page says in its body when what it shows is not there (not found, no station): centred, grey. Not a wait. */
export const mGone = style({
  flex: "1", display: "grid", placeItems: "center", padding: "32px", fontSize: vars.textMeta, color: "var(--m-muted)",
  textAlign: "center",
});
globalStyle(`${mAvatar} img`, { width: "100%", height: "100%", objectFit: "cover" });
globalStyle(`${mNavbarTitle} b`, {
  maxWidth: "100%", fontSize: vars.textTitle, fontWeight: "600", lineHeight: "30px", marginBottom: "2px", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
globalStyle(`${mLargeTitle} span`, { fontSize: vars.textMeta, color: "var(--m-muted)" });
globalStyle(`${mLargeTitle} h1`, {
  margin: "0", fontSize: vars.textDisplay, fontWeight: "600", letterSpacing: "-0.6px", lineHeight: "1.25",
});
globalStyle(`${mSection} b`, { fontSize: vars.textBody, fontWeight: "600" });
globalStyle(`${mSection} span:not(${mSectionMark})`, { marginLeft: "auto", fontSize: vars.textMeta, color: "var(--m-muted)" });
globalStyle(`${mPickText} > span`, { fontSize: vars.textBody });
globalStyle(`${mPickText} small`, { fontSize: vars.textCaption, color: "var(--m-muted)" });
/** Here rather than with its class: it comes after .m-navbar-title b, and wins over it. */
globalStyle(`${mInfoAgent} b`, {
  fontSize: vars.textBody, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-large-title span, and wins over it. */
globalStyle(`${mInfoAgent} > span`, {
  display: "flex", alignItems: "center", gap: "4px", fontSize: vars.textCaption, color: "var(--m-muted)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Words in a line (a clock runs in them), cut short at its end. */
globalStyle(`${mInfoAgent} > span${mInfoStatus}`, { display: "block" });
/** Here rather than with its class: it comes after .m-ring-disc b, and wins over it. */
globalStyle(`${mHomeWorkspace} b`, {
  minWidth: "0", fontSize: vars.textDisplay, lineHeight: "34px", fontWeight: "600", letterSpacing: "-0.4px", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-ring-disc b, and wins over it. */
globalStyle(`${mSheetHead} b`, { flex: "1", fontSize: vars.textTitle, fontWeight: "600" });
/** Here rather than with its class: it comes after .m-section b, and wins over it. */
globalStyle(`${mChatBarTitle} b`, {
  flex: "0 1 auto", minWidth: "0", fontSize: vars.textTitle, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-loading, and wins over it. */
globalStyle(`${mMessages} > *`, { flex: "none" });
globalStyle(`:root[data-desktop] :is(${mHomeBar}, ${mPlaceHead}, ${mChatBar}, ${mNavbar}, ${mTopBack}, ${mReaderBar})`, { WebkitAppRegion: "drag" });
globalStyle(`:root[data-desktop] :is(${mHomeBar}, ${mPlaceHead}, ${mChatBar}, ${mNavbar}, ${mTopBack}, ${mReaderBar}) :is(button, a)`, { WebkitAppRegion: "no-drag" });
globalStyle(`${mListRow} ${mRunLabel}`, { width: "32px", flex: "none", fontSize: vars.textMeta, color: "var(--m-muted)" });
/** Here rather than with its class: it comes after .m-quote-source > span, and wins over it. */
globalStyle(`${mJobHead} span`, { display: "flex", flexDirection: "column", minWidth: "0" });
/** A link's button: its spinner before its words while what it asked is under way. */
export const mLinkButton = style({
  display: "inline-flex", alignItems: "center", gap: "6px", textAlign: "left",
  selectors: { "&:disabled": { cursor: "default" } },
});
