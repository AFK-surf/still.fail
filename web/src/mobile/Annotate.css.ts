import { globalStyle, style } from "@vanilla-extract/css";
import { popKeyframes } from "../styles/keyframes.css.ts";

export const mAnnotate = style({});
export const mAnnotateScroll = style({
  paddingBottom: "calc(var(--m-foot) + 72px) !important",
  selectors: { "&[data-tray]": { paddingBottom: "calc(var(--m-foot) + 148px) !important" } },
});

/** The message's words, on the page's ground: the places over them (handles, pins, bubbles) are this sheet's. */
export const mSheet = style({ position: "relative", padding: "12px 20px 24px 32px" });

/** Picked by the page, not the browser: no selection of its own, no menu of its own. */
export const mWords = style({
  userSelect: "none", WebkitUserSelect: "none", WebkitTouchCallout: "none", fontSize: "16px", lineHeight: "1.6",
  cursor: "text",
});
globalStyle(`${mWords} a`, { pointerEvents: "none" });

globalStyle("::highlight(annotate-picked)", { backgroundColor: "color-mix(in srgb, var(--m-accent) 26%, transparent)", color: "inherit" });
globalStyle("::highlight(annotate-note)", {
  textDecoration: "underline 1.5px color-mix(in srgb, var(--m-accent) 70%, transparent)",
  textUnderlineOffset: "3px", color: "inherit",
});
globalStyle("::highlight(annotate-open)", {
  textDecoration: "underline 2px var(--m-accent)",
  textUnderlineOffset: "3px", color: "inherit",
});

/** An end of the picked passage: a line down its side with a knob, and room round it for a finger. */
export const mHandle = style({
  position: "absolute", width: "2px", marginLeft: "-1px", background: "var(--m-accent)", touchAction: "none", zIndex: "2",
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

/** What to do with the picked passage, over it. */
export const mPickBar = style({
  position: "absolute", zIndex: "3", transform: "translateX(-50%)", display: "flex", alignItems: "center", height: "40px",
  padding: "0 4px", borderRadius: "20px", whiteSpace: "nowrap", boxShadow: "0 1px 3px rgb(0 0 0 / .06), 0 6px 20px rgb(0 0 0 / .12)",
  animation: `${popKeyframes} 140ms var(--m-ease)`,
});
globalStyle(`${mAnnotate} ${mPickBar} button`, {
  display: "flex", alignItems: "center", gap: "5px", height: "32px", padding: "0 12px", border: "0", borderRadius: "16px",
  background: "none", color: "var(--m-ink)", font: "inherit", fontSize: "14px", cursor: "pointer",
});
globalStyle(`${mPickBar} button:active`, { background: "color-mix(in srgb, var(--m-ink) 8%, transparent)" });

/**
 * A note's number, as a web page's marks show theirs (../annotate/Marks.css.ts): a pin, in the margin, its point at the
 * start of its passage's first line (it grows to the left with more digits).
 */
export const mPin = style({
  position: "absolute", zIndex: "1", right: "calc(100% - 30px)", minWidth: "20px", height: "20px", padding: "0 4px",
  boxSizing: "border-box", display: "grid", placeItems: "center", border: "2px solid #fff", borderRadius: "10px 10px 2px 10px",
  background: "var(--m-accent)", color: "#fff", fontSize: "11px", fontWeight: "650", lineHeight: "16px",
  // Proportional figures: a tabular 1 sits left of the middle.
  fontVariantNumeric: "proportional-nums", boxShadow: "0 1px 4px rgb(0 0 0 / .2)", cursor: "pointer",
  transformOrigin: "100% 100%", animation: `${popKeyframes} 160ms var(--m-ease)`, transition: "transform 160ms var(--m-ease)",
  selectors: { "&[data-open]": { transform: "scale(1.12)" } },
});

/** Saying something about a passage: floating under it, frosted as the chat's composer is (ChatHost.css.ts). */
/** Its look, wherever it is (an image's marks put it at their foot: ../annotate/ImageMarks.tsx). */
export const mNoteBox = style({
  boxShadow: "0 1px 3px rgb(0 0 0 / .06)", display: "flex", flexDirection: "column", gap: "6px", padding: "10px 8px 8px", borderRadius: "26px",
  animation: `${popKeyframes} 140ms var(--m-ease)`,
});
export const mNote = style([mNoteBox, {
  position: "absolute", zIndex: "3", left: "12px", right: "12px", scrollMarginBottom: "calc(var(--m-foot) + 160px)",
}]);
export const mNoteQuote = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", padding: "0 8px", color: "var(--m-muted)", fontSize: "13px",
  lineHeight: "18px",
});
globalStyle(`${mNoteQuote} q`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", quotes: "none" });
export const mNotePin = style([mPin, { minWidth: "16px", height: "16px", padding: "0 4px", borderRadius: "8px 8px 2px 8px", fontSize: "10px", lineHeight: "16px", position: "static", flex: "none", boxShadow: "none", border: "0", animation: "none" }]);
export const mNoteBar = style({ display: "flex", alignItems: "flex-end", gap: "2px" });
export const mNoteInput = style({
  flex: "1", minWidth: "0", minHeight: "36px", maxHeight: "30vh", boxSizing: "border-box", margin: "0", padding: "7px 8px",
  border: "0", background: "none", resize: "none", color: "var(--m-ink)", font: "inherit", fontSize: "16px", lineHeight: "21px",
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

/** The notes as they are made, gathered over the foot's buttons in a row that scrolls sideways: a tap goes back to one. */
export const mTray = style({
  // Room round the cards inside the row (it clips what is outside it, as a row that scrolls does), taken back outside.
  pointerEvents: "auto", display: "flex", gap: "8px", listStyle: "none", margin: "-12px -16px -12px", padding: "12px 16px",
  overflowX: "auto", scrollbarWidth: "none", overscrollBehaviorX: "contain",
});
export const mCard = style({
  display: "flex", flexDirection: "column", gap: "3px", width: "160px", flex: "none", padding: "9px 12px", border: "0", borderRadius: "16px",
  color: "var(--m-ink)", textAlign: "left", cursor: "pointer",
  selectors: { "&[data-open]": { boxShadow: "inset 0 0 0 1.5px var(--m-accent), 0 1px 3px rgb(0 0 0 / .04)" } },
});
export const mCardHead = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", fontSize: "14px", lineHeight: "20px", whiteSpace: "nowrap",
  overflow: "hidden", textOverflow: "ellipsis",
});
export const mCardSaid = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${mCardHead} [data-empty]`, { color: "var(--m-muted)" });
export const mCardPin = style([mPin, { minWidth: "16px", height: "16px", padding: "0 4px", borderRadius: "8px 8px 2px 8px", fontSize: "10px", lineHeight: "16px", position: "static", flex: "none", boxShadow: "none", border: "0", animation: "none" }]);
export const mCardQuote = style({
  display: "block", color: "var(--m-muted)", fontSize: "12px", lineHeight: "17px", whiteSpace: "nowrap", overflow: "hidden",
  textOverflow: "ellipsis", quotes: "none",
});

/** Copying all of it, and putting the notes (or the whole message, as a quote) into the chat. */
export const mFoot = style({
  position: "absolute", left: "0", right: "0", bottom: "0", zIndex: "4", display: "flex", flexDirection: "column", gap: "10px",
  padding: "10px 16px calc(var(--m-foot) + 10px)", pointerEvents: "none",
});
export const mFootRow = style({ display: "flex", gap: "10px" });
const footBtn = {
  pointerEvents: "auto", display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", height: "44px",
  padding: "0 18px", borderRadius: "22px", font: "inherit", fontSize: "15px", cursor: "pointer",
} as const;
export const mFootBtn = style({ ...footBtn, color: "var(--m-ink)", boxShadow: "0 1px 3px rgb(0 0 0 / .06)" });
export const mFootSend = style({ ...footBtn, flex: "1", color: "var(--m-accent) !important", fontWeight: "600", boxShadow: "0 1px 3px rgb(0 0 0 / .06)" });

// The phone's rule for buttons' type (root.css.ts) is stronger than a class of their own: said again here, as strong.
globalStyle(`${mAnnotate} button${mPin}`, { color: "#fff", fontSize: "11px", fontWeight: "650", lineHeight: "16px" });
globalStyle(`${mAnnotate} button${mFootBtn}, ${mAnnotate} button${mFootSend}`, { fontSize: "15px" });
globalStyle(`${mAnnotate} button${mCard}`, { fontSize: "14px" });
