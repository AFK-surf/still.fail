import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import * as listCss from "../SidebarList.css.ts";

/** A folder's row that takes a drop: ringed in the accent while something it takes is over it, saying what a drop does. */
export const drop = style({
  position: "relative", borderRadius: vars.rNav,
  selectors: { "&[data-over]": { background: vars.accentBg, boxShadow: `inset 0 0 0 1px ${vars.accent}` } },
});
export const dropSays = style({
  position: "absolute", right: "8px", top: "50%", transform: "translateY(-50%)", padding: "1px 7px", borderRadius: "999px",
  background: vars.accent, color: vars.onPrimary, fontSize: vars.textCaption, fontWeight: "600", pointerEvents: "none",
});

export const empty = style({ margin: "8px 12px", color: vars.muted, fontSize: vars.textMeta });
/** Where favourites go while there are none: a place to drop, as tall as a row, outlined. */
export const hint = style({
  display: "grid", placeItems: "center", minHeight: "34px", margin: "0", boxSizing: "border-box", borderRadius: vars.rNav,
  border: `1px dashed ${vars.lineStrong}`, color: vars.subtle, fontSize: vars.textMeta,
});
/** 个人收藏: ringed while a folder dragged over it would be kept there. */
export const keep = style({ borderRadius: vars.rNav, selectors: { "&[data-over]": { boxShadow: `inset 0 0 0 1px ${vars.accent}` } } });
export const favorite = style({ position: "relative" });
export const unkeep = style({
  position: "absolute", right: "6px", top: "8px", display: "grid", placeItems: "center", width: "20px", height: "20px", padding: "0", border: "0",
  borderRadius: vars.rOption, background: vars.list, color: vars.muted, cursor: "pointer", opacity: "0",
  selectors: { [`${favorite}:hover &`]: { opacity: "1" }, "&:hover": { color: vars.text } },
});

export const station = style({ display: "grid" });
/** A station's line: its disclosure, then its row (its home). */
export const stationLine = style({ position: "relative", display: "flex", alignItems: "center" });
globalStyle(`${stationLine} > :last-child`, { flex: "1", minWidth: "0" });
// Its end (This machine, the disk bar) is short and whole: the row's 45% cap would cut the bar off after the badge.
globalStyle(`${stationLine} ${listCss.end}`, { maxWidth: "none" });
export const disclosure = style({
  position: "absolute", left: "-2px", top: "50%", zIndex: "1", transform: "translateY(-50%)", display: "grid", placeItems: "center",
  width: "16px", height: "20px", padding: "0", border: "0", background: "none", color: vars.subtle, cursor: "pointer",
});
globalStyle(`${disclosure} svg`, { transition: `transform ${vars.dur} ${vars.easeOut}` });
globalStyle(`${disclosure}[data-open] svg`, { transform: "rotate(90deg)" });
export const stationName = style({ padding: "7px 12px 7px 36px", color: vars.muted, fontSize: vars.textUi });
export const here = style({ padding: "0 5px", borderRadius: "999px", background: vars.accentBg, color: vars.accentText, fontSize: vars.textCaption });
/** How full the disk is: 28 wide, amber past 90%. */
export const disk = style({ display: "block", width: "28px", height: "3px", borderRadius: "2px", background: vars.line, overflow: "hidden" });
globalStyle(`${disk} > span`, { display: "block", height: "100%", background: vars.muted, transformOrigin: "left" });
globalStyle(`${disk}[data-full] > span`, { background: vars.amber });
/** A station's places, in under it. */
export const places = style({ paddingLeft: "14px" });
export const reading = style({ margin: "4px 12px 6px 22px", color: vars.subtle, fontSize: vars.textMeta });
// Rows next to each other never touch (Sidebar.css.ts navRow): here each is in a box of its own (a drop, a station),
// so the 2px goes between the boxes.
globalStyle(`:is(${drop}, ${station}, ${favorite}) + :is(${drop}, ${station}, ${favorite})`, { marginTop: "2px" });
