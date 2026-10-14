import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { cardLook } from "./styles/pages.css.ts";
import { DIALOG_INNER } from "./ui.css.ts";

/** What a public snapshot would hold, as the chat draws it (its messages' heads in line, the phone's way), on a card. */
export const preview = style({
  ...cardLook, display: "grid", gap: "16px", padding: "16px 18px", maxHeight: "340px", overflowY: "auto", minHeight: "0",
  selectors: {
    // In the dialog its corners follow the dialog's (ui.css.ts DIALOG_INNER); on the phone's sheet, the cards' own.
    "&:not([data-whole])": { borderRadius: DIALOG_INNER },
    "&[data-whole]": { maxHeight: "none", minHeight: "auto", overflowY: "visible" },
  },
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
/** Its attachments, on a card as the preview: a row each, its size and its switch at its end (one too big: off, greyed). */
export const files = style({
  ...cardLook, borderRadius: DIALOG_INNER, margin: "0", padding: "6px 0", listStyle: "none",
});
export const fileRow = style({
  display: "flex", alignItems: "center", gap: "10px", minHeight: "40px", padding: "0 16px 0 18px", color: vars.muted,
  selectors: { "&[data-off]": { color: vars.subtle } },
});
export const fileName = style({
  flex: "1 1 0", width: "0", fontSize: vars.textUi, color: vars.text, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: { [`${fileRow}[data-off] &`]: { color: vars.subtle } },
});
export const fileSize = style({ flex: "none", fontSize: vars.textMeta, color: "inherit" });
/** In the footer, on the buttons' left: how many things were hidden in all. */
export const footNote = style({
  display: "flex", alignItems: "center", gap: "6px", marginRight: "auto", fontSize: vars.textMeta, color: vars.muted, minWidth: "0",
});
/** What went wrong (the preview not read, the ticked too big together), in red. */
export const problem = style({ margin: "0", fontSize: vars.textUi, color: vars.red });
/** The link once published, as a one-line field shows it (a pill, as the buttons under it): cut short at its end. */
export const madeLink = style({
  display: "block", minWidth: "0", height: "40px", padding: "0 18px", borderRadius: "999px", background: cardLook.background,
  fontSize: vars.textUi, lineHeight: "40px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", userSelect: "all",
});
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
