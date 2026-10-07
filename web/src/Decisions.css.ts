import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { composerWrap } from "./styles/cloud.css.ts";
import { vars } from "./styles/tokens.css.ts";
import { spinner } from "./styles/waiting.css.ts";
import { glass } from "./styles/glass.ts";
import { m } from "./mobile/styles/root.css.ts";

// A decision's options (Decisions.tsx): under the message that asks it in a chat (or in its composer, when the chat ends
// on it), and at the foot of the decisions page. One per line, as wide as the message's column; the recommended one
// last, in ink on the wide screen (the accent is kept for what waits: 奏, the unread line), in the accent on the phone.
// The phone's page colours (`--m-*`) where they are set, the wide screen's otherwise.
const ground = `var(--m-bg, ${vars.canvas})`;
const accent = `var(--m-accent, ${vars.accent})`;
const chip = `var(--m-chip, color-mix(in srgb, ${vars.text} 7%, transparent))`;

export const options = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "6px", marginTop: "6px" });

export const archiveOptions = style([options, { gridTemplateColumns: "repeat(2, minmax(0, 1fr))" }]);

export const option = style({
  position: "relative", display: "grid", gap: "0", width: "100%", boxSizing: "border-box", padding: "9px 14px",
  border: "0", borderRadius: vars.rField, cornerShape: vars.cornerShape, background: chip, color: vars.text,
  fontFamily: "inherit", textAlign: "left", cursor: "pointer", WebkitTapHighlightColor: "transparent",
  transition: `filter ${vars.dur}, opacity ${vars.dur}`,
  selectors: {
    "&:hover:not(:disabled)": { filter: "brightness(.96)" },
    "&[data-recommended]": { background: vars.primary, color: vars.onPrimary },
    "&[data-recommended]:hover:not(:disabled)": { filter: "none", opacity: ".88" },
    "&:disabled": { cursor: "default" },
    // Another one of them is being sent: the rest step back.
    "&:disabled:not([data-busy])": { opacity: ".5" },
  },
});
globalStyle(`${m} ${option}[data-recommended]`, { background: accent, color: "#fff" });
export const optionLabel = style({
  fontSize: vars.textSm, lineHeight: "20px", fontWeight: "500", overflowWrap: "anywhere",
  selectors: { [`${option}[data-busy] &`]: { paddingRight: "22px" } },
});
export const optionDetail = style({
  fontSize: vars.textXs, lineHeight: "18px", color: vars.muted, overflowWrap: "anywhere",
  selectors: { [`${option}[data-recommended] &`]: { color: "color-mix(in srgb, currentColor 72%, transparent)" } },
});
/** Being sent: a small ring at the button's right. */
export const optionSpinner = style({ position: "absolute", right: "14px", top: "12px" });
globalStyle(`${optionSpinner}${spinner}`, { width: "12px", height: "12px", borderWidth: "1.5px" });

/** The number that picks an option in a composer (DockedDecision), at the button's right. */
export const optionKey = style({
  position: "absolute", right: "10px", top: "50%", transform: "translateY(-50%)", minWidth: "18px", height: "18px",
  padding: "0 4px", boxSizing: "border-box", borderRadius: "5px", boxShadow: "inset 0 0 0 1px currentColor",
  fontFamily: "inherit", fontSize: "11px", lineHeight: "18px", textAlign: "center", opacity: ".45",
});
globalStyle(`${option}:has(${optionKey})`, { paddingRight: "40px" });

/**
 * A decision the chat ends on, at the top of its composer (DockedDecision): who decides, by 奏's mark, then the
 * options, a little in from the box's round corners.
 */
export const docked = style({ display: "grid", gap: "4px", padding: "2px 2px 4px", cursor: "default" });
export const dockedHead = style({
  display: "flex", alignItems: "center", gap: "8px", margin: "0", padding: "0 4px", fontSize: vars.textXs,
  lineHeight: "20px", color: vars.muted,
});
export const dockedTag = style({
  padding: "0 6px", borderRadius: "6px", background: vars.accentBg, color: vars.accentText, fontWeight: "600",
});
globalStyle(`${docked} ${options}`, { marginTop: "2px" });
globalStyle(`${docked} ${option}:not([data-recommended])`, { background: `color-mix(in srgb, ${vars.text} 5%, transparent)` });

/** Under an agent's post in its chat: its options, or how it was settled; what settles leaves over it (useSettling). */
export const decision = style({ position: "relative" });

/** Answered (or replaced), in the chat: who did what, quiet, where the options were. */
export const settledLine = style({ margin: "2px 0 0", fontSize: vars.textXs, lineHeight: "18px", color: vars.subtle });

// ── the decisions page ────────────────────────────────────────────────

/** The page's body under its bar: what a swipe shows under the decision, and the decision over it. */
export const deck = style({ position: "relative", flex: "1", minHeight: "0", overflow: "hidden" });

/** What letting go would do, under the decision as it is swiped aside: 不再提醒 to the left, 待定 to the right. */
export const under = style({
  position: "absolute", inset: "0", display: "flex", alignItems: "center", justifyContent: "space-between",
  padding: "0 28px", color: vars.muted, fontSize: vars.textBody, fontWeight: "600", pointerEvents: "none",
});
export const underSide = style({
  opacity: "0",
  selectors: {
    [`${under}[data-side="right"] &[data-side="right"], ${under}[data-side="left"] &[data-side="left"]`]: { opacity: "1" },
  },
});

/** One decision: its chat's title, messages and options scrolling, the composer floating at the foot. Covers what is under it. */
export const card = style({
  position: "absolute", inset: "0", zIndex: "1", display: "flex", flexDirection: "column", background: ground,
  touchAction: "pan-y",
  selectors: { "&[data-dragging]": { WebkitUserSelect: "none", userSelect: "none" } },
});
/** A copy of it on its way off (Decisions.tsx leave), over the next one, taking nothing. */
export const ghost = style({ zIndex: "2", pointerEvents: "none" });

export const scroll = style({
  flex: "1", minHeight: "0", overflowY: "auto", overscrollBehavior: "contain", display: "flex", flexDirection: "column",
  // Its own scrolling is up and down only; across is the swipe's (touch-action stops at the nearest scroller).
  touchAction: "pan-y",
  // Its end clear of the foot floating over it (DecisionFoot: its height).
  padding: "24px 32px calc(12px + var(--foot-height, 0px))",
  "@media": { "(max-width: 700px)": { padding: "16px 16px calc(8px + var(--foot-height, 0px))" } },
});
/** The column, the chat's width: at the foot of the scroller while it is short, so the post sits over its options. */
export const column = style({
  width: "100%", maxWidth: "760px", margin: "auto auto 0", boxSizing: "border-box", display: "flex",
  flexDirection: "column", gap: "20px",
});
export const head = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", height: "20px" });
/** The chat's title: small, opening the chat. */
export const chatLink = style({
  flex: "0 1 auto", minWidth: "0", padding: "0", border: "0", background: "none", color: vars.muted,
  fontFamily: "inherit", fontSize: vars.textXs, lineHeight: "20px", textAlign: "left", cursor: "pointer",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: { "&:hover": { color: vars.text } },
});
export const count = style({
  marginLeft: "auto", flex: "none", color: vars.subtle, fontSize: vars.textXs, lineHeight: "20px",
  fontVariantNumeric: "tabular-nums",
});

/** The composer (and the phone's hint) over the messages' foot, nothing of its own behind it: they run on under it. */
export const foot = style({
  position: "absolute", left: "0", right: "0", bottom: "0", padding: "8px 32px 16px", pointerEvents: "none",
  "@media": { "(max-width: 700px)": { padding: "8px 16px calc(12px + var(--m-foot, 0px))" } },
});
/** The composer, right under the options. */
export const reply = style({ position: "relative", display: "flex", flexDirection: "column" });
/**
 * The room of one expanded line, kept over the options (DecisionFoot: the messages' end clear of it), not between them
 * and the composer: focus grows the capsule into it, never moving the messages. Drawn as nothing; only measured.
 */
export const replyRoom = style({
  position: "absolute", left: "0", bottom: "0", width: "0", visibility: "hidden", pointerEvents: "none",
  height: `calc(${vars.textBody} * 1.5 + 102px)`,
  selectors: { [`${reply}[data-mobile] &`]: { height: "100px" } },
});
// The footer already supplies the page gutters. Do not inset the chat composer a second time.
globalStyle(`${reply} > ${composerWrap}`, { paddingLeft: "0", paddingRight: "0" });
export const footColumn = style({ maxWidth: "760px", margin: "0 auto" });
// Only what is drawn takes the pointer: the room kept over the composer passes it to the messages under it.
globalStyle(`${footColumn} > :not(${reply}), ${reply} > *`, { pointerEvents: "auto" });
/**
 * ← 待定　不再提醒 →: what a swipe does (the phone). Over the messages as the composer is, on the composer's glass, so
 * they never show through it.
 */
export const hint = style({
  display: "flex", justifyContent: "center", alignItems: "center", gap: "16px", width: "fit-content", height: "24px",
  margin: "8px auto 0", padding: "0 12px", borderRadius: "12px", color: vars.subtle, fontSize: vars.textXs, lineHeight: "24px",
  ...glass,
});
export const hintButton = style({
  height: "20px", padding: "0 4px", border: "0", borderRadius: "6px", background: "none", color: vars.subtle,
  fontFamily: "inherit", fontSize: vars.textXs, lineHeight: "20px", cursor: "pointer",
  selectors: { "&:hover": { color: vars.text } },
});

export const empty = style({
  position: "absolute", inset: "0", display: "grid", placeItems: "center", margin: "0", color: vars.muted,
  fontSize: vars.textSm,
});

const rise = keyframes({ from: { transform: "translateY(12px) scale(.98)", opacity: "0" }, to: { transform: "none", opacity: "1" } });
/** The next decision, as the one before goes. */
export const arriving = style({
  animation: `${rise} 240ms ${vars.easeOut} both`,
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
});

// ── entries ───────────────────────────────────────────────────────────

/** 奏 N in the sidebar's foot: the word bold, the count beside it. */
export const sideEntry = style({ marginBottom: "4px", color: vars.text });
export const sideEntryLead = style({ width: "16px", flex: "none", textAlign: "center", fontWeight: "600" });
export const sideEntryCount = style({ flex: "1", color: vars.muted, fontVariantNumeric: "tabular-nums" });

/** The wide screen's page (pages/Decisions.tsx): its bar, then the decision filling the pane. */
export const page = style({ flex: "1", minHeight: "0", display: "flex", flexDirection: "column", background: vars.canvas });

/** A card this page does not know: the way to its chat, to answer there. */
export const elsewhere = style({
  display: "block", width: "100%", height: "38px", padding: "0 14px", border: "0", borderRadius: vars.rField,
  cornerShape: vars.cornerShape, background: chip, color: vars.text, fontFamily: "inherit", fontSize: vars.textSm,
  fontWeight: "500", cursor: "pointer",
  selectors: { "&:hover": { filter: "brightness(.96)" } },
});
