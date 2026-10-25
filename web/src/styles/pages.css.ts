import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { iconBtn } from "@stillfail/ui/styles/page.css.ts";
import { btnDangerSolid, btnPrimary } from "@stillfail/ui/styles/controls.css.ts";

export const page = style({
  flex: "1", minHeight: "0", overflowY: "auto", padding: "40px 40px 80px",
  "@media": {
    "(max-width: 700px)": {
      padding: "24px 18px 60px",
    },
  },
});
export const pageNarrow = style({});
export const pageHead = style({
  display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: "16px", marginBottom: "28px",
});
// Its buttons may reach into the row that drags the desktop window (styles/shell.css.ts main): they are still pressed.
// Only the page's head: anything further down, scrolled up out of sight, would still cut holes in that row.
globalStyle(`[data-desktop] ${pageHead} :is(a, button, input, select, textarea, [role="button"], [tabindex])`, { WebkitAppRegion: "no-drag" });
export const identity = style({ display: "flex", alignItems: "center", gap: "16px", marginBottom: "28px" });
export const identityText = style({ flex: "1", minWidth: "0" });
export const identityName = style({
  display: "flex", alignItems: "center", gap: "4px", margin: "0", fontSize: vars.textHeading, lineHeight: "34px", fontWeight: "600",
});
// Its name's buttons (an edit's pencil) stand back until the name is pointed at.
globalStyle(`${identityName} ${iconBtn}`, { opacity: ".55" });
globalStyle(`${identityName}:hover ${iconBtn}`, { opacity: "1" });
export const identitySub = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "6px 14px", margin: "6px 0 0", color: vars.muted,
  fontSize: vars.textUi, lineHeight: "20px",
});
/**
 * Page cards (docs/ui-panels.md 页面卡片), two kinds, each its corner from what stands in it:
 * - a card of words (a title, what it says, maybe a button: `card`): its words and what has a ground of its own (a
 *   button: its ground's edge, not its words, is what the eye lines up) on one line, CARD_PAD in from every side. With
 *   a button at its foot (`cardFoot`), the button is in its corner, concentric with it: the card's corner is CARD_PAD
 *   and the button's half height together; with nothing drawn in its corners, the settings' corner (CARD_CORNER);
 * - a card of rows each to be pressed (a decision's options: `listCard`): a row's ground shows only under the pointer,
 *   reaching LIST_PAD from the card's edge, rounded as the card less that; its words where a card of words' stand.
 */
export const CARD_PAD = 20;
/** A button's height (controls.css.ts btn), whose half the corners here take. */
export const CARD_BUTTON = 36;
export const LIST_PAD = 8;
/** The settings cards' corner, for one with nothing drawn in its corners. */
const CARD_CORNER = `calc(22px * ${vars.cornerScale})`;
/** A pressable row's corner in a list card, and a button's: one curve. */
export const ROW_CORNER = `calc(${CARD_BUTTON / 2}px * ${vars.cornerScale})`;
export const cardGround = `color-mix(in oklab, ${vars.text} 4%, ${vars.canvas})`;
/** A card of words' ground and corner, for the other cards of the settings pages (a station's, the first station's) too. */
export const cardLook = { borderRadius: CARD_CORNER, cornerShape: vars.cornerShape, background: cardGround } as const;
/** Its buttons, at its foot: their grounds on the card's line of words, the first in its corner. */
export const cardFoot = style({ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" });
/** A card of words' corner with a button in it: the card's padding and the button's half (in round terms, scaled as
 *  the app's corners are: a round button in a squarer corner). */
export const BUTTON_CARD_CORNER = `calc(${CARD_PAD + CARD_BUTTON / 2}px * ${vars.cornerScale})`;
export const card = style({
  ...cardLook, padding: CARD_PAD,
  display: "grid", gap: "14px",
  selectors: {
    "& + &": { marginTop: "10px" },
    // A solid button in its corner: in its buttons' row at its foot, or ending its last row. (Its other buttons are
    // words, a ground only under the pointer, reaching past them as a row's does: pageControls.css.ts.)
    [`&:has(> ${cardFoot}:last-child :is(${btnPrimary}, ${btnDangerSolid}), > :last-child > :is(${btnPrimary}, ${btnDangerSolid}):last-child)`]: { borderRadius: BUTTON_CARD_CORNER },
  },
});
/** A card of pressable rows: the rows LIST_PAD in, the card's corner theirs and that together (both squarer). */
export const listCardLook = { borderRadius: `calc(${ROW_CORNER} + ${LIST_PAD}px)`, cornerShape: vars.cornerShape, background: cardGround } as const;
export const listCard = style({ ...listCardLook, padding: LIST_PAD, display: "grid" });
/** A row of it: its ground under the pointer, its words where a card of words' stand (CARD_PAD from the card's edge). */
export const listCardRow = style({
  padding: `10px ${CARD_PAD - LIST_PAD}px`, borderRadius: ROW_CORNER, cornerShape: vars.cornerShape,
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover:not(:disabled)": { background: vars.hover } },
});
export const cardRow = style({ display: "flex", alignItems: "center", gap: "12px" });
export const cardRowText = style({ flex: "1", display: "grid", gap: "2px", minWidth: "0", fontSize: vars.textUi });
export const cardActions = style({ display: "flex", justifyContent: "flex-end", gap: "8px" });
export const list = style({});
export const listRow = style({
  display: "flex", alignItems: "center", gap: "12px", minHeight: "52px", padding: "10px 12px",
  borderRadius: vars.rField, cornerShape: vars.cornerShape, fontSize: vars.textUi,
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
  },
});
export const listRowText = style({ flex: "1", display: "grid", gap: "2px", minWidth: "0" });
export const listRowTitle = style({
  flex: "1", minWidth: "0", fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: {
    [`${listRowText} &`]: { flex: "none" },
  },
});
export const mark = style({
  display: "inline-grid", placeItems: "center", flex: "none", borderRadius: `calc(10px * ${vars.cornerScale})`,
  background: vars.paper, color: vars.text, cornerShape: vars.cornerShape,
});
globalStyle(`${pageHead} h1`, { margin: "0", fontSize: vars.textHeading, lineHeight: "34px", fontWeight: "600" });
