// 外观 › 字体 (FontSetting.tsx): the places' switch, the faces as tiles, a chat as they set it.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { PANEL_PAD, TEXT_IN } from "@stillfail/ui/styles/align.ts";
import { CARD_PAD, cardGround, cardLook } from "./styles/pages.css.ts";

export const setting = style({ display: "grid", gap: "14px", maxWidth: "640px", justifyItems: "start" });

/** The faces of a place, as tiles: each its name and a sample in itself, the chosen one ringed. */
export const tiles = style({ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))", gap: "10px", width: "100%" });
export const tile = style({
  position: "relative", display: "grid", justifyItems: "center", alignContent: "center", gap: "6px", minWidth: "0", height: "96px",
  padding: "12px 10px", border: "0", borderRadius: vars.rCard, cornerShape: vars.cornerShape, background: cardGround, color: vars.text,
  cursor: "pointer", font: "inherit", transition: `box-shadow ${vars.dur} ${vars.easeOut}, background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: `color-mix(in oklab, ${vars.text} 7%, ${vars.canvas})` },
    '&[aria-pressed="true"]': { boxShadow: `inset 0 0 0 1.5px ${vars.accent}` },
    "&:focus-visible": { outline: `2px solid ${vars.fieldFocus}`, outlineOffset: "2px" },
  },
});
export const tileGlyph = style({ fontSize: vars.textDisplay, lineHeight: "36px", whiteSpace: "nowrap" });
export const tileName = style({
  maxWidth: "100%", fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: { '[aria-pressed="true"] > &': { color: vars.text } },
});
/** The chosen one's check, in its corner. */
export const tileCheck = style({
  position: "absolute", top: "10px", right: "10px", color: vars.accent, opacity: "0",
  selectors: { '[aria-pressed="true"] > &': { opacity: "1" } },
});

/** The faces installed here: a filter on top, the families under it, each in itself. */
export const localPanel = style({ width: "300px", display: "grid" });
export const localSearch = style({
  display: "flex", alignItems: "center", gap: "8px", padding: `4px ${TEXT_IN}px 8px`, color: vars.subtle, cursor: "text",
  borderBottom: `1px solid color-mix(in srgb, ${vars.text} 10%, transparent)`, marginBottom: `${PANEL_PAD}px`,
});
globalStyle(`${localSearch} input`, {
  flex: "1", minWidth: "0", border: "0", outline: "none", background: "none", color: vars.text, font: "inherit", fontSize: vars.textUi,
});
globalStyle(`${localSearch} input::placeholder`, { color: vars.subtle });
export const localList = style({ maxHeight: "320px", overflowY: "auto", display: "grid", alignContent: "start" });
export const localRow = style({ selectors: { '&[aria-pressed="true"]': { background: vars.hover } } });
export const localName = style({ flex: "1", minWidth: "0", fontSize: vars.textBody, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${localRow}:not([aria-pressed="true"]) ${tileCheck}`, { opacity: "0" });
globalStyle(`${localRow}[aria-pressed="true"] ${tileCheck}`, { position: "static", opacity: "1" });
export const localNote = style({ margin: "0", padding: `8px ${TEXT_IN}px`, fontSize: vars.textUi, color: vars.muted });

/**
 * The preview: a card of the settings (pages.css.ts), a chat in it as the faces set it. Its words are set here by the
 * page's variables, so a face tried (on the card itself) is what they take.
 */
export const preview = style({
  ...cardLook, padding: CARD_PAD, display: "grid", gap: "14px", width: "100%", boxSizing: "border-box",
  fontFamily: vars.fontBody, color: vars.text,
});
export const previewMine = style({ display: "flex", justifyContent: "flex-end" });
export const previewWords = style({ fontFamily: vars.fontText, fontVariantNumeric: "normal", fontSize: vars.textBody, lineHeight: "1.55" });
export const previewName = style({ fontSize: vars.textUi, fontWeight: "600", color: vars.accentText });
// On the settings' grey card, the bubble and the code on the page's own ground, as a chat has them.
globalStyle(`${preview} ${previewMine} > *, ${preview} pre`, { background: vars.canvas });
