import { style } from "@vanilla-extract/css";

export const mVersionText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column" });
export const mVersionHead = style({ display: "flex", alignItems: "baseline", gap: "6px", minWidth: "0" });
export const mVersionName = style({ fontSize: "15px", color: "var(--m-ink)", whiteSpace: "nowrap" });
export const mVersionShown = style({
  fontSize: "13px", color: "var(--m-muted)", fontVariantNumeric: "tabular-nums", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
export const mVersionNote = style({
  fontSize: "13px", color: "var(--m-muted)",
  selectors: { "&[data-failed]": { color: "var(--m-red)" } },
});
/** What wants doing, at the row's end: grey but for a newer version, an update going on, one that failed. */
export const mVersionState = style({
  display: "flex", alignItems: "center", gap: "10px", flex: "none", fontSize: "13px", fontWeight: "500",
  color: "var(--m-accent-ink)", whiteSpace: "nowrap",
  selectors: { "&[data-failed]": { color: "var(--m-red)" } },
});
export const mVersionAction = style({
  // The phone's buttons inherit font and colour (./styles/root.css.ts): its own are kept.
  padding: "0", border: "0", background: "none", fontSize: "15px !important", fontWeight: "500 !important", color: "var(--m-accent) !important", cursor: "pointer",
});
export const mVersionCheck = style({ flex: "1", fontSize: "15px", color: "var(--m-muted)" });
export const mVersionError = style({ margin: "0", padding: "0 24px 10px", fontSize: "13px", color: "var(--m-red)" });
