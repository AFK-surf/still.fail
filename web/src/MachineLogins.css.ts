import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { pillInner, surfaceCorner, TEXT_IN, PANEL_PILL } from "@stillfail/ui/styles/align.ts";

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
export const cardDone = style([cardStatus, { color: vars.text, fontWeight: "500" }]);
export const cardFailed = style([cardStatus, { color: vars.red, fontWeight: "500" }]);
/** A device code, large enough to read and copy by eye (it is copied as its page opens, too). */
export const cardCode = style({
  ...cardText, paddingBlock: "4px", fontFamily: vars.fontMono, fontSize: vars.textHeading, fontWeight: "600", letterSpacing: "0.08em",
  lineHeight: "1.3", userSelect: "all",
});
export const cardActions = style({ display: "flex", flexWrap: "wrap", gap: "4px", marginTop: "6px" });
/** 取消, small, under what is to be done. */
export const cardFoot = style({ display: "flex", marginTop: "2px" });
/** A button's words, sized here: the phone's buttons take their font from what they are in. */
export const cardButtonText = style({ fontSize: vars.textMeta, fontWeight: "500", lineHeight: `${PANEL_PILL}px` });
globalStyle(`${card} :focus-visible`, { outlineOffset: "-2px" });
