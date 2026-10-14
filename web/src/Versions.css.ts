import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** A station's software in a line: grey, but for a newer version out, an update going on, or one that failed. */
export const versions = style({
  display: "flex", flexWrap: "wrap", alignItems: "baseline", gap: "2px 14px", fontSize: vars.textMeta, color: vars.muted,
});
export const item = style({ display: "inline-flex", alignItems: "baseline", gap: "5px", whiteSpace: "nowrap" });
export const version = style({ fontVariantNumeric: "tabular-nums" });
export const newer = style({ color: vars.accentText, fontWeight: "500" });
export const failed = style({ color: vars.red, fontWeight: "500" });
export const action = style({
  padding: "0", border: "0", background: "none", font: "inherit", fontWeight: "500", color: vars.accentText, cursor: "pointer",
  textDecoration: "underline", textUnderlineOffset: "2px",
  selectors: { "&:disabled": { cursor: "default", opacity: "0.6" } },
});
export const check = style([action, { color: vars.muted, fontWeight: "400" }]);
/** The station on the test channel: a small tag beside its version. */
export const betaTag = style({
  alignSelf: "center", padding: "0 5px", borderRadius: "999px", background: vars.accentBg, color: vars.accentText,
  fontSize: vars.textCaption, fontWeight: "500", lineHeight: "16px",
});
/** The 测试版 switch, with its name before it. */
export const channel = style({ display: "inline-flex", alignItems: "center", gap: "6px", alignSelf: "center", cursor: "pointer", whiteSpace: "nowrap" });

/** A single overview line; version numbers and settings live in the station detail. */
export const summary = style({ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: "16px", fontSize: vars.textUi, color: vars.muted });
export const summaryText = style({ display: "flex", flexWrap: "wrap", gap: "4px 12px", minWidth: 0 });
export const summaryAction = style({ display: "inline-flex", alignItems: "center", gap: "6px", flexShrink: 0 });

/** The station's page: a row each, as its lists' rows (not pressed: no ground on hover), its mark in a square as a profile's is (ProfileCard). */
export const softRow = style({ selectors: { "&:hover": { background: "none" } } });
export const softMark = style({ width: "36px", height: "36px" });
export const softName = style({ display: "inline-flex", alignItems: "center", gap: "6px", fontWeight: "500", color: vars.text });
export const softVersion = style({ color: vars.muted, fontVariantNumeric: "tabular-nums" });
/** The station's switches under its version, side by side. */
export const softSwitches = style({ display: "flex", flexWrap: "wrap", gap: "4px 16px", marginTop: "4px", fontSize: vars.textMeta, color: vars.muted });
export const softRest = style({ display: "inline-flex", alignItems: "center", gap: "10px", flex: "none", fontSize: vars.textUi });
/** When it was last checked and checking again, quiet, under the rest. */
export const cardFoot = style({ padding: "4px 12px 0", display: "flex", flexWrap: "wrap", alignItems: "baseline", gap: "4px 12px", fontSize: vars.textMeta, color: vars.muted });
