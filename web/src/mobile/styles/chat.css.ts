import { globalStyle, style } from "@vanilla-extract/css";
import { avatarFlying } from "../../Chat.css.ts";

export const mChat = style({ position: "absolute", inset: "0", background: "var(--m-bg)" });
export const mMessages = style({
  position: "absolute", inset: "0", display: "flex", flexDirection: "column", gap: "14px", overflowY: "auto",
  overscrollBehavior: "contain", overflowAnchor: "none",
  padding: "calc(var(--m-top) + 68px) 14px calc(var(--m-bottom) + 10px)",
  scrollPaddingTop: "calc(var(--m-top) + 60px)",
});
export const mMine = style({ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "4px" });
export const mBubble = style({
  boxSizing: "border-box", maxWidth: "82%", padding: "9px 14px", borderRadius: "20px 20px 6px 20px",
  background: "var(--m-bubble)", fontSize: "15px", lineHeight: "22px", whiteSpace: "pre-wrap",
  overflowWrap: "anywhere", WebkitTouchCallout: "none",
  selectors: {
    "&[data-pressed]": { boxShadow: "inset 0 0 0 999px color-mix(in srgb, var(--m-accent) 12%, transparent)" },
  },
});
export const mMeta = style({ fontSize: "11px", color: "var(--m-subtle)", whiteSpace: "nowrap" });
export const mWaiting = style({ display: "inline-flex", alignItems: "center", gap: "5px" });
export const mPlain = style({
  margin: "0", fontSize: "15px", lineHeight: "23px", whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
export const mMarkdown = style({ fontSize: "15px", lineHeight: "23px", overflowWrap: "anywhere" });
globalStyle(`${mMessages} > ${avatarFlying}`, {
  position: "absolute", zIndex: "2", margin: "0", maxWidth: "none", pointerEvents: "none",
});
globalStyle(`${mMarkdown} > :first-child`, { marginTop: "0" });
globalStyle(`${mMarkdown} > :last-child`, { marginBottom: "0" });
globalStyle(`${mMarkdown} p`, { margin: "0 0 8px" });
globalStyle(`${mMarkdown} pre`, {
  overflowX: "auto", padding: "8px 10px", borderRadius: "10px", background: "var(--m-surface2)", fontSize: "12px",
  lineHeight: "18px",
});
globalStyle(`${mMarkdown} code`, { fontSize: ".9em" });
