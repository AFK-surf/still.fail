import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const setting = style({ display: "grid", gap: "14px", maxWidth: "560px" });
export const rows = style({ display: "grid", gridTemplateColumns: "auto minmax(0, 1fr)", alignItems: "center", gap: "10px 16px" });
export const row = style({ display: "contents" });
export const label = style({ fontSize: vars.textUi, color: vars.text });
export const failed = style({ margin: "6px 0 0", fontSize: vars.textMeta, color: vars.red });

/** The preview (a card of words, pages.css.ts card): each place's sample under its name; the code without a ground of
 *  its own, so nothing is drawn in the card's corners. */
export const samples = style({ display: "grid", gap: "14px" });
export const sample = style({ display: "grid", gap: "4px", minWidth: "0" });
export const sampleLabel = style({ fontSize: vars.textCaption, color: vars.subtle });
export const sampleUi = style({ fontFamily: vars.fontBody, fontSize: vars.textUi, color: vars.text });
export const sampleText = style({ margin: "0", fontFamily: vars.fontText, fontSize: vars.textBody, lineHeight: "1.65", color: vars.text });
export const sampleCode = style({
  margin: "0", fontFamily: vars.fontMono, fontSize: vars.textMeta, lineHeight: "1.55", color: vars.text, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
