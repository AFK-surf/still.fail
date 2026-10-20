import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { settledLine } from "./Decisions.css.ts";
import { pillInner, surfaceCorner, TEXT_IN, PANEL_PILL } from "@stillfail/ui/styles/align.ts";
import { input } from "@stillfail/ui/styles/controls.css.ts";

// A station's logins (MachineLogins.tsx, docs/remote-login.md): the login card (a chat's, 奏's, and the station page's
// for one under way) and the station page's rows of those ended. Grey but for what is off, and the code.

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;
/** The ground a link pointed to (`?login=`) is shown on, a moment: the accent, faint. */
const markedGround = `color-mix(in srgb, ${vars.accent} 12%, transparent)`;

// ── the station page ──

/** The cards of those under way, one under another, above the rows of those ended. */
export const cards = style({ display: "grid", justifyItems: "start", gap: "8px", marginBottom: "8px" });
/** A login that ended: what it says is all there is (not pressed). */
export const pastRow = style({ selectors: { "&:hover": { background: "none" }, "&[data-marked]": { background: markedGround } } });
export const mark = style({ width: "36px", height: "36px", color: vars.muted });
export const name = style({ fontWeight: "500", color: vars.text, ...ellipsis });
/** The chat whose agent started it. */
export const chatLink = style({ color: "inherit", textDecoration: "underline", textUnderlineOffset: "2px" });
export const state = style({ color: vars.muted, ...ellipsis });
export const stateFailed = style({ color: vars.red, ...ellipsis });
/** The phone's station page: the cards of those under way, in from its edges as its cards are. */
export const phoneCards = style({ display: "grid", gap: "8px", padding: "0 16px" });
/** The phone's station page: a login's command over who, when and how it ended. */
export const phoneRowText = style({ flex: "1", minWidth: 0, display: "grid", gap: "2px" });
export const phoneState = style({ fontSize: vars.textMeta, color: "var(--m-muted)", ...ellipsis });
/** The phone's station page: under the list, what it is. */
export const phoneLead = style({ margin: "8px 24px 0", fontSize: vars.textCaption, color: "var(--m-muted)" });

// ── the card ──

/** Where the card's buttons stand from its edges: they sit at its corner, its corner theirs and this together. */
const CARD_PAD = 8;
/**
 * A login, as a card: under the agent's message as a decision's options are, the same grey ground and no line; its title,
 * what the person does now or how it stands, its buttons (small pills) along its foot. It opens nothing.
 */
export const card = style({
  padding: CARD_PAD, borderRadius: surfaceCorner(CARD_PAD, pillInner(CARD_PAD, PANEL_PILL, vars.cornerScale)), cornerShape: vars.cornerShape,
  display: "grid", justifyItems: "start", gap: "2px", width: "fit-content", minWidth: "min(100%, 360px)", maxWidth: "100%",
  boxSizing: "border-box", marginTop: "8px", background: `var(--m-chip, color-mix(in srgb, ${vars.text} 5%, transparent))`,
  color: vars.text, textAlign: "left", transition: `background-color ${vars.dur}`,
  selectors: { "&[data-marked]": { background: markedGround } },
});
/** Its words in by a row's padding (as a small panel's), and as far from its top and foot when first or last. */
const cardText = {
  paddingInline: TEXT_IN, maxWidth: "100%", boxSizing: "border-box", overflowWrap: "anywhere",
  selectors: { "&:first-child": { paddingTop: TEXT_IN }, "&:last-child": { paddingBottom: TEXT_IN } },
} as const;
export const cardTitle = style({ ...cardText, fontSize: vars.textUi, lineHeight: "20px", fontWeight: "500" });
export const cardStatus = style({ ...cardText, display: "inline-flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted });
/** What kept this device from taking the browser's callback (its port taken): the one line in red. */
export const cardStatusFailed = style([cardStatus, { color: vars.red }]);
/** Ended: a line where the card was, as an answered decision's in its chat (Decisions.css.ts settledLine); failed, red. */
export const ended = style([settledLine, { overflowWrap: "anywhere" }]);
export const endedFailed = style([ended, { color: vars.red }]);
/**
 * A device code, large enough to read and copy by eye (it is copied as its page opens, too), and a button: pressed, it is
 * copied. No ground, at rest or under the pointer (none to round): the pointer's hand says it can be pressed, a toast that
 * it was copied.
 */
export const cardCode = style({
  ...cardText, display: "block", width: "fit-content", paddingBlock: "4px", border: "0", background: "none", color: "inherit",
  textAlign: "left", cursor: "pointer", WebkitTapHighlightColor: "transparent",
});
/** Its words, set on them rather than the button: a phone's root gives every button `font: inherit`. */
export const cardCodeText = style({
  fontFamily: vars.fontMono, fontSize: vars.textHeading, fontWeight: "600", letterSpacing: "0.08em", lineHeight: "1.3",
});
/**
 * One row of buttons at its foot: what is to be done first, then 取消 (they fit a phone's width side by side). The pills'
 * grounds on the card's padding, concentric with its corner; their words in by 10 more, in line with the title's.
 */
export const cardActions = style({ display: "flex", flexWrap: "nowrap", alignItems: "center", gap: "4px", marginTop: "6px" });
globalStyle(`${card} :focus-visible`, { outlineOffset: "-2px" });
/**
 * What the page gave (a code), pasted back: a field as wide as the card allows, its 完成 beside it, under the card's
 * buttons (the page is opened first); in from the card's edge as the pills are.
 */
export const cardPaste = style({ display: "flex", alignItems: "center", gap: "4px", width: "100%", minWidth: "min(100%, 344px)", marginTop: "6px" });
export const cardPasteInput = style([input, {
  // As tall as the pills: the row's foot as far from the card's as its side.
  flex: "1", minWidth: 0, minHeight: PANEL_PILL, height: PANEL_PILL, paddingBlock: "0", boxSizing: "border-box", fontSize: vars.textMeta,
  // The code in mono; what to paste said in the card's own letters.
  selectors: { "&:not(:placeholder-shown)": { fontFamily: vars.fontMono } },
}]);
