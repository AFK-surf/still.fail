import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** A chat's letters (Letters.tsx): the chats it wrote with, a row each; one opened, its letters as the chat lays out messages. */
export const letters = style({ flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column" });
export const lettersList = style({ display: "flex", flexDirection: "column", gap: "2px", padding: "6px 8px 16px" });
/** A chat it wrote with: its title and when, the last letter in brief under them; a press opens it. */
export const lettersRow = style({
  display: "flex", flexDirection: "column", gap: "2px", width: "100%", padding: "8px 12px", border: "0",
  borderRadius: vars.rOption, background: "none", color: vars.text, font: "inherit", textAlign: "left", cursor: "pointer",
  cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover": { background: vars.hover } },
});
export const lettersRowHead = style({ display: "flex", alignItems: "baseline", gap: "8px", minWidth: "0" });
export const lettersRowTitle = style({
  flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textUi,
  fontWeight: "500", lineHeight: "20px",
});
export const lettersRowMeta = style({ flex: "none", fontSize: vars.textMeta, color: vars.muted, fontVariantNumeric: "tabular-nums" });
export const lettersRowLast = style({
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textMeta, color: vars.muted,
});
/** One opened: back to the list, and its title (which opens that chat). */
export const lettersHead = style({
  display: "flex", alignItems: "center", gap: "4px", minWidth: "0", padding: "6px 12px 6px 6px", fontSize: vars.textUi,
});
export const lettersName = style({
  minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontWeight: "500", color: vars.text,
  textDecoration: "none",
  selectors: { "a&:hover": { textDecoration: "underline" } },
});
export const lettersMessages = style({ display: "flex", flexDirection: "column", gap: "20px", padding: "10px 16px 24px" });
export const lettersMore = style({ display: "flex", justifyContent: "center", padding: "4px 0" });
