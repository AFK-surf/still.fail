import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { mJobLast } from "./Chat.css.ts";
import { mDetails } from "./Profiles.css.ts";
import { mButton } from "./parts.css.ts";

export const mDangerButton = style({});
export const mCommand = style({
  display: "flex", alignItems: "flex-start", gap: "8px", padding: "10px 10px 10px 12px", borderRadius: "12px",
  background: "var(--m-surface2)", border: "1px solid var(--m-line)",
  selectors: {
    [`${mDetails} &`]: { marginTop: "6px" },
  },
});
/** Asking: a destructive action's button in red; a command with its copy button. */
globalStyle(`${mDangerButton}[data-danger] ${mButton}`, { background: "var(--m-red)", color: "#fff !important" });
globalStyle(`${mCommand} code`, {
  flex: "1", minWidth: "0", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: vars.textLabel,
  lineHeight: "18px", overflowWrap: "anywhere", userSelect: "all",
});
globalStyle(`${mCommand} button`, {
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", padding: "0", border: "0",
  borderRadius: "8px", background: "var(--m-chip)", cursor: "pointer",
});
/** Here rather than with its class: it comes after .m-command code, and wins over it. */
globalStyle(`${mJobLast} code`, {
  font: `${vars.textCaption}/1.5 ui-monospace, SFMono-Regular, Menlo, monospace`, color: "var(--m-muted)", whiteSpace: "nowrap",
  overflow: "hidden", textOverflow: "ellipsis",
});
