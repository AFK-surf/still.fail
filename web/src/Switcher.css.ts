// ⌘K's switcher (Switcher.tsx): a dialog high on the window, the search on top, the chats under it. Its words stand
// where a dialog's do (ui.css.ts: 24 in); a row's ground reaches to 12 from its edge, a pill, and the switcher's corner
// is from it (12 + its half height, align.ts pillInner), not a dialog's 42: a 38 high row cannot round 30 to follow that.
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { panel } from "@stillfail/ui/styles/glass.ts";

const EDGE = 12;
const ROW = 38;
import { fadeKeyframes, popKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { centredX } from "@stillfail/ui/styles/align.ts";
import { inner, outset, pillInner, surface } from "@stillfail/ui/styles/align.ts";
import { DIALOG_PAD } from "@stillfail/ui/parts.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

export const overlay = style({
  position: "fixed", inset: "0", zIndex: "40", background: vars.overlay,
  animation: `${fadeKeyframes} 120ms ${vars.easeOut}`,
});
export const switcher = style({
  position: "fixed", top: "14vh", zIndex: "50", ...centredX,
  display: "flex", flexDirection: "column", width: "min(560px, calc(100vw - 32px))", maxHeight: "min(480px, 72vh)",
  ...surface(EDGE, pillInner(EDGE, ROW, vars.cornerScale), vars.cornerShape), color: vars.text, ...panel,
  boxShadow: `0 24px 64px ${vars.shadow}`, transformOrigin: "top", animation: `${popKeyframes} 140ms ${vars.easeOut}`,
  cornerShape: vars.cornerShape, outline: "none",
});
export const hidden = style({ position: "absolute", width: 1, height: 1, overflow: "hidden", clip: "rect(0 0 0 0)" });
export const search = style({
  flex: "none", height: 48, padding: "0 12px", border: 0, outline: "none", background: "none", color: vars.text,
  fontSize: vars.textTitle,
  selectors: { "&::placeholder": { color: vars.subtle } },
});
// Under the search, a little room; at its foot none: the last row's ground is as far from the foot as from the sides.
// It reaches out to the switcher's edge (its rows where they were, in by its padding), so its scrollbar runs in the
// room beside the rows, not over them, and stops short of the corner (scroll-padding-bottom: scrollbars.ts).
export const results = style({
  flex: 1, minHeight: 0, overflowY: "auto", ...outset(EDGE), padding: `4px ${EDGE}px 0`, scrollPaddingBottom: inner,
});
export const row = style({
  display: "flex", alignItems: "center", gap: 10, minHeight: ROW, padding: `8px ${DIALOG_PAD - EDGE}px`, borderRadius: inner,
  fontSize: vars.textUi, cursor: "pointer", userSelect: "none", cornerShape: vars.cornerShape,
  // A shade of the text, as the menus' rows are lit.
  selectors: { '&[aria-selected="true"]': { background: `color-mix(in srgb, ${vars.text} 7%, transparent)` } },
});
export const picture = style({ flex: "none", display: "grid", placeItems: "center", width: 20, height: 20 });
// An action's row: a quiet ⌘ where a chat has its picture, its keys where a chat says where and when.
export const actionMark = style({ color: vars.muted });
export const title = style({
  flex: 1, ...ellipsis,
  selectors: { "&[data-unread]": { fontWeight: 600 } },
});
export const meta = style({ flex: "none", display: "flex", gap: 8, fontSize: vars.textMeta, color: vars.muted });
export const none = style({ margin: "14px 12px", fontSize: vars.textUi, color: vars.muted });
// The messages found, under the chats: a few words over them, then each as its chat and who said it when, over the
// line that has the words, those drawn out (the text's colour and weight, the rest muted).
export const section = style({ margin: "10px 12px 4px", fontSize: vars.textMeta, color: vars.muted });
export const said = style({ alignItems: "flex-start" });
export const saidBody = style({ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2 });
export const saidHead = style({ display: "flex", alignItems: "center", gap: 10, minWidth: 0 });
export const saidChat = style({ flex: 1, ...ellipsis });
export const saidText = style({ ...ellipsis, color: vars.muted });
export const hit = style({ background: "none", color: vars.text, fontWeight: 600 });
// 查看更多: a quieter row under its kind, that kind alone once picked.
export const more = style({ color: vars.muted });
// What the list says under it: the stations not answered yet, those offline or too old to search.
export const note = style({ margin: 0, padding: "8px 12px 10px", fontSize: vars.textMeta, color: vars.muted });
