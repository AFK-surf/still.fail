// The chats' own page (ChatsHome.tsx): a column in the middle of the window, the search on top of it.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { navRow, navSession, navSessionWrap, navTime, rowPicture } from "./Sidebar.css.ts";
import { pageBar } from "./styles/sidebar.css.ts";
import { pageBarTitle } from "./styles/conversation.css.ts";
import { sessionPage } from "./styles/session.css.ts";
import { pageBarActions } from "./pages/ChatPage.css.ts";

export const home = style({ flex: 1, minHeight: 0, display: "flex", flexDirection: "column" });
export const bar = style({ borderBottom: 0 });
export const barActions = style({ display: "flex", alignItems: "center", justifyContent: "flex-end", gap: 4, minWidth: 0 });
export const station = style({ minWidth: 0 });
globalStyle(`${station} > *`, { margin: 0 });
globalStyle(`${station} a`, { marginBottom: 0 });
export const scroll = style({ flex: 1, minHeight: 0, overflowY: "auto" });
export const column = style({ width: "min(720px, calc(100% - 48px))", margin: "0 auto", padding: "8vh 0 80px" });

export const searchBox = style({
  display: "flex", alignItems: "center", gap: 10, height: 52, padding: "0 16px", borderRadius: vars.rCard,
  background: `color-mix(in srgb, ${vars.text} 5%, transparent)`, color: vars.subtle, cursor: "text",
  cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:focus-within": { background: `color-mix(in srgb, ${vars.text} 7%, transparent)` } },
});
export const searchInput = style({
  flex: 1, minWidth: 0, height: "100%", padding: 0, border: 0, outline: "none", background: "none", color: vars.text,
  font: "inherit", fontSize: vars.textMd,
  selectors: { "&::placeholder": { color: vars.subtle } },
});
export const searchKeys = style({ flex: "none", fontFamily: "inherit", fontSize: vars.textXs, color: vars.subtle });

export const tools = style({ display: "flex", alignItems: "center", gap: 8, margin: "14px 0 6px" });
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
 * A chat's bar, with no sidebar: the title as wide as the messages under it (760px at most), the way back leading it;
 * its actions at the right, pushing it aside when there is no room beside the messages.
 */
const listBar = `:root [data-layout="list"] ${sessionPage} ${pageBar}`;
globalStyle(listBar, { gridTemplateColumns: "minmax(0, 1fr) minmax(0, 760px) minmax(max-content, 1fr)", gap: 0, paddingLeft: 12 });
globalStyle(`${listBar} ${pageBarTitle}`, { gridColumn: "2", paddingLeft: 0 });
globalStyle(`${listBar} ${pageBarActions}`, { gridColumn: "3" });

/** In a chat's bar, before its title: back to the list, and the others' states; a short line between it and the title. */
export const back = style({
  display: "inline-flex", alignItems: "center", gap: 10, height: 32, padding: "0 10px 0 8px", borderRadius: 999,
  position: "relative", flex: "none", marginLeft: -8, marginRight: 7, color: vars.muted, fontSize: vars.textXs, fontVariantNumeric: "tabular-nums",
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&::after": {
      content: '""', position: "absolute", right: -8, top: 9, bottom: 9, width: 1, background: vars.lineStrong, pointerEvents: "none",
    },
  },
});
export const backCount = style({ display: "inline-flex", alignItems: "center", gap: 5 });
