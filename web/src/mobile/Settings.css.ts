import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mMe = style({ display: "flex", alignItems: "center", gap: "14px" });
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
