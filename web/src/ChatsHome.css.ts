// The chats' own page (ChatsHome.tsx): a column in the middle of the window, the search on top of it.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { navRow, navSession, navSessionWrap, navTime, rowPicture } from "./Sidebar.css.ts";
import { pageBar } from "./styles/sidebar.css.ts";
import { pageBarTitle } from "./styles/conversation.css.ts";
import { sessionPage } from "./styles/session.css.ts";
import { pageBarActions } from "./pages/ChatPage.css.ts";

export const home = style({ position: "relative", flex: 1, minHeight: 0, display: "flex", flexDirection: "column" });
export const bar = style({ display: "flex", gap: 12, paddingRight: "calc(12px + var(--avoid-previews, 0px))" });
// The tools line up with the column below them: no padding of the bar's own at the left.
globalStyle(`:root [data-layout="list"] ${bar}`, { paddingLeft: 0 });
/** A column as a chat's: 760px at most, 32px in from each side, clear of previews at the right (or where it was left). */
const columned = { width: "min(760px, calc(100% - 64px))", margin: "0 auto" } as const;
export const tools = style({ ...columned, display: "flex", alignItems: "center", gap: 8 });
export const barActions = style({
  position: "absolute", right: "calc(12px + var(--avoid-previews, 0px))", top: 0, height: 44, display: "flex", alignItems: "center", gap: 4, minWidth: 0,
});
export const station = style({ minWidth: 0 });
globalStyle(`${station} > *`, { margin: 0 });
globalStyle(`${station} a`, { marginBottom: 0 });
export const scroll = style({ flex: 1, minHeight: 0, overflowY: "auto", paddingRight: "var(--avoid-previews, 0px)" });
export const column = style({ ...columned, paddingBottom: 96 });

/** The search, where a chat's composer is and as it looks: a frosted pill 16px over the bottom. */
export const bottom = style({
  position: "absolute", left: 0, right: "var(--avoid-previews, 0px)", bottom: 16, display: "flex", pointerEvents: "none",
});
export const searchBox = style({
  ...columned, display: "flex", alignItems: "center", gap: 8, height: 44, padding: "0 16px", borderRadius: 999,
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, WebkitBackdropFilter: "blur(20px)", backdropFilter: "blur(20px)",
  boxShadow: "0 1px 3px rgb(0 0 0 / .04)", color: vars.subtle, cursor: "text", pointerEvents: "auto",
});
/** The search and the filters' menu over it, in the chat's column. */
export const searchWrap = style({ ...columned, position: "relative", pointerEvents: "auto" });
globalStyle(`${searchWrap} > label`, { width: "100%", margin: 0 });
/** The filters' menu, over the search as the composer's `@` menu is over it (ChatRef.css.ts). */
export const filterMenu = style({ bottom: "calc(100% + 8px)", cursor: "default" });
export const filterItem = style({ gridTemplateColumns: "16px minmax(0, 1fr) auto" });
/** A filter in use, before what is typed. */
export const chip = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: 2, height: 26, padding: "0 4px 0 10px", borderRadius: 999,
  background: vars.accentBg, color: vars.accentText, fontSize: vars.textXs, fontWeight: 500, whiteSpace: "nowrap",
});
export const chipOff = style({
  display: "grid", placeItems: "center", width: 18, height: 18, border: 0, borderRadius: 999, background: "none", color: "inherit",
  cursor: "pointer", opacity: 0.7,
  selectors: { "&:hover": { opacity: 1 } },
});
export const searchInput = style({
  flex: 1, minWidth: 0, height: "100%", padding: 0, border: 0, outline: "none", background: "none", color: vars.text,
  font: "inherit", fontSize: vars.textSm,
  selectors: { "&::placeholder": { color: vars.subtle } },
});
export const searchKeys = style({ flex: "none", fontFamily: "inherit", fontSize: vars.textXs, color: vars.subtle });

globalStyle(`${tools} [role="radio"]`, { whiteSpace: "nowrap", minWidth: "5em" });
export const newChat = style({ marginLeft: "auto" });
export const jobs = style({ margin: "6px 0 0" });
export const list = style({ paddingTop: 4 });
export const day = style({ margin: "18px 10px 4px", fontSize: vars.textXs, lineHeight: "18px", color: vars.muted });
export const none = style({ margin: "20px 10px", fontSize: vars.textSm, color: vars.muted });

// The sidebar's rows, a little larger on a page of their own, on the page's ground; the time always shown.
export const row = style({});
globalStyle(`${row} .${navSession}`, { padding: "9px 12px", gap: 12, vars: { "--mark-around": vars.canvas } });
globalStyle(`${row} .${rowPicture}`, { width: 34, height: 34, marginTop: 3 });
globalStyle(`${row} .${navTime}`, { display: "inline" });
globalStyle(`${row}[data-picked] .${navRow}`, { background: vars.hover, vars: { "--mark-around": vars.hover } });
globalStyle(`${row} .${navSessionWrap}`, { position: "relative" });

/**
 * A chat's bar, with no sidebar: the title as wide as the messages under it (760px at most), level with them; the way
 * back just left of it, its actions at the right, either pushing it aside when there is no room beside the messages.
 */
const listBar = `:root [data-layout="list"] ${sessionPage} ${pageBar}`;
globalStyle(listBar, { gridTemplateColumns: "minmax(max-content, 1fr) minmax(0, 760px) minmax(max-content, 1fr)", gap: 0, paddingLeft: 12 });
globalStyle(`${listBar} ${pageBarTitle}`, { gridColumn: "2", paddingLeft: 0 });
globalStyle(`${listBar} ${pageBarActions}`, { gridColumn: "3" });

/**
 * In a chat's bar, just left of its title: back to the list, and the others' states; a short line between it and the
 * title, 2px clear of the pill it shows when pointed at, as far from the last count as from the title.
 */
export const back = style({
  display: "inline-flex", alignItems: "center", gap: 10, height: 32, borderRadius: 999,
  gridColumn: "1", justifySelf: "end", position: "relative", marginRight: 13, padding: "0 8px", color: vars.muted, fontSize: vars.textXs, fontVariantNumeric: "tabular-nums",
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&::after": {
      content: '""', position: "absolute", right: -3, top: 6, bottom: 6, width: 1, background: vars.lineStrong, pointerEvents: "none",
    },
  },
});
export const backCount = style({ display: "inline-flex", alignItems: "center", gap: 5 });
