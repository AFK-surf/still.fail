import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** A chat's letters (Letters.tsx): each other chat's, one after another, the way the chat lays out messages. */
export const letters = style({
  flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", gap: "28px", padding: "12px 16px 24px",
});
export const lettersChat = style({ display: "flex", flexDirection: "column", gap: "20px" });
/** The other chat: its title (which opens it) and how many, over its letters. */
export const lettersHead = style({
  display: "flex", alignItems: "baseline", gap: "8px", minWidth: "0", fontSize: vars.textMeta, color: vars.muted,
});
export const lettersName = style({
  minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontWeight: "500", color: vars.text,
  textDecoration: "none",
  selectors: { "a&:hover": { textDecoration: "underline" } },
});
export const lettersCount = style({ flex: "none" });
export const lettersMore = style({ display: "flex", justifyContent: "center", padding: "4px 0" });
