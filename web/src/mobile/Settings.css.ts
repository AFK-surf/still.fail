import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
/** A settings row's icon, before its name (Android's RowIcon). */
export const mRowIcon = style({ flex: "none", color: "var(--m-muted)" });
/**
 * The workspace's mark on its card, as the account's picture is on its own (Android's WorkspaceTile): its first letter,
 * muted, on the chips' ground (the wide screen's rail, Rail.css.ts); one of still.fail's icons or an emoji there too; a
 * picture put up fills it. In the card's corners (its padding from its edges, 14 above and under): concentric with the
 * card's corner (lists.css.ts mCard, 20).
 */
export const mWorkspace = style({
  display: "grid", placeItems: "center", flex: "none", width: "46px", height: "46px", overflow: "hidden",
  borderRadius: `calc(20px * ${vars.cornerScale} - 14px)`, cornerShape: vars.cornerShape, background: "var(--m-chip)",
  color: "var(--m-muted)", fontSize: "22px", fontWeight: "600", lineHeight: "1",
  selectors: {
    "&[data-marked]": { color: "var(--m-ink)" },
    "&[data-picture]": { background: "none" },
  },
});
/** How things stand, at a row's end before its chevron. */
export const mValue = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", maxWidth: "60%", overflow: "hidden",
  fontSize: vars.textMeta, color: "var(--m-muted)", whiteSpace: "nowrap", textOverflow: "ellipsis",
});
/** What a choice above it does (the appearance's motion): quiet, under it. */
/** 外观 › 字体 (mobile/Fonts.tsx): the places' switch, the preview card, a face's sample under its name. */
export const mFontPlaces = style({ padding: "0 12px 12px" });
export const mFontPreview = style({ display: "grid", gap: "12px" });
export const mFontSample = style({ fontSize: vars.textMeta, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const mSegNote = style({ padding: "8px 24px 0", fontSize: vars.textMeta, lineHeight: "1.5", color: "var(--m-muted)" });
