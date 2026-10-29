import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { popKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { bleedX, bleedY, surfaceCorner } from "@stillfail/ui/styles/align.ts";

/**
 * A note's number, as a web page's marks show theirs (../annotate/Marks.css.ts): a pin, its point at the bottom right
 * (it grows to the left with more digits).
 */
const pin = style({
  minWidth: "16px", height: "16px", padding: "0 4px", boxSizing: "border-box", display: "grid", placeItems: "center", flex: "none",
  border: "0", background: "var(--m-accent)", color: "#fff", fontSize: vars.textCaption,
  borderRadius: "8px 8px 2px 8px", // own corner: a pin's, round but for its point
  fontWeight: "600", lineHeight: "16px",
  // Proportional figures: a tabular 1 sits left of the middle.
  fontVariantNumeric: "proportional-nums",
});

/**
 * Saying something about a mark, floating at the foot of what it is on, frosted as the chat's composer is
 * (ChatHost.css.ts): its corner its round buttons' (36) and the 8 they stand in from its edge together.
 */
export const mNoteBox = style({
  boxShadow: "0 1px 3px rgb(0 0 0 / .06)", display: "flex", flexDirection: "column", gap: "6px", padding: "10px 8px 8px",
  borderRadius: surfaceCorner(8, 18), animation: `${popKeyframes} 140ms var(--ease-out)`,
});
export const mNoteQuote = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", padding: "0 8px", color: "var(--m-muted)", fontSize: vars.textMeta,
  lineHeight: "18px",
});
globalStyle(`${mNoteQuote} q`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", quotes: "none" });
export const mNotePin = pin;
export const mNoteBar = style({ display: "flex", alignItems: "flex-end", gap: "2px" });
export const mNoteInput = style({
  flex: "1", minWidth: "0", minHeight: "36px", maxHeight: "30vh", boxSizing: "border-box", margin: "0", padding: "7px 8px",
  border: "0", background: "none", resize: "none", color: "var(--m-ink)", font: "inherit", fontSize: vars.textInput, lineHeight: "21px",
  textWrap: "wrap", selectors: { "&:focus": { outline: "none" }, "&::placeholder": { color: "var(--m-subtle)" } },
});
export const mNoteBtn = style({
  flex: "none", width: "36px", height: "36px", display: "grid", placeItems: "center", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-muted) !important", cursor: "pointer",
});
/** Done: round, as the chat's send button is. */
export const mNoteDone = style({
  flex: "none", width: "36px", height: "36px", display: "grid", placeItems: "center", padding: "0", border: "0",
  borderRadius: "50%", background: "var(--m-ink)", color: "var(--m-bg) !important", cursor: "pointer",
});

/** The notes as they are made, gathered at the foot in a row that scrolls sideways: a tap goes back to one. */
export const mTray = style({
  // Room round the cards inside the row (it clips what is outside it, as a row that scrolls does), taken back outside.
  pointerEvents: "auto", display: "flex", gap: "8px", listStyle: "none", ...bleedX(16), ...bleedY(12),
  overflowX: "auto", scrollbarWidth: "none", overscrollBehaviorX: "contain",
});
export const mCard = style({
  display: "flex", flexDirection: "column", gap: "3px", width: "160px", flex: "none", padding: "9px 12px", border: "0",
  borderRadius: `calc(16px * ${vars.cornerScale})`, // own corner: a note's card, as the notes have always had it
  cornerShape: vars.cornerShape,
  color: "var(--m-ink)", textAlign: "left", cursor: "pointer",
  selectors: { "&[data-open]": { boxShadow: "inset 0 0 0 1.5px var(--m-accent), 0 1px 3px rgb(0 0 0 / .04)" } },
});
export const mCardHead = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", fontSize: vars.textUi, lineHeight: "20px", whiteSpace: "nowrap",
  overflow: "hidden", textOverflow: "ellipsis",
});
export const mCardSaid = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${mCardHead} [data-empty]`, { color: "var(--m-muted)" });
export const mCardPin = pin;
export const mCardQuote = style({
  display: "block", color: "var(--m-muted)", fontSize: vars.textCaption, lineHeight: "17px", whiteSpace: "nowrap", overflow: "hidden",
  textOverflow: "ellipsis", quotes: "none",
});
