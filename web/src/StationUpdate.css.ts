import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { IN, PANEL_PAD, PANEL_PILL, TEXT_IN, pillInner } from "@stillfail/ui/styles/align.ts";
import { panelCard, popover as popover0 } from "@stillfail/ui/styles/controls.css.ts";
import { panelButton, panelIcon } from "@stillfail/ui/parts.css.ts";

export const trigger = style({ display: "inline-flex", alignItems: "center", gap: "5px", flexShrink: 0, padding: "6px 0", border: 0, background: "none", color: vars.accentText, fontSize: vars.textMeta, lineHeight: "18px", cursor: "pointer", whiteSpace: "nowrap", borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, outline: "none", selectors: { "&:focus-visible": { boxShadow: `0 0 0 2px ${vars.fieldFocus}` }, '&[data-tone="trouble"]': { color: vars.red } } });
export const dot = style({ width: "6px", height: "6px", borderRadius: "50%", background: "currentColor", flexShrink: 0 });
/**
 * A small panel of words (controls.css.ts popover, panelCard: docs/ui-panels.md); its head and foot at its padding, a close and a button at their corners.
 * Its corner from those pills (align.ts pillInner): a menu's, for rows taller than they are, would leave a crescent by them.
 */
export const popover = style([popover0, panelCard, { vars: { [IN]: pillInner(PANEL_PAD, PANEL_PILL, vars.cornerScale) }, display: "flex", flexDirection: "column", gap: "8px", width: "min(288px, calc(100vw - 24px))", boxSizing: "border-box", zIndex: 100, color: vars.text, fontSize: vars.textUi, lineHeight: "19px", outline: "none", animation: "none" }]);
/** Its words in by a row's padding and a little down (align.ts panelText); its close in the top right corner, at the padding. */
export const head = style({ display: "flex", alignItems: "flex-start", gap: "8px", paddingLeft: TEXT_IN });
export const words = style({ display: "flex", flexDirection: "column", gap: "2px", minWidth: 0, flex: 1, paddingTop: TEXT_IN, selectors: { [`${head}:last-child &`]: { paddingBottom: TEXT_IN } } });
export const title = style({ display: "flex", alignItems: "baseline", gap: "8px", minWidth: 0 });
export const name = style({ fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: 0 });
export const state = style({ flexShrink: 0, fontSize: vars.textMeta, color: vars.accentText, selectors: { '[data-tone="trouble"] &': { color: vars.red } } });
export const detail = style({ color: vars.muted, fontSize: vars.textMeta, lineHeight: "17px", overflowWrap: "anywhere" });
/** Its progress (waiting.tsx Progress): a line on the words' line (its fill reaches its box, so it is placed by its margin, not padded). */
export const bar = style({ marginInline: TEXT_IN });
export const foot = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", minHeight: "24px", paddingLeft: TEXT_IN });
export const versions = style({ color: vars.muted, fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "16px", fontVariantNumeric: "tabular-nums", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: 0 });
/** Its one thing to do, filled (it must be seen); its close an icon: a small panel's (ui.css.ts). */
export const update = style([panelButton, { marginLeft: "auto" }]);
/** In the card's top right corner as its update is in the bottom right: as far from both edges, rounded as the card less that. */
export const dismiss = panelIcon;
