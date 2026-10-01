import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

// The card of what waits to be decided, over a chat's composer (Asks.tsx). Its colours are its own variables, the wide
// screen's by default; the phone's page gives it its own (mobile/Chat.css.ts).
const glass = (amount: string) => `color-mix(in srgb, ${vars.raised} ${amount}, transparent)`;
const dark = { "--ask-glass": "84%" };

/** Where it sits: its foot 10px over the composer's box, as wide as it. Only the card takes the pointer. */
export const asks = style({
  pointerEvents: "none",
  vars: {
    "--ask-ink": vars.text, "--ask-ground": vars.canvas, "--ask-muted": vars.muted, "--ask-subtle": vars.subtle,
    "--ask-chip": `color-mix(in srgb, ${vars.text} 7%, transparent)`, "--ask-solid": vars.canvas, "--ask-glass": "72%",
  },
  selectors: {
    // Dark: the glass thicker, so it does not go a muddy grey over what is light under it.
    ":root[data-theme=\"dark\"] &": { vars: dark },
  },
  "@media": {
    "(prefers-color-scheme: dark)": { selectors: { ":root:not([data-theme=\"light\"]) &": { vars: dark } } },
  },
});

/** The wide screen's: over the composer's box, which is 760px at most, 32px in from the pane's sides (12px narrow). */
export const wideAsks = style({
  position: "absolute", zIndex: "2", left: "0", right: "var(--avoid-previews, 0px)",
  bottom: "calc(var(--composer-height) - 2px)", padding: "0 32px",
  "@media": { "(max-width: 700px)": { padding: "0 12px", bottom: "calc(var(--composer-height) + 2px)" } },
});

/** The card, what peeks under it, and what a swipe shows under it: all in one place, the card's. */
export const stack = style({ position: "relative", maxWidth: "760px", margin: "0 auto", paddingBottom: "0" });

const ground = {
  background: glass("var(--ask-glass)"), WebkitBackdropFilter: "blur(20px)", backdropFilter: "blur(20px)",
  boxShadow: "0 1px 4px rgb(0 0 0 / .06)",
} as const;

export const card = style({
  ...ground,
  position: "relative", zIndex: "2", boxSizing: "border-box", padding: "12px 14px", borderRadius: "20px",
  color: "var(--ask-ink)", pointerEvents: "auto", touchAction: "pan-y", transformOrigin: "50% 100%",
  WebkitUserSelect: "none", userSelect: "none",
  selectors: {
    // Taken by the finger: solid, so what it would do shows only beside it, not through it.
    "&[data-dragging]": { background: "var(--ask-solid)", boxShadow: "0 4px 16px rgb(0 0 0 / .12)" },
  },
});
/** A copy of the card on its way off (Asks.tsx leave): over where it was, taking nothing. */
export const ghost = style({ position: "absolute", left: "0", right: "0", zIndex: "3", pointerEvents: "none" });

/** The next one's edge, under the card's foot: narrower, a little of it showing. */
export const peek = style({
  ...ground,
  position: "absolute", zIndex: "1", left: "12px", right: "12px", bottom: "-6px", height: "20px", borderRadius: "20px",
  opacity: ".6",
});

/** What a swipe does, under the card: 随便 on ink to the left of a card going right; 待定 on grey to the right of one going left. */
export const under = style({
  position: "absolute", inset: "0", zIndex: "1", display: "none", alignItems: "center", padding: "0 22px",
  borderRadius: "20px", fontSize: "15px", lineHeight: "20px",
  selectors: {
    "&[data-side=\"right\"]": { display: "flex", background: "var(--ask-ink)", color: "var(--ask-ground)" },
    "&[data-side=\"left\"]": { display: "flex", justifyContent: "flex-end", background: "var(--ask-chip)", color: "var(--ask-muted)" },
  },
});
export const underRight = style({
  display: "none", alignItems: "baseline", gap: "8px",
  selectors: { [`${under}[data-side="right"] &`]: { display: "flex" } },
});
export const underLeft = style({
  display: "none", alignItems: "baseline", gap: "8px",
  selectors: { [`${under}[data-side="left"] &`]: { display: "flex" } },
});
globalStyle(`${under} b`, { fontWeight: 600 });
globalStyle(`${under} small`, { fontSize: "12px", opacity: ".7" });

export const top = style({ display: "flex", alignItems: "center", gap: "8px", height: "16px", fontSize: "12px", lineHeight: "16px", color: "var(--ask-muted)" });
export const lead = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** 1 / N ›: the next one, here. */
export const count = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: "2px", height: "24px", margin: "-4px -6px -4px 0",
  padding: "0 6px", border: "0", borderRadius: "12px", background: "none", color: "var(--ask-muted)", cursor: "pointer",
  font: "inherit", fontSize: "12px", fontVariantNumeric: "tabular-nums",
  selectors: { "&:hover": { color: "var(--ask-ink)" } },
});
/** What is to be decided: the card's main line. */
export const title = style({ margin: "6px 0 0", fontSize: "15px", lineHeight: "21px", fontWeight: "500", overflowWrap: "anywhere" });
export const answers = style({ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "6px", marginTop: "10px" });
/** An answer: a pill on the card's grey; yes in ink. 待定 (wide screen) is plain words at the row's end. */
export const answer = style({
  height: "30px", padding: "0 12px", border: "0", borderRadius: "15px", background: "var(--ask-chip)", color: "var(--ask-ink)",
  fontFamily: "inherit", fontSize: "14px", lineHeight: "30px", whiteSpace: "nowrap", cursor: "pointer",
  transition: `filter ${vars.dur}`,
  selectors: {
    "&:hover": { filter: "brightness(.96)" },
    "&[data-kind=\"yes\"]": { background: "var(--ask-ink)", color: "var(--ask-ground)" },
    "&[data-kind=\"yes\"]:hover": { filter: "none", opacity: ".88" },
  },
});
/** The card's own field: anything else, said of the piece of work. */
export const reply = style({ position: "relative", display: "flex", alignItems: "center", marginTop: "8px" });
export const replyInput = style({
  flex: "1", minWidth: "0", height: "34px", padding: "0 38px 0 12px", border: "0", borderRadius: "17px", outline: "none",
  background: "var(--ask-chip)", color: "var(--ask-ink)", fontFamily: "inherit", fontSize: "14px",
  selectors: { "&::placeholder": { color: "var(--ask-subtle)" } },
});
export const replySend = style({
  position: "absolute", right: "4px", top: "4px", display: "grid", placeItems: "center", width: "26px", height: "26px", padding: "0",
  border: "0", borderRadius: "13px", background: "var(--ask-ink)", color: "var(--ask-ground)", cursor: "pointer",
});
/** Where 待定 and 随便 would be, on a touch screen: which way to swipe for them. */
export const hint = style({ marginLeft: "auto", fontSize: "12px", lineHeight: "16px", color: "var(--ask-subtle)", whiteSpace: "nowrap" });
