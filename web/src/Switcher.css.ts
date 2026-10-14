// ⌘K's switcher (Switcher.tsx): a card high on the window, the search on top, the chats under it.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { panel } from "./styles/glass.ts";
import { fadeKeyframes, popKeyframes } from "./styles/keyframes.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

export const overlay = style({
  position: "fixed", inset: "0", zIndex: "40", background: vars.overlay,
  animation: `${fadeKeyframes} 120ms ${vars.easeOut}`,
});
export const switcher = style({
  position: "fixed", left: "50%", top: "14vh", zIndex: "50", marginLeft: "calc(min(560px, 100vw - 32px) / -2)",
  display: "flex", flexDirection: "column", width: "min(560px, calc(100vw - 32px))", maxHeight: "min(480px, 72vh)",
  padding: "6px", borderRadius: vars.rMenu, color: vars.text, ...panel,
  boxShadow: `0 24px 64px ${vars.shadow}`, transformOrigin: "top", animation: `${popKeyframes} 140ms ${vars.easeOut}`,
  cornerShape: vars.cornerShape, outline: "none",
});
export const hidden = style({ position: "absolute", width: 1, height: 1, overflow: "hidden", clip: "rect(0 0 0 0)" });
export const search = style({
  flex: "none", height: 48, padding: "0 10px", border: 0, outline: "none", background: "none", color: vars.text,
  fontSize: vars.textTitle,
  selectors: { "&::placeholder": { color: vars.subtle } },
});
export const results = style({ flex: 1, minHeight: 0, overflowY: "auto", padding: "4px 0" });
export const row = style({
  display: "flex", alignItems: "center", gap: 10, minHeight: 38, padding: "8px 10px", borderRadius: `calc(${vars.rMenu} - 6px)`,
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
export const none = style({ margin: "14px 10px", fontSize: vars.textUi, color: vars.muted });
// The messages found, under the chats: a few words over them, then each as its chat and who said it when, over the
// line that has the words, those drawn out (the text's colour and weight, the rest muted).
export const section = style({ margin: "10px 10px 4px", fontSize: vars.textMeta, color: vars.muted });
export const said = style({ alignItems: "flex-start" });
export const saidBody = style({ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2 });
export const saidHead = style({ display: "flex", alignItems: "center", gap: 10, minWidth: 0 });
export const saidChat = style({ flex: 1, ...ellipsis });
export const saidText = style({ ...ellipsis, color: vars.muted });
export const hit = style({ background: "none", color: vars.text, fontWeight: 600 });
