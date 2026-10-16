import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { popover } from "@stillfail/ui/styles/controls.css.ts";
import { IN, PANEL_PAD, TEXT_IN, inner, innerShape, pillInner } from "@stillfail/ui/styles/align.ts";
import { mChat } from "./styles/chat.css.ts";

/** The passage picked in a message of the chat's list (pick.tsx): on the accent's ground, its words as they are. */
globalStyle("::highlight(chat-picked)", { backgroundColor: "color-mix(in srgb, var(--m-accent) 26%, transparent)", color: "inherit" });

/**
 * An end of the picked passage, over the list where its words are: a line down its side with a knob, and room round it
 * for a finger. Placed by pick.tsx as the list scrolls.
 */
export const mHandle = style({
  position: "absolute", top: "0", left: "0", width: "2px", translate: "-50% 0", background: "var(--m-accent)", touchAction: "none", zIndex: "2",
  selectors: {
    // The finger's room: 36px round the knob.
    "&::before": { content: "", position: "absolute", left: "-17px", width: "36px", height: "36px" },
    "&::after": { content: "", position: "absolute", left: "-5px", width: "12px", height: "12px", borderRadius: "50%", background: "var(--m-accent)" },
    "&[data-end=start]::before": { top: "-28px" },
    "&[data-end=start]::after": { top: "-11px" },
    "&[data-end=end]::before": { bottom: "-28px" },
    "&[data-end=end]::after": { bottom: "-11px" },
  },
});

/** The height of the pick bar's buttons: the bar's corner is theirs and its padding together (concentric). */
const BUTTON = 32;

/**
 * What to do with the picked passage, over it (under it near the list's top): a small panel (docs/ui-panels.md) of
 * pills a finger can take, its corner from theirs.
 */
export const mPickBar = style([popover, {
  vars: { [IN]: pillInner(PANEL_PAD, BUTTON, vars.cornerScale) },
  position: "absolute", top: "0", left: "0", zIndex: "3", display: "flex", alignItems: "center", whiteSpace: "nowrap",
}]);
// The phone's rule for buttons' type (styles/root.css.ts) is stronger than a class of their own: said again here, as strong.
globalStyle(`${mChat} ${mPickBar} button`, {
  display: "flex", alignItems: "center", gap: "5px", height: `${BUTTON}px`, padding: `0 ${TEXT_IN}px`, border: "0",
  borderRadius: inner, cornerShape: innerShape, background: "none", color: "var(--m-ink)", fontSize: vars.textUi, cursor: "pointer",
});
globalStyle(`${mChat} ${mPickBar} button:active`, { background: "color-mix(in srgb, var(--m-ink) 8%, transparent)" });
