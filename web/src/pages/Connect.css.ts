import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const kindTag = style({ display: "inline-flex", alignItems: "center", gap: "5px", color: vars.text });
export const listRowTime = style({ flex: "none", minWidth: "5.5em", textAlign: "right", fontSize: vars.textMeta });
export const moreSessions = style({ marginTop: "8px" });
export const pageError = style({ margin: "-16px 0 20px" });
export const dialogStep = style({
  fontSize: vars.textUi, fontWeight: "400", color: vars.muted, fontVariantNumeric: "tabular-nums",
});
export const sessionChoices = style({ maxHeight: "min(52vh, 460px)", overflowY: "auto", padding: "2px", margin: "-2px" });
export const stepActions = style({});
export const ownerLine = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
export const inputLink = style({
  display: "flex", alignItems: "center", color: vars.accentText, textDecoration: "none", cursor: "pointer",
  selectors: {
    "&:hover": { borderColor: vars.fieldHover },
  },
});
export const slackTeamIcon = style({});
export const tokenOwner = style({ display: "inline-flex", alignItems: "center", gap: "6px", flexWrap: "wrap" });
export const tokenStart = style({ display: "grid", gap: "8px" });
export const tokenManual = style({ margin: "8px 0 0", fontSize: vars.textMeta });
export const teamMore = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: "8px",
});
/** The connect page: how it runs in one card, the Slack app folded. */
export const connectStatus = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
export const runCard = style({ display: "grid", gap: "14px" });
export const runCardRow = style({ display: "flex", alignItems: "flex-start", gap: "14px" });
export const runCardLabel = style({
  flex: "none", width: "36px", paddingTop: "2px", fontSize: vars.textUi, color: vars.muted,
});
export const runCardText = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px", fontSize: vars.textUi });
globalStyle(`${tokenOwner} img`, { borderRadius: "50%" });
globalStyle(`${tokenStart} h3`, { margin: "0", fontSize: vars.textTitle });
globalStyle(`${teamMore} ${tokenManual}`, { margin: "0", color: vars.muted });
