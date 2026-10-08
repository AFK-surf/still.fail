import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { mGrow, mLink } from "./styles/parts.css.ts";
import { mJobHead, mJobText, mJobsAll, mJobsEmpty } from "./Chat.css.ts";

export const mChoices = style({ display: "flex", flexDirection: "column", gap: "8px" });
export const mChoice = style({
  display: "flex", flexDirection: "column", gap: "2px", padding: "12px 14px", border: "1px solid var(--m-line)",
  borderRadius: "14px", background: "var(--m-surface)", textAlign: "left", cursor: "pointer",
  selectors: {
    "&[data-on]": { borderColor: "var(--m-accent)", boxShadow: "inset 0 0 0 1px var(--m-accent)" },
  },
});
export const mSwitchRow = style({
  display: "flex", alignItems: "center", gap: "12px", padding: "10px 14px", border: "0", borderRadius: "14px",
  background: "var(--m-chip)", textAlign: "left", cursor: "pointer",
});
export const mSwitch = style({
  position: "relative", flex: "none", width: "44px", height: "26px", borderRadius: "13px", background: "var(--m-line)",
  transition: "background 160ms",
  selectors: {
    "&::after": {
      content: "\"\"", position: "absolute", top: "3px", left: "3px", width: "20px", height: "20px",
      borderRadius: "50%", background: "#fff", boxShadow: "0 1px 3px rgba(0, 0, 0, .2)",
      transition: "transform 160ms var(--m-standard)",
    },
    "&[data-on]": { background: "var(--m-green)" },
    "&[data-on]::after": { transform: "translateX(18px)" },
  },
});
export const mGreen = style({ color: "var(--m-green)" });
export const mStepsList = style({
  margin: "0", paddingLeft: "20px", display: "flex", flexDirection: "column", gap: "8px", fontSize: vars.textUi,
  lineHeight: "1.55",
});
globalStyle(`${mChoice} b`, { fontSize: vars.textBody, fontWeight: "600" });
globalStyle(`${mChoice} span, ${mSwitchRow} ${mGrow} span`, { fontSize: vars.textMeta, color: "var(--m-muted)" });
globalStyle(`${mSwitchRow} ${mGrow}`, { display: "flex", flexDirection: "column" });
globalStyle(`${mSwitchRow} b`, { fontSize: vars.textUi, fontWeight: "600" });
globalStyle(`${mStepsList} a, ${mStepsList} ${mLink}`, { color: "var(--m-accent)" });
/** Here rather than with its class: it comes after .m-choice b, and wins over it. */
globalStyle(`${mJobText} b`, {
  fontSize: vars.textBody, fontWeight: "500", lineHeight: "21px", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-choice span, and wins over it. */
globalStyle(`${mJobText} > span`, {
  fontSize: vars.textCaption, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .m-choice b, and wins over it. */
globalStyle(`${mJobHead} b`, { fontSize: vars.textTitle, fontWeight: "600", lineHeight: "23px" });
/** Here rather than with its class: it comes after .m-switch-row b, and wins over it. */
globalStyle(`${mJobsEmpty} b`, { fontSize: vars.textBody, fontWeight: "600", color: "var(--m-ink)" });
/** Here rather than with its class: it comes after .m-choice span, and wins over it. */
globalStyle(`${mJobsAll} span`, { fontSize: vars.textCaption, color: "var(--m-muted)" });
/** 全部 or 我建的, over the list of every station's connects. */
export const mListSeg = style({ padding: "4px 16px 2px" });
