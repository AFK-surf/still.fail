import { style } from "@vanilla-extract/css";
import { vars } from "../../styles/tokens.css.ts";

export const mPill = style({
  marginLeft: "6px", padding: "1px 6px", borderRadius: "6px", fontSize: vars.textCaption, whiteSpace: "nowrap",
  selectors: {
    "&[data-tone=\"blue\"]": { color: "var(--m-blue)", background: "color-mix(in srgb, var(--m-blue) 12%, transparent)" },
    "&[data-tone=\"red\"]": { color: "var(--m-red)", background: "color-mix(in srgb, var(--m-red) 12%, transparent)" },
    "&[data-tone=\"accent\"]": {
      color: "var(--m-accent-ink)", background: "color-mix(in srgb, var(--m-accent-ink) 12%, transparent)",
    },
    "&[data-tone=\"green\"]": { color: "var(--m-green)", background: "color-mix(in srgb, var(--m-green) 12%, transparent)" },
    "&[data-tone=\"amber\"]": { color: "var(--m-warn)", background: "color-mix(in srgb, var(--m-warn) 14%, transparent)" },
    "&[data-tone=\"neutral\"]": { color: "var(--m-muted)", background: "var(--m-chip)" },
  },
});
export const mRunLabel = style({ width: "32px", flex: "none", fontSize: vars.textSecondary, color: "var(--m-muted)" });
export const mSettingMain = style({
  fontSize: vars.textBody, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mEffortNote = style({ paddingBottom: "8px" });
export const mChips = style({ display: "flex", flexWrap: "wrap", gap: "8px" });
export const mChip = style({
  padding: "9px 16px", border: "0", borderRadius: "18px", background: "var(--m-chip)", fontSize: `${vars.textControl} !important`,
  cursor: "pointer",
  selectors: {
    "&[data-on]": { background: "var(--m-ink)", color: "var(--m-bg) !important", fontWeight: "600" },
  },
});
export const mRunGo = style({
  display: "flex", alignItems: "center", justifyContent: "center", gap: "8px", flex: "none", minHeight: "52px",
  margin: "12px 18px calc(12px + var(--m-foot))", padding: "12px 16px", border: "0", borderRadius: "16px",
  background: "var(--m-chip)", fontSize: `${vars.textBody} !important`, fontWeight: "600", textAlign: "center", cursor: "pointer",
  selectors: {
    "&[data-changed]": { background: "var(--m-ink)", color: "var(--m-bg) !important" },
  },
});
