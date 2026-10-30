import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";
import { CARD_PAD, LIST_PAD, ROW_CORNER, listCardLook } from "./styles/pages.css.ts";

// A decision's options (Decisions.tsx): under the message that asks it in a chat. One card, a row each, numbered in a
// circle; the recommended one last, told by its number in the accent alone. The phone's page colours (`--m-*`) where
// they are set, the wide screen's otherwise.
const accent = `var(--m-accent, ${vars.accent})`;
const chip = `var(--m-chip, color-mix(in srgb, ${vars.text} 7%, transparent))`;

/** A card of pressable rows (pages.css.ts listCard, docs/ui-panels.md 页面卡片): each option LIST_PAD from its edge. */
export const options = style({
  ...listCardLook, display: "flex", flexDirection: "column", width: "fit-content", minWidth: "min(100%, 460px)", maxWidth: "100%",
  boxSizing: "border-box", marginTop: "8px", padding: LIST_PAD,
  background: `var(--m-chip, color-mix(in srgb, ${vars.text} 5%, transparent))`,
});

/** Its number in its row's corner, as far from both its edges and concentric with it: the row's corner less its half. */
const NUMBER = 20;
const NUMBER_IN = 8;
/**
 * One option: its number, then its label over its detail; a row of the card's, its ground under the pointer, rounded as
 * the card less its padding.
 */
export const choice = style({
  position: "relative", display: "grid", gridTemplateColumns: `${NUMBER}px minmax(0, 1fr)`, columnGap: "12px", width: "100%",
  boxSizing: "border-box", padding: `${NUMBER_IN}px ${CARD_PAD - LIST_PAD}px ${NUMBER_IN}px ${NUMBER_IN}px`, border: "0",
  borderRadius: ROW_CORNER, cornerShape: vars.cornerShape, background: "none", color: vars.text,
  fontFamily: "inherit", textAlign: "left", cursor: "pointer", WebkitTapHighlightColor: "transparent",
  transition: `background-color ${vars.dur}, opacity ${vars.dur}`,
  selectors: {
    "&:hover:not(:disabled)": { background: vars.hover },
    "&:disabled": { cursor: "default" },
    // Another one of them is being sent, or was picked: the rest step back.
    "&:disabled:not([data-busy]):not([data-chosen])": { opacity: ".5" },
  },
});
/**
 * Its number: a circle as tall as the label's line and level with it, the digit drawn (icons Option1…6,
 * scripts/option-digits.py) rather than set, so that it is in the middle at any scale.
 */
export const choiceNumber = style({
  gridRow: "1 / span 2", alignSelf: "start", display: "grid", placeItems: "center", width: "20px", height: "20px",
  borderRadius: "50%", background: `color-mix(in srgb, ${vars.text} 9%, transparent)`,
  color: vars.muted, fontSize: vars.textCaption, fontWeight: "600", lineHeight: "20px", fontVariantNumeric: "tabular-nums",
  // (picked, answered: its ground and ink over --dur, as a control answers)
  transition: `background-color ${vars.dur}, color ${vars.dur}`,
  selectors: { [`${choice}[data-recommended] &, ${choice}[data-chosen] &`]: { background: accent, color: "#fff" } },
});
globalStyle(`${choiceNumber} > svg`, { display: "block" });
export const choiceLabel = style({
  gridColumn: "2", fontSize: vars.textUi, lineHeight: "20px", fontWeight: "500", overflowWrap: "anywhere",
  selectors: { [`${choice}[data-busy] &`]: { paddingRight: "22px" } },
});
/** Being sent: a small ring at the option's right, level with its label. */
export const choiceSpinner = style({ position: "absolute", right: `${CARD_PAD - LIST_PAD}px`, top: `${NUMBER_IN + 4}px` });
export const choiceDetail = style({ gridColumn: "2", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted, overflowWrap: "anywhere" });

export const option = style({
  position: "relative", display: "grid", gap: "0", width: "100%", boxSizing: "border-box", padding: "9px 14px",
  border: "0", borderRadius: vars.rField, cornerShape: vars.cornerShape, background: chip, color: vars.text,
  fontFamily: "inherit", textAlign: "left", cursor: "pointer", WebkitTapHighlightColor: "transparent",
  transition: `opacity ${vars.dur}`,
  selectors: {
    "&:hover:not(:disabled)": litOver,
    "&[data-recommended]": { background: accent, color: "#fff" },
    // A solid ground pointed at: a step towards the page (docs/ui-panels.md 悬停).
    "&[data-recommended]:hover:not(:disabled)": { background: `color-mix(in srgb, ${accent} 85%, ${vars.canvas})` },
    "&:disabled": { cursor: "default" },
    // The other one is under way: this one steps back.
    "&:disabled:not([data-busy])": { opacity: ".5" },
  },
});
export const optionLabel = style({
  fontSize: vars.textUi, lineHeight: "20px", fontWeight: "500", overflowWrap: "anywhere",
  selectors: { [`${option}[data-busy] &`]: { paddingRight: "22px" } },
});
/** Being sent: a small ring at the button's right. */
export const optionSpinner = style({ position: "absolute", right: "14px", top: "12px" });

/** Under an agent's post in its chat: its options, or how it was settled; what settles leaves over it (useSettling). */
export const decision = style({ position: "relative" });

/** Answered (or replaced), in the chat: who did what, quiet, where the options were. */
export const settledLine = style({ margin: "2px 0 0", fontSize: vars.textMeta, lineHeight: "18px", color: vars.subtle });
