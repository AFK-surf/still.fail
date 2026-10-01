import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** 重试 as a small grey pill (Connection.tsx). */
export const connectionRetry = style({
  flex: "none", height: "22px", padding: "0 10px", borderRadius: "999px", border: "0", cursor: "pointer",
  background: vars.hover, color: vars.text, fontSize: vars.textSm,
  selectors: { "&:hover": { background: vars.line } },
});
