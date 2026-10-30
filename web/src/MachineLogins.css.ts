import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";
import { settledLine } from "./Decisions.css.ts";
import { pillInner, surfaceCorner, TEXT_IN, PANEL_PILL } from "@stillfail/ui/styles/align.ts";

// A station's logins (MachineLogins.tsx, docs/remote-login.md): the login card (a chat's and the station page's
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
  display: "grid", justifyItems: "start", gap: "2px", width: "fit-content", minWidth: "min(100%, 360px)", maxWidth: "min(100%, 560px)",
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
/**
 * Its title, with 取消 as its × in the card's top corner (on the card's padding, concentric with its corner): the title
 * takes the row, the × its own pill's width.
 */
export const cardHead = style({ display: "flex", alignItems: "flex-start", gap: "4px", width: "100%", minWidth: 0 });
globalStyle(`${cardHead} > ${cardTitle}`, { flex: "1", minWidth: 0 });
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
globalStyle(`${card} :focus-visible`, { outlineOffset: "-2px" });
/** A pasted-back code's two steps (its page's button, its field): taller than the pills, a finger's row on a phone. */
const STEP = 32;
/** Their corners: the card's less its padding (the field at its foot concentric with it), the button above as round. */
const stepCorner = pillInner(CARD_PAD, PANEL_PILL, vars.cornerScale);
/**
 * The first step, its page: the card's width, solid (as a primary button) while it is the next thing to do, then a
 * plain grey one once pressed (the eye on to the field, 完成 the solid one then).
 */
export const cardStep = style({
  display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", width: "100%", height: STEP, marginTop: "8px",
  padding: "0 12px", boxSizing: "border-box", border: 0, borderRadius: stepCorner, cornerShape: vars.cornerShape,
  background: `color-mix(in srgb, ${vars.text} 7%, transparent)`, color: vars.text, font: "inherit", fontSize: vars.textUi, fontWeight: 500,
  cursor: "pointer",
  selectors: {
    "&:hover": litOver,
    "&[data-next]": { background: vars.primary, color: vars.onPrimary },
    "&[data-next]:hover": { background: vars.primaryHover },
  },
});
/** A step's button and, at its end, a ⋯ of the other ways of doing it (seldom used): side by side, the ⋯ round, as high. */
export const cardStepRow = style({ display: "flex", alignItems: "center", gap: "6px", width: "100%", marginTop: "8px" });
globalStyle(`${cardStepRow} > ${cardStep}:first-child`, { marginTop: 0, flex: "1", minWidth: 0 });
export const cardStepMore = style([cardStep, { flex: "none", width: STEP, padding: 0, marginTop: 0, borderRadius: "999px" }]);
/**
 * The second, what the page gave (a code): a field the card's width at its foot, 完成 in its end once a code is in
 * (concentric with it, solid: the next thing to do then).
 */
export const cardPaste = style({
  display: "flex", alignItems: "center", gap: "4px", width: "100%", minWidth: "min(100%, 344px)", height: STEP, marginTop: "6px",
  padding: "0 4px 0 12px", boxSizing: "border-box", borderRadius: stepCorner, cornerShape: vars.cornerShape, background: vars.canvas,
});
export const cardPasteInput = style({
  flex: "1", minWidth: 0, height: "100%", padding: 0, border: 0, outline: "none", background: "none", color: vars.text, font: "inherit",
  fontSize: vars.textUi,
  // The code in mono; what to paste said in the card's own letters.
  selectors: { "&:not(:placeholder-shown)": { fontFamily: vars.fontMono }, "&::placeholder": { color: vars.muted } },
});
globalStyle(`${cardPaste}:focus-within`, { boxShadow: `0 0 0 2px color-mix(in srgb, ${vars.accent} 40%, transparent)` });
/** 完成 in the field's end: solid; while what was entered is checked, a spinner in place of its word (nothing moves). */
export const cardPasteDone = style({
  position: "relative", flex: "none", height: STEP - 8, padding: "0 12px", border: 0, cornerShape: vars.cornerShape,
  borderRadius: `calc(${stepCorner} - 4px)`, background: vars.primary, color: vars.onPrimary, font: "inherit", fontSize: vars.textMeta,
  fontWeight: 500, cursor: "pointer", selectors: { "&:hover:not([aria-busy])": { background: vars.primaryHover } },
});
export const cardPasteDoneWord = style({ selectors: { [`${cardPasteDone}[aria-busy="true"] &`]: { visibility: "hidden" } } });
export const cardPasteDoneSpin = style({ position: "absolute", inset: 0, display: "grid", placeItems: "center" });
