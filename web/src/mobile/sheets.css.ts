import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { mJobLast } from "./Chat.css.ts";
import { mDetails } from "./Profiles.css.ts";
import { mButton } from "./parts.css.ts";
import { surfaceCorner } from "@stillfail/ui/styles/align.ts";

export const mDangerButton = style({});
/** A command's box: its copy button in its top right corner, 10 in from both edges, the box's corner from it. */
const COMMAND_PAD = 10;
const COMMAND_BUTTON_CORNER = `calc(8px * ${vars.cornerScale})`;
export const mCommand = style({
  display: "flex", alignItems: "flex-start", gap: "8px", padding: `${COMMAND_PAD}px ${COMMAND_PAD}px ${COMMAND_PAD}px 12px`,
  borderRadius: surfaceCorner(COMMAND_PAD, COMMAND_BUTTON_CORNER), cornerShape: vars.cornerShape,
  background: "var(--m-surface2)", border: "1px solid var(--m-line)",
  selectors: {
    [`${mDetails} &`]: { marginTop: "6px" },
  },
});
/** Asking: a destructive action's button in red; a command with its copy button. */
globalStyle(`${mDangerButton}[data-danger] ${mButton}`, { background: "var(--m-red)", color: "#fff !important" });
globalStyle(`${mCommand} code`, {
  flex: "1", minWidth: "0", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: vars.textCaption,
  lineHeight: "18px", overflowWrap: "anywhere", userSelect: "all",
});
globalStyle(`${mCommand} button`, {
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", padding: "0", border: "0",
  borderRadius: COMMAND_BUTTON_CORNER, cornerShape: vars.cornerShape, background: "var(--m-chip)", cursor: "pointer",
});
/** Here rather than with its class: it comes after .m-command code, and wins over it. */
globalStyle(`${mJobLast} code`, {
  font: `${vars.textCaption}/1.5 ui-monospace, SFMono-Regular, Menlo, monospace`, color: "var(--m-muted)", whiteSpace: "nowrap",
  overflow: "hidden", textOverflow: "ellipsis",
});
