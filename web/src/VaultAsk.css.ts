import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { CARD_PAD, LIST_PAD, listCardLook } from "./styles/pages.css.ts";
import { inClient } from "./VaultApproval.css.ts";

// An agent's request for a vault item in its chat (VaultAsk.tsx): one card in the options' ground, what is asked over a
// rule, the approval's rows (or how it ended) under it.
const ground = `var(--m-chip, color-mix(in srgb, ${vars.text} 5%, transparent))`;
const inset = `color-mix(in srgb, ${vars.text} 6%, transparent)`;
const SIDE = CARD_PAD - LIST_PAD;

export const card = style({
  ...listCardLook, background: ground, display: "flex", flexDirection: "column", width: "fit-content", minWidth: "min(100%, 460px)",
  maxWidth: "min(100%, 640px)", boxSizing: "border-box", marginTop: "2px", padding: LIST_PAD,
});
export const info = style({ display: "grid", gap: "8px", padding: `${SIDE - 6}px ${SIDE}px 12px` });
export const head = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", flexWrap: "wrap" });
/** The key, in a round of the amber a secret is told by. */
export const key = style({
  display: "inline-grid", placeItems: "center", width: "24px", height: "24px", borderRadius: "50%", flex: "none",
  background: vars.amberBg, color: vars.amber,
});
export const verb = style({ fontSize: vars.textUi, lineHeight: vars.leadingUi, color: vars.muted });
export const name = style({ fontSize: vars.textUi, lineHeight: vars.leadingUi, fontWeight: "600", color: vars.text, overflowWrap: "anywhere" });
export const tag = style({
  display: "inline-flex", alignItems: "center", padding: "1px 8px", borderRadius: "999px", fontSize: vars.textMeta,
  lineHeight: vars.leadingMeta, color: vars.muted, background: inset, overflowWrap: "anywhere",
});
export const host = style({ fontFamily: vars.fontMono });
export const reason = style({ margin: "0", fontSize: vars.textUi, lineHeight: vars.leadingBody, color: vars.text, overflowWrap: "anywhere" });
/** The command in its inset; its words three lines of it until opened (`commandText`). */
export const command = style({
  margin: "0", padding: "8px 10px", borderRadius: vars.rField, cornerShape: vars.cornerShape, background: inset,
});
export const commandText = style({
  fontFamily: vars.fontMono, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.text, whiteSpace: "pre-wrap",
  wordBreak: "break-all", overflow: "hidden", display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: "3",
  selectors: { "&[data-open]": { display: "block" } },
});
export const more = style({
  justifySelf: "start", padding: "0", border: "0", background: "none", color: vars.muted, fontSize: vars.textMeta,
  lineHeight: vars.leadingMeta, fontFamily: "inherit", cursor: "pointer", selectors: { "&:hover": { color: vars.text } },
});
export const rule = style({ height: "1px", margin: `0 ${SIDE}px 4px`, background: vars.line });
export const who = style({ margin: `4px ${SIDE}px 2px`, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.subtle });
/** The approval's rows in the card: their own card's ground, room and width taken off. */
export const rows = style({});
globalStyle(`${rows} > *`, { background: "none", margin: "0", padding: "0", minWidth: "0", width: "100%" });
// A web page's word in their place: level with the card's words.
globalStyle(`${rows} > ${inClient}`, { padding: `4px ${SIDE}px 8px` });
/** How it ended, where the rows were. */
export const outcome = style({
  display: "flex", alignItems: "center", gap: "6px", padding: `8px ${SIDE}px 6px`, fontSize: vars.textUi, lineHeight: vars.leadingUi,
  color: vars.muted,
  selectors: { "&[data-tone=granted]": { color: vars.green }, "&[data-tone=denied]": { color: vars.red } },
});
