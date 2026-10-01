import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** Failed a moment ago (DoingMark.tsx): a small red round "!" where the spinner was (as the phone's), why on hover. */
export const failedMark = style({
  display: "inline-grid", placeItems: "center", flex: "none", boxSizing: "border-box", borderRadius: "50%",
  background: vars.red, color: "#fff", fontWeight: "700", lineHeight: "1", cursor: "help",
});
