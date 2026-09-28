import { globalStyle, style } from "@vanilla-extract/css";
import { mGrow } from "./parts.css.ts";
import { mForm } from "./sheets.css.ts";
import { mCard } from "./lists.css.ts";

export const mStationPage = style({ paddingTop: "12px", paddingBottom: "var(--m-foot)" });
export const mProfileTools = style({ display: "flex", alignItems: "center", gap: "12px", padding: "0 12px 8px" });
export const mModelRow = style({
  display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "100%", padding: "11px 24px",
  border: "0", background: "none", textAlign: "left", cursor: "pointer",
});
export const mCheck = style({
  display: "grid", placeItems: "center", flex: "none", width: "20px", height: "20px", borderRadius: "6px",
  background: "var(--m-chip)", color: "var(--m-bg)",
  selectors: {
    "&[data-on]": { background: "var(--m-accent)" },
  },
});
/** Connects: a page's note, a row's status, the mode choices, a switch, tokens, steps. */
export const mPageNote = style({ padding: "0 24px 10px", fontSize: "13px", color: "var(--m-muted)" });
export const mRowAside = style({ fontSize: "13px", color: "var(--m-muted)" });
export const mRowStatus = style({
  display: "inline-flex", alignItems: "center", gap: "5px", flex: "none", fontSize: "12px", color: "var(--m-muted)",
  whiteSpace: "nowrap",
});
export const mPresence = style({
  display: "inline-block", width: "7px", height: "7px", borderRadius: "50%", background: "var(--m-subtle)",
  flex: "none",
  selectors: {
    "&[data-state=\"online\"]": { background: "var(--m-green)" },
    "&[data-state=\"busy\"]": { background: "var(--m-accent)" },
    "&[data-state=\"error\"]": { background: "var(--m-red)" },
    "&[data-state=\"offline\"]": { background: "none", boxShadow: "inset 0 0 0 1.5px var(--m-subtle)" },
  },
});
export const mWrap = style({ whiteSpace: "normal" });
export const mCallout = style({
  margin: "0 12px 10px", padding: "10px 12px", borderRadius: "12px",
  background: "color-mix(in srgb, var(--m-warn) 12%, transparent)", fontSize: "13px", lineHeight: "1.5",
  selectors: {
    [`${mForm} &`]: { margin: "0" },
  },
});
export const mFormGroup = style({
  display: "flex", flexDirection: "column", gap: "8px",
  selectors: {
    [`${mCard}&`]: { gap: "10px" },
  },
});
export const mSteps = style({ display: "flex", flexDirection: "column", gap: "12px", paddingTop: "8px" });
export const mStepAlt = style({ alignSelf: "flex-start" });
/** A profile: its head (whether it works), a device code, variables, what is folded. */
export const mProfileHead = style({ display: "flex", alignItems: "flex-start", gap: "12px" });
globalStyle(`${mSteps} ${mCallout}`, { margin: "0" });
globalStyle(`${mCallout} ul`, { margin: "4px 0 0", paddingLeft: "18px" });
globalStyle(`${mProfileHead} ${mGrow}`, { display: "flex", flexDirection: "column", gap: "4px", alignItems: "flex-start" });
