import { style } from "@vanilla-extract/css";

export const mChat = style({ position: "absolute", inset: "0", background: "var(--m-bg)" });
/** The chat's messages, drawn as the wide screen draws them (../../Chat.tsx), a little closer together. */
export const mMessages = style({
  position: "absolute", inset: "0", display: "flex", flexDirection: "column", gap: "var(--list-gap)", overflowY: "auto",
  overscrollBehavior: "contain", overflowAnchor: "none",
  // Its end clear of the composer, and of what waits to be decided over it (../../Asks.tsx), while there is something.
  padding: "calc(var(--chat-top, calc(var(--m-top) + 54px)) + 14px) 14px calc(var(--m-composer-room) + var(--asks-height, 0px) + 10px)",
  scrollPaddingTop: "calc(var(--chat-top, calc(var(--m-top) + 54px)) + 6px)",
  vars: { "--list-gap": "20px" },
});
export const mWaiting = style({ display: "inline-flex", alignItems: "center", gap: "5px" });
export const mPlain = style({
  margin: "0", fontSize: "15px", lineHeight: "23px", whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
