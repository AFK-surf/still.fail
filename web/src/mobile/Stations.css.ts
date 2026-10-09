import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { mGrow } from "./styles/parts.css.ts";
import { connectionRetry } from "../Connection.css.ts";

export const mPad20 = style({ padding: "20px" });
export const mBuddy = style({ display: "block", flex: "none" });
export const mStationHead = style({ display: "flex", alignItems: "center", gap: "12px" });
export const mStationName = style({ fontSize: vars.textTitle, fontWeight: "600" });
export const mStationSummary = style({ fontSize: vars.textMeta, color: "var(--m-muted)" });
export const mStationRings = style({ display: "flex", gap: "14px", paddingTop: "10px", minHeight: "30px" });
/** A station's load and network in the list, always in their room: what is not there is laid out unseen. */
export const mStationBody = style({ display: "grid", position: "relative" });
export const mStationLoad = style({ gridArea: "1 / 1", display: "flex", flexDirection: "column", minWidth: "0" });
export const mStationNet = style({ display: "block" });
globalStyle(`${mStationBody} [data-hidden]`, { visibility: "hidden" });
/** Reconnecting: the figures as last heard, faded. */
globalStyle(`${mStationLoad}[data-stale]`, { opacity: "0.45" });
export const mStationFaded = style({ display: "block", selectors: { "&[data-stale]": { opacity: "0.45" } } });
/** The station is up but not reached just now (its card's head, its page's title). */
export const mReconnecting = style({ display: "inline-flex", alignItems: "center", gap: "5px", flex: "none", fontSize: vars.textCaption, lineHeight: "16px", color: "var(--m-muted)" });
/** Offline, over that room (taking none of its own): the picture of it asleep as tall as the room, the line beside it. */
export const mStationNap = style({
  position: "absolute", inset: "10px 0 0 0", display: "flex", alignItems: "center", gap: "12px",
  fontSize: vars.textMeta, lineHeight: "18px", color: "var(--m-muted)",
});
globalStyle(`${mStationNap} img`, { display: "block", height: "100%", width: "auto", flex: "none" });
/** Not read yet: grey bars where the rings and the figures go. */
export const mStationBars = style({ gridArea: "1 / 1", display: "flex", flexDirection: "column" });
export const mBarChips = style({ display: "flex", gap: "4px", height: "20px", marginTop: "10px" });
export const mBarNet = style({ flex: "1", display: "flex", justifyContent: "space-between", alignItems: "center", paddingTop: "10px" });
globalStyle(`${mBarNet} > span`, { display: "flex", flexDirection: "column", gap: "9px" });
globalStyle(`${mStationBars} i`, { display: "block", height: "10px", borderRadius: "5px", background: "color-mix(in srgb, var(--m-line) 70%, transparent)" });
globalStyle(`${mBarChips} i`, { display: "block", height: "20px", borderRadius: "6px", background: "color-mix(in srgb, var(--m-line) 70%, transparent)" });
export const mStationOffline = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: "4px", paddingTop: "6px", textAlign: "center",
});
/** 重试 under it: as weighty as root.css.ts's `button { font: inherit }`, and after it. */
globalStyle(`${mStationOffline} button${connectionRetry}`, { marginTop: "6px", fontSize: vars.textMeta });
export const mStationLine = style({ display: "block", paddingTop: "8px", fontSize: vars.textMeta, lineHeight: "18px", color: "var(--m-muted)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${mStationLine}[data-unknown] i`, { display: "inline-block", verticalAlign: "middle", height: "10px", borderRadius: "5px", background: "color-mix(in srgb, var(--m-line) 70%, transparent)" });
globalStyle(`${mStationHead} ${mGrow}`, { display: "flex", flexDirection: "column" });
/** A station's mark in its sheet: which grid, and (for emoji) a field taking any pasted or typed. */
export const mMarkHead = style({ display: "flex", flexDirection: "column", gap: "10px", padding: "0 18px 10px" });
export const mMarkField = style({
  height: "40px", padding: "0 16px", border: "0", borderRadius: "999px", outline: "none",
  background: "color-mix(in srgb, var(--m-ink) 6%, transparent)", color: "var(--m-ink)", fontSize: vars.textInput,
});
/** The grid: six to a row, wide enough for a thumb. */
export const mMarkGrid = style({});
// Doubled, to win over the wide grid's eight columns whatever order the sheets load in.
globalStyle(`${mMarkGrid}${mMarkGrid}`, { gridTemplateColumns: "repeat(6, 1fr)", gap: "4px", padding: "0 14px 10px" });
globalStyle(`${mMarkGrid} > button:not([aria-pressed=true])`, { color: "var(--m-ink)" });
export const mMarkEmoji = style({});
globalStyle(`${mMarkEmoji}${mMarkEmoji}`, { fontSize: `calc(${vars.textTitle} * 1.6)` });
export const mMarkPicture = style({ width: "20px", height: "20px", objectFit: "cover", borderRadius: "24%" });
