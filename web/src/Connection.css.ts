import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";

/** 重试 as a small grey pill (Connection.tsx). */
export const connectionRetry = style({
  flex: "none", height: "22px", padding: "0 10px", borderRadius: "999px", border: "0", cursor: "pointer",
  background: vars.hover, color: vars.text, fontSize: vars.textUi,
  display: "inline-flex", alignItems: "center", gap: "5px",
  selectors: { "&:hover:not(:disabled)": litOver, "&:disabled": { cursor: "progress" } },
});
