import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mVersionText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column" });
export const mVersionHead = style({ display: "flex", alignItems: "baseline", gap: "6px", minWidth: "0" });
export const mVersionName = style({ fontSize: vars.textBody, color: "var(--m-ink)", whiteSpace: "nowrap" });
export const mVersionShown = style({
  fontSize: vars.textSecondary, color: "var(--m-muted)", fontVariantNumeric: "tabular-nums", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
/** The station on the test channel: a small tag beside its version. */
export const mVersionBeta = style({
  alignSelf: "center", flex: "none", padding: "0 6px", borderRadius: "999px", background: "var(--m-accent-bg)",
  color: "var(--m-accent-ink)", fontSize: vars.textCaption, fontWeight: "500", lineHeight: "18px",
});
export const mVersionNote = style({
  fontSize: vars.textSecondary, color: "var(--m-muted)",
  selectors: { "&[data-failed]": { color: "var(--m-red)" } },
});
/** What wants doing, at the row's end: grey but for a newer version, an update going on, one that failed. */
export const mVersionState = style({
  display: "flex", alignItems: "center", gap: "10px", flex: "none", fontSize: vars.textSecondary, fontWeight: "500",
  color: "var(--m-accent-ink)", whiteSpace: "nowrap",
  selectors: { "&[data-failed]": { color: "var(--m-red)" } },
});
export const mVersionAction = style({
  // The phone's buttons inherit font and colour (./styles/root.css.ts): its own are kept.
  padding: "0", border: "0", background: "none", fontSize: `${vars.textBody} !important`, fontWeight: "500 !important", color: "var(--m-accent) !important", cursor: "pointer",
});
export const mVersionCheck = style({ flex: "1", fontSize: vars.textBody, color: "var(--m-muted)" });
export const mVersionError = style({ margin: "0", padding: "0 24px 10px", fontSize: vars.textSecondary, color: "var(--m-red)" });
