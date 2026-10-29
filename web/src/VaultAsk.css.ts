import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

// An agent's request about a vault item in its chat (VaultAsk.tsx): a card of words (pagesCss.card: CARD_PAD on every
// side, its corner the button's in its foot); what is asked over the answer's buttons. Once decided, a line.
export const card = style({ width: "fit-content", minWidth: "min(100%, 320px)", maxWidth: "min(100%, 560px)", boxSizing: "border-box", marginTop: "2px" });
export const what = style({ display: "grid", gap: "2px", minWidth: "0" });
export const title = style({ fontSize: vars.textUi, lineHeight: vars.leadingUi, fontWeight: "400", color: vars.text, overflowWrap: "anywhere" });
/** The item's name in its title: heavier than the words around it, in place of quotes (docs/ui-panels.md 文字). */
export const titleName = style({ fontWeight: "600" });
/** The account a secret to keep is for, after its title. */
export const sub = style({ marginLeft: "8px", fontWeight: "400", color: vars.muted });
/** The command, one line of it (the rest in its tip). */
export const command = style({
  fontFamily: vars.fontMono, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted,
  whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
});
/** What is out of the ordinary (a command that reads the secret itself): the one thing given a colour. */
export const risk = style({ fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.amber });
/** Where there is no answer to give here: whose it is, or where it is approved. */
export const note = style({ margin: "0", fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted });
/** How it ended: a dot and its words. */
export const outcome = style({
  display: "flex", alignItems: "center", gap: "8px", marginTop: "2px", fontSize: vars.textUi, lineHeight: vars.leadingUi, color: vars.muted,
});
/** The item's name in it: the strong ink, a weight heavier, in place of quotes. */
export const name = style({ fontWeight: "500", color: vars.text });
export const dot = style({
  width: "6px", height: "6px", borderRadius: "50%", flex: "none", background: vars.subtle,
  selectors: { "&[data-tone=granted]": { background: vars.green } },
});
/** What the person types in for a secret theirs to type (VaultApproval.tsx): its fields, 8 apart, the card's width. */
export const typed = style({ display: "grid", gap: "8px", minWidth: "0" });
/** A private key's lines, in the code's letters. */
/** A file to pick: its name and size, then the button that picks it. */
export const typedFile = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0" });
export const typedFileName = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textBody });
export const typedKey = style({ fontFamily: vars.fontMono, fontSize: vars.textMeta, resize: "vertical" });
