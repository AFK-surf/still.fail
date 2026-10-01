import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { spinner } from "./styles/waiting.css.ts";

/** 重试 as a small grey pill (Connection.tsx). */
export const connectionRetry = style({
  flex: "none", height: "22px", padding: "0 10px", borderRadius: "999px", border: "0", cursor: "pointer",
  background: vars.hover, color: vars.text, fontSize: vars.textSm,
  display: "inline-flex", alignItems: "center", gap: "5px",
  selectors: { "&:hover:not(:disabled)": { background: vars.line }, "&:disabled": { cursor: "progress" } },
});
/** Trying again: a small ring before the word. */
export const retrySpinner = style({});
globalStyle(`${retrySpinner}${spinner}`, { width: "10px", height: "10px", borderWidth: "1.5px" });
