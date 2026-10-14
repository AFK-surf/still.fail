import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { cardLook } from "./styles/pages.css.ts";

/** What a public snapshot would hold, as the chat draws it (its messages' heads in line, the phone's way), on a card. */
export const preview = style({
  ...cardLook, display: "grid", gap: "16px", padding: "16px 18px", maxHeight: "340px", overflowY: "auto", minHeight: "0",
  selectors: { "&[data-whole]": { maxHeight: "none", minHeight: "auto", overflowY: "visible" } },
});
/** Under a message: how many things in it were hidden (as looking secret), or its attachments' names. */
export const note = style({
  display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: vars.muted, minWidth: "0",
});
/** An attachment in a message's words or under it: its name on a soft chip (the preview has no file to show). */
export const fileChip = style({
  display: "inline-flex", alignItems: "center", gap: "4px", maxWidth: "100%", padding: "1px 8px", verticalAlign: "middle",
  borderRadius: vars.rOption, cornerShape: vars.cornerShape, background: vars.neutralBg, color: vars.muted,
  fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Its attachments to tick: a row each, its size at its end. */
export const files = style({ margin: "0 -12px", padding: "0", listStyle: "none" });
export const fileSize = style({ flex: "none", fontSize: vars.textMeta, color: vars.muted });
export const fileRow = style({
  selectors: {
    "&[data-off]": { color: vars.subtle, cursor: "default" },
    "&[data-off]:hover": { background: "none" },
  },
});
/** What went wrong (the preview not read, the ticked too big together), in red. */
export const problem = style({ margin: "0", fontSize: vars.textUi, color: vars.red });
/** The link once published: the whole of it, cut short at its end, and its copy button. */
export const made = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0" });
export const madeLink = style({
  ...cardLook, minWidth: "0", padding: "8px 14px", fontSize: vars.textUi, lineHeight: "20px",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", userSelect: "all",
});
globalStyle(`${made} > ${madeLink}`, { flex: "1 1 0", width: "0" });
/** A chat's public links in its info: a row each under 「公开分享」, when and by whom, 复制 and 撤销 at its end. */
export const link = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "30px", padding: "2px 10px 2px 32px",
  fontSize: vars.textMeta, color: vars.muted,
});
export const linkText = style({ flex: "1 1 0", width: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const linkAction = style({
  flex: "none", padding: "2px 4px", border: "0", background: "none", color: vars.muted, font: "inherit", cursor: "pointer",
  borderRadius: vars.rOption, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { color: vars.text, background: vars.hover },
    "&:disabled": { cursor: "default", opacity: "0.5" },
  },
});
