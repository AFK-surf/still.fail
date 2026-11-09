import { style } from "@vanilla-extract/css";
/** New chat: a centred composer with the choices of where and on what it runs. */
export const newChat = style({
  flex: "1", minHeight: "0", display: "grid", placeItems: "center", padding: "32px", overflowY: "auto",
});
